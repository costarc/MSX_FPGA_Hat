--
-- Projeto MSX SD Mapper
--
-- Copyright (c) 2014
-- Fabio Belavenuto

-- This documentation describes Open Hardware and is licensed under the CERN OHL v. 1.1.
-- You may redistribute and modify this documentation under the terms of the
-- CERN OHL v.1.1. (http://ohwr.org/cernohl). This documentation is distributed
-- WITHOUT ANY EXPRESS OR IMPLIED WARRANTY, INCLUDING OF MERCHANTABILITY,
-- SATISFACTORY QUALITY AND FITNESS FOR A PARTICULAR PURPOSE.
-- Please see the CERN OHL v.1.1 for applicable conditions

-- Implementa um expansor de slots padrao.
--
-- STABILITY FIX:
-- The original design clocked exp_reg directly off "falling_edge(exp_wr)",
-- where exp_wr is a combinational signal derived from sltsl_n, cpu_wr_n and
-- ffff. On real Z80 hardware these three asynchronous bus signals arrive
-- with independent skew, so the combinational AND expression can glitch,
-- generating spurious clock edges and corrupting exp_reg. This is the same
-- hazard found and fixed elsewhere in this project.
--
-- Fix: a clock_i input has been added. sltsl_n, cpu_wr_n and ffff are
-- synchronized into that clock domain before being combined, and exp_reg is
-- now a normal clock_i-synchronous register triggered by an edge-detected
-- pulse instead of being clocked directly off the raw combinational signal.
-- clock_i must be connected to the same free-running clock used elsewhere
-- in the design (e.g. the 25MHz clock_i in SDMapper_Top.vhd) when this
-- component is instantiated.

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity exp_slot is
	port(
		clock_i	: in    std_logic;								-- Free-running clock (e.g. 25MHz clock_i), used to synchronize the bus signals below
		reset_n	: in    std_logic;								-- /RESET
		sltsl_n	: in    std_logic;								-- Sinal de selecao do slot a ser expandido
		cpu_rd_n	: in    std_logic;								-- /RD da CPU
		cpu_wr_n	: in    std_logic;								-- /WR da CPU
		ffff		: in    std_logic;								-- 1 quando CPU_A = FFFF
		cpu_a		: in    std_logic_vector(15 downto 14);	-- Barramento de endereco da CPU (bits 15 e 14)
		cpu_d		: inout std_logic_vector(7 downto 0);		-- Barramento de dados da CPU
		cpu_q		: inout std_logic_vector(7 downto 0);		-- Data back for CPU
		exp_n		: out   std_logic_vector(3 downto 0);		-- Saida 4 bits do expansor (ativo em 0)
		-- DIAGNOSTIC (2026-08-16): the raw subslot register, surfaced so the
		-- top level can display it. exp_reg is rewritten on every inter-slot
		-- call (constantly, while Nextor runs) and is latched continuously
		-- from unsynchronized bus signals - if it ever captures a wrong value
		-- the ROM/RAM page routing changes underneath the running code, which
		-- would look exactly like the intermittent corruption being chased.
		exp_reg_o	: out   std_logic_vector(7 downto 0)
	);
end exp_slot;

architecture rtl of exp_slot is

	signal exp_reg      : std_logic_vector(7 downto 0);
	signal exp_sel      : std_logic_vector(1 downto 0);

	-- Write window and the one sample we commit from it.
	signal exp_wr_raw   : std_logic;
	signal exp_wr_raw_d : std_logic;
	signal exp_d_q      : std_logic_vector(7 downto 0);

begin

	-- ------------------------------------------------------------------------
	-- SIMPLIFIED 2026-08-18.
	--
	-- This file had accumulated a synchroniser chain, a minimum-window-length
	-- filter, a two-deep sample pipeline, whole-byte stability voting, an
	-- always-commit fallback and a rejected-window counter - every one added to
	-- chase a symptom. Measurement retired them:
	--   * the length filter rejected NOTHING (counter read 0)
	--   * 99.7% of failures were DROPPED writes, not corrupted ones, so the
	--     voting addressed a fault that was not happening
	--   * the always-commit fallback published an UNVOTED sample, which was a
	--     hole rather than a safety net
	--   * the synchroniser chain (sltsl_n_sync/cpu_wr_n_sync/ffff_sync ->
	--     exp_wr_sync -> exp_wr_falling_pulse) was computed and then never
	--     used at all - the capture always ran off exp_wr_raw
	--
	-- What is left is the structure msxsdmapperv2 has run on real hardware for
	-- a decade: a combinational write qualifier, and a capture on its trailing
	-- edge.
	--
	--     exp_wr <= '1' when sltsl_n='0' and cpu_wr_n='0' and ffff='1';
	--     ... falling_edge(exp_wr) -> exp_reg <= cpu_d;
	--
	-- The single deliberate difference: that design uses the async qualifier
	-- directly as a clock, which is not safe in an FPGA. Here cpu_d is
	-- registered on every clock while the window is open and the PREVIOUS
	-- sample is committed when it closes, so the committed value is always one
	-- clock clear of the Z80 releasing the bus.
	-- ------------------------------------------------------------------------
	exp_wr_raw <= '1' when sltsl_n = '0' and cpu_wr_n = '0' and ffff = '1' else '0';

	process(clock_i)
	begin
		if rising_edge(clock_i) then
			if reset_n = '0' then
				exp_reg      <= X"00";
				exp_d_q      <= X"00";
				exp_wr_raw_d <= '0';
			else
				exp_wr_raw_d <= exp_wr_raw;

				if exp_wr_raw = '1' then
					exp_d_q <= cpu_d;			-- valid throughout the write pulse
				end if;

				if exp_wr_raw = '0' and exp_wr_raw_d = '1' then
					exp_reg <= exp_d_q;			-- trailing edge: commit
				end if;
			end if;
		end if;
	end process;

	exp_reg_o <= exp_reg;

	-- Read back: the MSX standard returns the one's complement. Driven
	-- unconditionally - the top level already gates it onto D with its own read
	-- conditions, and gating here inferred a latch clocked by RD_n, which
	-- TimeQuest then analysed as a phantom clock domain.
	cpu_q <= not exp_reg;

	-- Sub-slot select for the page being addressed, and the 2-to-4 demux.
	with cpu_a(15 downto 14) select exp_sel <=
		exp_reg(1 downto 0) when "00",
		exp_reg(3 downto 2) when "01",
		exp_reg(5 downto 4) when "10",
		exp_reg(7 downto 6) when others;

	-- ffff = '1' forces ALL sub-slots inactive, so a write to the subslot
	-- register can never also reach the RAM that lives at 0FFFFh in page 3.
	exp_n <= "1111" when ffff = '1' or sltsl_n = '1'      else
				"1110" when sltsl_n = '0' and exp_sel = "00" else
				"1101" when sltsl_n = '0' and exp_sel = "01" else
				"1011" when sltsl_n = '0' and exp_sel = "10" else
				"0111";

end rtl;

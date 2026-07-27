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
		exp_n		: out   std_logic_vector(3 downto 0)		-- Saida 4 bits do expansor (ativo em 0)
	);
end exp_slot;

architecture rtl of exp_slot is

	signal exp_reg  : std_logic_vector(7 downto 0);
	signal exp_sel  : std_logic_vector(1 downto 0);
	signal exp_wr   : std_logic;
	signal exp_rd   : std_logic;

	-- ------------------------------------------------------------------------
	-- Synchronizers for the write-qualifying signals. All three are sampled
	-- together on every clock_i edge so they stay aligned with each other,
	-- removing the dependency on their real-world relative skew.
	-- ------------------------------------------------------------------------
	signal sltsl_n_meta, sltsl_n_sync    : std_logic;
	signal cpu_wr_n_meta, cpu_wr_n_sync  : std_logic;
	signal ffff_meta, ffff_sync          : std_logic;

	signal exp_wr_sync, exp_wr_sync_d    : std_logic;
	signal exp_wr_falling_pulse          : std_logic;

begin

	-- Sinais de selecao do slot (kept combinational, level-based - used only
	-- for the read-side tri-state mux below, not as a clock)
	exp_rd <= '1' when sltsl_n = '0' and cpu_rd_n = '0' and ffff = '1'	else '0';

	-- ------------------------------------------------------------------------
	-- Synchronize sltsl_n, cpu_wr_n and ffff into the clock_i domain.
	-- ------------------------------------------------------------------------
	process(clock_i)
	begin
		if rising_edge(clock_i) then
			sltsl_n_meta  <= sltsl_n;
			sltsl_n_sync  <= sltsl_n_meta;

			cpu_wr_n_meta <= cpu_wr_n;
			cpu_wr_n_sync <= cpu_wr_n_meta;

			ffff_meta     <= ffff;
			ffff_sync     <= ffff_meta;
		end if;
	end process;

	-- Recompute the write qualifier from the now-synchronized, glitch-free
	-- signals, then edge-detect its falling edge to get a one clock_i-wide
	-- pulse at the end of the write cycle (same trigger point as the
	-- original falling_edge(exp_wr) design).
	exp_wr_sync <= '1' when sltsl_n_sync = '0' and cpu_wr_n_sync = '0' and ffff_sync = '1' else '0';

	process(clock_i)
	begin
		if rising_edge(clock_i) then
			exp_wr_sync_d <= exp_wr_sync;
		end if;
	end process;

	exp_wr_falling_pulse <= exp_wr_sync_d and not exp_wr_sync;

	-- Expansion register - now fully synchronous
	process(clock_i)
	begin
		if rising_edge(clock_i) then
			if reset_n = '0' then				-- Zerar registrador do expansor em um reset
				exp_reg <= X"00";
			elsif exp_wr_falling_pulse = '1' then	-- Escrita no endereco &HFFFF
				exp_reg <= cpu_d;
			end if;
		end if;
	end process;

	-- Leitura dos registros
	cpu_q <= (not exp_reg) when exp_rd = '1';

	-- Seleciona qual subslot acionar de acordo com endereco do barramento e registros
	with cpu_a(15 downto 14) select exp_sel <=
		exp_reg(1 downto 0) when "00",
		exp_reg(3 downto 2) when "01",
		exp_reg(5 downto 4) when "10",
		exp_reg(7 downto 6) when others;

	-- Demux 2-to-4
	exp_n <= "1111" when ffff = '1' or sltsl_n = '1'      else
				"1110" when sltsl_n = '0' and exp_sel = "00" else
				"1101" when sltsl_n = '0' and exp_sel = "01" else
				"1011" when sltsl_n = '0' and exp_sel = "10" else
				"0111";

end rtl;
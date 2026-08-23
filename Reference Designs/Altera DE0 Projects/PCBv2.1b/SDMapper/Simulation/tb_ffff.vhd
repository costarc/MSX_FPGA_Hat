-- ---------------------------------------------------------------------------
-- tb_ffff.vhd - why does the FFFFh sub-slot register drop writes?
--
-- Real hardware (MapperTest slot 7, "ffffstress") reports ~3300 DROPPED writes
-- to FFFFh per run and ZERO corrupt ones: the register keeps its PREVIOUS
-- value. Everything else passes - 32 mapper segments, all patterns, page 0,
-- soak with and without interrupts.
--
-- FINDINGS SO FAR
-- ---------------------------------------------------------------------------
-- 1. exp_slot's own logic is NOT at fault. With a perfect address bus it
--    accepts 1000/1000 writes, and the write window is 13-14 clocks against a
--    4-clock threshold - 9 clocks of headroom. The length filter and the
--    "window never opens" theory are both dead.
--
-- 2. A WRONG ADDRESS CAPTURE reproduces the hardware signature exactly:
--    dropped, never corrupt, window never opens. If s_A is not FFFFh we never
--    recognise the write at all.
--
-- WHAT THIS VERSION TESTS
-- ---------------------------------------------------------------------------
-- The capture does this:
--     S_LOW_EN  : U2OE_n <= '0'            -- enable the '245
--     S_LOW_CAP : s_A(7:0) <= A_MUX        -- sample it ONE clock later (20ns)
--
-- 20 ns must cover FPGA output pin -> PCB trace -> 74LVC245 output-enable time
-- -> trace back -> FPGA input. The LVC245's enable time alone is up to ~10 ns.
-- So this is not random noise: it is a deterministic timing violation that
-- usually resolves correctly.
--
-- BUF_DELAY models that path as a real propagation delay. SETTLE_CLOCKS is how
-- many clocks we wait after enabling a buffer before sampling it. Sweeping
-- SETTLE_CLOCKS shows the exact point where the design becomes correct BY
-- CONSTRUCTION rather than by luck - no voting, no statistics.
-- ---------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_ffff is
	generic (
		-- Round-trip delay of the multiplexed address path:
		-- FPGA pin -> trace -> '245 enable -> trace -> FPGA pin.
		BUF_DELAY_NS  : integer := 25;
		-- Clocks to wait after enabling a buffer before sampling it.
		-- 1 = what SDMapper_Top.vhd does today.
		SETTLE_CLOCKS : integer := 1
	);
end tb_ffff;

architecture sim of tb_ffff is

	constant T      : time := 279.365 ns;   -- 3.579545 MHz Z80
	constant HALF_T : time := 139.682 ns;

	constant CLK50_PERIOD : time := 20 ns;
	constant ITERATIONS   : integer := 1000;

	-- ffffstress runs from our own cartridge ROM at 4000-7FFF, so SLTSL_n is
	-- asserted for instruction fetches too, not only for the FFFFh access.
	constant CODE_BASE : std_logic_vector(15 downto 0) := x"4100";

	signal CLOCK_50 : std_logic := '0';
	signal MREQ_n   : std_logic := '1';
	signal IORQ_n   : std_logic := '1';
	signal RD_n     : std_logic := '1';
	signal WR_n     : std_logic := '1';
	signal SLTSL_n  : std_logic := '1';
	signal D        : std_logic_vector(7 downto 0) := (others => 'Z');

	signal addr_bus : std_logic_vector(15 downto 0) := (others => '0');
	signal amux_src : std_logic_vector(7 downto 0);
	signal A_MUX    : std_logic_vector(7 downto 0);

	type addr_capture_state_t is (S_IDLE, S_LOW_EN, S_LOW_WAIT, S_LOW_CAP,
	                              S_GUARD, S_HIGH_EN, S_HIGH_WAIT, S_HIGH_CAP);
	signal addr_capture_state   : addr_capture_state_t := S_IDLE;
	signal U2OE_n, U3OE_n       : std_logic := '1';
	signal s_A                  : std_logic_vector(15 downto 0) := (others => '0');
	signal s_addr_valid         : std_logic := '0';
	signal s_bus_req_n          : std_logic;
	signal bus_req_meta         : std_logic := '1';
	signal bus_req_sync         : std_logic := '1';
	signal bus_req_sync_d       : std_logic := '1';
	signal addr_capture_trigger : std_logic;
	signal s_reset              : std_logic := '1';
	signal settle_cnt           : integer := 0;

	-- how often a captured byte did not match what was really on the bus
	signal amux_bad : integer := 0;

	signal s_ffff_slt    : std_logic;
	signal s_legacy_en   : std_logic := '1';
	signal s_sltsl_dis_n : std_logic;
	signal s_reset_n     : std_logic;
	signal s_expn_q      : std_logic_vector(7 downto 0);
	signal slt_exp_n     : std_logic_vector(3 downto 0);
	signal dbg_exp_reg   : std_logic_vector(7 downto 0);

	signal exp_wr_raw_tb : std_logic;
	signal wr_len_tb     : integer := 0;
	signal wr_len_max    : integer := 0;
	signal saw_window    : boolean := false;
	signal iter_id       : integer := 0;

begin

	CLOCK_50 <= not CLOCK_50 after CLK50_PERIOD / 2;

	-- The FPGA sees the address only through the 8-bit multiplexer, and the
	-- path has real delay: when an OE changes, the data on A_MUX does not
	-- follow until BUF_DELAY later. Until then the previous state persists.
	amux_src <= addr_bus(7 downto 0)  when U2OE_n = '0' else
	            addr_bus(15 downto 8) when U3OE_n = '0' else
	            (others => 'Z');

	A_MUX <= transport amux_src after (BUF_DELAY_NS * 1 ns);

	-- ---------------------------------------------------------------------
	-- Address capture. Identical to SDMapper_Top.vhd except that the wait
	-- between enabling a buffer and sampling it is SETTLE_CLOCKS instead of
	-- being hard-wired to one clock.
	-- ---------------------------------------------------------------------
	s_bus_req_n <= MREQ_n and IORQ_n;

	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			bus_req_meta   <= s_bus_req_n;
			bus_req_sync   <= bus_req_meta;
			bus_req_sync_d <= bus_req_sync;
		end if;
	end process;

	addr_capture_trigger <= bus_req_sync_d and not bus_req_sync;

	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				addr_capture_state <= S_IDLE;
				U2OE_n <= '1';
				U3OE_n <= '1';
				s_addr_valid <= '0';
				settle_cnt   <= 0;
			elsif addr_capture_trigger = '1' then
				addr_capture_state <= S_LOW_EN;
				U2OE_n <= '1';
				U3OE_n <= '1';
				s_addr_valid <= '0';
				settle_cnt   <= 0;
			else
				case addr_capture_state is
					when S_IDLE =>
						U2OE_n <= '1';
						U3OE_n <= '1';

					when S_LOW_EN =>
						U2OE_n <= '0';
						U3OE_n <= '1';
						settle_cnt <= 1;
						-- SETTLE_CLOCKS=0 reproduces SDMapper_Top.vhd exactly:
						-- sample on the very next clock, 20ns after the OE.
						if SETTLE_CLOCKS = 0 then
							addr_capture_state <= S_LOW_CAP;
						else
							addr_capture_state <= S_LOW_WAIT;
						end if;

					when S_LOW_WAIT =>
						if settle_cnt >= SETTLE_CLOCKS then
							addr_capture_state <= S_LOW_CAP;
						else
							settle_cnt <= settle_cnt + 1;
						end if;

					when S_LOW_CAP =>
						s_A(7 downto 0) <= A_MUX;
						if A_MUX /= addr_bus(7 downto 0) then
							amux_bad <= amux_bad + 1;
						end if;
						addr_capture_state <= S_GUARD;

					when S_GUARD =>
						U2OE_n <= '1';
						U3OE_n <= '1';
						addr_capture_state <= S_HIGH_EN;

					when S_HIGH_EN =>
						U2OE_n <= '1';
						U3OE_n <= '0';
						settle_cnt <= 1;
						if SETTLE_CLOCKS = 0 then
							addr_capture_state <= S_HIGH_CAP;
						else
							addr_capture_state <= S_HIGH_WAIT;
						end if;

					when S_HIGH_WAIT =>
						if settle_cnt >= SETTLE_CLOCKS then
							addr_capture_state <= S_HIGH_CAP;
						else
							settle_cnt <= settle_cnt + 1;
						end if;

					when S_HIGH_CAP =>
						s_A(15 downto 8) <= A_MUX;
						if A_MUX /= addr_bus(15 downto 8) then
							amux_bad <= amux_bad + 1;
						end if;
						s_addr_valid <= '1';
						addr_capture_state <= S_IDLE;

					when others =>
						addr_capture_state <= S_IDLE;
				end case;
			end if;
		end if;
	end process;

	s_ffff_slt    <= '1' when s_A = x"FFFF" and s_addr_valid = '1' and s_legacy_en = '1' else '0';
	s_sltsl_dis_n <= SLTSL_n;
	s_reset_n     <= not s_reset;

	dut: entity work.exp_slot
	port map (
		clock_i   => CLOCK_50,
		reset_n   => s_reset_n,
		sltsl_n   => s_sltsl_dis_n,
		cpu_rd_n  => RD_n,
		cpu_wr_n  => WR_n,
		ffff      => s_ffff_slt,
		cpu_a     => s_A(15 downto 14),
		cpu_d     => D,
		cpu_q     => s_expn_q,
		exp_n     => slt_exp_n,
		exp_reg_o => dbg_exp_reg
	);

	exp_wr_raw_tb <= '1' when s_sltsl_dis_n = '0' and WR_n = '0' and s_ffff_slt = '1' else '0';

	process(CLOCK_50)
		variable prev_iter : integer := 0;
	begin
		if rising_edge(CLOCK_50) then
			if iter_id /= prev_iter then
				prev_iter  := iter_id;
				wr_len_tb  <= 0;
				wr_len_max <= 0;
				saw_window <= false;
			elsif exp_wr_raw_tb = '1' then
				wr_len_tb <= wr_len_tb + 1;
				if wr_len_tb + 1 > wr_len_max then
					wr_len_max <= wr_len_tb + 1;
				end if;
				saw_window <= true;
			else
				wr_len_tb <= 0;
			end if;
		end if;
	end process;

	-- ---------------------------------------------------------------------
	-- Z80 bus model
	-- ---------------------------------------------------------------------
	stim: process

		procedure set_addr(a : std_logic_vector(15 downto 0)) is
		begin
			addr_bus <= a;
			if a(15 downto 14) = "01" or a(15 downto 14) = "11" then
				SLTSL_n <= '0';
			else
				SLTSL_n <= '1';
			end if;
		end procedure;

		-- 4 T-states; the REFRESH in T3/T4 asserts MREQ_n a second time, so
		-- one M1 produces two capture triggers.
		procedure m1_fetch(a : std_logic_vector(15 downto 0)) is
		begin
			set_addr(a);
			wait for HALF_T;
			MREQ_n <= '0'; RD_n <= '0';
			wait for 1.5 * T;
			MREQ_n <= '1'; RD_n <= '1';
			wait for HALF_T;
			addr_bus <= x"0000";
			SLTSL_n  <= '1';
			MREQ_n   <= '0';
			wait for T;
			MREQ_n <= '1';
			wait for HALF_T;
		end procedure;

		procedure mem_read(a : std_logic_vector(15 downto 0)) is
		begin
			set_addr(a);
			wait for HALF_T;
			MREQ_n <= '0'; RD_n <= '0';
			wait for 2 * T;
			MREQ_n <= '1'; RD_n <= '1';
			wait for HALF_T;
		end procedure;

		procedure mem_write(a : std_logic_vector(15 downto 0); dat : std_logic_vector(7 downto 0)) is
		begin
			set_addr(a);
			wait for HALF_T;
			MREQ_n <= '0';
			wait for T;
			WR_n <= '0'; D <= dat;
			wait for T;
			WR_n <= '1'; MREQ_n <= '1';
			wait for HALF_T;
			D <= (others => 'Z');
		end procedure;

		variable expected  : std_logic_vector(7 downto 0);
		variable prev      : std_logic_vector(7 downto 0);
		variable got       : std_logic_vector(7 downto 0);
		variable l         : line;
		variable reported  : integer := 0;
		variable v_dropped : integer := 0;
		variable v_corrupt : integer := 0;
		variable v_ok      : integer := 0;
		variable v_never   : integer := 0;
		variable v_chopped : integer := 0;
		variable v_minall  : integer := 9999;
	begin
		s_reset <= '1';
		wait for 1 us;
		s_reset <= '0';
		wait for 1 us;

		prev := x"00";

		for i in 1 to ITERATIONS loop
			expected := std_logic_vector(to_unsigned(((i * 5) mod 256), 8));

			iter_id <= i;
			wait for 3 * CLK50_PERIOD;

			m1_fetch(CODE_BASE);
			mem_read(CODE_BASE + 1);
			m1_fetch(CODE_BASE + 2);
			mem_read(CODE_BASE + 3);
			mem_read(CODE_BASE + 4);
			mem_write(x"FFFF", expected);

			wait for 2 * T;

			got := dbg_exp_reg;

			if wr_len_max < v_minall then v_minall := wr_len_max; end if;

			if got = expected then
				v_ok := v_ok + 1;
			elsif got = prev then
				v_dropped := v_dropped + 1;
				if not saw_window then
					v_never := v_never + 1;
				else
					v_chopped := v_chopped + 1;
				end if;
				if reported < 6 then
					write(l, string'("  DROP  iter="));      write(l, i);
					write(l, string'("  exp="));             hwrite(l, expected);
					write(l, string'("  got="));             hwrite(l, got);
					write(l, string'("  window_opened="));   write(l, saw_window);
					writeline(output, l);
					reported := reported + 1;
				end if;
			else
				v_corrupt := v_corrupt + 1;
			end if;

			prev := got;
		end loop;

		write(l, string'(""));                                               writeline(output, l);
		write(l, string'("=================================================")); writeline(output, l);
		write(l, string'("BUF_DELAY=")); write(l, BUF_DELAY_NS); write(l, string'("ns"));
		write(l, string'("   SETTLE_CLOCKS=")); write(l, SETTLE_CLOCKS);
		write(l, string'(" (")); write(l, SETTLE_CLOCKS * 20); write(l, string'(" ns)"));  writeline(output, l);
		write(l, string'("=================================================")); writeline(output, l);
		write(l, string'("  writes attempted   : ")); write(l, ITERATIONS);   writeline(output, l);
		write(l, string'("  accepted           : ")); write(l, v_ok);         writeline(output, l);
		write(l, string'("  DROPPED            : ")); write(l, v_dropped);    writeline(output, l);
		write(l, string'("  corrupt            : ")); write(l, v_corrupt);    writeline(output, l);
		write(l, string'("  bad address bytes  : ")); write(l, amux_bad);     writeline(output, l);
		write(l, string'("  window never opened: ")); write(l, v_never);      writeline(output, l);
		write(l, string'("  window chopped     : ")); write(l, v_chopped);    writeline(output, l);
		write(l, string'("=================================================")); writeline(output, l);

		assert false report "simulation finished" severity note;
		wait;
	end process;

end sim;

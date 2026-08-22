-- tb_spi.vhd
--
-- GHDL-only functional testbench for spi.vhd IN ISOLATION (not through the
-- full SDMapper_TOP bus-capture machinery). Written to investigate a real
-- symptom reported on real hardware: Nextor reports "SD Card 1: Failed"
-- (not "absent"/"empty") - meaning card-presence detection works, but the
-- actual SPI transaction with the card does not. This testbench directly
-- observes spi.vhd's own internal FSM: does wait_n_o correctly stall the
-- (simulated) CPU for the whole 8-bit transfer, and does data shift
-- correctly in both directions?
--
-- Analyze order (GHDL, --std=08 -fsynopsys):
--   spi.vhd, sim/tb_spi.vhd

library ieee;
use ieee.std_logic_1164.all;

entity tb_spi is
end entity;

architecture sim of tb_spi is

	signal clock_i     : std_logic := '0';
	signal reset_n_i   : std_logic := '0';
	signal cs_i        : std_logic := '0';
	signal data_bus_io : std_logic_vector(7 downto 0) := (others => 'Z');
	signal wr_n_i      : std_logic := '1';
	signal rd_n_i      : std_logic := '1';
	signal wait_n_o    : std_logic;
	signal spi_sclk_o  : std_logic;
	signal spi_mosi_o  : std_logic;
	signal spi_miso_i  : std_logic := '1';
	signal spi_dout    : std_logic_vector(7 downto 0);
	signal spi_rd_en   : std_logic;

	constant CLK_PERIOD : time := 40 ns;  -- 25MHz, matches clock_i in SDMapper_Top.vhd

	-- Captured MOSI bits (testbench-side observer, sampled on spi_sclk_o
	-- rising edge - standard SPI mode 0: master drives MOSI on the falling
	-- edge, so it's stable and valid to sample on the following rising edge).
	signal mosi_capture : std_logic_vector(7 downto 0) := (others => '0');
	signal mosi_bit_count : integer := 0;
	signal capture_clear : std_logic := '0';  -- pulsed by the stimulus process to reset the capture (avoids two drivers on mosi_capture/mosi_bit_count)

	-- Slave-side MISO model: shifts out a fixed test byte, MSB first, one
	-- bit per spi_sclk_o falling edge (so it's stable for the master's
	-- next rising-edge... NOTE: see the process below for the exact
	-- edge this model uses, chosen to match what spi.vhd itself expects).
	signal miso_shift_reg : std_logic_vector(7 downto 0) := x"3C";  -- known test byte
	signal miso_load_value : std_logic_vector(7 downto 0) := x"3C";
	signal miso_load : std_logic := '0';  -- pulsed by the stimulus to (re)load miso_shift_reg (avoids two drivers)

	signal sclk_prev : std_logic := '0';

begin

	dut: entity work.spi
		port map (
			clock_i     => clock_i,
			reset_n_i   => reset_n_i,
			cs_i        => cs_i,
			data_bus_io => data_bus_io,
			wr_n_i      => wr_n_i,
			rd_n_i      => rd_n_i,
			wait_n_o    => wait_n_o,
			spi_sclk_o  => spi_sclk_o,
			spi_mosi_o  => spi_mosi_o,
			spi_miso_i  => spi_miso_i,
			spi_dout    => spi_dout,
			spi_rd_en   => spi_rd_en
		);

	clock_i <= not clock_i after CLK_PERIOD / 2;

	-- ------------------------------------------------------------------
	-- MOSI capture + MISO drive, synchronized to spi_sclk_o edges (the
	-- REAL output pin, not any internal signal) - this is exactly what a
	-- real SD card would see/drive, so it's a faithful external observer.
	-- ------------------------------------------------------------------
	process(clock_i)
	begin
		if rising_edge(clock_i) then
			sclk_prev <= spi_sclk_o;

			if capture_clear = '1' then
				mosi_capture   <= (others => '0');
				mosi_bit_count <= 0;
			-- Rising edge of spi_sclk_o: sample MOSI (mode 0 - data set up
			-- on the falling edge, sampled on the rising edge). "/= '1'"
			-- rather than "= '0'" so the very first transition (out of
			-- spi_sclk_o's power-up 'U') is still caught.
			elsif sclk_prev /= '1' and spi_sclk_o = '1' then
				mosi_capture   <= mosi_capture(6 downto 0) & spi_mosi_o;
				mosi_bit_count <= mosi_bit_count + 1;
			end if;

			if miso_load = '1' then
				miso_shift_reg <= miso_load_value;
			-- Falling edge of spi_sclk_o: slave drives its next bit (mode 0
			-- convention - slave changes MISO on the falling edge so it's
			-- stable for the master's next rising-edge sample).
			elsif sclk_prev = '1' and spi_sclk_o /= '1' then
				miso_shift_reg <= miso_shift_reg(6 downto 0) & '1';
			end if;
		end if;
	end process;

	spi_miso_i <= miso_shift_reg(7);

	-- Timeline monitor: report every transition of every DUT-observable
	-- signal, so the exact sequence/timing of events can be read directly
	-- from the simulation transcript instead of inferred indirectly.
	monitor: process
	begin
		wait on wait_n_o, spi_sclk_o, spi_rd_en, cs_i, wr_n_i, rd_n_i;
		report "MONITOR t=" & time'image(now) &
		       " wait_n_o=" & std_logic'image(wait_n_o) &
		       " sclk=" & std_logic'image(spi_sclk_o) &
		       " mosi=" & std_logic'image(spi_mosi_o) &
		       " rd_en=" & std_logic'image(spi_rd_en) &
		       " cs_i=" & std_logic'image(cs_i) &
		       " wr_n=" & std_logic'image(wr_n_i) &
		       " rd_n=" & std_logic'image(rd_n_i) &
		       " mosi_bit_count=" & integer'image(mosi_bit_count) &
		       " mosi_capture=" & to_string(mosi_capture);
	end process;

	-- ------------------------------------------------------------------
	stimulus: process
		variable pass_count : integer := 0;
		variable fail_count : integer := 0;

		procedure check(name : string; cond : boolean) is
		begin
			if cond then
				pass_count := pass_count + 1;
				report "PASS: " & name;
			else
				fail_count := fail_count + 1;
				report "FAIL: " & name severity error;
			end if;
		end procedure;

	begin
		reset_n_i <= '0';
		wait for 5 * CLK_PERIOD;
		reset_n_i <= '1';
		wait for 5 * CLK_PERIOD;

		report "==== CHECK A: WRITE transfer (CPU writes 0xA5, should appear on MOSI) ====";
		capture_clear <= '1';
		wait for CLK_PERIOD;
		capture_clear <= '0';
		data_bus_io <= x"A5";
		wr_n_i <= '0';
		cs_i <= '1';

		-- Wait for wait_n_o to assert (go low = busy), with a generous
		-- timeout - if this never happens, the CPU would never actually
		-- be held, which is exactly the bug under investigation.
		wait until wait_n_o = '0' for 40 * CLK_PERIOD;
		check("A1: wait_n_o asserts (goes low) after a write access begins",
		      wait_n_o = '0');

		-- Wait for it to deassert again (transfer complete), generous timeout.
		wait until wait_n_o = '1' for 60 * CLK_PERIOD;
		check("A2: wait_n_o deasserts (goes high) once the transfer completes",
		      wait_n_o = '1');

		check("A3: exactly 8 bits were clocked out on MOSI",
		      mosi_bit_count = 8);
		check("A4: MOSI carried the written byte 0xA5, MSB first",
		      mosi_capture = x"A5");

		wr_n_i <= '1';
		cs_i <= '0';
		data_bus_io <= (others => 'Z');
		wait for 10 * CLK_PERIOD;

		report "==== CHECK B: READ transfer (slave drives 0x3C via MISO, CPU should read it back) ====";
		miso_load_value <= x"3C";
		miso_load <= '1';
		capture_clear <= '1';
		wait for CLK_PERIOD;
		miso_load <= '0';
		capture_clear <= '0';
		rd_n_i <= '0';
		cs_i <= '1';

		wait until wait_n_o = '0' for 40 * CLK_PERIOD;
		check("B1: wait_n_o asserts on a read access too",
		      wait_n_o = '0');

		wait until wait_n_o = '1' for 60 * CLK_PERIOD;
		wait for 0 ns;	-- let any same-instant delta-cycle updates settle before sampling
		check("B2: wait_n_o deasserts once the read transfer completes",
		      wait_n_o = '1');

		-- spi_dout/spi_rd_en are combinational off cs_i/rd_n_i, still
		-- asserted right now since cs_i/rd_n_i haven't been released yet -
		-- this is the CPU's actual read-data sampling window.
		check("B3: spi_rd_en is asserted while cs_i='1' and rd_n_i='0'",
		      spi_rd_en = '1');
		check("B4: spi_dout presents the byte clocked in from MISO (0x3C)",
		      spi_dout = x"3C");

		rd_n_i <= '1';
		cs_i <= '0';
		wait for 10 * CLK_PERIOD;

		report "==============================================";
		report "SPI TB SUMMARY: " & integer'image(pass_count) & " passed, " &
		       integer'image(fail_count) & " failed.";
		report "==============================================";

		if fail_count = 0 then
			report "ALL SPI CHECKS PASSED";
		else
			report "SOME SPI CHECKS FAILED" severity error;
		end if;

		std.env.stop;
	end process;

end architecture;

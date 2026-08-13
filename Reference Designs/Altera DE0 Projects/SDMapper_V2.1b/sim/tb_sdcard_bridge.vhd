-- tb_sdcard_bridge.vhd
--
-- GHDL-only functional testbench for sdcard_bridge.vhd IN ISOLATION,
-- driving it through its actual CPU-facing register interface (cs_i/
-- reg_addr_i/data_bus_i/wr_n_i/rd_n_i) the same way the real Z80 bus +
-- Nextor driver (driver.mac) would, against the same mock SD card model
-- used in tb_sdcard_xess.vhd. tb_sdcard_xess.vhd already verified the
-- ported core's own FSM logic is correct in isolation (7/7 pass) for
-- exactly the "first read after init" scenario that hung on real
-- hardware - this testbench checks the OTHER half: does the bridge's own
-- Z80-bus-facing handshake/WAIT_n logic correctly drive that core.
--
-- CPU access modeling: a real Z80 WAIT-extended bus cycle holds cs_i/
-- rd_n_i/wr_n_i asserted for the WHOLE duration of the stall, only
-- releasing once WAIT_n deasserts - this testbench's stimulus mimics that
-- exactly (assert, wait for wait_n_o to release, then deassert), not just
-- a fixed-width pulse.
--
-- Analyze order (GHDL, --std=08 -fsynopsys):
--   sdcard_xess.vhd, sdcard_bridge.vhd, sim/tb_sdcard_bridge.vhd

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_sdcard_bridge is
end entity;

architecture sim of tb_sdcard_bridge is

	signal clock_i         : std_logic := '0';
	signal reset_n_i       : std_logic := '0';
	signal cs_i            : std_logic := '0';
	signal reg_addr_i      : std_logic_vector(3 downto 0) := (others => '0');
	signal data_bus_i      : std_logic_vector(7 downto 0) := (others => '0');
	signal wr_n_i          : std_logic := '1';
	signal rd_n_i          : std_logic := '1';
	signal wait_n_o        : std_logic;
	signal card_present_i  : std_logic := '1';
	signal write_protect_i : std_logic := '0';
	signal reg_dout        : std_logic_vector(7 downto 0);
	signal sd_dout         : std_logic_vector(7 downto 0);
	signal sd_rd_en        : std_logic;
	signal sd_cs_o         : std_logic;
	signal sd_sclk_o       : std_logic;
	signal sd_mosi_o       : std_logic;
	signal sd_miso_i       : std_logic := '1';
	signal dbg_busy_o      : std_logic;
	signal dbg_error_o     : std_logic_vector(15 downto 0);
	signal dbg_timeout_o   : std_logic;
	signal dbg_last_tx_o   : std_logic_vector(7 downto 0);
	signal dbg_last_rx_o   : std_logic_vector(7 downto 0);
	signal dbg_ever_accessed_o : std_logic;
	signal dbg_init_done_o : std_logic;

	constant CLK_PERIOD : time := 40 ns;	-- 25MHz

	-- Register indices, matching driver.mac's SD_* equates
	constant REG_DATA   : std_logic_vector(3 downto 0) := "0000";
	constant REG_ADDR0  : std_logic_vector(3 downto 0) := "0001";
	constant REG_ADDR1  : std_logic_vector(3 downto 0) := "0010";
	constant REG_ADDR2  : std_logic_vector(3 downto 0) := "0011";
	constant REG_ADDR3  : std_logic_vector(3 downto 0) := "0100";
	constant REG_CMD    : std_logic_vector(3 downto 0) := "0101";
	constant REG_STATUS : std_logic_vector(3 downto 0) := "0110";

	-- ------------------------------------------------------------------
	-- Mock SD card model - identical in behavior to tb_sdcard_xess.vhd's.
	-- ------------------------------------------------------------------
	signal sclk_prev      : std_logic := '0';
	signal cs_bo_prev     : std_logic := '1';
	signal rx_shift       : std_logic_vector(7 downto 0) := (others => '0');
	signal rx_bit_cnt     : integer range 0 to 7 := 0;
	signal frame_byte_idx : integer range 0 to 7 := 0;
	signal cmd_count      : integer := 0;
	signal cmd_seen       : std_logic_vector(7 downto 0) := (others => '0');

	signal resp_byte    : std_logic_vector(7 downto 0) := x"FF";
	signal resp_bit_cnt : integer range 0 to 7 := 0;
	signal resp_active  : boolean := false;
	signal resp_step    : integer := 0;

	constant CMD17_NOTREADY_BYTES : integer := 3;
	signal cmd17_data_byte : unsigned(7 downto 0) := (others => '0');

begin

	dut: entity work.sdcard_bridge
		port map (
			clock_i         => clock_i,
			reset_n_i       => reset_n_i,
			cs_i            => cs_i,
			reg_addr_i      => reg_addr_i,
			data_bus_i      => data_bus_i,
			wr_n_i          => wr_n_i,
			rd_n_i          => rd_n_i,
			wait_n_o        => wait_n_o,
			card_present_i  => card_present_i,
			write_protect_i => write_protect_i,
			reg_dout        => reg_dout,
			sd_dout         => sd_dout,
			sd_rd_en        => sd_rd_en,
			sd_cs_o         => sd_cs_o,
			sd_sclk_o       => sd_sclk_o,
			sd_mosi_o       => sd_mosi_o,
			sd_miso_i       => sd_miso_i,
			dbg_busy_o           => dbg_busy_o,
			dbg_error_o          => dbg_error_o,
			dbg_timeout_o        => dbg_timeout_o,
			dbg_last_tx_o        => dbg_last_tx_o,
			dbg_last_rx_o        => dbg_last_rx_o,
			dbg_ever_accessed_o  => dbg_ever_accessed_o,
			dbg_init_done_o      => dbg_init_done_o
		);

	clock_i <= not clock_i after CLK_PERIOD / 2;

	-- ------------------------------------------------------------------
	-- Mock card (identical logic to tb_sdcard_xess.vhd - see that file
	-- for detailed comments on the resync-on-cs_bo-falling-edge fix).
	-- ------------------------------------------------------------------
	process(clock_i)
		variable new_byte_v : std_logic_vector(7 downto 0);
	begin
		if rising_edge(clock_i) then
			sclk_prev  <= sd_sclk_o;
			cs_bo_prev <= sd_cs_o;

			if cs_bo_prev = '1' and sd_cs_o = '0' then
				rx_bit_cnt     <= 0;
				frame_byte_idx <= 0;
				resp_bit_cnt   <= 7;
			end if;

			if sclk_prev = '0' and sd_sclk_o = '1' then
				new_byte_v := rx_shift(6 downto 0) & sd_mosi_o;
				rx_shift   <= new_byte_v;
				if rx_bit_cnt = 7 then
					rx_bit_cnt <= 0;
					if frame_byte_idx = 0 and new_byte_v(7 downto 6) = "01" then
						cmd_seen       <= new_byte_v;
						frame_byte_idx <= 1;
					elsif frame_byte_idx > 0 and frame_byte_idx < 5 then
						frame_byte_idx <= frame_byte_idx + 1;
					elsif frame_byte_idx = 5 then
						frame_byte_idx <= 0;
						cmd_count      <= cmd_count + 1;
						resp_active    <= true;
						resp_step      <= 0;
					end if;
				else
					rx_bit_cnt <= rx_bit_cnt + 1;
				end if;
			end if;

			if sclk_prev = '1' and sd_sclk_o = '0' then
				if resp_bit_cnt = 0 then
					resp_bit_cnt <= 7;
				else
					resp_bit_cnt <= resp_bit_cnt - 1;
				end if;
				if resp_bit_cnt = 0 and resp_active then
					case cmd_count is
						when 1 =>
							resp_byte   <= x"01";
							resp_active <= false;
						when 2 =>
							case resp_step is
								when 0 => resp_byte <= x"01"; resp_step <= 1;
								when 1 => resp_byte <= x"00"; resp_step <= 2;
								when 2 => resp_byte <= x"00"; resp_step <= 3;
								when 3 => resp_byte <= x"01"; resp_step <= 4;
								when others =>
									resp_byte   <= x"AA";
									resp_active <= false;
							end case;
						when 3 =>
							resp_byte   <= x"01";
							resp_active <= false;
						when 4 =>
							resp_byte   <= x"00";
							resp_active <= false;
						when 5 =>
							if resp_step = 0 then
								resp_byte <= x"00";
								resp_step <= 1;
							elsif resp_step <= CMD17_NOTREADY_BYTES then
								resp_byte <= x"FF";
								resp_step <= resp_step + 1;
							elsif resp_step = CMD17_NOTREADY_BYTES + 1 then
								resp_byte       <= x"FE";
								resp_step       <= resp_step + 1;
								cmd17_data_byte <= (others => '0');
							elsif resp_step <= CMD17_NOTREADY_BYTES + 1 + 512 then
								resp_byte       <= std_logic_vector(cmd17_data_byte);
								cmd17_data_byte <= cmd17_data_byte + 1;
								resp_step       <= resp_step + 1;
							elsif resp_step <= CMD17_NOTREADY_BYTES + 1 + 512 + 2 then
								resp_byte <= x"AA";
								resp_step <= resp_step + 1;
								if resp_step = CMD17_NOTREADY_BYTES + 1 + 512 + 2 then
									resp_active <= false;
								end if;
							end if;
						when others =>
							resp_byte <= x"FF";
					end case;
				elsif resp_bit_cnt = 0 and not resp_active then
					resp_byte <= x"FF";
				end if;
			end if;
		end if;
	end process;

	sd_miso_i <= resp_byte(resp_bit_cnt);

	-- ------------------------------------------------------------------
	dbgmon: process(cmd_count, dbg_busy_o, dbg_timeout_o, dbg_init_done_o)
	begin
		report "DBG t=" & time'image(now) & " cmd_count=" & integer'image(cmd_count) &
		       " busy=" & std_logic'image(dbg_busy_o) & " timeout=" & std_logic'image(dbg_timeout_o) &
		       " init_done=" & std_logic'image(dbg_init_done_o) & " error=" & to_hstring(dbg_error_o);
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

		-- Models a real Z80 WAIT-extended write cycle: assert cs_i/
		-- wr_n_i/reg_addr_i/data_bus_i, hold until wait_n_o releases (for
		-- SD_DATA - other registers aren't WAIT-gated but this still
		-- works, wait_n_o just never asserts for them), then release.
		procedure cpu_write(reg : std_logic_vector(3 downto 0); val : std_logic_vector(7 downto 0)) is
		begin
			reg_addr_i <= reg;
			data_bus_i <= val;
			wr_n_i     <= '0';
			cs_i       <= '1';
			wait for CLK_PERIOD;
			wait until wait_n_o = '1' for 200000 * CLK_PERIOD;
			wr_n_i <= '1';
			cs_i   <= '0';
			wait for CLK_PERIOD;
		end procedure;

		-- Models a real Z80 WAIT-extended read cycle, returning the byte
		-- read via reg_dout (immediate registers) or sd_dout (SD_DATA).
		procedure cpu_read(reg : std_logic_vector(3 downto 0); result : out std_logic_vector(7 downto 0)) is
		begin
			reg_addr_i <= reg;
			rd_n_i     <= '0';
			cs_i       <= '1';
			wait for CLK_PERIOD;
			wait until wait_n_o = '1' for 200000 * CLK_PERIOD;
			if reg = REG_DATA then
				result := sd_dout;
			else
				result := reg_dout;
			end if;
			rd_n_i <= '1';
			cs_i   <= '0';
			wait for CLK_PERIOD;
		end procedure;

		variable byte_v      : std_logic_vector(7 downto 0);
		variable data_ok     : boolean := true;
		variable expect      : unsigned(7 downto 0) := (others => '0');

	begin
		reset_n_i <= '0';
		wait for 10 * CLK_PERIOD;
		reset_n_i <= '1';

		report "==== Waiting for SdCardCtrl init (CMD0/CMD8/CMD55/CMD41) via the bridge ====";
		wait until dbg_busy_o = '0' for 100000 * CLK_PERIOD;
		check("A1: init completes (dbg_busy_o goes low)", dbg_busy_o = '0');
		check("A2: no error after init", dbg_error_o = x"0000");
		check("A3: all 4 init commands seen", cmd_count = 4);

		report "==== DRV_INIT-style: SD_STATUS poll, exactly like driver.mac ====";
		cpu_read(REG_STATUS, byte_v);
		check("A4: SD_STATUS reports not busy, present, no error",
		      byte_v(0) = '0' and byte_v(1) = '0' and byte_v(2) = '1');

		report "==== DEV_RW-style single-block read (sector 0), exactly like driver.mac ====";
		cpu_write(REG_ADDR0, x"00");
		cpu_write(REG_ADDR1, x"00");
		cpu_write(REG_ADDR2, x"00");
		cpu_write(REG_ADDR3, x"00");
		cpu_write(REG_CMD, x"01");	-- SD_CMD_READ

		expect := (others => '0');
		for i in 0 to 511 loop
			cpu_read(REG_DATA, byte_v);
			if byte_v /= std_logic_vector(expect) then
				data_ok := false;
			end if;
			expect := expect + 1;
		end loop;
		check("B1: all 512 bytes read via the bridge match the expected pattern", data_ok);

		cpu_read(REG_STATUS, byte_v);
		check("B2: SD_STATUS shows no error/timeout after the read",
		      byte_v(1) = '0' and byte_v(4) = '0');
		check("B3: dbg_timeout_o never fired", dbg_timeout_o = '0');

		report "==============================================";
		report "BRIDGE TB SUMMARY: " & integer'image(pass_count) & " passed, " &
		       integer'image(fail_count) & " failed.";
		report "==============================================";

		if fail_count = 0 then
			report "ALL CHECKS PASSED";
		else
			report "SOME CHECKS FAILED" severity error;
		end if;

		std.env.stop;
	end process;

end architecture;

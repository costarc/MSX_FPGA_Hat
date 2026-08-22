-- tb_sdcard_xess.vhd
--
-- GHDL-only functional testbench for sdcard_xess.vhd (the ported XESS
-- SdCardCtrl core) IN ISOLATION, driving it against a mock SPI-slave SD
-- card model that answers CMD0/CMD8/CMD55/CMD41/CMD17 realistically
-- enough to exercise the full init sequence AND a first block read -
-- exactly the sequence that hung on real hardware right after "SD card
-- ready" was printed (init succeeded, first DEV_RW hung).
--
-- The mock card responds immediately (no artificial per-command delay)
-- EXCEPT for CMD17, where it deliberately holds MISO at the "not ready"
-- token (0xFF) for a few byte-times before sending the real start token
-- (0xFE) - this is exactly the case that exposed the doDeselect_v bug
-- (RD_BLK's "wait for start token" loop only ever runs meaningfully if
-- the card doesn't respond with the token on the very first poll).
--
-- Analyze order (GHDL, --std=08 -fsynopsys):
--   sdcard_xess.vhd, sim/tb_sdcard_xess.vhd

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.SdCardXessPckg.all;

entity tb_sdcard_xess is
end entity;

architecture sim of tb_sdcard_xess is

	signal clk_i      : std_logic := '0';
	signal reset_i     : std_logic := '1';
	signal rd_i        : std_logic := '0';
	signal wr_i        : std_logic := '0';
	signal continue_i  : std_logic := '0';
	signal addr_i      : std_logic_vector(31 downto 0) := (others => '0');
	signal data_i      : std_logic_vector(7 downto 0) := (others => '0');
	signal data_o      : std_logic_vector(7 downto 0);
	signal busy_o      : std_logic;
	signal hndShk_i    : std_logic := '0';
	signal hndShk_o    : std_logic;
	signal error_o     : std_logic_vector(15 downto 0);
	signal cs_bo       : std_logic;
	signal sclk_o      : std_logic;
	signal mosi_o      : std_logic;
	signal miso_i      : std_logic := '1';

	constant CLK_PERIOD : time := 40 ns;	-- 25MHz, matches FREQ_G=25.0

	-- ------------------------------------------------------------------
	-- Mock SD card model
	-- ------------------------------------------------------------------
	signal sclk_prev     : std_logic := '0';
	signal cs_bo_prev    : std_logic := '1';
	signal rx_shift      : std_logic_vector(7 downto 0) := (others => '0');
	signal rx_bit_cnt    : integer range 0 to 7 := 0;
	signal frame_byte_idx: integer range 0 to 7 := 0;	-- position within the current 6-byte command frame
	signal cmd_count     : integer := 0;			-- how many complete command frames have been seen
	signal cmd_seen      : std_logic_vector(7 downto 0) := (others => '0');	-- the command byte of the CURRENT frame

	signal resp_byte     : std_logic_vector(7 downto 0) := x"FF";
	signal resp_bit_cnt  : integer range 0 to 7 := 0;
	signal resp_active   : boolean := false;
	signal resp_step     : integer := 0;	-- byte position within the current response sequence

	-- CMD17 read-data model: after R1, hold "not ready" (0xFF) for this
	-- many byte-times before sending the start token - deliberately
	-- non-trivial so the RD_BLK polling loop actually has to loop.
	constant CMD17_NOTREADY_BYTES : integer := 3;
	signal cmd17_data_byte : unsigned(7 downto 0) := (others => '0');

	-- Test result tracking
	signal read_data_ok   : boolean := true;
	signal bytes_read      : integer := 0;

begin

	dut: entity work.SdCardCtrl
		generic map (
			FREQ_G          => 25.0,
			INIT_SPI_FREQ_G => 0.4,
			SPI_FREQ_G      => 12.5,
			BLOCK_SIZE_G    => 512,
			CARD_TYPE_G     => SDHC_CARD_E
		)
		port map (
			clk_i      => clk_i,
			reset_i    => reset_i,
			rd_i       => rd_i,
			wr_i       => wr_i,
			continue_i => continue_i,
			addr_i     => addr_i,
			data_i     => data_i,
			data_o     => data_o,
			busy_o     => busy_o,
			hndShk_i   => hndShk_i,
			hndShk_o   => hndShk_o,
			error_o    => error_o,
			cs_bo      => cs_bo,
			sclk_o     => sclk_o,
			mosi_o     => mosi_o,
			miso_i     => miso_i
		);

	clk_i <= not clk_i after CLK_PERIOD / 2;

	-- ------------------------------------------------------------------
	-- Mock card: receive command bytes (MSB-first, sampled on sclk_o
	-- rising edge, mode 0), track how many 6-byte command frames have
	-- gone by, and drive miso_i accordingly on sclk_o falling edges.
	-- ------------------------------------------------------------------
	process(clk_i)
		variable new_byte_v : std_logic_vector(7 downto 0);
	begin
		if rising_edge(clk_i) then
			sclk_prev <= sclk_o;
			cs_bo_prev <= cs_bo;

			-- Resync on cs_bo falling edge (card just selected for a new
			-- command) - a real card doesn't process bits while
			-- deselected, and the DUT's own DESELECT state inserts 1-2
			-- extra PULSE_SCLK cycles between commands that would
			-- otherwise throw off a naive free-running bit counter,
			-- misaligning every subsequent command's byte framing.
			if cs_bo_prev = '1' and cs_bo = '0' then
				rx_bit_cnt     <= 0;
				frame_byte_idx <= 0;
				resp_bit_cnt   <= 7;
			end if;

			-- RX: sample MOSI on sclk_o rising edge
			if sclk_prev = '0' and sclk_o = '1' then
				new_byte_v := rx_shift(6 downto 0) & mosi_o;
				rx_shift   <= new_byte_v;
				if rx_bit_cnt = 7 then
					rx_bit_cnt <= 0;
					-- A full byte just landed in new_byte_v - detect a new command
					-- frame start: top two bits "01" (0x40-0x7F) AND we're not
					-- already mid-frame.
					if frame_byte_idx = 0 and new_byte_v(7 downto 6) = "01" then
						cmd_seen       <= new_byte_v;
						frame_byte_idx <= 1;
					elsif frame_byte_idx > 0 and frame_byte_idx < 5 then
						frame_byte_idx <= frame_byte_idx + 1;
					elsif frame_byte_idx = 5 then
						-- 6th byte (CRC) just landed - frame complete.
						frame_byte_idx <= 0;
						cmd_count      <= cmd_count + 1;
						resp_active    <= true;
						resp_step      <= 0;
					end if;
				else
					rx_bit_cnt <= rx_bit_cnt + 1;
				end if;
			end if;

			-- TX: drive MISO on sclk_o falling edge
			if sclk_prev = '1' and sclk_o = '0' then
				if resp_bit_cnt = 0 then
					resp_bit_cnt <= 7;
				else
					resp_bit_cnt <= resp_bit_cnt - 1;
				end if;
				if resp_bit_cnt = 0 and resp_active then
					-- Just finished shifting out resp_byte - pick the next one.
					case cmd_count is
						when 1 =>	-- response to CMD0: R1 = 0x01 (idle, no error)
							resp_byte   <= x"01";
							resp_active <= false;
						when 2 =>	-- response to CMD8: R7 = 5 bytes (R1 + echoed 0x000001AA)
							case resp_step is
								when 0 => resp_byte <= x"01"; resp_step <= 1;
								when 1 => resp_byte <= x"00"; resp_step <= 2;
								when 2 => resp_byte <= x"00"; resp_step <= 3;
								when 3 => resp_byte <= x"01"; resp_step <= 4;
								when others =>
									resp_byte   <= x"AA";
									resp_active <= false;
							end case;
						when 3 =>	-- response to CMD55: R1 = 0x01 (still idle)
							resp_byte   <= x"01";
							resp_active <= false;
						when 4 =>	-- response to CMD41: R1 = 0x00 (ready - first try, keep the mock simple)
							resp_byte   <= x"00";
							resp_active <= false;
						when 5 =>	-- response to CMD17 (read single block): R1=0x00, then
							-- CMD17_NOTREADY_BYTES bytes of 0xFF, then start token 0xFE,
							-- then 512 data bytes (counting pattern), then 2 CRC bytes.
							if resp_step = 0 then
								resp_byte <= x"00";	-- R1
								resp_step <= 1;
							elsif resp_step <= CMD17_NOTREADY_BYTES then
								resp_byte <= x"FF";	-- not ready yet
								resp_step <= resp_step + 1;
							elsif resp_step = CMD17_NOTREADY_BYTES + 1 then
								resp_byte      <= x"FE";	-- start token
								resp_step      <= resp_step + 1;
								cmd17_data_byte <= (others => '0');
							elsif resp_step <= CMD17_NOTREADY_BYTES + 1 + 512 then
								resp_byte      <= std_logic_vector(cmd17_data_byte);
								cmd17_data_byte <= cmd17_data_byte + 1;
								resp_step      <= resp_step + 1;
							elsif resp_step <= CMD17_NOTREADY_BYTES + 1 + 512 + 2 then
								resp_byte <= x"AA";	-- dummy CRC bytes
								resp_step <= resp_step + 1;
								if resp_step = CMD17_NOTREADY_BYTES + 1 + 512 + 2 then
									resp_active <= false;
								end if;
							end if;
						when others =>
							resp_byte <= x"FF";	-- idle
					end case;
				elsif resp_bit_cnt = 0 and not resp_active then
					resp_byte <= x"FF";	-- idle between/after known responses
				end if;
			end if;
		end if;
	end process;

	-- resp_byte holds the current response byte for the whole bit period;
	-- resp_bit_cnt tracks which bit position is "next" (7=MSB, counting
	-- down), matching the MSB-first shift order used everywhere else in
	-- this project's testbenches.
	miso_i <= resp_byte(resp_bit_cnt);

	-- ------------------------------------------------------------------
	-- Capture bytes read via the DUT's own hndShk protocol during the
	-- CMD17 read, to verify the counting-pattern data actually arrives
	-- correctly at the host side (not just that SOME handshake occurred).
	-- ------------------------------------------------------------------
	process(clk_i)
	begin
		if rising_edge(clk_i) then
			if hndShk_o = '1' and hndShk_i = '0' then
				hndShk_i <= '1';
				if bytes_read < 512 then
					if data_o /= std_logic_vector(to_unsigned(bytes_read mod 256, 8)) then
						read_data_ok <= false;
					end if;
				end if;
				bytes_read <= bytes_read + 1;
			elsif hndShk_o = '0' and hndShk_i = '1' then
				hndShk_i <= '0';
			end if;
		end if;
	end process;

	-- ------------------------------------------------------------------
	-- DEBUG: trace mock-card frame/command progress and cs_bo/busy_o.
	dbgmon: process(cmd_count, cs_bo, busy_o)
	begin
		report "DBG t=" & time'image(now) & " cmd_count=" & integer'image(cmd_count) &
		       " cs_bo=" & std_logic'image(cs_bo) & " busy_o=" & std_logic'image(busy_o) &
		       " error_o=" & to_hstring(error_o);
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
		reset_i <= '1';
		wait for 10 * CLK_PERIOD;
		reset_i <= '0';

		report "==== Waiting for init (CMD0/CMD8/CMD55/CMD41) to complete ====";
		-- Generous margin over the ~1.07ms this mock's init actually takes
		-- (measured via the DBG trace) - a "wait ... for" proceeds after
		-- the timeout regardless of whether the condition was ever met, so
		-- too tight a window here would silently let the stimulus issue
		-- rd_i while the DUT is still mid-init, with no visible error.
		wait until busy_o = '0' for 100000 * CLK_PERIOD;
		check("A1: init completes (busy_o goes low) within a generous timeout",
		      busy_o = '0');
		check("A2: no error reported after init", error_o = x"0000");
		check("A3: all 4 init commands were seen by the mock card (cmd_count=4)",
		      cmd_count = 4);

		report "==== Issuing first block read (CMD17) - the sequence that hung on real hardware ====";
		addr_i <= x"00000000";
		rd_i   <= '1';
		wait for CLK_PERIOD;
		rd_i   <= '0';

		wait until bytes_read = 512 for 40000 * CLK_PERIOD;
		check("B1: all 512 bytes of the block were transferred to the host",
		      bytes_read = 512);
		check("B2: every byte matched the expected counting pattern",
		      read_data_ok);

		wait until busy_o = '0' for 5000 * CLK_PERIOD;
		check("B3: controller returns to idle (busy_o low) after the read completes",
		      busy_o = '0');
		check("B4: no error reported after the read", error_o = x"0000");

		report "==============================================";
		report "XESS CORE TB SUMMARY: " & integer'image(pass_count) & " passed, " &
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

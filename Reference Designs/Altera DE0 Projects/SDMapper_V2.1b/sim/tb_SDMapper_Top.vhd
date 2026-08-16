-- tb_SDMapper_Top.vhd
--
-- GHDL-only functional testbench for SDMapper_TOP (DE0 port,
-- Reference Designs/Altera DE0 Projects/SDMapper_V2.1b).
--
-- This testbench never touches the real DUT sources. It instantiates
-- SDMapper_TOP directly ("entity work.SDMapper_TOP") and relies on the
-- clock_25mhz_sim.vhd stand-in (see sim/clock_25mhz_sim.vhd) being analyzed
-- into the "work" library INSTEAD OF the real, Altera-PLL-based
-- clock_25mhz.vhd. Analyze order into a fresh work library (GHDL, --std=08
-- required for the std.env.stop call at the end; -fsynopsys required since
-- every DUT file uses ieee.std_logic_unsigned):
--   decoder_7seg.vhd, exp_slot.vhd, sdcard_xess.vhd, sdcard_bridge.vhd,
--   sim/clock_25mhz_sim.vhd, SDMapper_Top.vhd, sim/tb_SDMapper_Top.vhd
--
-- UPDATED (2026-08-12, XESS SD core pivot): CHECKS 1-5 predate the SD
-- protocol swap (spi.vhd/spi2.vhd -> sdcard_bridge.vhd wrapping a ported
-- XESS Corp SdCardCtrl core) and are unaffected by it - ROM/RAM sub-slot
-- and mapper I/O behavior are unchanged. CHECK 6+ is new: it drives the
-- real SD register window (0x7B00-7B08) through this same real-bus-timing
-- harness, including WAIT_n-extended reads of SD_DATA, against a mock SPI
-- SD card - the same isolated-core (tb_sdcard_xess.vhd) and isolated-
-- bridge (tb_sdcard_bridge.vhd) testbenches both already pass 7/7 driven
-- directly; this is the first check of the FULL chain including the
-- top-level's own address-capture FSM and D-bus arbitration, which real
-- hardware still hangs on even with both lower layers verified correct -
-- built specifically to find what the isolated testbenches can't see.
--
-- What is modeled:
--   - CLOCK_50: free-running 50MHz clock (20ns period).
--   - The A_MUX time-multiplexed address bus: the DUT drives U2OE_n/U3OE_n
--     to request the low or high address byte; this testbench plays the
--     role of the external level-shifter buffers (U2/U3) and the Z80's own
--     address bus, presenting msx_addr's low or high byte on A_MUX
--     according to whichever *_OE_n is currently asserted.
--   - FL_DQ: modeled as a trivial single-byte "Flash" (DE0's 16-bit chip in
--     8-bit byte mode - see SDMapper_Top.vhd's entity comment) - this
--     testbench drives a known test byte onto FL_DQ(7 downto 0) whenever
--     FL_CE_N/FL_OE_N are both asserted (mirrors a real Flash's
--     output-enable behavior), and leaves it high-Z otherwise. FL_DQ15_AM1
--     is driven by the DUT (it carries the ROM address's LSB in byte mode),
--     not modeled here since none of the checks below need it.
--   - SRAM_DQ is only 8 bits on this DE0 port (the SRAM addon board only
--     wires 8 physical GPIO data pins - see entity comment) but no check
--     below exercises the SRAM/mapper RAM path, so this doesn't affect the
--     checks either way.
--   - All other DUT inputs not exercised by the checks below (SD card
--     presence, etc.) are tied to inactive defaults, since the top-level
--     architecture never reads them.
--
-- Checks performed (see CHECK 1-5 below, all observed purely through
-- SDMapper_TOP's ports - no internal signal probing):
--   1) Address-bus capture handshake: U2OE_n (low byte) then U3OE_n (high
--      byte) each pulse low, in that order, once per bus cycle. (A brief
--      2026-08-12 experiment swapped this order to shave latency off
--      spi_cs_s - reverted after it caused a real-hardware hang; see
--      SDMapper_Top.vhd's address-capture process for the full story.)
--   2) Mapper segment register FC reads back its documented reset default
--      ("00011") via an I/O read cycle.
--   3) A CPU I/O write to port FC followed by an I/O read of the same port
--      reflects the newly written value (register write + readback path).
--   4) A CPU memory read from 0x4000 (ROM bank-1 window, bank register at
--      its post-reset value of 0; exp_slot's reset default routes every page
--      to sub-slot 0/ROM, so no FFFF write is needed for this to work)
--      returns the byte this testbench's Flash model drives on FL_DQ, with
--      FL_ADDR/FL_CE_N/BUSDIR_n/U1_DIR decoded as expected. U1_DIR expects
--      the CORRECTED polarity ('0' = drive toward MSX) - see
--      SDMapper_Top.vhd's header note on the real-hardware-confirmed fix.
--   5) Writing a new bank number to the bank-1 switch register (0x6000)
--      changes FL_ADDR on the next ROM read to reflect the new bank.
--      NOTE: FL_ADDR on this DE0 port carries s_rom_a(22 downto 1), not
--      s_rom_a(21 downto 0) as on DE1 - bit 0 goes out on FL_DQ15_AM1
--      instead (byte-mode addressing) - so expected FL_ADDR values are
--      s_rom_a's DE1-equivalent value shifted right by one bit.
--
-- NOT exercised by this testbench (still simulation-elaboration-clean per
-- the analyze step above, but functionally untested here): exp_slot
-- sub-slot switching via an FFFF write (the RAM sub-slot is never actually
-- selected), the RAM/mapper memory-space read/write path, and the SD card
-- SPI/status/timer register protocol (7B00-7EFF/7FF0/7FF1). Checks 2/3
-- (mapper I/O ports) and 5 (ROM bank-switch register) now go through an
-- 8-CLOCK_50-cycle glitch filter before a read/write is trusted (see
-- SDMapper_Top.vhd's s_io_mapper_*_qualified / s_cart_write_qualified) -
-- the do_io_read/do_io_write/do_mem_write procedures' settle waits were
-- extended accordingly.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_SDMapper_Top is
end entity;

architecture sim of tb_SDMapper_Top is

	-- ------------------------------------------------------------------
	-- DUT port signals
	-- ------------------------------------------------------------------
	signal CLOCK_50     : std_logic := '0';

	signal KEY          : std_logic_vector(2 downto 0) := (others => '1');	-- DE0 has only 3 buttons
	-- SW(0) = card-present (wired to the bridge's card_present_i), SW(9)='0'
	-- selects SDMapper mode. BUG FIX (2026-08-13): this was (others => '0'),
	-- so every SD test below ran with the bridge told "no card inserted" -
	-- harmless while the bridge ignored card_present_i for SD_DATA accesses,
	-- but it meant the mock-card tests never exercised the realistic wiring.
	-- The never-stall guard in sdcard_bridge.vhd (which correctly refuses to
	-- assert WAIT_n for an absent card) made this latent bug visible: all 512
	-- bytes came back 0xFF. SW(0) now reflects the card the mock model is
	-- actually emulating.
	signal SW           : std_logic_vector(9 downto 0) := (0 => '1', others => '0');

	signal HEX0, HEX1, HEX2, HEX3 : std_logic_vector(6 downto 0);
	signal LEDG         : std_logic_vector(9 downto 0);	-- DE0 has 10 green LEDs, no red ones

	-- DE0 onboard parallel Flash: 16-bit chip in 8-bit byte mode (see
	-- SDMapper_Top.vhd entity comment) - FL_DQ15_AM1 carries the byte-mode
	-- A-1 address bit, driven by the DUT, not modeled here.
	signal FL_DQ         : std_logic_vector(14 downto 0) := (others => 'Z');
	signal FL_DQ15_AM1   : std_logic := 'Z';
	signal FL_ADDR       : std_logic_vector(21 downto 0);
	signal FL_WE_N       : std_logic;
	signal FL_RST_N      : std_logic;
	signal FL_OE_N       : std_logic;
	signal FL_CE_N       : std_logic;
	signal FL_WP_N       : std_logic;
	signal FL_BYTE_N     : std_logic;

	-- DE0 SRAM addon board: only 8 physical GPIO data pins (see entity
	-- comment) - not exercised by any check below.
	signal SRAM_DQ       : std_logic_vector(7 downto 0);
	signal SRAM_ADDR     : std_logic_vector(17 downto 0);
	signal SRAM_UB_N     : std_logic;
	signal SRAM_LB_N     : std_logic;
	signal SRAM_WE_N     : std_logic;
	signal SRAM_CE_N     : std_logic;
	signal SRAM_OE_N     : std_logic;

	signal SD1_CS, SD1_SCK, SD1_MOSI : std_logic;
	signal SD1_MISO      : std_logic := '1';

	signal MSX_CLK       : std_logic := '0';
	signal A_MUX         : std_logic_vector(7 downto 0) := (others => '0');
	signal D             : std_logic_vector(7 downto 0) := (others => 'Z');
	signal RD_n          : std_logic := '1';
	signal WR_n          : std_logic := '1';
	signal MREQ_n        : std_logic := '1';
	signal IORQ_n        : std_logic := '1';
	signal SLTSL_n       : std_logic := '1';
	signal CS1_n         : std_logic := '1';
	signal BUSDIR_n      : std_logic;
	signal M1_n          : std_logic := '1';
	signal INT_n         : std_logic;
	signal WAIT_n        : std_logic;
	signal RESET_n       : std_logic := '0';
	signal SOUNDIN       : std_logic := '0';
	signal SOUNDOUT      : std_logic;
	signal CS2_RFSH_n    : std_logic := '1';
	signal U1_DIR        : std_logic;
	signal U1OE_n        : std_logic;
	signal U2OE_n        : std_logic;
	signal U3OE_n        : std_logic;
	signal U4OE_n        : std_logic;

	-- ------------------------------------------------------------------
	-- Testbench-side bus model
	-- ------------------------------------------------------------------

	-- Full 16-bit address the emulated Z80 is presenting this bus cycle.
	-- Mirrors what the real interface board's U2/U3 buffers would put on
	-- A_MUX, gated by the DUT's own U2OE_n/U3OE_n outputs.
	signal msx_addr      : std_logic_vector(15 downto 0) := (others => '0');

	constant CLK50_PERIOD : time := 20 ns; -- 50MHz

	-- NOTE: pass_count/fail_count are process-local variables (declared in
	-- the "stimulus" process below), not signals. Several checks below are
	-- called back-to-back with no "wait" between them (e.g. CHECK4a..4e);
	-- signal assignments only become visible on the next delta cycle, so a
	-- signal-based counter would silently net-increment by only 1 across a
	-- whole such group instead of once per call. Variables update immediately.
	procedure check(name : string; cond : boolean; variable p : inout integer; variable f : inout integer) is
	begin
		if cond then
			p := p + 1;
			report "PASS: " & name;
		else
			f := f + 1;
			report "FAIL: " & name severity error;
		end if;
	end procedure;

	-- ------------------------------------------------------------------
	-- Mock SD card model (identical behavior to tb_sdcard_xess.vhd/
	-- tb_sdcard_bridge.vhd - see tb_sdcard_xess.vhd for detailed comments),
	-- wired to the DUT's real SD1_CS/SD1_SCK/SD1_MOSI/SD1_MISO pins.
	-- ------------------------------------------------------------------
	signal mock_sclk_prev      : std_logic := '0';
	signal mock_cs_prev        : std_logic := '1';
	signal mock_rx_shift       : std_logic_vector(7 downto 0) := (others => '0');
	signal mock_rx_bit_cnt     : integer range 0 to 7 := 0;
	signal mock_frame_byte_idx : integer range 0 to 7 := 0;

	-- CHECK9 monitor: watches whether /WAIT is ever asserted while armed.
	-- (Port polarity: pre-inverted for the board's Q2 stage, so '1' = wait
	-- ASSERTED, '0' = idle.)
	signal mon_arm       : boolean := false;
	signal mon_wait_seen : boolean := false;
	signal mock_cmd_count      : integer := 0;

	signal mock_resp_byte    : std_logic_vector(7 downto 0) := x"FF";
	signal mock_resp_bit_cnt : integer range 0 to 7 := 0;
	signal mock_resp_active  : boolean := false;
	signal mock_resp_step    : integer := 0;

	constant MOCK_CMD17_NOTREADY_BYTES : integer := 3;
	signal mock_cmd17_data_byte : unsigned(7 downto 0) := (others => '0');

begin

	-- ------------------------------------------------------------------
	-- DUT instantiation
	-- ------------------------------------------------------------------
	dut : entity work.SDMapper_TOP
		port map (
			CLOCK_50     => CLOCK_50,
			KEY          => KEY,
			SW           => SW,
			HEX0         => HEX0,
			HEX1         => HEX1,
			HEX2         => HEX2,
			HEX3         => HEX3,
			LEDG         => LEDG,
			FL_DQ        => FL_DQ,
			FL_DQ15_AM1  => FL_DQ15_AM1,
			FL_ADDR      => FL_ADDR,
			FL_WE_N      => FL_WE_N,
			FL_RST_N     => FL_RST_N,
			FL_OE_N      => FL_OE_N,
			FL_CE_N      => FL_CE_N,
			FL_WP_N      => FL_WP_N,
			FL_BYTE_N    => FL_BYTE_N,
			SRAM_DQ      => SRAM_DQ,
			SRAM_ADDR    => SRAM_ADDR,
			SRAM_UB_N    => SRAM_UB_N,
			SRAM_LB_N    => SRAM_LB_N,
			SRAM_WE_N    => SRAM_WE_N,
			SRAM_CE_N    => SRAM_CE_N,
			SRAM_OE_N    => SRAM_OE_N,
			SD1_CS       => SD1_CS,
			SD1_SCK      => SD1_SCK,
			SD1_MOSI     => SD1_MOSI,
			SD1_MISO     => SD1_MISO,
			MSX_CLK      => MSX_CLK,
			A_MUX        => A_MUX,
			D            => D,
			RD_n         => RD_n,
			WR_n         => WR_n,
			MREQ_n       => MREQ_n,
			IORQ_n       => IORQ_n,
			SLTSL_n      => SLTSL_n,
			CS1_n        => CS1_n,
			BUSDIR_n     => BUSDIR_n,
			M1_n         => M1_n,
			INT_n        => INT_n,
			WAIT_n       => WAIT_n,
			RESET_n      => RESET_n,
			SOUNDIN      => SOUNDIN,
			SOUNDOUT     => SOUNDOUT,
			CS2_RFSH_n   => CS2_RFSH_n,
			U1_DIR       => U1_DIR,
			U1OE_n       => U1OE_n,
			U2OE_n       => U2OE_n,
			U3OE_n       => U3OE_n,
			U4OE_n       => U4OE_n
		);

	-- ------------------------------------------------------------------
	-- CLOCK_50 generator
	-- ------------------------------------------------------------------
	CLOCK_50 <= not CLOCK_50 after CLK50_PERIOD / 2;

	-- ------------------------------------------------------------------
	-- A_MUX bus model: plays the role of the U2/U3 level-shifter buffers.
	-- Whichever *_OE_n the DUT asserts selects which half of msx_addr is
	-- driven onto the shared A_MUX pins.
	-- ------------------------------------------------------------------
	A_MUX <= msx_addr(7 downto 0)  when U2OE_n = '0' else
	         msx_addr(15 downto 8) when U3OE_n = '0' else
	         (others => '0');

	-- ------------------------------------------------------------------
	-- FL_DQ Flash model: a single fixed test byte on the low 8 bits, driven
	-- only while the DUT asserts both FL_CE_N and FL_OE_N (mirrors a real
	-- Flash chip's output-enable gating), high-Z otherwise. The upper 7
	-- bits of this 15-bit byte-mode data bus are unused by any check below.
	-- ------------------------------------------------------------------
	FL_DQ <= "0000000" & x"A5" when (FL_CE_N = '0' and FL_OE_N = '0') else (others => 'Z');

	-- ------------------------------------------------------------------
	-- SRAM model (added 2026-08-13): a fixed test byte, driven only while
	-- the DUT genuinely selects the chip for a read - same output-enable
	-- gating as the Flash model above, high-Z otherwise.
	--
	-- There was NO SRAM model before, so the mapper-RAM read path was never
	-- actually exercised by this testbench - which is exactly how the D-bus
	-- mux bug (ROM selected in the mux for pages 0/2/3 where the Flash is
	-- deselected and NOT driving, beating the RAM entry on priority) survived
	-- undetected in simulation while breaking real hardware. The byte is
	-- deliberately different from the Flash model's 0xA5 so the two sources
	-- can never be confused by a check.
	-- ------------------------------------------------------------------
	SRAM_DQ <= x"3C" when (SRAM_CE_N = '0' and SRAM_OE_N = '0') else (others => 'Z');

	-- ------------------------------------------------------------------
	-- Mock SD card: receives command bytes off SD1_MOSI (MSB-first,
	-- sampled on SD1_SCK rising edge, mode 0), tracks how many 6-byte
	-- command frames have gone by, and drives SD1_MISO accordingly on
	-- SD1_SCK falling edges. Resyncs on SD1_CS falling edge (see
	-- tb_sdcard_xess.vhd for why that's needed). Responds to CMD0/CMD8/
	-- CMD55/CMD41/CMD17 - the same init+first-read sequence both lower
	-- testbenches already verified in isolation.
	-- ------------------------------------------------------------------
	process(CLOCK_50)
		variable new_byte_v : std_logic_vector(7 downto 0);
	begin
		if rising_edge(CLOCK_50) then
			mock_sclk_prev <= SD1_SCK;
			mock_cs_prev   <= SD1_CS;

			if mock_cs_prev = '1' and SD1_CS = '0' then
				mock_rx_bit_cnt     <= 0;
				mock_frame_byte_idx <= 0;
				mock_resp_bit_cnt   <= 7;
			end if;

			if mock_sclk_prev = '0' and SD1_SCK = '1' then
				new_byte_v    := mock_rx_shift(6 downto 0) & SD1_MOSI;
				mock_rx_shift <= new_byte_v;
				if mock_rx_bit_cnt = 7 then
					mock_rx_bit_cnt <= 0;
					if mock_frame_byte_idx = 0 and new_byte_v(7 downto 6) = "01" then
						mock_frame_byte_idx <= 1;
					elsif mock_frame_byte_idx > 0 and mock_frame_byte_idx < 5 then
						mock_frame_byte_idx <= mock_frame_byte_idx + 1;
					elsif mock_frame_byte_idx = 5 then
						mock_frame_byte_idx <= 0;
						mock_cmd_count      <= mock_cmd_count + 1;
						mock_resp_active    <= true;
						mock_resp_step      <= 0;
					end if;
				else
					mock_rx_bit_cnt <= mock_rx_bit_cnt + 1;
				end if;
			end if;

			if mock_sclk_prev = '1' and SD1_SCK = '0' then
				if mock_resp_bit_cnt = 0 then
					mock_resp_bit_cnt <= 7;
				else
					mock_resp_bit_cnt <= mock_resp_bit_cnt - 1;
				end if;
				if mock_resp_bit_cnt = 0 and mock_resp_active then
					case mock_cmd_count is
						when 1 =>
							mock_resp_byte   <= x"01";
							mock_resp_active <= false;
						when 2 =>
							case mock_resp_step is
								when 0 => mock_resp_byte <= x"01"; mock_resp_step <= 1;
								when 1 => mock_resp_byte <= x"00"; mock_resp_step <= 2;
								when 2 => mock_resp_byte <= x"00"; mock_resp_step <= 3;
								when 3 => mock_resp_byte <= x"01"; mock_resp_step <= 4;
								when others =>
									mock_resp_byte   <= x"AA";
									mock_resp_active <= false;
							end case;
						when 3 =>
							mock_resp_byte   <= x"01";
							mock_resp_active <= false;
						when 4 =>
							mock_resp_byte   <= x"00";
							mock_resp_active <= false;
						when 5 =>
							if mock_resp_step = 0 then
								mock_resp_byte <= x"00";
								mock_resp_step <= 1;
							elsif mock_resp_step <= MOCK_CMD17_NOTREADY_BYTES then
								mock_resp_byte <= x"FF";
								mock_resp_step <= mock_resp_step + 1;
							elsif mock_resp_step = MOCK_CMD17_NOTREADY_BYTES + 1 then
								mock_resp_byte        <= x"FE";
								mock_resp_step         <= mock_resp_step + 1;
								mock_cmd17_data_byte   <= (others => '0');
							elsif mock_resp_step <= MOCK_CMD17_NOTREADY_BYTES + 1 + 512 then
								mock_resp_byte       <= std_logic_vector(mock_cmd17_data_byte);
								mock_cmd17_data_byte <= mock_cmd17_data_byte + 1;
								mock_resp_step       <= mock_resp_step + 1;
							elsif mock_resp_step <= MOCK_CMD17_NOTREADY_BYTES + 1 + 512 + 2 then
								mock_resp_byte <= x"AA";
								mock_resp_step <= mock_resp_step + 1;
								if mock_resp_step = MOCK_CMD17_NOTREADY_BYTES + 1 + 512 + 2 then
									mock_resp_active <= false;
								end if;
							end if;
						when others =>
							mock_resp_byte <= x"FF";
					end case;
				elsif mock_resp_bit_cnt = 0 and not mock_resp_active then
					mock_resp_byte <= x"FF";
				end if;
			end if;
		end if;
	end process;

	SD1_MISO <= mock_resp_byte(mock_resp_bit_cnt);

	-- ------------------------------------------------------------------
	-- Main stimulus / checks process
	-- ------------------------------------------------------------------
	-- Records any /WAIT assertion during the armed window. Used by CHECK9 to
	-- prove the card's latency never reaches the bus during a real block read.
	wait_monitor : process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if mon_arm and WAIT_n = '1' then
				mon_wait_seen <= true;
			end if;
		end if;
	end process;

	stimulus : process
		variable pass_count : integer := 0;
		variable fail_count : integer := 0;

		-- Used only by CHECK6c's SD_DATA read loop.
		variable sd_byte_v  : std_logic_vector(7 downto 0);
		variable sd_data_ok : boolean := true;
		variable sd_expect  : unsigned(7 downto 0) := (others => '0');

		-- Used only by CHECK9's ready-bit polling.
		variable sd_ready_ok : boolean := false;

		-- Drives a full MSX bus cycle: sets up msx_addr, pulses the
		-- request strobes long enough for the DUT's address-capture state
		-- machine (5 CLOCK_50 cycles) plus its downstream synchronizers
		-- (3 more CLOCK_50 cycles) to settle, then releases the cycle.
		-- NOTE: the mapper I/O ports (FC-FF) now go through an 8-CLOCK_50-cycle
		-- glitch filter (MIN_PULSE_CYCLES) before a read/write is trusted -
		-- see SDMapper_Top.vhd's s_io_mapper_rd_qualified/wr_qualified. The
		-- settle wait below must cover: address-capture latency (~5 cycles)
		-- PLUS the 8-cycle qualification window, with margin.
		procedure do_io_read(addr : std_logic_vector(15 downto 0)) is
		begin
			msx_addr <= addr;
			wait until rising_edge(CLOCK_50);
			IORQ_n <= '0';
			M1_n   <= '1';
			wait for 4 * CLK50_PERIOD;   -- let address-capture reach S_GUARD/S_HIGH_*
			RD_n <= '0';
			wait for 20 * CLK50_PERIOD;  -- settle s_A, then clear the 8-cycle mapper-read glitch filter
		end procedure;

		procedure end_io_cycle is
		begin
			RD_n   <= '1';
			IORQ_n <= '1';
			wait for 4 * CLK50_PERIOD;   -- let the falling-edge synchronizers clear
		end procedure;

		procedure do_io_write(addr : std_logic_vector(15 downto 0); data : std_logic_vector(7 downto 0)) is
		begin
			msx_addr <= addr;
			D        <= data;
			wait until rising_edge(CLOCK_50);
			IORQ_n <= '0';
			M1_n   <= '1';
			wait for 4 * CLK50_PERIOD;
			WR_n <= '0';
			wait for 20 * CLK50_PERIOD;  -- s_A settles, then clear the 8-cycle mapper-write glitch filter (register must see qualified='1' BEFORE WR_n rises)
			WR_n <= '1';
			IORQ_n <= '1';
			wait for 4 * CLK50_PERIOD;
			D <= (others => 'Z');
		end procedure;

		procedure do_mem_read(addr : std_logic_vector(15 downto 0)) is
		begin
			msx_addr <= addr;
			wait until rising_edge(CLOCK_50);
			MREQ_n  <= '0';
			SLTSL_n <= '0';
			M1_n    <= '1';
			wait for 4 * CLK50_PERIOD;
			RD_n <= '0';
			wait for 6 * CLK50_PERIOD;
		end procedure;

		procedure end_mem_cycle is
		begin
			RD_n    <= '1';
			MREQ_n  <= '1';
			SLTSL_n <= '1';
			wait for 4 * CLK50_PERIOD;
		end procedure;

		-- NOTE: the ROM bank-switch register (and the SD card slot-select
		-- register, both driven by i_ROM_Banks) now go through the same
		-- 8-CLOCK_50-cycle glitch filter as the mapper I/O ports
		-- (s_cart_write_qualified), continuously re-latching D while
		-- qualified rather than sampling once on a delayed edge. s_A must
		-- already be fully captured (~7 CLOCK_50 cycles after the
		-- address-capture trigger) BEFORE WR_n goes low, or the write will
		-- be evaluated against a stale/incomplete address; WR_n must then
		-- stay low long enough to clear the 8-cycle qualifier before rising.
		procedure do_mem_write(addr : std_logic_vector(15 downto 0); data : std_logic_vector(7 downto 0)) is
		begin
			msx_addr <= addr;
			D        <= data;
			wait until rising_edge(CLOCK_50);
			MREQ_n  <= '0';
			SLTSL_n <= '0';
			M1_n    <= '1';
			wait for 8 * CLK50_PERIOD;   -- let address-capture state machine fully latch s_A first
			WR_n <= '0';
			wait for 20 * CLK50_PERIOD;  -- clear the 8-cycle cart-write glitch filter before releasing WR_n
			WR_n    <= '1';
			MREQ_n  <= '1';
			SLTSL_n <= '1';
			wait for 4 * CLK50_PERIOD;
			D <= (others => 'Z');
		end procedure;

		-- WAIT_n-extended memory read - models a real Z80 bus cycle under
		-- hardware WAIT stall: asserts the read exactly like do_mem_read,
		-- but then holds RD_n/SLTSL_n/MREQ_n asserted until WAIT_n
		-- deasserts (bounded by a generous timeout) before sampling D,
		-- instead of a fixed short settle delay. Needed for SD_DATA reads,
		-- the only WAIT_n-gated register in this design (see
		-- sdcard_bridge.vhd) - do_mem_read's fixed 6-cycle settle is
		-- nowhere near enough for a real handshake-gated access.
		procedure do_mem_read_wait(addr : std_logic_vector(15 downto 0); result : out std_logic_vector(7 downto 0)) is
		begin
			msx_addr <= addr;
			wait until rising_edge(CLOCK_50);
			MREQ_n  <= '0';
			SLTSL_n <= '0';
			M1_n    <= '1';
			wait for 4 * CLK50_PERIOD;
			RD_n <= '0';
			-- Let the top-level address-capture FSM finish (s_addr_valid) AND
			-- give /WAIT a chance to assert, before either testing the stall or
			-- sampling D.
			--
			-- UPDATED (2026-08-15): this was 2 cycles (40ns). That only ever
			-- worked because the old design always stalled, so the subsequent
			-- "wait until WAIT_n" pushed sampling far past address capture.
			-- With the bridge prefetching there is normally no stall at all,
			-- and sampling 40ns in landed BEFORE s_addr_valid asserted - cs_i
			-- was still low, nothing drove D, and every byte read as 'Z'. A
			-- real Z80 latches D at the end of T3, ~840ns into the cycle; this
			-- is nowhere near that tight.
			wait for 10 * CLK50_PERIOD;
			-- Bridge-level tb_sdcard_bridge.vhd measured ~823 CLOCK_50-
			-- equivalent cycles per successfully-completed byte - 8000
			-- gives ~10x margin without letting a genuine hang burn
			-- excessive simulated (and real) time across all 512 bytes.
			--
			-- POLARITY (2026-08-12, root cause of the CHECK6c "got=ZZ /
			-- stale byte" failures): SDMapper_Top.WAIT_n is NOT the real
			-- MSX bus level - it is the FPGA's raw pin, deliberately
			-- pre-inverted (`WAIT_n <= not s_sdbridge_wait_n_o;`) to
			-- compensate for the board's Q2 open-collector inverter stage
			-- between the FPGA and the real bus. This testbench wires
			-- WAIT_n straight to the DUT port with no Q2 model, so it sees
			-- the inverted level: idle = '0', wait-asserted = '1'. Waiting
			-- for '1' was catching the IDLE->BUSY edge (the wait being
			-- asserted), not its release, so the CPU model released RD_n
			-- almost immediately instead of waiting for the real transfer.
			-- "wait until" only wakes on a TRANSITION. With the bridge prefetching,
		-- the normal case is that no stall ever happens and WAIT_n is ALREADY
		-- at its idle level - waiting unconditionally then burned the full
		-- timeout on every single byte (~160us each, 83ms for one sector).
		-- Test the level first and only wait when genuinely stalled.
		if WAIT_n = '1' then
			wait until WAIT_n = '0' for 8000 * CLK50_PERIOD;
		end if;
			wait for 2 * CLK50_PERIOD;   -- settle after WAIT_n releases, before sampling D
			result := D;
			RD_n    <= '1';
			MREQ_n  <= '1';
			SLTSL_n <= '1';
			-- Widened from 4 to 40 cycles (2026-08-12, found via CHECK6c
			-- debug trace: byte i=1 came back identical to byte i=0 - a
			-- stale read, not corrupted data). Root cause: 4 CLK50_PERIOD
			-- (80ns) is far shorter than the bridge's own 3-stage clock_i
			-- (40ns period) cs_i synchronizer needs to fully propagate a
			-- LOW value through all 3 stages before the NEXT access's
			-- rising edge can be correctly detected - too short a gap
			-- meant the second read's cs_rising_pulse silently never
			-- fired, so wait_n_s never dropped, and "wait until WAIT_n='1'
			-- for ..." (which only wakes on an EVENT, not on an
			-- already-true condition) just sat out the full timeout
			-- without ever seeing a fresh transfer happen. A real Z80
			-- driver loop has several full instructions (each several
			-- ~280ns T-states) between successive SD_DATA reads - this
			-- testbench's tight back-to-back timing was unrealistic
			-- compared to that, not a real hardware bug.
			wait for 40 * CLK50_PERIOD;
		end procedure;

	begin
		-- ----------------------------------------------------------------
		-- Reset
		-- ----------------------------------------------------------------
		KEY(0)  <= '0';   -- hold local reset
		RESET_n <= '1';
		-- Held long enough to pass the reset noise filter in SDMapper_Top.vhd
		-- (128 clocks): a real reset lasts milliseconds, so this is still
		-- vastly shorter than hardware, but it must clear the filter.
		wait for 200 * CLK50_PERIOD;
		KEY(0) <= '1';    -- release reset
		wait for 10 * CLK50_PERIOD;

		-- Board configuration used by every check below: SDMapper mode
		-- (SW(9)='0' - see SDMapper_Top.vhd header; this alone gates ROM,
		-- RAM/mapper, and SD - SW(8) is unused/free).
		--
		-- SW(0)='1' = card present (wired to the bridge's card_present_i).
		-- BUG FIX (2026-08-13): this used to force SW(7 downto 0) to all
		-- zeros, i.e. "no card inserted", while the SD checks below happily
		-- exercised a fully-responding mock card - a contradiction that only
		-- went unnoticed because nothing depended on card_present_i and
		-- CHECK6b's assertion never actually tested the present bit. The
		-- never-stall guard in sdcard_bridge.vhd does depend on it (it
		-- refuses to assert WAIT_n for a card that cannot answer), so the
		-- stimulus now has to describe the board honestly.
		SW(9) <= '0';
		SW(8) <= '0';
		SW(6 downto 1) <= (others => '0');
		-- SW(7)='1' = drive the mapper port read-back. CHECK2/CHECK3 below
		-- specifically exercise that path, so they need it enabled. On real
		-- hardware SW(7) is normally '0' (see the BUS CONTENTION FIX note in
		-- SDMapper_Top.vhd: a machine with its own internal mapper - any 64KB+
		-- MSX2, e.g. the Canon V-25 - already answers those reads, and two
		-- devices driving D corrupts whatever the BIOS reads back).
		SW(7) <= '1';
		SW(0) <= '1';		-- card present, matching the mock SD card model below
		wait for 2 * CLK50_PERIOD;

		-- ----------------------------------------------------------------
		-- CHECK 1: address-mux handshake - U2OE_n pulses low before U3OE_n
		-- does, once per bus cycle (observed on the very first I/O read).
		-- ----------------------------------------------------------------
		msx_addr <= x"00FC";
		wait until rising_edge(CLOCK_50);
		IORQ_n <= '0';
		M1_n   <= '1';

		wait until falling_edge(U2OE_n) for 10 * CLK50_PERIOD;
		check("CHECK1a: U2OE_n asserted (low byte enable) after bus-cycle trigger",
		      U2OE_n = '0', pass_count, fail_count);

		wait until rising_edge(U2OE_n) for 10 * CLK50_PERIOD;
		wait until falling_edge(U3OE_n) for 10 * CLK50_PERIOD;
		check("CHECK1b: U3OE_n asserted (high byte enable) after U2OE_n released",
		      U3OE_n = '0', pass_count, fail_count);

		wait until rising_edge(U2OE_n) for 10 * CLK50_PERIOD;
		check("CHECK1c: both U2OE_n/U3OE_n released (idle) once capture completes",
		      U2OE_n = '1' and U3OE_n = '1', pass_count, fail_count);

		RD_n <= '0';
		wait for 20 * CLK50_PERIOD;  -- clear the 8-cycle mapper-read glitch filter (see do_io_read note above)

		-- ----------------------------------------------------------------
		-- CHECK 2: mapper segment register FC reads back its reset default
		-- ("00011") as D = "111" & "00011" = x"E3".
		--
		-- UPDATED (2026-08-16): was 0xE3 ("111" & "00011"), i.e. a 5-bit /
		-- 32-segment / 512KB mapper. This board only wires 8 of the SRAM's 16
		-- data lines, so segments 16-31 selected an unwired byte lane and
		-- silently lost data - see the MAPPER SIZE FIX note in
		-- SDMapper_Top.vhd. The mapper is now 4-bit / 16 segments / 256KB, and
		-- the unimplemented high bits read back as 1s, which is how MSX-DOS
		-- sizes a mapper.
		-- ----------------------------------------------------------------
		check("CHECK2: mapper port FC reset default reads back as 0xE3 (32 segments)",
		      D = x"E3", pass_count, fail_count);

		end_io_cycle;

		-- ----------------------------------------------------------------
		-- CHECK 3: I/O write a new value to port FC, then read it back.
		-- ----------------------------------------------------------------
		do_io_write(x"00FC", "11010101");  -- s_fc <= D(4 downto 0) = "10101"
		wait for 2 * CLK50_PERIOD;

		do_io_read(x"00FC");
		check("CHECK3: mapper port FC readback reflects newly written value (0xF5)",
		      D = x"F5", pass_count, fail_count);   -- "111" & "10101" = xF5
		end_io_cycle;

		-- ----------------------------------------------------------------
		-- CHECK 4: ROM read at 0x4000 (bank-1 window, bank register at its
		-- post-reset value of 0) returns the Flash model's test byte, with
		-- FL_ADDR/FL_CE_N/BUSDIR_n/U1_DIR decoded as expected.
		-- ----------------------------------------------------------------
		do_mem_read(x"4000");
		check("CHECK4a: ROM read at 0x4000 returns Flash model byte 0xA5",
		      D = x"A5", pass_count, fail_count);
		check("CHECK4b: FL_ADDR decodes to bank 0 offset (0x000000) for 0x4000",
		      FL_ADDR = "00" & x"00000", pass_count, fail_count);   -- s_rom_a=0, so the byte-mode right-shift doesn't change this case
		check("CHECK4c: FL_CE_N asserted low during the ROM read",
		      FL_CE_N = '0', pass_count, fail_count);
		check("CHECK4d: BUSDIR_n stays inactive (high) for an ordinary memory read",
		      BUSDIR_n = '1', pass_count, fail_count);
		-- CORRECTED polarity (2026-08-11, see SDMapper_Top.vhd header note):
		-- U1_DIR='0' drives toward the MSX bus, '1' listens - the opposite
		-- of what this testbench originally assumed, per MegaROM_ASCII16's
		-- real-hardware-confirmed U1_DIR polarity fix.
		check("CHECK4e: U1_DIR drives towards the MSX bus during the ROM read",
		      U1_DIR = '0', pass_count, fail_count);
		end_mem_cycle;

		-- ----------------------------------------------------------------
		-- CHECK 5: switch ROM bank 1 to bank 5 via the 0x6000 bank-switch
		-- register, then confirm FL_ADDR reflects the new bank on the next
		-- ROM read at 0x4000 (expected offset = 5 * 0x4000 = 0x014000).
		-- ----------------------------------------------------------------
		do_mem_write(x"6000", "00000101");
		wait for 2 * CLK50_PERIOD;

		do_mem_read(x"4000");
		-- DE1 equivalent would be s_rom_a=0x014000; on this DE0 port FL_ADDR
		-- carries s_rom_a(22 downto 1), i.e. that value right-shifted by 1
		-- bit (0x014000 >> 1 = 0x00A000) - see file header note.
		check("CHECK5: FL_ADDR reflects new ROM bank 5 (0x00A000, byte-mode-shifted) after bank switch",
		      FL_ADDR = "00" & x"0A000", pass_count, fail_count);
		check("CHECK5b: FL_DQ15_AM1 carries the address LSB dropped by the byte-mode shift (0 for this bank)",
		      FL_DQ15_AM1 = '0', pass_count, fail_count);
		end_mem_cycle;

		-- ----------------------------------------------------------------
		-- CHECK 6: SD register window (0x7B00-7B08), reached through the
		-- REAL top-level address-capture FSM and D-bus arbitration - the
		-- first check of the full chain both tb_sdcard_xess.vhd (core
		-- alone) and tb_sdcard_bridge.vhd (bridge alone, driven directly)
		-- already pass 7/7 for, but real hardware still fails on even with
		-- both those layers verified. Switch bank 1 to segment 7 first
		-- (0x6000 bank-switch register) to reach the SD window, matching
		-- the same convention the real driver uses.
		-- ----------------------------------------------------------------
		do_mem_write(x"6000", "00000111");
		wait for 2 * CLK50_PERIOD;

		report "==== Waiting for SdCardCtrl init (through the real top-level) ====";
		wait until mock_cmd_count = 4 for 100000 * CLK50_PERIOD;
		check("CHECK6a: all 4 init commands reached the mock card via the real SD1_* pins",
		      mock_cmd_count = 4, pass_count, fail_count);
		wait for 2000 * CLK50_PERIOD;   -- let SdCardCtrl's busy_o actually drop after ACMD41 completes

		report "==== SD_STATUS poll (0x7B06), exactly like driver.mac's DRV_INIT ====";
		do_mem_read(x"7B06");
		-- BUG FIX (2026-08-13): this claimed to check "present" but only ever
		-- asserted D(0)/D(1) - the present bit D(2) went unchecked, so it
		-- passed happily even though SW(0) (card_present_i) was stuck '0'.
		-- Now actually verifies what the message says: bit0=busy, bit1=error,
		-- bit2=present.
		check("CHECK6b: SD_STATUS reports not busy, present, no error",
		      D(0) = '0' and D(1) = '0' and D(2) = '1', pass_count, fail_count);
		end_mem_cycle;

		report "==== DEV_RW-style single-block read (sector 0) through the real bus ====";
		do_mem_write(x"7B01", x"00");   -- SD_ADDR0
		do_mem_write(x"7B02", x"00");   -- SD_ADDR1
		do_mem_write(x"7B03", x"00");   -- SD_ADDR2
		do_mem_write(x"7B04", x"00");   -- SD_ADDR3
		do_mem_write(x"7B05", x"01");   -- SD_CMD = SD_CMD_READ

		-- UPDATED (2026-08-15): poll SD_STATUS bit5 before touching SD_DATA,
		-- exactly like driver.mac's SD_WAIT_READY. The card's start-token
		-- latency must never be taken as a bus stall - see the DECOUPLING note
		-- in sdcard_bridge.vhd (a multi-millisecond /WAIT halts Z80 refresh and
		-- corrupts MSX main DRAM). Reading SD_DATA straight after the command,
		-- as this loop used to, is precisely the pattern that is now illegal.
		sd_ready_ok := false;
		for i in 0 to 2000 loop
			do_mem_read(x"7B06");
			if D(5) = '1' then
				sd_ready_ok := true;
			end if;
			end_mem_cycle;
			exit when sd_ready_ok;
			wait for 20 * CLK50_PERIOD;
		end loop;
		check("CHECK6c0: SD_DATA ready bit rises before the block is read", sd_ready_ok, pass_count, fail_count);

		mon_arm <= true;
		for i in 0 to 511 loop
			do_mem_read_wait(x"7B00", sd_byte_v);
			if sd_byte_v /= std_logic_vector(sd_expect) then
				report "DEBUG: mismatch at byte i=" & integer'image(i) &
				       " expected=" & to_hstring(std_logic_vector(sd_expect)) &
				       " got=" & to_hstring(sd_byte_v);
				sd_data_ok := false;
			end if;
			sd_expect := sd_expect + 1;
		end loop;
		mon_arm <= false;
		wait for 2 * CLK50_PERIOD;
		check("CHECK6c: all 512 bytes read via the real bus match the expected pattern", sd_data_ok, pass_count, fail_count);

		do_mem_read(x"7B06");
		check("CHECK6d: SD_STATUS shows no error/timeout after the read (bit1=error, bit4=timeout)",
		      D(1) = '0' and D(4) = '0', pass_count, fail_count);
		end_mem_cycle;

		-- ----------------------------------------------------------------
		-- CHECK7: the address-capture chimera (regression test for the
		-- SD+mapper hang found on real hardware 2026-08-13)
		--
		-- s_A's low byte is captured 3 cycles before its high byte, so
		-- mid-capture s_A = <new low byte> & <PREVIOUS cycle's high byte>.
		-- This reproduces the exact killer sequence from DEV_RW's inner loop:
		-- an SD_DATA access at 0x7B00 (leaving 0x7B in the high-byte latch)
		-- immediately followed by a mapper-RAM write to 0xC100 - whose low
		-- byte 0x00 transiently pairs with the stale 0x7B to form 0x7B00,
		-- i.e. SD_DATA, with WR_n asserted. Before the s_addr_valid gate the
		-- bridge treated that chimera as a genuine SD write access: it
		-- asserted WAIT_n and started a transfer nobody requested, hanging
		-- the machine on the first boot-sector read (sector buffers are
		-- 512-byte aligned, so low bytes 0x00-0x08 are always walked).
		--
		-- Passing means: no WAIT_n stall is produced by the RAM write, and
		-- the SD bridge reports no error/timeout from a spurious transfer.
		-- ----------------------------------------------------------------
		report "==== CHECK7: mapper write aliasing into the SD window (chimera regression) ====";
		do_mem_read(x"7B00");   -- leaves 0x7B in the high-byte latch
		end_mem_cycle;
		wait for 4 * CLK50_PERIOD;

		-- Write to 0xC100: low byte 0x00 transiently pairs with stale 0x7B.
		do_mem_write(x"C100", x"5A");
		wait for 4 * CLK50_PERIOD;

		-- WAIT_n must never have been asserted by that write. Note the
		-- polarity: this port is pre-inverted for the board's Q2 stage, so
		-- '0' here is the idle (not-waiting) level - see do_mem_read_wait.
		check("CHECK7a: mapper-RAM write aliasing SD_DATA does not assert WAIT_n",
		      WAIT_n = '0', pass_count, fail_count);

		do_mem_read(x"7B06");
		check("CHECK7b: SD_STATUS shows no error/timeout after the aliasing write",
		      D(1) = '0' and D(4) = '0', pass_count, fail_count);
		end_mem_cycle;

		-- ----------------------------------------------------------------
		-- CHECK8: mapper-RAM read in a page where the Flash is deselected
		-- (regression test for the D-bus mux priority bug, real hardware
		-- 2026-08-13 - config 000 unstable while 010 was clean).
		--
		-- Page 2 (0x8000-0xBFFF) with the reset-default subslot 0 selected:
		-- s_sltsl_rom_en AND s_sltsl_ram_en are BOTH true (the RAM enable is
		-- deliberately unconditional for pages 0/2/3), but the Flash is NOT
		-- driving here because rom_bank2_q < 8, so FL_CE_N stays high. The mux
		-- used to pick FL_DQ anyway on an unrestricted "rom_en and RD_n=0"
		-- term, handing the MSX floating garbage instead of the SRAM byte on
		-- every cart mapper-RAM read. Expect the SRAM model's 0x3C, and
		-- specifically NOT the Flash model's 0xA5 or high-Z.
		-- ----------------------------------------------------------------
		report "==== CHECK8: mapper-RAM read where Flash is deselected (mux priority regression) ====";
		-- SW(6)='1' selects the LEGACY unconditional-RAM mode. That is the only
		-- mode in which s_sltsl_rom_en and s_sltsl_ram_en can both be true for
		-- the same access, which is exactly the hazard this check exists to
		-- catch (ROM winning the D-mux while the Flash is deselected and not
		-- driving). In the STANDARD mode (SW(6)='0', the real-hardware default
		-- since 2026-08-15) the two are mutually exclusive by construction and
		-- the hazard cannot arise at all.
		SW(6) <= '1';
		wait for 4 * CLK50_PERIOD;
		do_mem_read(x"8000");
		check("CHECK8a: page-2 RAM read returns the SRAM byte, not floating Flash",
		      D = x"3C", pass_count, fail_count);
		check("CHECK8b: Flash is genuinely deselected for that read (FL_CE_N high)",
		      FL_CE_N = '1', pass_count, fail_count);
		end_mem_cycle;
		SW(6) <= '0';		-- back to standard subslot-compliant behaviour
		wait for 4 * CLK50_PERIOD;

		-- ----------------------------------------------------------------
		-- CHECK9: the card's start-token latency must NEVER land on the bus
		-- (regression test for the DRAM-refresh corruption seen on real
		-- hardware, 2026-08-15).
		--
		-- This check replaces an earlier "/WAIT must assert within 100ns"
		-- test. That test encoded the OLD design, where the CPU access itself
		-- waited for the card and the only question was whether the stall
		-- arrived in time for the Z80's T2 sampling point. It is obsolete by
		-- construction now: with the bridge prefetching, a correct design
		-- asserts /WAIT rarely, and ideally never.
		--
		-- Why this matters more than latency: on MSX the Z80's refresh cycles
		-- refresh main DRAM, so a frozen CPU means no refresh, and DRAM only
		-- retains ~2-4ms. The first byte after CMD17 can take MILLISECONDS,
		-- so stalling for it corrupts main memory outright - observed as a
		-- corrupted boot logo, RAM detected as 8KB instead of 32KB, and
		-- random restarts.
		--
		-- The invariant is therefore: after issuing a read command, the CPU
		-- must be able to poll SD_STATUS bit5 freely (no stall), and once
		-- that bit is set the SD_DATA read must complete WITHOUT asserting
		-- /WAIT at all - the byte is already there.
		-- NOTE ON POLARITY: this DUT port is pre-inverted for the board's Q2
		-- open-collector stage, so '1' = wait ASSERTED, '0' = idle.
		-- ----------------------------------------------------------------
		report "==== CHECK9: start-token latency stays off the bus (no /WAIT stall) ====";
		-- Asserted over CHECK6c's real 512-byte block read (see the wait_monitor
		-- process), rather than by issuing a second block: the mock card only
		-- serves one CMD17, and this is the stronger statement anyway - across
		-- an entire genuine sector transfer the CPU was never stalled once.
		check("CHECK9: /WAIT never asserted during the whole 512-byte block read",
		      not mon_wait_seen, pass_count, fail_count);

		-- ----------------------------------------------------------------
		-- CHECK10: 0xFFFF (subslot register) must not touch mapper RAM
		-- (regression test for the real-hardware hang right after NEXTOR.SYS
		-- loads and the kernel starts running from mapper RAM, 2026-08-15).
		--
		-- In a real expanded slot 0xFFFF IS the subslot-select register and the
		-- RAM byte behind it is inaccessible. s_sltsl_ram_en is unconditional
		-- for pages 0/2/3, so a write to 0xFFFF used to assert SRAM_WE_N as
		-- well and destroy one byte of the currently-mapped segment. Nextor
		-- writes 0xFFFF on every inter-slot call, so once its kernel lived in
		-- mapper RAM it was steadily corrupting its own memory.
		-- ----------------------------------------------------------------
		-- NOTE: the SRAM strobes must be sampled DURING the write cycle, while
		-- SLTSL_n/WR_n are still asserted. A first version of this check called
		-- do_mem_write() and then sampled, by which time SLTSL_n was already
		-- high and SRAM_WE_N was trivially '1' - it passed even with the bug
		-- deliberately reinstated, i.e. it tested nothing. The cycle is driven
		-- inline here so the sample lands in the middle of it.
		report "==== CHECK10: 0xFFFF subslot write must not reach the SRAM ====";
		msx_addr <= x"FFFF";
		D        <= x"80";
		wait until rising_edge(CLOCK_50);
		MREQ_n  <= '0';
		SLTSL_n <= '0';
		M1_n    <= '1';
		wait for 8 * CLK50_PERIOD;   -- let the address-capture FSM latch s_A
		WR_n <= '0';
		wait for 10 * CLK50_PERIOD;  -- sample mid-write, strobes fully settled

		check("CHECK10a: SRAM write strobe stays inactive for a 0xFFFF write",
		      SRAM_WE_N = '1', pass_count, fail_count);
		check("CHECK10b: SRAM is not even selected for 0xFFFF",
		      SRAM_CE_N = '1', pass_count, fail_count);

		WR_n    <= '1';
		MREQ_n  <= '1';
		SLTSL_n <= '1';
		wait for 4 * CLK50_PERIOD;
		D <= (others => 'Z');

		-- ----------------------------------------------------------------
		-- Summary
		-- ----------------------------------------------------------------
		wait for 5 * CLK50_PERIOD;
		report "==============================================";
		report "TEST SUMMARY: " & integer'image(pass_count) & " passed, " &
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

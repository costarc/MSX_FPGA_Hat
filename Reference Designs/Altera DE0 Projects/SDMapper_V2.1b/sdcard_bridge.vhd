-- sdcard_bridge.vhd
--
-- Byte-level Z80-bus register bridge for the ported XESS SdCardCtrl core
-- (sdcard_xess.vhd). This is the ONLY new component the Nextor driver
-- talks to - it hides SdCardCtrl's handshake/block-level protocol behind
-- a simple set of poke/peek registers, the same style DRIVER.ASM's
-- SPIDATA/SPICTRL registers already used for the (now abandoned) raw-SPI
-- protocol, so the WAIT_n/CPU-interface plumbing follows this project's
-- own already-proven conventions (see spi.vhd's "STABILITY FIX" comment).
--
-- REGISTER MAP (all offsets from this bridge's base address - see
-- SDMapper_Top.vhd for where that lands in the Z80 address space):
--   0  SD_DATA   (R/W) - next byte to/from the SD card during an active
--                        block read/write. Every access here blocks the
--                        Z80 (WAIT_n) until SdCardCtrl's handshake
--                        completes for that byte, or until a bridge-level
--                        timeout gives up (see TIMEOUT_MAX_C below) -
--                        this timeout is NOT part of XESS's own design,
--                        it's added here because a WAIT_n that could get
--                        stuck asserted forever (e.g. if the SD card
--                        errors out mid-transfer and SdCardCtrl's FSM
--                        stalls in REPORT_ERROR without ever raising
--                        hndShk_o again) would hang the whole MSX, not
--                        just the driver.
--   1  SD_ADDR0  (W)   - block address bits 7:0
--   2  SD_ADDR1  (W)   - block address bits 15:8
--   3  SD_ADDR2  (W)   - block address bits 23:16
--   4  SD_ADDR3  (W)   - block address bits 31:24 (SDHC card, so this is
--                        a block/sector number, not a byte address)
--   5  SD_CMD    (W)   - bit7=1: pulse reset_i (re-run CMD0/CMD8/ACMD41
--                          init sequence from scratch)
--                        bit1=1: pulse wr_i (start a block WRITE using
--                          SD_ADDR0-3)
--                        bit0=1: pulse rd_i (start a block READ using
--                          SD_ADDR0-3)
--                        bit2  : continue_i, sampled together with the
--                          rd_i/wr_i pulse (multi-block sequential access)
--                        Only one of bit7/bit1/bit0 should be set per
--                        write; if more than one is set bit7 wins, then
--                        bit1, then bit0.
--   6  SD_STATUS (R)   - bit0: busy_o (SdCardCtrl is mid-operation)
--                        bit1: (error_o /= 0) - SdCardCtrl stalled on an
--                          error, needs a SD_CMD bit7 reset to recover
--                        bit2: card present (SW(0), same convention as
--                          the abandoned SPI design)
--                        bit3: write-protect (SW(2), same convention)
--                        bit4: sticky bridge-timeout flag (see SD_DATA) -
--                          cleared automatically on the next SD_CMD write
--   7  SD_ERRLO  (R)   - error_o(7 downto 0), for diagnostics
--   8  SD_ERRHI  (R)   - error_o(15 downto 8), for diagnostics
--
-- CLOCK DOMAIN: this whole bridge (and the SdCardCtrl instance it wraps)
-- runs on clock_i (25MHz) - same domain split rationale as spi.vhd/spi2.vhd
-- before it (see SDMapper_Top.vhd's "CLOCK DOMAINS" note). CPU-facing
-- inputs (cs_i, rd_n_i, wr_n_i) are synchronized into clock_i internally,
-- the same 3-stage meta/sync/sync_d technique already proven there.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.SdCardXessPckg.all;

entity sdcard_bridge is
	port (
		clock_i			: in    std_logic;		-- 25MHz
		reset_n_i		: in    std_logic;
		-- CPU interface
		cs_i				: in    std_logic;		-- asserted when the Z80 addresses this bridge's register range
		reg_addr_i		: in    std_logic_vector(3 downto 0);	-- register index (0-8), see map above
		-- Input-only, exactly like spi.vhd's own data_bus_i - this bridge
		-- never drives the MSX data bus itself, it only ever reads write
		-- data off it. The top level owns D-bus arbitration via its own
		-- single "D <= ..." mux (see SDMapper_Top.vhd), incorporating
		-- reg_dout/sd_dout below into that mux exactly like spi.vhd's own
		-- spi_dout/spi_rd_en - avoids any dual-driver ambiguity.
		data_bus_i		: in    std_logic_vector(7 downto 0);
		wr_n_i			: in    std_logic;
		rd_n_i			: in    std_logic;
		wait_n_o			: out   std_logic;
		card_present_i	: in    std_logic;		-- SW(0)
		write_protect_i: in    std_logic;		-- SW(2)
		-- Register-read data, for the top level's D-bus mux. reg_dout is
		-- the immediate/combinational content of SD_STATUS/SD_ERRLO/
		-- SD_ERRHI (top level qualifies when to actually mux it onto D,
		-- same as spi_ctrl_rd_s did before); sd_dout/sd_rd_en are the
		-- WAIT_n-gated SD_DATA register (same pattern spi.vhd's own
		-- spi_dout/spi_rd_en already used).
		reg_dout			: out   std_logic_vector(7 downto 0);
		sd_dout			: out   std_logic_vector(7 downto 0);
		sd_rd_en			: out   std_logic;
		-- SD card physical interface
		sd_cs_o			: out   std_logic;
		sd_sclk_o		: out   std_logic;
		sd_mosi_o		: out   std_logic;
		sd_miso_i		: in    std_logic;
		-- debug outputs for HEX/LEDG (see SDMapper_Top.vhd)
		dbg_busy_o				: out   std_logic;
		dbg_error_o				: out   std_logic_vector(15 downto 0);
		dbg_timeout_o			: out   std_logic;
		dbg_last_tx_o			: out   std_logic_vector(7 downto 0);
		dbg_last_rx_o			: out   std_logic_vector(7 downto 0);
		dbg_ever_accessed_o	: out   std_logic;
		dbg_init_done_o		: out   std_logic;
		-- DIAGNOSTIC (2026-08-13): counts COMPLETED SD_DATA byte transfers.
		-- dbg_ever_accessed_o is sticky over the whole register window and is
		-- already set by DRV_INIT's own SD_CMD write, so it cannot distinguish
		-- "DEV_RW ran" from "DEV_RW was never called". This counter only moves
		-- for genuine SD_DATA transfers, i.e. only when the sector-read byte
		-- loop actually executes.
		dbg_data_cnt_o			: out   std_logic_vector(7 downto 0);
		-- SD_DEBUG (register 9, write-only): whatever the driver last wrote,
		-- surfaced on HEX. Lets the driver trace itself WITHOUT calling the
		-- BIOS - CHPUT is only safe while page 0 still holds the BIOS, which
		-- is true during DRV_INIT but NOT once Nextor is running, so a
		-- print-based trace can hang the machine it is trying to measure.
		dbg_marker_o			: out   std_logic_vector(7 downto 0)
	);
end entity;

architecture rtl of sdcard_bridge is

	-- ------------------------------------------------------------------
	-- SdCardCtrl instance signals
	-- ------------------------------------------------------------------
	signal xess_reset_s    : std_logic;
	signal xess_rd_s       : std_logic;
	signal xess_wr_s       : std_logic;
	signal xess_continue_s : std_logic;
	signal xess_addr_s     : std_logic_vector(31 downto 0);
	signal xess_data_i_s   : std_logic_vector(7 downto 0);
	signal xess_data_o_s   : std_logic_vector(7 downto 0);
	signal xess_busy_s     : std_logic;
	signal xess_hndshk_i_s : std_logic;
	signal xess_hndshk_o_s : std_logic;
	signal xess_error_s    : std_logic_vector(15 downto 0);

	-- ------------------------------------------------------------------
	-- CPU-interface synchronization (same technique as spi.vhd's own
	-- "STABILITY FIX" - cs_i is combinationally derived from async MSX
	-- bus signals at the top level, so it's synchronized here rather than
	-- used directly as an edge source).
	--
	-- BUG FIX (2026-08-12, found by tb_SDMapper_Top.vhd's full-chain
	-- CHECK6c, debugged down to "byte i=1 came back identical to byte
	-- i=0"): cs_i on its own is PURE ADDRESS DECODE (no rd_n_i/wr_n_i
	-- component) - for repeated accesses to the SAME address, exactly
	-- what a 512-byte SD_DATA read loop does, cs_i never actually toggles
	-- between accesses, only rd_n_i does. Edge-detecting on cs_i alone
	-- (as originally written) meant cs_rising_pulse only ever fired once,
	-- for the very first byte - every subsequent read silently found
	-- wait_n_s already at '1' (nothing new triggered) and returned the
	-- stale data_o_reg from the first byte, with no error or timeout
	-- (wait_n_s never asserted, so there was nothing TO time out). This
	-- exists even with a synchronizer-settle-time margin of hundreds of
	-- ns between accesses - it's a logic gap, not a timing margin issue.
	-- spi.vhd's OWN proven design avoids exactly this by combining the
	-- address decode WITH rd_n_i/wr_n_i before edge-detecting
	-- ("spi_cs_s <= cs_i AND (rd_n_i='0' OR wr_n_i='0')") - cs_active_s
	-- below applies that same combination, and is what actually gets
	-- synchronized/edge-detected now, not raw cs_i.
	-- ------------------------------------------------------------------
	signal cs_active_s                 : std_logic;
	signal sd_data_access_s            : std_logic;	-- combinational "a genuine SD_DATA access is happening right now" (drives /WAIT - see its assignment)
	signal cs_meta, cs_sync, cs_sync_d : std_logic;
	signal cs_rising_pulse              : std_logic;

	-- ------------------------------------------------------------------
	-- Address/command registers (written by the CPU)
	-- ------------------------------------------------------------------
	signal sd_addr0_q, sd_addr1_q, sd_addr2_q, sd_addr3_q : std_logic_vector(7 downto 0) := (others => '0');

	-- ------------------------------------------------------------------
	-- SD_DATA per-byte handshake state machine
	-- ------------------------------------------------------------------
	type handshake_state_t is (S_IDLE, S_WAIT_HNDSHK, S_HOLD, S_ACK_HIGH);
	signal handshake_state : handshake_state_t := S_IDLE;

	-- ------------------------------------------------------------------
	-- DECOUPLING (2026-08-15) - why this bridge prefetches.
	--
	-- Real hardware: with the SD_DATA stall bounded at 10ms the MSX logo
	-- came up corrupted, internal RAM detected as 8KB instead of 32KB, and
	-- the machine restarted at random. Root cause is not the SD card at
	-- all: MSX main RAM is DRAM, and it is refreshed by the Z80's OWN
	-- refresh cycles (the CS2_RFSH_n line on the cartridge bus). While
	-- /WAIT is asserted the CPU is frozen, no M1 cycles happen, and
	-- refresh STOPS. DRAM retention is only ~2-4ms, so a multi-millisecond
	-- /WAIT physically decays main memory - which is exactly what "8KB of
	-- 32KB survived" and a corrupted logo look like.
	--
	-- The first byte of a block genuinely can take milliseconds (the
	-- card's start-token latency after CMD17), so that wait simply cannot
	-- happen on the bus at ANY timeout value. It is moved off the bus
	-- entirely here: the transfer FSM starts on the SD_CMD write and
	-- fetches bytes in the BACKGROUND while the CPU is free to run. The
	-- driver polls SD_STATUS bit5 (a plain, non-stalling register read)
	-- until the first byte is ready, then reads the block; each subsequent
	-- byte is prefetched during the driver's own loop overhead (~2.8us at
	-- 3.58MHz) which comfortably exceeds one SPI byte time (~0.6us at
	-- 12.5MHz), so /WAIT normally never asserts at all.
	-- ------------------------------------------------------------------
	-- acc_served_q: this SD_DATA access has already been satisfied.
	-- Needed because consumption is flagged EARLY in the bus cycle (at
	-- cs_rising_pulse) while the cycle itself runs on for ~840ns. Without it,
	-- clearing rx_ready_q mid-access made /WAIT re-assert for the remainder
	-- of that same access, while the transfer FSM was waiting for the access
	-- to END before fetching the next byte - a deadlock, each side waiting on
	-- the other. It also keeps the byte driven onto D for the whole cycle.
	signal acc_served_q    : std_logic := '0';
	signal rx_ready_q      : std_logic := '0';	-- a byte is prefetched and waiting for the CPU to read it
	signal tx_ready_q      : std_logic := '0';	-- the core is ready to accept a byte from the CPU
	signal tx_data_q       : std_logic_vector(7 downto 0) := (others => '0');
	signal xfer_is_write_q : std_logic := '0';	-- direction of the block transfer in progress
	signal xfer_start_q    : std_logic := '0';	-- one-cycle pulse: driver issued a rd/wr command
	-- Command requests, held until SdCardCtrl is idle enough to accept them -
	-- see the RACE FIX note in the command process.
	signal cmd_rd_pending_q : std_logic := '0';
	signal cmd_wr_pending_q : std_logic := '0';	-- one-cycle pulse: driver issued a rd/wr command

	signal wait_n_s        : std_logic := '1';

	-- BUG FIX (2026-08-12, found by tb_SDMapper_Top.vhd's full-chain
	-- CHECK6c): sd_rd_en was gated on "wait_n_s='1'" alone, which is ALSO
	-- true simply because the bridge is idle from the PREVIOUS access -
	-- for the first cycle or two of a brand new access (cs_i/rd_n_i just
	-- asserted, handshake_state hasn't left S_IDLE yet), wait_n_s is STILL
	-- '1' from before, so sd_rd_en briefly went true showing STALE
	-- data_o_reg left over from the previous byte, before the real
	-- handshake even started and wait_n_s genuinely dropped. This
	-- momentary glitch was enough to confuse the CPU-side wait logic
	-- (real hardware/testbench alike) into treating the access as already
	-- complete. data_ready_q instead only goes high once THIS access's own
	-- handshake has genuinely finished (S_WAIT_LOW's completion), and is
	-- cleared as soon as a NEW access starts or the current one ends - no
	-- level-based ambiguity with the idle-from-before state.
	signal data_o_reg      : std_logic_vector(7 downto 0) := (others => '0');	-- byte captured from the card, presented to the CPU on read

	-- Bridge-level timeout: see file header - protects against WAIT_n
	-- getting stuck asserted forever if SdCardCtrl stalls mid-handshake.
	--
	-- WIDENED (2026-08-12, real hardware: first real success - "SD card
	-- ready" printed, meaning CMD0/CMD8/ACMD41 genuinely completed - but
	-- the MSX hung a few seconds later, LEDG(0)/dbg_timeout_o lit).
	-- Root cause: 16 bits (~2.6ms) was sized only for a single SPI byte
	-- transfer, but SdCardCtrl's own RD_BLK state polls the card
	-- internally for a start token (0xFE) after issuing CMD17/CMD24, and
	-- never raises hndShk_o at all while doing so (rtnData_v stays false
	-- until the token arrives) - a real card can legitimately take longer
	-- than 2.6ms to prepare that data. The old timeout fired mid-poll,
	-- handed back stale data, and the byte loop kept going regardless -
	-- 512 accumulated ~2.6ms timeouts per sector reads as "hangs after a
	-- few seconds", not a true infinite lock, but bad either way.
	--
	-- NARROWED BACK (2026-08-13, real hardware: DRV_INIT never exercises
	-- this WAIT_n-gated SD_DATA path at all - CMD0/CMD8/ACMD41 run inside
	-- SdCardCtrl automatically, and DRV_INIT only ever touches SD_CMD
	-- (plain fast write) and SD_STATUS/SD_ERRLO/SD_ERRHI (immediate,
	-- non-WAIT_n reads). So "SD card ready" printing reliably never
	-- actually proved a 671ms WAIT_n hold was safe - the FIRST real
	-- exercise of this path is DEV_RW's boot-sector read, and that is
	-- exactly where the MSX now hangs/reboots, consistently right after
	-- "SD card ready" clears and before BASIC. 671ms is a single,
	-- uninterrupted Z80 bus hold (SLTSL_n/MREQ_n/RD_n all held low the
	-- whole time by hardware WAIT) - long enough to plausibly trip
	-- something on the real host (a bus-timeout supervisor, or similar)
	-- that the DE0 testbench/host-free bench setup never exercised. Cut
	-- to ~100ms (still ~38x the proven-insufficient 2.6ms) as a cheap,
	-- reversible experiment: short enough to plausibly dodge whatever is
	-- resetting the machine, long enough to keep covering legitimate
	-- start-token latency for any reasonably healthy card.
	-- CORRECTED (2026-08-15): this had been to_unsigned(2500, 24), which is
	-- 100 MICROseconds at 25MHz, not the ~100ms the comment claimed (three
	-- zeros were missing). 100us cannot work: the FIRST byte of a block read
	-- has to wait for the card's start token after CMD17, which a real card
	-- typically takes 1-2ms to produce (the SD spec allows up to 100ms). Every
	-- sector would therefore time out on byte 0 - and because timeout_flag_q
	-- is sticky until the next SD_CMD write, the combinational WAIT_n below
	-- then stops asserting at all, so the remaining 511 bytes complete
	-- instantly with stale data instead of the card's.
	--
	-- 10ms is a deliberate compromise, not a spec-derived number: ~5-10x
	-- typical card latency, while staying under the MSX's 16.7ms (60Hz)
	-- interrupt period so a worst-case stall can delay at most one interrupt
	-- rather than dropping a whole frame. Raise it if a slow card proves to
	-- need more; the driver detects the timeout and retries cleanly either way.
	constant TIMEOUT_MAX_C : unsigned(23 downto 0) := to_unsigned(2500, 24);	-- ~100us @ 25MHz - see the DRAM-refresh note below
	signal timeout_cnt_q   : unsigned(23 downto 0) := (others => '0');
	signal timeout_flag_q  : std_logic := '0';

	-- ------------------------------------------------------------------
	-- Diagnostics
	-- ------------------------------------------------------------------
	signal last_tx_q       : std_logic_vector(7 downto 0) := (others => '0');
	signal last_rx_q       : std_logic_vector(7 downto 0) := (others => '0');
	signal ever_accessed_q : std_logic := '0';
	signal marker_q        : std_logic_vector(7 downto 0) := (others => '0');	-- SD_DEBUG (reg 9)
	signal data_cnt_q      : unsigned(7 downto 0) := (others => '0');	-- completed SD_DATA transfers (diagnostic, free-running/wrapping)
	signal init_done_q     : std_logic := '0';	-- sticky: busy_o has gone low at least once (init finished)

	-- Register-read mux
	signal reg_rdata_s   : std_logic_vector(7 downto 0);
	signal sd_ready_s      : std_logic;	-- SD_STATUS bit5: prefetched byte available / core ready for a write byte
	signal error_flag_s  : std_logic;	-- '1' when xess_error_s /= 0 - kept as its own signal since
	                                    -- a boolean comparison can't be concatenated directly into a
	                                    -- std_logic_vector expression.

	-- SD_CMD bit7 (software reset pulse) - see file header register map.
	-- One-cycle pulse, ORed into SdCardCtrl's own reset_i alongside the
	-- bridge's hardware reset_n_i - lets the driver force SdCardCtrl back
	-- to START_INIT (re-running CMD0/CMD8/ACMD41) without a full MSX
	-- reset, matching SdCardCtrl's own documented error-recovery
	-- requirement ("you have to pulse reset_i to unfreeze").
	signal sw_reset_pulse_s : std_logic := '0';

begin

	-- ------------------------------------------------------------------
	-- Port the XESS core
	-- ------------------------------------------------------------------
	-- Modified manually
	xess_reset_s <= (not reset_n_i) or sw_reset_pulse_s;

	process(clock_i)
	begin
		if rising_edge(clock_i) then
			if reset_n_i = '0' then
				xess_rd_s        <= '0';
				xess_wr_s        <= '0';
				xess_continue_s  <= '0';
				sw_reset_pulse_s <= '0';
				xfer_start_q     <= '0';
				xfer_is_write_q  <= '0';
				cmd_rd_pending_q <= '0';
				cmd_wr_pending_q <= '0';
			else
				-- 1. Present a pending command ONLY while the core can actually
				--    take it, i.e. while it is idle.
				--
				-- RACE FIX (2026-08-15, real hardware: multi-sector reads passed
				-- or failed at random, and the bridge timeout flag was seen set).
				-- This used to assert rd_i/wr_i immediately on the SD_CMD write
				-- and auto-clear them as soon as busy_o went high ("the core has
				-- acknowledged"). But busy_o is ALSO still high while the core is
				-- finishing the PREVIOUS block (reading its CRC), which is
				-- exactly where the driver issues the next READ+CONTINUE. In
				-- that window the clear fired one cycle later and threw the
				-- command away before the core ever reached WAIT_FOR_HOST_RW to
				-- sample it. The command was silently lost, the transfer FSM
				-- waited forever for a byte that never came, and the next
				-- SD_DATA read hit the 100us guard. Whether it happened at all
				-- depended purely on how far the core had got in the gap - hence
				-- the intermittency, and hence a first sector that always
				-- worked.
				--
				-- Now the request is HELD until the core is genuinely idle, then
				-- presented, and only retired once the core has actually started
				-- it (busy_o rising while we were presenting it). SdCardCtrl
				-- samples rd_i/wr_i by LEVEL in WAIT_FOR_HOST_RW, so holding is
				-- the correct protocol, not a workaround.
				if cmd_rd_pending_q = '1' and xess_busy_s = '0' then
					xess_rd_s <= '1';
				else
					xess_rd_s <= '0';
				end if;

				if cmd_wr_pending_q = '1' and xess_busy_s = '0' then
					xess_wr_s <= '1';
				else
					xess_wr_s <= '0';
				end if;

				-- Retire the request once the core has taken it (it is busy now
				-- BECAUSE of us - we only ever present while it is idle).
				if xess_busy_s = '1' then
					if xess_rd_s = '1' then
						cmd_rd_pending_q <= '0';
					end if;
					if xess_wr_s = '1' then
						cmd_wr_pending_q <= '0';
					end if;
				end if;

				-- 2. Software reset and transfer-start are single-cycle pulses
				sw_reset_pulse_s <= '0';
				xfer_start_q     <= '0';

				-- 3. Latch commands when CPU writes to SD_CMD (reg_addr 5)
				if cs_rising_pulse = '1' and wr_n_i = '0' and reg_addr_i = "0101" then
					sw_reset_pulse_s <= data_bus_i(7);
					xess_continue_s  <= data_bus_i(2);

					-- A genuine block rd/wr command (not a reset) arms the
					-- background transfer engine - see the DECOUPLING note.
					if data_bus_i(7) = '0' and (data_bus_i(1) = '1' or data_bus_i(0) = '1') then
						cmd_wr_pending_q <= data_bus_i(1);
						cmd_rd_pending_q <= data_bus_i(0);
						xfer_start_q     <= '1';
						xfer_is_write_q  <= data_bus_i(1);
					end if;

					-- A reset abandons anything queued.
					if data_bus_i(7) = '1' then
						cmd_rd_pending_q <= '0';
						cmd_wr_pending_q <= '0';
					end if;
				end if;
			end if;
		end if;
	end process;

	sdcard_ctrl_inst: entity work.SdCardCtrl
		generic map (
			FREQ_G          => 25.0,
			INIT_SPI_FREQ_G => 0.4,
			SPI_FREQ_G      => 12.5,
			BLOCK_SIZE_G    => 512,
			CARD_TYPE_G     => SDHC_CARD_E
		)
		port map (
			clk_i      => clock_i,
			reset_i    => xess_reset_s,
			rd_i       => xess_rd_s,
			wr_i       => xess_wr_s,
			continue_i => xess_continue_s,
			addr_i     => xess_addr_s,
			data_i     => xess_data_i_s,
			data_o     => xess_data_o_s,
			busy_o     => xess_busy_s,
			hndShk_i   => xess_hndshk_i_s,
			hndShk_o   => xess_hndshk_o_s,
			error_o    => xess_error_s,
			cs_bo      => sd_cs_o,
			sclk_o     => sd_sclk_o,
			mosi_o     => sd_mosi_o,
			miso_i     => sd_miso_i
		);

	xess_addr_s   <= sd_addr3_q & sd_addr2_q & sd_addr1_q & sd_addr0_q;
	-- Write data comes from tx_data_q, latched when the CPU wrote SD_DATA -
	-- NOT from the live bus. With the transfer decoupled from the CPU access
	-- (see the DECOUPLING note), the core consumes the byte after the Z80 has
	-- long since released D, so sampling data_bus_i here would capture garbage.
	xess_data_i_s <= tx_data_q;

	-- ------------------------------------------------------------------
	-- Synchronize CPU interface into clock_i, exactly as spi.vhd does -
	-- cs_active_s (address decode combined with rd_n_i/wr_n_i, see the
	-- BUG FIX note on its declaration above), not raw cs_i, is what
	-- actually gets edge-detected.
	-- ------------------------------------------------------------------
	cs_active_s <= '1' when cs_i = '1' and (rd_n_i = '0' or wr_n_i = '0') else '0';

	-- Only cs_active_s (genuinely async, derived from combinational MSX
	-- bus signals) needs metastability synchronization. reg_addr_i/rd_n_i/
	-- wr_n_i are used directly everywhere below instead of through their
	-- own independent synchronizer chains - see the S_IDLE bug-fix note
	-- further down for why re-syncing them separately was itself the bug.
	process(clock_i)
	begin
		if rising_edge(clock_i) then
			cs_meta   <= cs_active_s;
			cs_sync   <= cs_meta;
			cs_sync_d <= cs_sync;
		end if;
	end process;

	cs_rising_pulse <= cs_sync and not cs_sync_d;

	-- ------------------------------------------------------------------
	-- Register writes: address/command registers, and triggering rd_i/
	-- wr_i/reset_i pulses. All single-cycle pulses derived from
	-- cs_rising_pulse, qualified by wr_n_i='0' (a genuine write access)
	-- and the register index.
	-- ------------------------------------------------------------------

	process(clock_i)
	begin
		if rising_edge(clock_i) then
			if reset_n_i = '0' then
				sd_addr0_q <= (others => '0');
				sd_addr1_q <= (others => '0');
				sd_addr2_q <= (others => '0');
				sd_addr3_q <= (others => '0');
				ever_accessed_q <= '0';
			elsif cs_rising_pulse = '1' and wr_n_i = '0' then
				ever_accessed_q <= '1';
				case reg_addr_i is
					when "0001" => sd_addr0_q <= data_bus_i;
					when "0010" => sd_addr1_q <= data_bus_i;
					when "0011" => sd_addr2_q <= data_bus_i;
					when "0100" => sd_addr3_q <= data_bus_i;
					when "1001" => marker_q <= data_bus_i;	-- SD_DEBUG: driver trace marker
					when others => null;	-- SD_DATA/SD_CMD handled by their own dedicated logic below
				end case;
			elsif cs_rising_pulse = '1' and rd_n_i = '0' then
				ever_accessed_q <= '1';
			end if;
		end if;
	end process;

	-- ------------------------------------------------------------------
	-- SD_DATA handshake state machine - the heart of this bridge. See
	-- file header for the exact 4-step protocol this implements against
	-- (identical shape for both read and write, only the data direction
	-- differs).
	-- ------------------------------------------------------------------
	process(clock_i)
	begin
		if rising_edge(clock_i) then
			if reset_n_i = '0' then
				handshake_state  <= S_IDLE;
				wait_n_s         <= '1';
				xess_hndshk_i_s  <= '0';
				timeout_cnt_q    <= (others => '0');
				timeout_flag_q   <= '0';
				data_o_reg       <= (others => '0');
				rx_ready_q       <= '0';
				acc_served_q     <= '0';
				tx_ready_q       <= '0';
				tx_data_q        <= (others => '0');
				last_tx_q        <= (others => '0');
				last_rx_q        <= (others => '0');
				init_done_q      <= '0';
				-- NOTE: data_cnt_q is deliberately NOT cleared here. This reset
				-- also fires on the driver's SD_CMD software-reset pulse, which
				-- DRV_INIT issues on every boot - clearing the counter there
				-- would erase exactly the evidence it exists to capture.
			else

				-- Clear the sticky timeout flag whenever a new command is
				-- issued (SD_CMD write) - matches "you have to reset to
				-- unfreeze" but lets the driver observe the flag first.
				if cs_rising_pulse = '1' and wr_n_i = '0' and reg_addr_i = "0101" then
					timeout_flag_q <= '0';
				end if;

				if xess_busy_s = '0' then
					init_done_q <= '1';	-- sticky: SdCardCtrl has reached WAIT_FOR_HOST_RW at least once
				end if;

				case handshake_state is

					when S_IDLE =>
						-- BUG FIX (2026-08-12, found by tb_SDMapper_Top.vhd's
						-- full-chain CHECK6c, traced to a real race): using
						-- reg_addr_sync/rd_n_sync/wr_n_sync here required
						-- cs_rising_pulse (from cs_active_s's 3-stage sync)
						-- and reg_addr_sync (its OWN, independent 2-stage
						-- sync) to land on the EXACT SAME clock_i cycle -
						-- but both derive from signals that changed at the
						-- same instant, so their DIFFERENT-length
						-- synchronizer chains settle on DIFFERENT cycles.
						-- Traced live: cs_rising_pulse fired one cycle
						-- before reg_addr_sync caught up to the new
						-- address, so the trigger was silently missed for
						-- the very first SD_DATA access following an
						-- SD_CMD write to a different register - wait_n_s
						-- never asserted, and the CPU read stale/undriven
						-- data with no error. Fixed by using the raw
						-- reg_addr_i/rd_n_i/wr_n_i here instead: by the time
						-- cs_active_s (and therefore cs_rising_pulse)
						-- reflects a genuine access, those raw signals were
						-- ALREADY stable and combinationally folded into
						-- cs_active_s several cycles ago - re-synchronizing
						-- them independently was both unnecessary and the
						-- actual source of the race.
						--wait_n_s <= '1';
						-- if cs_rising_pulse = '1' and reg_addr_i = "0000" and (rd_n_i = '0' or wr_n_i = '0') then
						-- 	-- NEVER-STALL GUARD (2026-08-13, real hardware: the MSX
						-- 	-- crashed/rebooted at random even with NO card inserted
						-- 	-- and after DEV_RW learned to bail out early - i.e. with
						-- 	-- zero driver-initiated SD activity. SW(9)='1' (this whole
						-- 	-- core gated off) is rock solid, so the fault is here.)
						-- 	--
						-- 	-- Root cause class: the SD register window is aliased
						-- 	-- INSIDE ROM address space (7B00-7B08, live whenever ROM
						-- 	-- bank1 = segment 7 - which is the driver's own bank, so
						-- 	-- essentially always). ANY read of those 9 addresses -
						-- 	-- a stray instruction fetch, a kernel data read, a
						-- 	-- mis-captured address from the A_MUX FSM, anything -
						-- 	-- looks exactly like a genuine SD_DATA access and used to
						-- 	-- assert WAIT_n unconditionally. With no card, SdCardCtrl
						-- 	-- has given up (REPORT_ERROR, stalled until reset) and
						-- 	-- will NEVER issue the handshake being waited for, so
						-- 	-- every such access stalled the Z80 for the full timeout.
						-- 	-- That is entirely software-independent, which is exactly
						-- 	-- why fixing DEV_RW alone couldn't cure it.
						-- 	--
						-- 	-- Fix: if the card cannot possibly respond (not present,
						-- 	-- or the core has latched an error / is stalled), complete
						-- 	-- the access IMMEDIATELY - return 0xFF (the SPI idle/no-
						-- 	-- card byte, what a real bus-floating read looks like) and
						-- 	-- never drop wait_n_s at all. This enforces the standing
						-- 	-- hardware requirement that the MSX must always keep
						-- 	-- running when no valid SD card is present, in the one
						-- 	-- place that can actually guarantee it, rather than
						-- 	-- relying on every driver code path to check first.
						-- 	-- REFINED (2026-08-13, real hardware: including
						-- 	-- card_present_i here put the MSX into a splash/reboot
						-- 	-- loop). card_present_i is wired to SW(0) - a MANUAL
						-- 	-- switch, not real card-detect sensing (this board has
						-- 	-- none). With the switch down but a card actually
						-- 	-- inserted, every SD_DATA read completed instantly with
						-- 	-- 0xFF, so Nextor read a garbage boot sector and looped
						-- 	-- trying to boot it. Nothing depended on SW(0) before, so
						-- 	-- its position had never mattered. Gate on error_flag_s
						-- 	-- ALONE: that is set by SdCardCtrl itself and genuinely
						-- 	-- means "this core cannot answer" (it stalls in
						-- 	-- REPORT_ERROR until reset), which is exactly and only
						-- 	-- the condition where stalling the Z80 would hang the
						-- 	-- machine forever. A merely mis-set switch must never
						-- 	-- silently corrupt real transfers.
						-- 	if error_flag_s = '1' then
						-- 		if rd_n_i = '0' then
						-- 			data_o_reg   <= x"FF";
						-- 			is_write_access <= '0';
						-- 			data_ready_q <= '1';	-- present 0xFF for this access
						-- 		end if;
						-- 		-- wait_n_s stays '1', handshake_state stays S_IDLE:
						-- 		-- the CPU is never stalled and the stalled core is
						-- 		-- never handed a request it cannot service.
						-- 	else
						-- 		wait_n_s        <= '0';
						-- 		data_ready_q    <= '0';	-- new access starting - previous byte's data no longer valid to re-present
						-- 		timeout_cnt_q   <= (others => '0');
						-- 		if wr_n_i = '0' and rd_n_i /= '0' then
						-- 			is_write_access <= '1';
						-- 		else
						-- 			is_write_access <= '0';
						-- 		end if;
						-- 		if wr_n_i = '0' then
						-- 			last_tx_q <= data_bus_i;
						-- 		end if;
						-- 		handshake_state <= S_WAIT_HNDSHK;
						-- 	end if;
						-- elsif cs_i = '0' or reg_addr_i /= "0000" or (rd_n_i = '1' and wr_n_i = '1') then
						-- 	data_ready_q <= '0';	-- CPU released SD_DATA (or moved elsewhere) - clear for next time
						-- end if;

						-- Idle: a transfer begins when the driver writes a rd/wr
						-- command to SD_CMD (xfer_start_q), NOT when the CPU
						-- touches SD_DATA. See the DECOUPLING note on
						-- rx_ready_q for why this distinction is the whole point.
						if xfer_start_q = '1' then
							timeout_cnt_q   <= (others => '0');
							handshake_state <= S_WAIT_HNDSHK;
						end if;

					when S_WAIT_HNDSHK =>
						-- Waiting for the core to present a byte (read) or ask
						-- for one (write). For the FIRST byte of a block this is
						-- the card's start-token latency - MILLISECONDS. The CPU
						-- is NOT stalled here: it polls SD_STATUS bit5 instead.
						-- No timeout runs in this state for the same reason.
						if xess_hndshk_o_s = '1' then
							if xfer_is_write_q = '0' then
								data_o_reg <= xess_data_o_s;
								last_rx_q  <= xess_data_o_s;
								rx_ready_q <= '1';	-- byte available for the CPU
							else
								tx_ready_q <= '1';	-- core is ready to accept a byte
							end if;
							handshake_state <= S_HOLD;
						end if;

					when S_HOLD =>
						-- Hold the core's handshake until the CPU has actually
						-- consumed (read) or supplied (write) this byte. Acking
						-- earlier would let the core overwrite data_o_reg with
						-- the next byte before the CPU ever saw this one.
						--
						-- The "sd_data_access_s = '0'" term matters just as much:
						-- consumption is flagged early in the CPU's bus cycle
						-- (cs_rising_pulse lands ~120ns in), but the Z80 does not
						-- latch D until the END of that cycle (~840ns). Without
						-- waiting for the access to finish, the next byte could
						-- be fetched into data_o_reg while the CPU is still
						-- reading the current one, and the Z80 would latch the
						-- WRONG byte. Waiting costs nothing: the next byte is
						-- then prefetched during the driver's loop overhead
						-- (~2.8us), still far more than one SPI byte (~0.6us).
						-- CLOCK-DOMAIN FIX (2026-08-15): this tested the RAW
						-- sd_data_access_s while the consume below is driven from
						-- the SYNCHRONIZED cs_sync. Raw and synchronized versions
						-- of the same access differ by ~3 clocks at each edge, so
						-- the flag was being set in one domain and acted on in
						-- another - a race that clean testbench timing hides and
						-- real bus timing exposes. Everything in the consume/
						-- advance path now uses cs_sync; only WAIT_n stays
						-- combinational on the raw signals, because it must be.
						if cs_sync = '0' and
						   ((xfer_is_write_q = '0' and rx_ready_q = '0') or
						    (xfer_is_write_q = '1' and tx_ready_q = '0')) then
							xess_hndshk_i_s <= '1';
	
							handshake_state <= S_ACK_HIGH;
						end if;

					when S_ACK_HIGH =>
						if xess_hndshk_o_s = '0' then
							xess_hndshk_i_s <= '0';
							-- Straight back to fetching/awaiting the next byte,
							-- in the background, while the CPU runs its loop
							-- overhead. That is what keeps rx_ready_q already
							-- set by the time the next SD_DATA access arrives,
							-- so /WAIT is normally never asserted at all.
							handshake_state <= S_WAIT_HNDSHK;
						end if;

					when others =>
						handshake_state <= S_IDLE;

				end case;

				-- A new command always re-arms the transfer engine, whatever
				-- state it was left in (e.g. a block that the driver abandoned).
				if xfer_start_q = '1' then
					-- DIAGNOSTIC (2026-08-15): count BLOCK COMMANDS, not bytes.
					-- This counter used to increment per byte and wrap at 256,
					-- but every transfer is a multiple of 512 bytes - so it
					-- displayed 00 no matter how much data moved and could
					-- never show whether reads were happening at all. Counting
					-- issued rd/wr commands makes it show sector activity
					-- directly.
					data_cnt_q      <= data_cnt_q + 1;
					rx_ready_q      <= '0';
					tx_ready_q      <= '0';
					xess_hndshk_i_s <= '0';
					timeout_cnt_q   <= (others => '0');
					handshake_state <= S_WAIT_HNDSHK;
				end if;

				-- ----------------------------------------------------------
				-- CPU side of SD_DATA: consume / supply. Deliberately separate
				-- from the transfer FSM above - the CPU and the card no longer
				-- wait for each other except when the CPU genuinely runs ahead.
				-- ----------------------------------------------------------
				-- LEVEL-triggered, not edge-triggered (2026-08-15). This used to
				-- fire on cs_rising_pulse, i.e. only at the instant the access
				-- began. If the byte was not ready yet at that exact moment -
				-- which is precisely the case whenever the CPU arrives before
				-- the prefetch, including the first byte of every block - the
				-- consume never happened at all, because there is no second
				-- rising edge inside the same access. The CPU then read the
				-- correct byte but it was never marked consumed, so the NEXT
				-- access consumed it instead and every read from then on lagged
				-- by one byte (caught by tb_sdcard_bridge.vhd; the full-chain
				-- test missed it because there the byte was always already
				-- prefetched before the access started). acc_served_q keeps this
				-- to exactly one consume per access.
				if cs_sync = '1' and acc_served_q = '0' and reg_addr_i = "0000" then
					if rd_n_i = '0' and rx_ready_q = '1' then
						rx_ready_q   <= '0';	-- consumed; FSM may now fetch the next byte
						acc_served_q <= '1';
					elsif wr_n_i = '0' and tx_ready_q = '1' then
						tx_data_q    <= data_bus_i;
						last_tx_q    <= data_bus_i;
						tx_ready_q   <= '0';	-- supplied; FSM may now hand it to the core
						acc_served_q <= '1';
					end if;
				end if;

				-- The served flag lives exactly as long as the access does, in
				-- the SAME (synchronized) domain it is set in - see the note in
				-- S_HOLD above.
				if cs_sync = '0' then
					acc_served_q <= '0';
				end if;

				-- ----------------------------------------------------------
				-- Bounded stall guard. /WAIT is only ever asserted when the CPU
				-- reaches SD_DATA before the background transfer has the byte
				-- ready - normally never, and at most one SPI byte time (~1us)
				-- when it does. This counter bounds even that pathological case
				-- to TIMEOUT_MAX_C, because on MSX a long /WAIT does not merely
				-- slow things down: the Z80's refresh cycles stop, and main RAM
				-- is DRAM that depends on them.
				-- ----------------------------------------------------------
				if sd_data_access_s = '1' and acc_served_q = '0' and rx_ready_q = '0' and tx_ready_q = '0' then
					if timeout_cnt_q = TIMEOUT_MAX_C then
						timeout_flag_q <= '1';
					else
						timeout_cnt_q <= timeout_cnt_q + 1;
					end if;
				elsif sd_data_access_s = '0' then
					timeout_cnt_q <= (others => '0');
				end if;
			end if;
		end if;
	end process;

	-- BUG FIX (2026-08-12, found by tb_SDMapper_Top.vhd's full-chain
	-- CHECK6c): sd_rd_en used to be a single clock_i-cycle pulse marking
	-- "data_o_reg valid for exactly the cycle the CPU read completes" -
	-- that assumed the CPU would sample D within that exact one-cycle
	-- (40ns) window, but nothing guarantees that (and nothing else in this
	-- project works that way - spi.vhd's own spi_dout/spi_rd_en and this
	-- bridge's own reg_dout are both LEVEL signals that stay valid for the
	-- whole CPU access). The isolated bridge testbench sampled data_o_reg
	-- one cycle earlier than the full top-level testbench's real-bus-timed
	-- read procedure does, so it never caught this - the full-chain test,
	-- driven through the real address-capture FSM and D-bus mux (closer to
	-- how a real Z80/driver actually samples data), did. Fixed by making
	-- sd_rd_en combinational instead: asserted for as long as the CPU is
	-- still actively holding an SD_DATA read access after the handshake
	-- has completed (wait_n_s='1'), matching every other readable
	-- register's "stays valid for the whole access" guarantee.
	sd_dout  <= data_o_reg;
	sd_rd_en <= '1' when cs_i = '1' and rd_n_i = '0' and reg_addr_i = "0000"
	                 and (rx_ready_q = '1' or acc_served_q = '1') else '0';

	-- ------------------------------------------------------------------
	-- Register reads: SD_STATUS/SD_ERRLO/SD_ERRHI. SD_DATA reads are
	-- handled by sd_dout/sd_rd_en above (through the top-level's D-bus
	-- mux, same convention spi.vhd already used).
	--
	-- Uses reg_addr_i directly (the write-trigger logic above does too now,
	-- see the S_IDLE bug-fix note): unlike cs_i (genuinely glitch-prone,
	-- combinationally derived from independent async MSX bus signals),
	-- reg_addr_i is just address bits already registered/settled by the
	-- top-level's address-capture FSM well before SLTSL_n/RD_n assert -
	-- matches how every other raw combinational read decode
	-- in this project treats s_A (no extra resync stage needed).
	-- ------------------------------------------------------------------
	error_flag_s <= '1' when xess_error_s /= x"0000" else '0';

	-- bit5 = SD_DATA ready: a prefetched byte is waiting to be read, or the
	-- core is ready to accept a byte to write. This is the bit the driver
	-- polls (a plain non-stalling register read) instead of stalling the bus
	-- through the card's multi-millisecond start-token latency.
	sd_ready_s <= rx_ready_q or tx_ready_q;

	-- SD_ADDR0-3 are READABLE (2026-08-15). They were write-only, which hid a
	-- critical blind spot: sector 0 is read with address 00 00 00 00, i.e. the
	-- registers' own reset default, so a sector-0 read succeeds even if the
	-- address writes never land at all. Sector 1 is the first read that
	-- actually depends on SD_ADDR0 latching a non-zero value - and on real
	-- hardware sector 0 is perfect while sector 1 comes back all 0xFF. Making
	-- these readable lets the driver verify what was actually latched instead
	-- of inferring it from the data that comes back.
	reg_rdata_s <= sd_addr0_q when reg_addr_i = "0001" else
	               sd_addr1_q when reg_addr_i = "0010" else
	               sd_addr2_q when reg_addr_i = "0011" else
	               sd_addr3_q when reg_addr_i = "0100" else
	               "00" & sd_ready_s & timeout_flag_q & write_protect_i & card_present_i & error_flag_s & xess_busy_s when reg_addr_i = "0110" else
	               xess_error_s(7 downto 0)  when reg_addr_i = "0111" else
	               xess_error_s(15 downto 8) when reg_addr_i = "1000" else
	               (others => '0');

	reg_dout <= reg_rdata_s;

	-- ------------------------------------------------------------------
	-- WAIT_n assertion: COMBINATIONAL (2026-08-13).
	--
	-- BUG FIX (real hardware): wait_n_o used to be wait_n_s alone - a
	-- registered signal the FSM only drives low AFTER cs_rising_pulse, which
	-- comes out of cs_active_s's 3-stage 25MHz synchronizer: up to ~120ns of
	-- latency plus decode. The Z80 samples /WAIT on the FALLING EDGE OF T2,
	-- about 140ns after /RD asserts at 3.58MHz. That is far too tight: when
	-- the assertion lands late the Z80 finishes the cycle with data that was
	-- never ready, AND the now-stale assertion bleeds into the FOLLOWING bus
	-- cycle, stalling an unrelated access. That corrupts bus traffic
	-- generally, which is why the machine only became unstable once DEV_RW's
	-- byte loop genuinely started running (512 stalled reads per sector):
	-- while init was failing and Nextor skipped the device, this path was
	-- never exercised and everything looked stable. The pre-existing
	-- "/WAIT latency theory" note in SDMapper_Top.vhd's address-capture
	-- section describes an earlier attempt at this that had to be reverted
	-- because it was done by reordering the address capture (which created a
	-- worse hazard); doing it here instead touches nothing else.
	--
	-- /WAIT is now asserted the moment a genuine SD_DATA access is decoded -
	-- combinationally, no synchronizer in the path - and released as soon as
	-- ANY of the three terminating conditions holds:
	--   data_ready_q  - the transfer completed normally
	--   timeout_flag_q- the bridge gave up (never stall the bus forever)
	--   error_flag_s  - the core cannot answer (never-stall guard)
	-- The FSM below is unchanged and still does the real handshaking; it just
	-- no longer gates when the CPU first gets stalled.
	sd_data_access_s <= '1' when cs_i = '1' and reg_addr_i = "0000" and (rd_n_i = '0' or wr_n_i = '0') else '0';

	wait_n_o <= '0' when sd_data_access_s = '1'
	                 and acc_served_q   = '0'
	                 and rx_ready_q     = '0'
	                 and tx_ready_q     = '0'
	                 and timeout_flag_q = '0'
	                 and error_flag_s   = '0'
	            else '1';

	-- ------------------------------------------------------------------
	-- Debug outputs
	-- ------------------------------------------------------------------
	dbg_busy_o           <= xess_busy_s;
	dbg_error_o          <= xess_error_s;
	dbg_timeout_o        <= timeout_flag_q;
	dbg_last_tx_o        <= last_tx_q;
	dbg_last_rx_o        <= last_rx_q;
	dbg_ever_accessed_o  <= ever_accessed_q;
	dbg_init_done_o      <= init_done_q;
	dbg_data_cnt_o       <= std_logic_vector(data_cnt_q);
	dbg_marker_o         <= marker_q;

end architecture;

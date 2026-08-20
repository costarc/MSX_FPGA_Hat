-- ============================================================================
-- SDMapper_V2.1b - MSX cartridge on Terasic DE0 (Cyclone III EP3C16F484C6)
-- Ronivon Costa, 2023-2026
--
-- Nextor kernel in Flash + SD card interface + 512KB MSX Memory Mapper, in one
-- expanded cartridge slot.
--
-- Derived from Fabio Belavenuto's MSX SD Mapper V2
-- (github.com/fbelavenuto/msxsdmapperv2). SD core is XESS Corp's SdCardCtrl.
--
-- ---------------------------------------------------------------------------
-- CONTENTS
--   1. Entity / MSX bus and board pins
--   2. Declarations
--   3. Reset
--   4. Address capture (A_MUX)          - the board's one real complication
--   5. Slot decode (expansion, ROM/RAM)
--   6. Flash / ROM banking
--   7. SD card bridge
--   8. Memory mapper (segment registers + SRAM)
--   9. MSX bus drivers (D, U1, BUSDIR, WAIT)
--  10. Display (HEX / LED)
--
-- ---------------------------------------------------------------------------
-- THE BOARD'S ONE COMPLICATION
-- The MSX address bus reaches the FPGA through two '245 buffers sharing eight
-- pins (A_MUX), gated by U2OE_n (A0-A7) and U3OE_n (A8-A15). Nothing can be
-- decoded until both halves have been captured, which is what s_addr_valid
-- means. Every reference design has all 16 lines immediately; we do not.
-- Data is separate: it crosses U1, whose direction is U1_DIR.
--
-- U1_DIR POLARITY: '0' drives towards the MSX, '1' listens. Confirmed on real
-- hardware; earlier versions of this file had it backwards.
--
-- ---------------------------------------------------------------------------
-- MEMORY MAP (within /SLTSL, SDMapper mode SW(9)='0')
--   ROM sub-slot 0 (the reset default for every page, so Nextor's kernel is
--   visible immediately with no FFFF write needed):
--     4000-7FFF  Bank 1 window, Flash base 0x000000 (Nextor)
--       6000-67FF, 7000-77FF  bank-switch registers (write-only)
--       7B00-7B0F             SD register window, only when rom_bank1_q = 7
--     8000-BFFF  Bank 2 window, Flash-backed only when rom_bank2_q >= 8
--   RAM sub-slot 1: all four pages, each via its own segment register.
--   FFFF         sub-slot select register (intercepted in every sub-slot).
--
-- I/O PORTS (system-wide, not slot-scoped - per the MSX standard)
--   FC-FF        memory-mapper segment registers, one per page
--
-- ---------------------------------------------------------------------------
-- SWITCHES                                  PUSHBUTTONS
--   SW(9)=0  SDMapper mode (cart enabled)     KEY(0)  reset (with MSX RESET_n)
--   SW(8)=1  mapper RAM + FC-FF ports OFF
--   SW(7)=0  SD register window ON  <- note inverted sense
--   SW(6)=1  legacy V-8 workaround (NOT subslot-compliant - leave off)
--   SW(4)=1  SRAM BIST
--   SW(2)    SD write-protect flag      SW(0)  SD card-present flag
-- ============================================================================

library ieee ;
use ieee.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
-- 1. ENTITY / MSX BUS AND BOARD PINS
-- ----------------------------------------------------------------------------
Entity SDMapper_TOP is
port (
    CLOCK_50:		in std_logic;								--	50 MHz

    KEY:				in std_logic_vector(2 downto 0);		--	Pushbutton[2:0] - DE0 has only 3 buttons (DE1 has 4)

    SW:				in std_logic_vector(9 downto 0);		--	Toggle Switch[9:0]

    HEX0:				out std_logic_vector(6 downto 0);	--	Seven Segment Digit 0
    HEX1:				out std_logic_vector(6 downto 0);	--	Seven Segment Digit 1
    HEX2:				out std_logic_vector(6 downto 0);	--	Seven Segment Digit 2
    HEX3:				out std_logic_vector(6 downto 0);	--	Seven Segment Digit 3

    -- DE0 has 10 green LEDs total and no red LEDs at all (DE1 has separate
    -- 8 green + 10 red) - the debug/status bits below are trimmed to fit.
    LEDG:				out std_logic_vector(9 downto 0);	--	LED Green[9:0]

    -- DE0 onboard parallel Flash: a 16-bit-wide chip forced into 8-bit "byte
    -- mode" (FL_BYTE_N='0'). In that mode the chip's D15 pin becomes the A-1
    -- address input instead of a data bit - hence FL_DQ15_AM1 is its own
    -- port, separate from the 15-bit FL_DQ(14 downto 0) data bus.
    FL_DQ:			inout std_logic_vector(14 downto 0);	--	FLASH Data bus (bits 14..0)
    FL_DQ15_AM1:	inout std_logic;							--	FLASH D15 pin / byte-mode A-1 address input
    FL_ADDR:			out std_logic_vector(21 downto 0);	--	FLASH Address bus, bits [22:1] (A-1 is FL_DQ15_AM1 above)
    FL_WE_N:			out std_logic;								--	FLASH Write Enable
    FL_RST_N:		out std_logic;								--	FLASH Reset
    FL_OE_N:			out std_logic;								--	FLASH Output Enable
    FL_CE_N:			out std_logic;								--	FLASH Chip Enable
    FL_WP_N:			out std_logic;								--	FLASH Hardware Write Protect
    FL_BYTE_N:		out std_logic;								--	FLASH Selects 8/16-bit mode (held low = 8-bit)

    -- DE0 SRAM addon board (ISSI IS61LV25616AL, GPIO_0) - the memory
    -- mapper's 512KB backing store. Only 8 physical GPIO data pins are
    -- wired (the addon's lower/upper byte lanes are tied together), so
    -- SRAM_DQ is 8 bits here (DE1's onboard SRAM was 16 bits).
    SRAM_DQ:			inout std_logic_vector(7 downto 0);	--	SRAM Data bus 8 Bits
    SRAM_ADDR:		out std_logic_vector(17 downto 0);	--	SRAM Address bus 18 Bits
    SRAM_UB_N:		out std_logic;								--	SRAM High-byte Data Mask (256K bank select)
    SRAM_LB_N:		out std_logic;								--	SRAM Low-byte Data Mask (256K bank select)
    SRAM_WE_N:		out std_logic;								--	SRAM Write Enable
    SRAM_CE_N:		out std_logic;								--	SRAM Chip Enable
    SRAM_OE_N:		out std_logic;								--	SRAM Output Enable

    -- Onboard microSD slot (this board has only one physical SD socket -
    -- unlike the DE1 predecessor this SD/timer/status protocol was ported
    -- from, there is no second SD2_* port set here).
    SD1_CS:			out std_logic;							--
    SD1_SCK:		out std_logic;							--
    SD1_MOSI: 		out std_logic;							--
    SD1_MISO: 		in std_logic;							--

    -- MSX Bus (GPIO_1 - see SDMapper.qsf for the verified pin-by-pin mapping;
    -- same 36-signal set and header-pin order as the DE1 version)
	MSX_CLK:		in std_logic;
    A_MUX:			in std_logic_vector(7 downto 0);	-- Shared, time-multiplexed address byte (low via U2, high via U3 - see U2OE_n/U3OE_n)
    D:				inout std_logic_vector(7 downto 0);
    RD_n:			in std_logic;
    WR_n:			in std_logic;
    MREQ_n:			in std_logic;
    IORQ_n:			in std_logic;
    SLTSL_n:		in std_logic;
    CS1_n:			in std_logic;
    BUSDIR_n:		out std_logic;
    M1_n:			in std_logic;
    INT_n:			out std_logic;
    WAIT_n:			out std_logic;
	RESET_n:			in std_logic;
	SOUNDIN:			in std_logic;
	SOUNDOUT:	   out std_logic;
	CS2_RFSH_n:		in std_logic;
	U1_DIR:			out std_logic;
	U1OE_n:			out std_logic;
    U2OE_n:			out std_logic;
	U3OE_n:			out std_logic;
	U4OE_n:			out std_logic);
end SDMapper_TOP;

architecture bevioural of SDMapper_TOP is

	-- ------------------------------------------------------------------------
	-- 2. DECLARATIONS (components, types, signals)
	-- ------------------------------------------------------------------------

	component decoder_7seg
	port (
		NUMBER		: in   std_logic_vector(3 downto 0);
		HEX_DISP	: out  std_logic_vector(6 downto 0));
	end component;

	component clock_25mhz
	PORT (
		inclk0              : IN STD_LOGIC  := '0';
		c0                  : OUT STD_LOGIC);
	end component;

	signal HEXDIGIT0		: std_logic_vector(3 downto 0);
	signal HEXDIGIT1		: std_logic_vector(3 downto 0);
	signal HEXDIGIT2		: std_logic_vector(3 downto 0);
	signal HEXDIGIT3		: std_logic_vector(3 downto 0);

	signal s_reset			: std_logic := '0';
	-- Active-low forms of s_reset/s_sltsl_en, used only as port-map actuals
	-- below (exp_slot/spi expect active-low inputs). Kept as their own
	-- signals rather than inline "not ..." expressions in the port maps -
	-- purely a GHDL simulation-tooling accommodation (some GHDL versions
	-- reject certain unary-operator expressions as direct port-map actuals
	-- under -fexplicit), functionally identical for synthesis either way.
	signal s_reset_n		: std_logic;
	-- Reset controller - see its process further down.
	signal s_rst_src_meta	: std_logic := '1';
	signal s_rst_src_sync	: std_logic := '1';
	signal s_rst_stretch	: std_logic_vector(2 downto 0) := (others => '1');
	signal s_rst_filter	: std_logic_vector(6 downto 0) := (others => '0');

	-- ------------------------------------------------------------------------
	-- SRAM self-test (BIST), SW(4). See the BIST process near the SRAM pins.
	-- ------------------------------------------------------------------------
	type bist_state_t is (B_IDLE, B_WR_SET, B_WR_PULSE, B_WR_END,
	                      B_RD_SET, B_RD_SAMPLE, B_NEXT, B_DONE);
	signal bist_state  : bist_state_t := B_IDLE;
	signal bist_addr   : std_logic_vector(18 downto 0) := (others => '0');
	signal bist_dq     : std_logic_vector(7 downto 0) := (others => '0');
	signal bist_drive  : std_logic := '0';
	signal bist_we_n   : std_logic := '1';
	signal bist_oe_n   : std_logic := '1';
	signal bist_ce_n   : std_logic := '1';
	signal bist_phase  : std_logic := '0';
	signal bist_errors : std_logic_vector(15 downto 0) := (others => '0');
	signal bist_done   : std_logic := '0';
	signal bist_wait   : std_logic_vector(2 downto 0) := (others => '0');
	signal bist_key_meta, bist_key_sync : std_logic := '0';

	-- ------------------------------------------------------------------------
	-- Self-timed SRAM write for the MSX side - see the process below.
	-- ------------------------------------------------------------------------
	signal wr_req_meta, wr_req_sync : std_logic := '0';
	signal wr_busy   : std_logic := '0';
	signal wr_served : std_logic := '0';
	signal wr_cnt    : std_logic_vector(2 downto 0) := (others => '0');
	signal wr_addr_q : std_logic_vector(17 downto 0) := (others => '0');
	signal wr_data_q : std_logic_vector(7 downto 0) := (others => '0');
	signal wr_we_n   : std_logic := '1';
	signal wr_drive  : std_logic := '0';

	-- U1 transceiver direction control - see the note at U1OE_n below.
	-- (u1_drive/u1_drive_q/u1_drive_q2/u1_dir_hold were removed 2026-08-18 -
	-- the direction no longer depends on which device won the read mux, so
	-- there is nothing to track or hold across. See the U1_DIR note.)

	-- Mapper segment-register capture pipeline - see the write process.
	signal map_d_q              : std_logic_vector(4 downto 0) := (others => '0');
	signal map_sel_q            : std_logic_vector(1 downto 0) := (others => '0');
	signal map_wr_q             : std_logic := '0';

	-- ROM bank-switch register capture - see the bank-switch write process.
	signal bank_d_s1, bank_d_s2 : std_logic_vector(7 downto 0) := (others => '0');
	signal bank_d_stable        : std_logic_vector(7 downto 0) := (others => '0');
	signal bank_have_stable     : std_logic := '0';
	signal bank_sel1, bank_sel2 : std_logic := '0';
	signal bank_wr_q            : std_logic := '0';
	signal s_sltsl_dis_n	: std_logic;
	signal s_sdbridge_wait_n_o	: std_logic;

	-- ------------------------------------------------------------------------
	-- Address bus reconstruction (see "ADDRESS BUS MULTIPLEXING" note above)
	-- Runs on CLOCK_50.
	-- ------------------------------------------------------------------------
	signal s_A				: std_logic_vector(15 downto 0) := (others => '0');

	signal s_bus_req_n		: std_logic;
	signal bus_req_meta, bus_req_sync, bus_req_sync_d : std_logic;
	signal addr_capture_trigger : std_logic;

	type addr_capture_state_t is (S_IDLE, S_LOW_EN, S_LOW_WAIT, S_LOW_CAP, S_GUARD, S_HIGH_EN, S_HIGH_WAIT, S_HIGH_CAP);

	-- ------------------------------------------------------------------------
	-- A_MUX SETTLE TIME (2026-08-18) - root cause of the lost 0FFFFh writes.
	--
	-- The capture used to sample A_MUX exactly ONE clock (20ns) after asserting
	-- U2OE_n/U3OE_n. A 74LVC245's output-enable time is ~6-9ns, on top of the
	-- FPGA's own output delay on the OE pin and the settling of eight lines
	-- through the GPIO header into the daughter board. 20ns was right at the
	-- edge, and worst-case exactly when all eight lines have to slew HIGH
	-- together.
	--
	-- That is why 0FFFFh specifically failed. It is the only address where all
	-- 16 bits are 1, so it demands a full all-high settle TWICE in one cycle.
	-- A single line not yet valid means s_A /= FFFF, so ffff never asserts,
	-- exp_wr_raw never opens a window, and the subslot write vanishes with no
	-- error and no retry.
	--
	-- Measured on real hardware: ffffstress.rom reported ~16% of subslot writes
	-- lost (10,670 of 65,536), 99.6% of them as "got == previous value" - i.e.
	-- dropped, not corrupted. The exp_slot rejected-window counter added for
	-- this read ZERO, proving the window never opened rather than being
	-- discarded by the length filter. Meanwhile 27MB of mapper soak was
	-- perfectly clean, because ordinary sequential addresses never demand this
	-- worst case.
	--
	-- Sampling 3 clocks (60ns) after the enable gives 3x the previous margin,
	-- and still completes the whole capture well before /WR falls.
	-- ------------------------------------------------------------------------
	-- ------------------------------------------------------------------------
	-- MEASURED 2026-08-18: this must be as SMALL as possible, not as large as
	-- possible. Raising it from 0 to 2 made the failure WORSE (16% -> 18% of
	-- subslot writes lost), which is the clearest evidence yet that the
	-- capture is racing /WR rather than failing to settle.
	--
	-- The budget: at 3.58MHz the Z80 drops MREQ at ~140ns into the cycle and
	-- /WR one full T-state later at ~419ns - 279ns to reconstruct the address.
	-- Cost with SETTLE=2: 60ns trigger synchroniser + 220ns FSM = ~280ns, dead
	-- level with the deadline. With SETTLE=0 the FSM is 7 clocks (140ns), so
	-- ~200ns total and ~79ns of margin.
	--
	-- Confirmed by measurement, not inference: the s_ffff_slt decode counter
	-- read 0000 (no shortfall - the address IS reconstructed correctly), while
	-- exp_slot's rejected-window counter read 0 and only 53,678 of 65,536
	-- writes committed. Windows are not being rejected, they are never
	-- OPENING - so ffff arrives outside the /WR window. Correct address,
	-- wrong time.
	-- ------------------------------------------------------------------------
	constant AMUX_SETTLE : integer := 0;	-- extra wait states; sample at SETTLE+1 clocks
	signal capture_wait  : integer range 0 to 7 := 0;
	signal addr_capture_state : addr_capture_state_t := S_IDLE;

	-- ------------------------------------------------------------------------
	-- s_addr_valid: '1' only while s_A holds a COMPLETE, self-consistent
	-- address (both bytes captured from the same bus cycle).
	--
	-- BUG FIX (2026-08-13, real hardware - this is the bug behind the
	-- "SD+mapper together hang, either one alone is fine" behaviour seen on
	-- both the Canon V-8 and V-25):
	-- s_A(7 downto 0) is captured at S_LOW_CAP but s_A(15 downto 8) only 3
	-- cycles later at S_HIGH_CAP, so for ~80ns in between s_A is a CHIMERA -
	-- the new cycle's low byte paired with the PREVIOUS cycle's high byte.
	-- Every combinational decode of s_A saw that chimera as if it were a real
	-- address. The pre-existing note above already flags this hazard for
	-- s_ffff_slt (a change was reverted once because of it), but the SD
	-- register window decode was never protected.
	--
	-- Concretely: DEV_RW's inner loop alternates a read of SD_DATA (0x7B00,
	-- page 1) with a write of that byte into the sector buffer. When the
	-- buffer lives in the CART's own mapper RAM (which only happens when the
	-- mapper is enabled - hence SD-alone and mapper-alone both testing clean),
	-- a write to e.g. 0xC100 transiently presents s_A = 0x7B00: the new low
	-- byte 0x00 against the stale high byte 0x7B. That is exactly SD_DATA,
	-- with WR_n asserted - so the bridge saw a spurious SD write access,
	-- asserted WAIT_n and started a handshake nobody asked for. Sector
	-- buffers are 512-byte aligned, so every sector transfer walks low bytes
	-- 0x00-0x08 and is GUARANTEED to hit the 0x7B00-0x7B08 window on the very
	-- first boot-sector read - matching the hang on the Nextor splash.
	--
	-- The same chimera also reached SRAM_WE_N/the SRAM address, so an
	-- in-progress write pulse could strobe a WRONG SRAM cell before the
	-- address settled - silent memory corruption on every mapper write.
	signal s_addr_valid : std_logic := '0';

	-- Glitch filter threshold shared by every register-write qualifier below
	-- (mapper I/O ports, ROM bank switch, SD slot-select, timer load) - see
	-- MegaROM_ASCII16/MSX_FPGA_Top.vhd for the real-hardware measurement
	-- (~80ns electrical glitch vs a genuine ~280ns T-state) that established
	-- this threshold. Never applied to reads or to memory-space bus-driving
	-- signals (FL_CE_N/FL_ADDR/D/U1OE_n/U1_DIR for ROM/RAM reads) - those
	-- stay raw/immediate, a real Z80 memory cycle has no slack to spare.
	constant MIN_PULSE_CYCLES : integer := 8;	-- 8 * 20ns = 160ns

	-- ------------------------------------------------------------------------
	-- Slot expansion: exp_slot.vhd creates 2 usable sub-slots inside this
	-- cartridge's primary slot - subslot 0 (ROM, the reset default for every
	-- page) and subslot 1 (RAM/mapper).
	-- ------------------------------------------------------------------------
	signal s_sltsl_en		: std_logic;
	signal s_ffff_slt		: std_logic;
	signal slt_exp_n		: std_logic_vector(3 downto 0);
	signal s_expn_q		: std_logic_vector(7 downto 0);
	signal s_sltsl_rom_en	: std_logic;
	signal s_sltsl_ram_en	: std_logic;

	-- Sticky "sub-slot was ever genuinely read" latches - the key real-
	-- hardware bring-up diagnostic for this integration (see header note).
	signal s_rom_subslot_ever_q : std_logic := '0';
	signal s_ram_subslot_ever_q : std_logic := '0';

	-- ------------------------------------------------------------------------
	-- ROM sub-slot: ASCII16 Flash boot, locked to flashbase 0x000000 (Nextor).
	-- ------------------------------------------------------------------------
	signal rom_bank1_q	: std_logic_vector(2 downto 0) := (others => '0');
	signal rom_bank2_q	: std_logic_vector(3 downto 0) := (others => '0');
	signal s_flashbase	: std_logic_vector(23 downto 0);
	signal s_rom_a			: std_logic_vector(31 downto 0);

	-- Shared glitch-filtered write qualifier for every register write inside
	-- the ROM sub-slot's memory space (bank-switch registers, SD card slot
	-- select, timer load) - these are not bus-driving/timing-critical, so
	-- they reuse this one qualifier instead of a raw combinational decode.
	-- D is re-latched CONTINUOUSLY while qualified='1' (never sampled once on
	-- a delayed edge) - see header note on the MegaROM_ASCII16 bug this
	-- avoids.
	signal s_cart_write_en        : std_logic;
	signal s_cart_write_dur_cnt   : std_logic_vector(3 downto 0) := (others => '0');
	signal s_cart_write_qualified : std_logic := '0';

	-- ------------------------------------------------------------------------
	-- SD card register bridge (see sdcard_bridge.vhd for the full register
	-- map and the ported XESS SdCardCtrl core it wraps). Single physical SD
	-- card slot on this DE0 board.
	-- ------------------------------------------------------------------------
	signal clock_i			: std_logic := '0';	-- 25MHz, feeds ONLY sdcard_bridge - see "CLOCK DOMAINS" note above
	signal s_sdbridge_cs_s	: std_logic;	-- combinational CS into the bridge (bridge does its own internal sync)

	signal sd_reg_dout		: std_logic_vector(7 downto 0);	-- SD_STATUS/SD_ERRLO/SD_ERRHI (immediate)
	signal sd_data_dout	: std_logic_vector(7 downto 0);	-- SD_DATA (WAIT_n-gated)
	signal sd_data_rd_en	: std_logic;

	signal s_sd_clk		: std_logic;
	signal s_sd_mosi		: std_logic;
	signal s_sd_cs			: std_logic;

	-- Debug outputs from the bridge, for HEX/LEDG below.
	signal dbg_sd_busy			: std_logic;
	signal dbg_sd_error		: std_logic_vector(15 downto 0);
	signal dbg_sd_timeout		: std_logic;
	signal dbg_sd_last_tx		: std_logic_vector(7 downto 0);
	signal dbg_sd_last_rx		: std_logic_vector(7 downto 0);
	signal dbg_sd_data_cnt		: std_logic_vector(7 downto 0);
	signal dbg_sd_marker		: std_logic_vector(7 downto 0);

	-- ------------------------------------------------------------------------
	-- DIAGNOSTIC (2026-08-18): count how many times the address capture ever
	-- decodes 0FFFFh at all (rising edges of s_ffff_slt).
	--
	-- exp_slot's rejected-window counter reads ZERO while ffffstress reports
	-- ~11,500 lost subslot writes, so the write window never OPENS. Two things
	-- can cause that and they need opposite fixes:
	--   s_A never reads FFFF          -> the A_MUX capture is producing the
	--                                    wrong address
	--   s_A reads FFFF but TOO LATE   -> capture finishes after /WR has risen,
	--                                    so the window has already gone
	--
	-- ffffstress performs exactly 65536 writes, so a 16-bit counter wraps to
	-- 0000 if every one of them decoded. Anything else is the shortfall:
	--   0000  -> every write decoded as FFFF; the capture is fine and the
	--            problem is timing (too late), or sltsl/wr qualification
	--   ~D2C6 -> ~11,500 writes never decoded as FFFF; the capture itself is
	--            producing wrong addresses
	-- ------------------------------------------------------------------------
	signal dbg_exp_reg		: std_logic_vector(7 downto 0);
	signal dbg_sd_ever_accessed: std_logic;
	signal dbg_sd_init_done	: std_logic;

	-- SD register-window read decode - not WAIT_n-gated (SD_STATUS/SD_ERRLO/
	-- SD_ERRHI are immediate reads, matching the old spi_ctrl_rd_s's raw/
	-- immediate style), qualifies when to mux sd_reg_dout onto D below.
	signal s_sdbridge_reg_rd_s : std_logic;

	-- ------------------------------------------------------------------------
	-- RAM sub-slot: standard MSX Memory Mapper (512KB), ported verbatim from
	-- MemoryMapper/MSX_FPGA_Top.vhd (real-hardware-tested on a Canon V-8/V-9
	-- today - see project_memorymapper_hardware_test memory). Reset defaults
	-- (3,2,1,0 for page0..page3) and register semantics unchanged.
	-- ------------------------------------------------------------------------
	-- MAPPER SIZE: 32 segments / 512KB.
	--
	-- CORRECTION (2026-08-16): this was briefly narrowed to 16 segments on the
	-- reasoning that only 8 of the SRAM's 16 data lines are wired, so only one
	-- byte lane could be reached. That reasoning was WRONG. The IS61LV25616AL
	-- is 256K x 16 = 512KB, and UB_N/LB_N select WHICH BYTE of each word is
	-- accessed. With the chip's DQ[7:0] and DQ[15:8] tied together onto the
	-- same 8 FPGA pins - a standard way to build a byte-wide memory from a x16
	-- part - address bit 18 selecting the lane yields the full 512KB through
	-- those 8 lines. That is what the original design did, and it is correct.
	--
	-- The BIST only ever swept the LOWER lane, so it could not have shown
	-- anything about the upper one; it is now extended to the full 19-bit space
	-- with address-driven lane selection, so it exercises both lanes exactly as
	-- the mapper does. If it passes, 512KB is genuinely present.
	signal reg_page0_q : std_logic_vector(4 downto 0) := "00011";
	signal reg_page1_q : std_logic_vector(4 downto 0) := "00010";
	signal reg_page2_q : std_logic_vector(4 downto 0) := "00001";
	signal reg_page3_q : std_logic_vector(4 downto 0) := "00000";

	-- Mapper I/O port decode (FCh-FFh) - global, gated only by SW(9)='0'
	-- (SDMapper mode), NOT by SLTSL_n/sub-slot - per msx.org/wiki/Memory_Mapper, mapper port writes
	-- are system-wide, not slot-scoped.
	signal s_io_mapper_en    : std_logic;
	signal s_io_mapper_rd_en : std_logic;
	signal s_io_mapper_wr_en : std_logic;


	signal s_mapper_rdata : std_logic_vector(7 downto 0);

	-- Memory (SLTSL_n, RAM sub-slot-gated) access - raw/immediate decode,
	-- same timing rationale as the ROM sub-slot's own memory access.
	signal s_mem_rd_en : std_logic;
	signal s_mem_wr_en : std_logic;

	-- ------------------------------------------------------------------------
	-- s_rom_rd_en: "the Flash is genuinely selected AND driving for this read".
	--
	-- BUG FIX (2026-08-13, real hardware: 000 still unstable after the
	-- s_addr_valid fix, while 010 - same design with the mapper switched off -
	-- stayed clean). The D-bus mux and U1_DIR selected FL_DQ on nothing more
	-- than "s_sltsl_rom_en = '1' and RD_n = '0'", with NO page restriction -
	-- but FL_CE_N only actually asserts for page 1, or page 2 when
	-- rom_bank2_q >= 8. So for a read in page 0, page 3, or page 2 with
	-- bank < 8, the mux happily drove the MSX bus from FL_DQ while the Flash
	-- chip was DESELECTED and not driving anything: floating garbage.
	--
	-- That collides head-on with the mapper: s_sltsl_ram_en is deliberately
	-- unconditional for pages 0/2/3 (see its own note), and exp_slot's
	-- reset-default subslot is 0 = ROM, so in those pages s_sltsl_rom_en and
	-- s_sltsl_ram_en are BOTH true. ROM won by mux priority, so every read of
	-- the cart's mapper RAM in pages 0/2/3 returned floating Flash data
	-- instead of the SRAM byte. With the mapper disabled there is no cart RAM
	-- to read and the conflict cannot arise - exactly why 010 tested clean and
	-- 000 did not.
	--
	-- Mirrors FL_CE_N's own conditions exactly, so the mux can never select
	-- FL_DQ unless the Flash is actually enabled and driving.
	signal s_rom_rd_en : std_logic;

	signal s_mem_page_seg  : std_logic_vector(4 downto 0);
	signal s_sram_full_addr : std_logic_vector(18 downto 0);	-- '0' & segment(3:0) & s_A(13:0) = 256K, lower byte lane only

begin

	-- Inverted here to compensate for the Q2 open-collector driver stage on
	-- the MSX_FPGA_Hat board, which inverts whatever level the FPGA drives.
	WAIT_n <= not s_sdbridge_wait_n_o;


	-- ----------------------------------------------------------------------------
	-- 3. RESET
	-- ----------------------------------------------------------------------------
	-- Reset circuit
	-- ------------------------------------------------------------------------
	-- Reset controller (2026-08-16).
	--
	-- Requested after observing that behaviour depends on WHEN the DE0 reset
	-- button is pressed relative to MSX power-on - i.e. state was surviving
	-- across resets and the machine could start with the cart in an arbitrary
	-- condition.
	--
	-- s_reset used to be a bare combinational term:
	--     s_reset <= not (KEY(0) and RESET_n);
	-- Both inputs are asynchronous to every clock in this design, so a short
	-- or noisy pulse could reset some registers and not others, leaving the
	-- cart internally inconsistent - which is exactly the kind of thing that
	-- makes boot behaviour depend on button timing.
	--
	-- Now: both sources are synchronized into CLOCK_50, and ANY assertion
	-- (MSX /RESET or KEY(0)) loads a stretch counter so the reset is held for
	-- a guaranteed minimum afterwards. Every register in this design resets
	-- from s_reset, including exp_slot's subslot register, the mapper segment
	-- registers, the ROM bank registers, the address-capture FSM and the SD
	-- bridge (which in turn re-runs SdCardCtrl's CMD0/CMD8/ACMD41 sequence),
	-- so an MSX reset or power-on now genuinely returns the cart to a known
	-- state rather than leaving whatever was there before.
	-- ------------------------------------------------------------------------
	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			s_rst_src_meta <= not (KEY(0) and RESET_n);
			s_rst_src_sync <= s_rst_src_meta;

			-- NOISE FILTER (2026-08-16). Real hardware evidence: LEDG(8) is a
			-- STICKY latch (s_ram_subslot_ever_q) that can only be cleared by
			-- s_reset - and it was observed lighting during boot and then going
			-- OUT at the moment the machine hangs. That is direct proof the
			-- design is being RESET mid-operation, which clears exp_reg to 0x00
			-- (matching readings seen), resets the mapper segment registers,
			-- and zeroes the ROM bank registers - swapping the code window out
			-- from under the running CPU. Hang with varying symptoms, exactly
			-- as observed.
			--
			-- RESET_n is a long unterminated line on a ribbon cable next to
			-- switching bus signals, so it picks up noise. A genuine MSX reset
			-- lasts MILLISECONDS; interference lasts nanoseconds. Requiring the
			-- source to stay asserted for 128 clocks (~2.6us at 50MHz) ignores
			-- interference by orders of magnitude while still responding to a
			-- real reset far faster than a human could notice.
			if s_rst_src_sync = '1' then
				if s_rst_filter /= "1111111" then
					s_rst_filter <= s_rst_filter + 1;
				end if;
			else
				s_rst_filter <= (others => '0');
			end if;

			if s_rst_filter = "1111111" then
				s_rst_stretch <= (others => '1');	-- genuine reset: (re)arm
			elsif s_rst_stretch /= "000" then
				s_rst_stretch <= s_rst_stretch - 1;	-- hold for a guaranteed minimum
			end if;
		end if;
	end process;

	s_reset <= '1' when s_rst_filter = "1111111" or s_rst_stretch /= "000" else '0';
	INT_n <= '0';	-- inverted due to the Q1 open-collector stage in the interface
	SOUNDOUT <= '0';
	U4OE_n <= '0';	-- unused buffer on this variant - disabled

	-- ------------------------------------------------------------------------
	-- Address bus capture: synchronize the "new bus cycle starting" trigger
	-- (falling edge of MREQ_n or IORQ_n), then run the low/high byte capture
	-- state machine, on CLOCK_50. See "ADDRESS BUS MULTIPLEXING" note above.
	--
	-- REVERTED (2026-08-12): briefly tried capturing HIGH byte first (low
	-- second) to shave latency off spi_cs_s's assertion, on the theory that
	-- /WAIT was arriving too late relative to a Z80's T2 sampling point (see
	-- SD/SPI investigation notes in memory). Real hardware regression: this
	-- caused a genuine HANG (confirmed after a full power-cycle, not just
	-- stale reprogram state) at the same point every time, worse than the
	-- "Card Failed!" it was meant to fix. Suspected mechanism: capturing
	-- high-then-low creates a brief window where s_A holds the NEW high
	-- byte paired with the STALE low byte from the previous cycle (the
	-- original low-then-high order has the same hazard, just with the byte
	-- pairing reversed) - s_ffff_slt ("s_A = x\"FFFF\"") is used directly,
	-- combinationally, in the D-bus mux, so a transient mismatched pairing
	-- that happens to read as 0xFFFF could spuriously trigger exp_slot's
	-- subslot-select register write and corrupt ROM/RAM page routing - a
	-- hang, not a clean failure, matches exactly what was observed. Reverted
	-- to the original low-then-high order pending a safer way to address
	-- the /WAIT latency theory (e.g. a dedicated, narrowly-scoped early
	-- high-byte snapshot used ONLY for spi_cs_s, never touching s_ffff_slt
	-- or other sensitive combinational decode).
	-- ------------------------------------------------------------------------

	-- ----------------------------------------------------------------------------
	-- 4. ADDRESS CAPTURE (A_MUX) - see the header note
	-- ----------------------------------------------------------------------------
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
			elsif addr_capture_trigger = '1' then
				-- Preemption always disables both OEs explicitly first,
				-- guaranteeing at least one dead cycle before S_LOW_EN's own
				-- branch re-enables U2 - avoids bus contention if a new cycle
				-- starts mid-capture.
				addr_capture_state <= S_LOW_EN;
				U2OE_n <= '1';
				U3OE_n <= '1';
				capture_wait <= 0;
				-- A new bus cycle invalidates the previous address IMMEDIATELY:
				-- from here until S_HIGH_CAP completes, s_A is a mix of old and
				-- new bytes and must not be decoded by anything (see the
				-- s_addr_valid declaration for the failure this caused).
				s_addr_valid <= '0';
			else
				case addr_capture_state is
					when S_IDLE =>
						U2OE_n <= '1';
						U3OE_n <= '1';
					when S_LOW_EN =>
						U2OE_n <= '0';		-- enable low address byte (A0-A7)
						U3OE_n <= '1';
						addr_capture_state <= S_LOW_CAP;
					when S_LOW_CAP =>
						s_A(7 downto 0) <= A_MUX;
						addr_capture_state <= S_GUARD;
					when S_GUARD =>
						U2OE_n <= '1';
						U3OE_n <= '1';
						addr_capture_state <= S_HIGH_EN;
					when S_HIGH_EN =>
						U2OE_n <= '1';
						U3OE_n <= '0';		-- enable high address byte (A8-A15)
						addr_capture_state <= S_HIGH_CAP;
					when S_HIGH_CAP =>
						s_A(15 downto 8) <= A_MUX;
						s_addr_valid <= '1';	-- both bytes now from the same cycle: s_A is safe to decode
						addr_capture_state <= S_IDLE;
					when others =>
						addr_capture_state <= S_IDLE;
				end case;
			end if;
		end if;
	end process;

	-- ------------------------------------------------------------------------

	-- ----------------------------------------------------------------------------
	-- 5. SLOT DECODE (expansion, ROM vs RAM sub-slot)
	-- ----------------------------------------------------------------------------
	-- Slot expansion
	-- ------------------------------------------------------------------------

	s_sltsl_en    <= (not SLTSL_n) when SW(9) = '0' else '0';		-- SDMapper (Nextor+Mapper) enabled only when SW(9)='0' - see SW(9) note above
	-- s_addr_valid gate: see its declaration. The pre-existing note in the
	-- address-capture section already identified s_ffff_slt as vulnerable to
	-- a transient mismatched byte pairing reading as 0xFFFF and spuriously
	-- triggering exp_slot's subslot-select write ("a hang, not a clean
	-- failure"); this makes that impossible rather than order-dependent.
	s_ffff_slt    <= '1' when s_A = x"FFFF" and s_addr_valid = '1' else '0';
	-- SYSTEMATIC s_addr_valid GATING (2026-08-16).
	--
	-- This board reconstructs the address from the time-multiplexed A_MUX, so
	-- s_A is only trustworthy once BOTH bytes are captured (s_addr_valid).
	-- Belavenuto's msxsdmapperv2 - the working reference for this same ROM+RAM
	-- expanded-slot structure - sits directly on all 16 address lines and has
	-- no such window, which is why its subslot logic behaves and ours has not.
	-- The rule here is simply: decode NOTHING until the address is complete.
	--
	-- These two were the remaining holes found by auditing every consumer of
	-- s_A. slt_exp_n is computed by exp_slot from RAW s_A(15 downto 14), so
	-- during the capture window it selects the PREVIOUS cycle's page - and
	-- s_sltsl_rom_en feeds s_cart_write_en (the ROM bank-switch qualifier),
	-- which had no gate of its own. Gating at the source means every
	-- downstream user inherits it rather than needing its own gate.
	s_sltsl_rom_en <= (not slt_exp_n(0)) when SW(9) = '0' and s_addr_valid = '1' else '0';

	-- RAM sub-slot arbitration: real sub-slot arbitration (via exp_slot,
	-- gated behind an FFFF write selecting sub-slot 1) is only needed for
	-- page 1 (0x4000-0x7FFF), where the ROM's ASCII16 bank-1 window is
	-- genuinely also present and Nextor's kernel is expected to switch
	-- between the two itself as part of its own driver logic. This Nextor
	-- image is exactly 128KB = 8x16KB, entirely reachable through
	-- rom_bank1_q (3 bits, values 0-7) alone - the ROM's bank-2 window
	-- (page 2) only ever activates when rom_bank2_q>=8, which this kernel
	-- never does, and the ROM never responds in pages 0/3 at all. So pages
	-- 0, 2, and 3 have no real ROM/RAM contest and RAM is made visible
	-- there unconditionally (matching the standalone, real-hardware-tested
	-- MemoryMapper project's own direct-SLTSL_n-gated behavior) rather than
	-- sitting invisible behind exp_slot's reset-default ROM routing with no
	-- guarantee anything (BIOS or kernel) will ever write FFFF to reach it.
	-- BUG FIX (2026-08-11, real hardware: Canon V-8 reported far less mapper
	-- RAM than expected after this port - that machine's own primary-slot
	-- routing only ever reaches this cartridge via page 2, exactly the page
	-- this fix stops gating behind a sub-slot switch nothing was issuing).
	--
	-- DIAGNOSTIC GATE (2026-08-13): SW(8)='1' disables the RAM mapper
	-- entirely, same bisection purpose as the SD gate below (see
	-- s_sdbridge_cs_s) - SW(9)='1' proved the machine is stable with
	-- ROM+RAM+SD all off together, but not which one is at fault. Paired
	-- with SW(7) (SD) this covers every combination in one build:
	--   SW(9)=1            -> everything off (known-stable baseline)
	--   SW(9)=0,SW(8)=1     -> ROM+SD only, mapper off
	--   SW(9)=0,SW(7)=1     -> ROM+RAM only, SD off
	--   SW(9)=0,SW(8)=SW(7)=0 -> normal operation (unchanged from before)
	-- SUBSLOT COMPLIANCE (2026-08-15, real hardware on a Canon V-25).
	--
	-- Evidence: SW(9)='1' (cart silent) gives a CLEAN boot logo; SW(9)='0'
	-- corrupts it, before the driver has done anything. The V-25's own 64KB
	-- lives in slot 3-2 and it has no mapper, so nothing is contending for the
	-- FC-FF ports (an earlier theory of mine, now disproven).
	--
	-- What DOES contend is the BIOS's boot-time RAM search across slots. The
	-- legacy behaviour below answered as RAM in pages 0/2/3 REGARDLESS of the
	-- selected subslot - i.e. our cart claimed RAM while its own reset-default
	-- subslot 0 (ROM) was selected. During the RAM search the BIOS can then
	-- latch onto this cartridge as the main RAM slot instead of 3-2, and every
	-- subsequent thing - including the workspace the logo routine uses - runs
	-- out of our SRAM behind an expanded slot and a mapper. That matches the
	-- corrupted logo, the absurd free-RAM figures and the Syntax Error loops,
	-- and matches SW(9)='1' being clean.
	--
	-- That unconditional behaviour was a workaround for the Canon V-8, where
	-- nothing ever wrote FFFF to select subslot 1 so the mapper was otherwise
	-- unreachable. It is NOT standard: a compliant cartridge only presents its
	-- RAM when its own subslot is selected.
	--
	-- SW(6) selects between them, so this can be tested rather than assumed:
	--   SW(6)='0' -> STANDARD: RAM only when subslot 1 is actually selected,
	--                in every page. Does not compete in the BIOS RAM search.
	--   SW(6)='1' -> LEGACY V-8 workaround: RAM visible in pages 0/2/3 with no
	--                subslot check (what this design did until now).
	s_sltsl_ram_en <= '0' when s_sltsl_en = '0' or SW(8) = '1' or s_addr_valid = '0'  else
	                  '1' when slt_exp_n(1) = '0'                                     else	-- RAM subslot genuinely selected
	                  '1' when SW(6) = '1' and s_A(15 downto 14) /= "01"              else	-- legacy V-8 workaround
	                  '0';

	s_reset_n     <= not s_reset;
	s_sltsl_dis_n <= not s_sltsl_en;

	exp: entity work.exp_slot
	port map (
		clock_i		=> CLOCK_50,
		reset_n		=> s_reset_n,
		sltsl_n		=> s_sltsl_dis_n,
		cpu_rd_n		=> RD_n,
		cpu_wr_n		=> WR_n,
		ffff			=> s_ffff_slt,
		cpu_a			=> s_A(15 downto 14),
		cpu_d			=> D,
		cpu_q			=> s_expn_q,
		exp_n			=> slt_exp_n,
		exp_reg_o	=> dbg_exp_reg
	);

	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				s_rom_subslot_ever_q <= '0';
				s_ram_subslot_ever_q <= '0';
			else
				if s_sltsl_rom_en = '1' and RD_n = '0' then
					s_rom_subslot_ever_q <= '1';
				end if;
				if s_sltsl_ram_en = '1' and RD_n = '0' then
					s_ram_subslot_ever_q <= '1';
				end if;
			end if;
		end if;
	end process;

	-- ------------------------------------------------------------------------
	-- ROM sub-slot: ASCII16 Flash boot (Nextor, flashbase 0x000000). DE0
	-- onboard parallel Flash is 16-bit forced into 8-bit "byte mode"
	-- (FL_BYTE_N='0'): FL_ADDR carries bits [22:1], the LSB (A-1) goes out on
	-- FL_DQ15_AM1 instead.
	-- ------------------------------------------------------------------------
	FL_RST_N <= not s_reset;
	FL_OE_N <= RD_n;
	FL_BYTE_N <= '0';	-- 8-bit byte mode
	FL_WP_N <= '0';		-- write-protect not used (writes are permanently disabled below anyway)
	FL_WE_N <= '1';		-- permanently disabled: never write to the shared Flash

	s_flashbase <= x"000000";		-- FlashRAM address for the Nextor Operating System

	-- Checks the address being accessed. Mirrors memory as per information in https://www.msx.org/wiki/MegaROM_Mappers#ASCII16_.28ASCII.29
	s_rom_a(23 downto 0) <= s_flashbase + (rom_bank1_q(2 downto 0) & s_A(13 downto 0)) when s_sltsl_rom_en = '1' and (s_A(15 downto 14) = "01" or s_A(15 downto 14) = "11") else		-- Bank1
                           s_flashbase + (rom_bank2_q(3 downto 0) & s_A(13 downto 0)) when s_sltsl_rom_en = '1' and (s_A(15 downto 14) = "10" or s_A(15 downto 14) = "00") else		-- Bank2:
	                        (others => '-');

	-- Excludes the SD card register window, which lives inside bank 1's
	-- address range - Flash must not drive its outputs while it's accessed.
	FL_CE_N <=
		'0'	when s_A(15 downto 14) = "01" and s_sltsl_rom_en = '1' and RD_n = '0' and s_sdbridge_cs_s = '0' and s_addr_valid = '1'	else
		'0'	when s_A(15 downto 14) = "10" and s_sltsl_rom_en = '1' and rom_bank2_q(3) = '1' and s_addr_valid = '1'					else		-- Only if bank > 7
		'1';

	-- "Flash is genuinely enabled AND driving for this read" - mirrors
	-- FL_CE_N's conditions above (plus RD_n for the page-2 branch, which
	-- FL_CE_N leaves to FL_OE_N). Used by the D-bus mux and U1_DIR so neither
	-- can ever source a byte from a deselected Flash chip. See the
	-- s_rom_rd_en declaration for the bug this fixes.
	--s_rom_rd_en <=
	--	'1'	when s_A(15 downto 14) = "01" and s_sltsl_rom_en = '1' and RD_n = '0' and s_sdbridge_cs_s = '0' and s_addr_valid = '1'	else
	--	'1'	when s_A(15 downto 14) = "10" and s_sltsl_rom_en = '1' and RD_n = '0' and rom_bank2_q(3) = '1' and s_addr_valid = '1'	else
	--	'0';
	-- Added manually to avoid bus contention between Flash and Mapper
	-- In SDMapper_TOP.vhd
	-- CRITICAL (2026-08-15): the "s_sdbridge_cs_s = '0'" term below is NOT
	-- optional. Without it, a read of the SD register window (0x7B00-0x7B0F,
	-- page 01, ROM subslot) also satisfies s_rom_rd_en - and in the D-bus mux
	-- the FL_DQ entry sits ABOVE the sd_data_dout entry, so SD_DATA reads get
	-- muxed from Flash instead of from the card. Worse, FL_CE_N (above) still
	-- excludes the SD window, so the Flash chip is DESELECTED and not driving:
	-- the CPU reads floating 'Z'. The bridge meanwhile captures the correct
	-- byte internally, so the diagnostic display shows perfect data (HEX=AA
	-- after a sector read) while Nextor receives garbage and can never mount.
	-- Keeping this term costs nothing and preserves the manual fix's intent
	-- (no Flash/Mapper contention).
	s_rom_rd_en <= '1' when s_addr_valid = '1'
                    and s_sltsl_rom_en = '1'
                    and RD_n = '0'
                    and s_sdbridge_cs_s = '0'
                    and (s_A(15 downto 14) = "01" or (s_A(15 downto 14) = "10" and rom_bank2_q >= 8))
               else '0';
	
	-- FL_ADDR carries address bits [22:1] of the flash's byte-mode address
	-- space; bit 0 (A-1) goes out on FL_DQ15_AM1 instead (see entity comment).
	FL_ADDR <= s_rom_a(22 downto 1);
	FL_DQ15_AM1 <= s_rom_a(0);

	-- SD card register window - see sdcard_bridge.vhd for the exact
	-- register map. Same "bank 1 switched to segment 7" convention the
	-- abandoned SPI protocol used.
	-- DIAGNOSTIC GATE (2026-08-13): SW(7)='1' disables the SD register window
	-- entirely, leaving ROM boot and the RAM mapper fully live. Purpose: the
	-- machine is stable with SW(9)='1', but that gates ROM, RAM and SD
	-- together, so it does not say WHICH subsystem destabilizes the bus.
	-- Paired with SW(8) (mapper, see s_sltsl_ram_en above) this covers every
	-- combination in one build without needing the mapper switched off on
	-- the V-8 (only 16KB onboard RAM - Nextor genuinely needs the cart's
	-- mapper there):
	--   SW(9)=1              -> everything off (known-stable baseline)
	--   SW(9)=0,SW(8)=1       -> ROM+SD only, mapper off
	--   SW(9)=0,SW(7)=1       -> ROM+RAM only, SD off
	--   SW(9)=0,SW(8)=SW(7)=0 -> normal operation (unchanged from before)
	-- With SW(7)='1': no WAIT_n can ever be asserted, and 7B00-7B08 stops
	-- aliasing over ROM space (those addresses fall through to Flash like
	-- any other ROM byte).
	-- s_addr_valid gate (2026-08-13): THE fix for the SD+mapper hang - see the
	-- s_addr_valid declaration for the full trace. Without it, a mapper-RAM
	-- write to any address whose low byte is 0x00-0x08 transiently looks like
	-- an SD register access while the high byte is still the previous cycle's
	-- 0x7B, spuriously asserting WAIT_n and starting an unrequested transfer.
	--- s_sdbridge_cs_s <= '1' when s_sltsl_rom_en = '1' and SW(7) = '0' and s_addr_valid = '1' and rom_bank1_q = "111" and s_A >= x"7B00" and s_A <= x"7B08" else '0';

   -- Added manually - to workaround address multiplexing "chimera" glitches 
	-- In SDMapper_TOP.vhd
	-- SW(7)='1' disables the SD register window entirely (2026-08-16), so the
	-- Flash ROM can host a standalone mapper test with nothing else of ours on
	-- the bus. The window lives inside ROM address space (7B00-7B0F in bank 7),
	-- so removing it guarantees the test ROM cannot trip over it.
	s_sdbridge_cs_s <= '1' when SW(7) = '0' and s_addr_valid = '1'
                        and s_sltsl_rom_en = '1' 
                        and rom_bank1_q = "111" 
                        and s_A(15 downto 8) = x"7B" 
                        and s_A(7 downto 4) = x"0"
                   else '0';

	-- ----------------------------------------------------------------------------
	-- 6. FLASH / ROM BANKING
	-- ----------------------------------------------------------------------------
	-- ------------------------------------------------------------------------
	-- Shared glitch-filtered write qualifier for ROM sub-slot register
	-- writes (bank switch) - see declaration above for the rationale.
	-- ------------------------------------------------------------------------
	s_cart_write_en <= '1' when s_sltsl_rom_en = '1' and WR_n = '0' else '0';

	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				s_cart_write_dur_cnt   <= (others => '0');
				s_cart_write_qualified <= '0';
			else
				if s_cart_write_en = '1' then
					if s_cart_write_dur_cnt < MIN_PULSE_CYCLES then
						s_cart_write_dur_cnt <= s_cart_write_dur_cnt + 1;
					end if;
					if s_cart_write_dur_cnt >= MIN_PULSE_CYCLES then
						s_cart_write_qualified <= '1';
					end if;
				else
					s_cart_write_dur_cnt   <= (others => '0');
					s_cart_write_qualified <= '0';
				end if;
			end if;
		end if;
	end process;

	-- ROM bank-switch registers: continuously re-latch D while
	-- s_cart_write_qualified holds (see header note on the MegaROM_ASCII16
	-- bug this avoids), rather than sampling once on a delayed edge.
	i_ROM_Banks: process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				rom_bank1_q <= (others => '0');
				rom_bank2_q <= (others => '0');
			else
				-- ----------------------------------------------------------
				-- BUG FIX (2026-08-16): these latched D CONTINUOUSLY while the
				-- write window was qualified, so the value that stuck was the
				-- last sample before the window closed - taken as the Z80
				-- releases the bus, from an asynchronous data bus with no
				-- metastability protection. Same fault as exp_slot's subslot
				-- register and the mapper segment registers, but the WORST of
				-- the three: rom_bank1_q selects which 16KB of Flash is visible
				-- at 4000-7FFF, which is where the kernel and this driver are
				-- EXECUTING. A corrupted bank register swaps the code out from
				-- under the running CPU.
				--
				-- Captured the same way as the others now: sample while the
				-- window is open, keep only values seen identically on two
				-- consecutive samples (D is stable for the whole ~1us write
				-- pulse, so agreement means the sample is real and not
				-- metastable), and commit when the window closes.
				-- ----------------------------------------------------------
				bank_wr_q <= s_cart_write_qualified;

				if s_cart_write_qualified = '1' then
					bank_d_s1 <= D;
					bank_d_s2 <= bank_d_s1;
					if s_A >= x"6000" and s_A <= x"67FF" then
						bank_sel1 <= '1';
						bank_sel2 <= '0';
					elsif s_A >= x"7000" and s_A <= x"77FF" then
						bank_sel1 <= '0';
						bank_sel2 <= '1';
					else
						bank_sel1 <= '0';
						bank_sel2 <= '0';
					end if;
					if bank_d_s1 = bank_d_s2 then
						bank_d_stable    <= bank_d_s2;
						bank_have_stable <= '1';
					end if;
				else
					bank_have_stable <= '0';
				end if;

				-- Same correction as exp_slot: never DROP a bank switch just
				-- because no two samples agreed - a missed bank switch leaves
				-- the wrong 16KB of Flash mapped, which is at least as bad as a
				-- mis-sampled one. Prefer the agreed value, fall back to the
				-- older sample.
				if s_cart_write_qualified = '0' and bank_wr_q = '1' then
					if bank_sel1 = '1' then
						if bank_have_stable = '1' then
							rom_bank1_q <= bank_d_stable(2 downto 0);
						else
							rom_bank1_q <= bank_d_s2(2 downto 0);
						end if;
					elsif bank_sel2 = '1' then
						if bank_have_stable = '1' then
							rom_bank2_q <= bank_d_stable(3 downto 0);
						else
							rom_bank2_q <= bank_d_s2(3 downto 0);
						end if;
					end if;
				end if;
			end if;
		end if;
	end process;

	-- SD register-window read decode - raw/immediate, not glitch-filtered
	-- (matches every other bus-driving read in this file). Only qualifies
	-- SD_STATUS/SD_ERRLO/SD_ERRHI (reg index /= 0) - SD_DATA (index 0) is
	-- WAIT_n-gated through sd_data_rd_en instead, driven by the bridge
	-- itself.
	s_sdbridge_reg_rd_s <= '1' when s_sdbridge_cs_s = '1' and RD_n = '0' and s_A /= x"7B00" else '0';

	-- Generate the 25MHz clock_i for the SD card bridge ONLY - see "CLOCK
	-- DOMAINS" note at the top of this file.
	clock_25mhz_inst : clock_25mhz PORT MAP (
		inclk0   => CLOCK_50,
		c0       => clock_i
	);

	-- SD card register bridge (ported XESS SdCardCtrl core + Z80-bus
	-- glue) - see sdcard_bridge.vhd for the full register map and design
	-- rationale.

	-- ----------------------------------------------------------------------------
	-- 7. SD CARD BRIDGE (sdcard_bridge.vhd / sdcard_xess.vhd)
	-- ----------------------------------------------------------------------------
	sdbridge_inst: entity work.sdcard_bridge
	port map (
		clock_i			=> clock_i,
		reset_n_i		=> s_reset_n,
		cs_i				=> s_sdbridge_cs_s,
		reg_addr_i		=> s_A(3 downto 0),
		data_bus_i		=> D,
		wr_n_i			=> WR_n,
		rd_n_i			=> RD_n,
		wait_n_o			=> s_sdbridge_wait_n_o,
		card_present_i	=> SW(0),
		write_protect_i=> SW(2),
		reg_dout			=> sd_reg_dout,
		sd_dout			=> sd_data_dout,
		sd_rd_en			=> sd_data_rd_en,
		sd_cs_o			=> s_sd_cs,
		sd_sclk_o		=> s_sd_clk,
		sd_mosi_o		=> s_sd_mosi,
		sd_miso_i		=> SD1_MISO,
		dbg_busy_o				=> dbg_sd_busy,
		dbg_error_o				=> dbg_sd_error,
		dbg_timeout_o			=> dbg_sd_timeout,
		dbg_last_tx_o			=> dbg_sd_last_tx,
		dbg_last_rx_o			=> dbg_sd_last_rx,
		dbg_ever_accessed_o	=> dbg_sd_ever_accessed,
		dbg_init_done_o		=> dbg_sd_init_done,
		dbg_data_cnt_o			=> dbg_sd_data_cnt,
		dbg_marker_o			=> dbg_sd_marker
	);

	-- Onboard microSD (single physical card - see header note). CS is now
	-- driven directly by the ported XESS core itself (it manages
	-- select/deselect internally as part of every command sequence),
	-- unlike the old sd_sel_q-selected scheme which only ever had one real
	-- card to select anyway.
	SD1_CS   <= s_sd_cs;
	SD1_SCK  <= s_sd_clk;
	SD1_MOSI <= s_sd_mosi;

	-- ------------------------------------------------------------------------
	-- RAM sub-slot: standard MSX Memory Mapper (512KB) - logic ported
	-- verbatim from MemoryMapper/MSX_FPGA_Top.vhd (see declarations above).
	-- ------------------------------------------------------------------------
	-- SW(8) gates the mapper I/O ports as well as the RAM (2026-08-16).
	--
	-- Taken from Belavenuto's msxsdmapperv2, which is the working reference for
	-- this exact ROM+RAM expanded-slot structure. There, ONE switch disables
	-- the mapper, the slot expander AND the FCh-FFh ports together:
	--     io_cs         <= not iorq_n_i and m1_n_i and sw_i(0);
	--     sltsl_ram_n_s <= slt_exp_n(1) when sw_i(0) = '1' else '1';
	--
	-- Ours gated the ports on SW(9) alone, so with SW(8)='1' the RAM was
	-- disabled but we STILL answered FCh-FFh - advertising a memory mapper
	-- with no memory behind it. DOS probes those ports, concludes a mapper
	-- exists, sizes it, and then writes into nothing. That made "mapper off"
	-- an incoherent configuration rather than a clean one, and any test run in
	-- it was measuring a machine being told a lie.
	-- s_addr_valid gate: the port number comes from s_A(7 downto 2), which is
	-- part of the same reconstructed address - a chimera can transiently read
	-- as a mapper port access. See the gating note at s_sltsl_rom_en.
	s_io_mapper_en    <= '1' when SW(9) = '0' and SW(8) = '0' and s_addr_valid = '1' and IORQ_n = '0' and M1_n = '1' and s_A(7 downto 2) = "111111" else '0';

	s_io_mapper_rd_en <= '1' when s_io_mapper_en = '1' and RD_n = '0' else '0';
	s_io_mapper_wr_en <= '1' when s_io_mapper_en = '1' and WR_n = '0' else '0';



	-- ----------------------------------------------------------------------------
	-- 8. MEMORY MAPPER (segment registers + SRAM)
	-- ----------------------------------------------------------------------------
	-- ------------------------------------------------------------------------
	-- Mapper segment registers. SIMPLIFIED 2026-08-18 to match exp_slot and the
	-- msxsdmapperv2 reference: a combinational write window, and a capture on
	-- its trailing edge taking the previous sample so the committed value is
	-- one clock clear of the Z80 releasing the bus.
	--
	-- Removed: an 8-clock (160ns) pulse-qualification counter and a 2-deep
	-- stability pipeline with a minimum-window check. Belavenuto's mapper.vhd
	-- has neither - just "mp_wr_s <= '1' when ioFx_i='1' and cpu_wr_n_i='0'"
	-- and a register clocked off it - and the qualification delay was pure
	-- latency on every port access.
	-- ------------------------------------------------------------------------
	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				reg_page0_q  <= "00011";	-- MSX reset defaults: 3/2/1/0
				reg_page1_q  <= "00010";
				reg_page2_q  <= "00001";
				reg_page3_q  <= "00000";
				map_d_q      <= (others => '0');
				map_sel_q    <= (others => '0');
				map_wr_q     <= '0';
			else
				map_wr_q <= s_io_mapper_wr_en;

				if s_io_mapper_wr_en = '1' then
					map_d_q   <= D(4 downto 0);
					map_sel_q <= s_A(1 downto 0);
				end if;

				if s_io_mapper_wr_en = '0' and map_wr_q = '1' then
					case map_sel_q is
						when "00"   => reg_page0_q <= map_d_q;
						when "01"   => reg_page1_q <= map_d_q;
						when "10"   => reg_page2_q <= map_d_q;
						when others => reg_page3_q <= map_d_q;
					end case;
				end if;
			end if;
		end if;
	end process;

	-- Unimplemented segment bits read back as 1, which is how MSX-DOS sizes a
	-- mapper: 3 unimplemented bits above a 5-bit segment number = 32 segments.
	s_mapper_rdata <= "111" & reg_page0_q when s_A(1 downto 0) = "00" else
	                   "111" & reg_page1_q when s_A(1 downto 0) = "01" else
	                   "111" & reg_page2_q when s_A(1 downto 0) = "10" else
	                   "111" & reg_page3_q;

	-- Memory (RAM sub-slot) access - raw/immediate decode.
	-- s_addr_valid gate (2026-08-13): the mid-capture chimera address also
	-- reached SRAM_WE_N and the SRAM address bus, so a write pulse could
	-- strobe a WRONG cell for the ~80ns before the high byte settled - silent
	-- corruption on every mapper write, not just the SD-window aliasing.
	-- BUG FIX (2026-08-15, real hardware: NEXTOR.SYS loads from SD and prints
	-- its banner, then the machine hangs - with the SD core idle, no error and
	-- no timeout, i.e. not a bus stall but corrupted memory).
	--
	-- 0xFFFF must be EXCLUDED from the RAM path. In a real expanded slot that
	-- address IS the subslot-select register and the RAM byte behind it is
	-- simply not accessible. Here s_sltsl_ram_en is unconditional for pages
	-- 0/2/3 (see its own note), so every write to 0xFFFF also asserted
	-- SRAM_WE_N and clobbered one byte of the currently-mapped mapper segment.
	-- Reads were already safe by mux priority (s_expn_q outranks SRAM_DQ), but
	-- writes were not gated anywhere.
	--
	-- Harmless while nothing important lived in mapper RAM - which is why this
	-- only began to bite at exactly this point: once NEXTOR.SYS is loaded and
	-- the kernel starts running from mapper RAM, it performs inter-slot calls
	-- constantly, and every one writes 0xFFFF and silently destroys a byte of
	-- its own working memory.
	s_mem_rd_en <= '1' when s_sltsl_ram_en = '1' and RD_n = '0' and s_addr_valid = '1' and s_ffff_slt = '0' else '0';
	s_mem_wr_en <= '1' when s_sltsl_ram_en = '1' and WR_n = '0' and s_addr_valid = '1' and s_ffff_slt = '0' else '0';

	s_mem_page_seg <= reg_page0_q when s_A(15 downto 14) = "00" else
	                   reg_page1_q when s_A(15 downto 14) = "01" else
	                   reg_page2_q when s_A(15 downto 14) = "10" else
	                   reg_page3_q;

	s_sram_full_addr <= s_mem_page_seg & s_A(13 downto 0);	-- 5 + 14 = 19 bits = 512K

	-- ------------------------------------------------------------------------
	-- SRAM BUILT-IN SELF TEST (2026-08-16), enabled by SW(4)='1'.
	--
	-- Switch testing isolated the remaining instability to the RAM subsystem
	-- (mapper off = stable and boots; mapper on = hangs, in either byte-lane
	-- position). But every RAM test so far ran THROUGH the MSX, the slot
	-- expander and Nextor, so a dead or miswired SRAM and a logic bug look
	-- identical. This takes the MSX out of the loop: the FPGA drives the SRAM
	-- itself, writes a pattern across 256KB, reads it back and counts errors.
	--
	-- Use: set SW(4)='1' and power on. Keep SW(9)='1' so the cart stays off the
	-- MSX bus while testing. Then read:
	--   HEX3:HEX0 = mismatch count (0000 = SRAM and its wiring are good)
	--   LEDG(9)   = test finished
	--   LEDG(8)   = PASS (finished with zero mismatches)
	-- SW(5) still selects the byte lane, so running this in both positions also
	-- settles which lane is physically wired.
	--
	-- The pattern is address-derived (low byte XOR high byte), so stuck ADDRESS
	-- lines fail the test as well as stuck data lines - a constant pattern
	-- would pass even with the address bus completely dead.
	-- ------------------------------------------------------------------------
	-- NOTE on the BIST's reset source: it deliberately does NOT use s_reset.
	-- s_reset includes the MSX's RESET_n line, and with the MSX powered OFF
	-- that line sits low - which held the whole design, and therefore this
	-- test, in permanent reset. Since the entire point is to exercise the SRAM
	-- with the MSX out of the loop, the BIST resets from KEY(0) alone.
	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			bist_key_meta <= not KEY(0);
			bist_key_sync <= bist_key_meta;

			if bist_key_sync = '1' then
				bist_state  <= B_IDLE;
				bist_addr   <= (others => '0');
				bist_phase  <= '0';
				bist_errors <= (others => '0');
				bist_done   <= '0';
				bist_drive  <= '0';
				bist_we_n   <= '1';
				bist_oe_n   <= '1';
				bist_ce_n   <= '1';
				bist_wait   <= (others => '0');
			else
				case bist_state is

					when B_IDLE =>
						bist_drive <= '0';
						bist_we_n  <= '1';
						bist_oe_n  <= '1';
						bist_ce_n  <= '1';
						if SW(4) = '1' and bist_done = '0' then
							bist_addr   <= (others => '0');
							bist_phase  <= '0';
							bist_errors <= (others => '0');
							bist_state  <= B_WR_SET;
						end if;

					when B_WR_SET =>
						bist_ce_n  <= '0';
						bist_oe_n  <= '1';
						bist_drive <= '1';
						bist_dq    <= bist_addr(7 downto 0) xor bist_addr(15 downto 8);
						bist_state <= B_WR_PULSE;

					when B_WR_PULSE =>
						bist_we_n  <= '0';
						bist_state <= B_WR_END;

					when B_WR_END =>
						bist_we_n  <= '1';
						bist_state <= B_NEXT;

					when B_RD_SET =>
						bist_drive <= '0';
						bist_ce_n  <= '0';
						bist_oe_n  <= '0';
						bist_wait  <= "010";
						bist_state <= B_RD_SAMPLE;

					when B_RD_SAMPLE =>
						if bist_wait /= "000" then
							bist_wait <= bist_wait - 1;
						else
							if SRAM_DQ /= (bist_addr(7 downto 0) xor bist_addr(15 downto 8)) then
								bist_errors <= bist_errors + 1;
							end if;
							bist_state <= B_NEXT;
						end if;

					when B_NEXT =>
						bist_we_n <= '1';
						bist_oe_n <= '1';
						if bist_addr = "1111111111111111111" then
							bist_addr <= (others => '0');
							if bist_phase = '0' then
								bist_phase <= '1';
								bist_state <= B_RD_SET;
							else
								bist_state <= B_DONE;
							end if;
						else
							bist_addr <= bist_addr + 1;
							if bist_phase = '0' then
								bist_state <= B_WR_SET;
							else
								bist_state <= B_RD_SET;
							end if;
						end if;

					when B_DONE =>
						bist_done  <= '1';
						bist_drive <= '0';
						bist_ce_n  <= '1';
						bist_oe_n  <= '1';
						bist_we_n  <= '1';

				end case;
			end if;
		end if;
	end process;

	-- ------------------------------------------------------------------------
	-- SELF-TIMED SRAM WRITE (2026-08-16).
	--
	-- The SRAM BIST passes with zero errors across 256KB, so the memory and its
	-- wiring are good - yet the mapper corrupts data when the MSX drives it.
	-- The difference is the write timing.
	--
	-- The MSX path used to be purely combinational:
	--     SRAM_WE_N <= '0' when s_mem_wr_en = '1' else '1';
	--     SRAM_DQ   <= D   when s_mem_wr_en = '1' else (others => 'Z');
	-- Both terms come from the same signal, so at the end of a write /WE rises
	-- and the data bus goes high-Z in the SAME instant. An asynchronous SRAM
	-- latches on the RISING edge of /WE and needs data held AFTER it (tDH);
	-- here the hold time is zero, so the chip can capture floating garbage.
	-- That is intermittent by nature and corrupts precisely what Nextor stores
	-- in mapper RAM - matching "mapper off = stable, mapper on = corruption".
	--
	-- The BIST does it correctly (data driven -> /WE low -> /WE high -> data
	-- released) and passes, which is the evidence this timing is the issue.
	-- The MSX write is now self-timed the same way: on a qualified write the
	-- address and data are captured, then a clean /WE pulse is issued with the
	-- data driven throughout and released only afterwards. The MSX write window
	-- (~1us) is far longer than this sequence (~120ns), so it always completes
	-- well inside the bus cycle.
	-- ------------------------------------------------------------------------
	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				wr_req_meta <= '0';
				wr_req_sync <= '0';
				wr_busy     <= '0';
				wr_served   <= '0';
				wr_cnt      <= (others => '0');
				wr_we_n     <= '1';
				wr_drive    <= '0';
			else
				wr_req_meta <= s_mem_wr_en;
				wr_req_sync <= wr_req_meta;

				-- One write per bus cycle: re-arm only once the request drops.
				if wr_req_sync = '0' then
					wr_served <= '0';
				end if;

				if wr_busy = '0' then
					wr_we_n  <= '1';
					wr_drive <= '0';
					if wr_req_sync = '1' and wr_served = '0' then
						wr_addr_q <= s_sram_full_addr(17 downto 0);
						wr_data_q <= D;
						wr_drive  <= '1';	-- data out first, before /WE
						wr_busy   <= '1';
						wr_served <= '1';
						wr_cnt    <= "000";
					end if;
				else
					wr_cnt <= wr_cnt + 1;
					case wr_cnt is
						when "000"  => wr_we_n <= '1';	-- address/data setup
						when "001"  => wr_we_n <= '0';	-- /WE low
						when "010"  => wr_we_n <= '0';
						when "011"  => wr_we_n <= '1';	-- /WE high, data STILL driven
						when others =>                 	-- hold time satisfied
							wr_we_n  <= '1';
							wr_drive <= '0';
							wr_busy  <= '0';
					end case;
				end if;
			end if;
		end if;
	end process;

	SRAM_ADDR <= bist_addr(17 downto 0) when SW(4) = '1'  else
	             wr_addr_q   when wr_busy = '1' else
	             s_sram_full_addr(17 downto 0);
	-- SRAM byte lane, driven by address bit 18 (restored 2026-08-16).
	--
	-- The chip is 256K x 16; UB_N/LB_N choose which byte of the addressed word
	-- is driven. With both byte lanes tied to the same 8 FPGA data pins, this
	-- gives 512K byte-wide locations: bit 18 picks the lane, bits 17:0 pick the
	-- word. In BIST mode the test drives the same scheme from its own counter
	-- so it exercises both lanes.
	SRAM_UB_N <= not bist_addr(18) when SW(4) = '1' else not s_sram_full_addr(18);
	SRAM_LB_N <= bist_addr(18)     when SW(4) = '1' else s_sram_full_addr(18);
	-- s_addr_valid gate (2026-08-13): SRAM_WE_N used to be driven straight
	-- from WR_n, so the write strobe reached the chip while s_A was still the
	-- mid-capture chimera (new low byte + previous cycle's high byte, see the
	-- s_addr_valid declaration) - writing the byte into the WRONG cell before
	-- the address settled, on every single mapper write. CE_N is gated too so
	-- the chip is not even selected with an unsettled address.
	-- 0xFFFF excluded here too (see s_mem_rd_en/s_mem_wr_en above): the chip is
	-- not even selected for the subslot register's address.
	SRAM_CE_N <= bist_ce_n when SW(4) = '1'  else
	             '0'       when wr_busy = '1' else
	             not (s_sltsl_ram_en and s_addr_valid and not s_ffff_slt);
	-- Outputs must stay disabled for the whole self-timed write, otherwise
	-- the SRAM would drive against our data.
	SRAM_OE_N <= bist_oe_n when SW(4) = '1'  else
	             '1'       when wr_busy = '1' else
	             RD_n;
	SRAM_WE_N <= bist_we_n when SW(4) = '1'  else
	             wr_we_n   when wr_busy = '1' else
	             '1';

	SRAM_DQ <= bist_dq         when (SW(4) = '1' and bist_drive = '1') else
	           (others => 'Z') when SW(4) = '1'                         else
	           wr_data_q       when wr_drive = '1'                      else
	           (others => 'Z');


	-- ----------------------------------------------------------------------------
	-- 9. MSX BUS DRIVERS (D, U1, BUSDIR_n, WAIT_n)
	-- ----------------------------------------------------------------------------
	-- ------------------------------------------------------------------------
	-- Load the MSX bus with data from whichever device in this core is
	-- currently selected. Single driver for D (VHDL doesn't allow two
	-- unconditional concurrent drivers) - the listed priority never actually
	-- matters in practice since MREQ_n/IORQ_n are mutually exclusive on a
	-- real Z80 bus cycle and the memory-space windows below don't overlap.
	-- ------------------------------------------------------------------------
	D <= sd_reg_dout            when s_sdbridge_reg_rd_s = '1' else							-- SD_STATUS/SD_ERRLO/SD_ERRHI
	     s_expn_q               when s_sltsl_en = '1' and s_ffff_slt = '1' and RD_n = '0' and s_sdbridge_cs_s = '0' else	-- Slot expansion register
	     FL_DQ(7 downto 0)      when s_rom_rd_en = '1' else										-- ROM / Flash (only when actually selected+driving - see s_rom_rd_en)
	     SRAM_DQ                when s_mem_rd_en = '1' else										-- RAM / Mapper
	     s_mapper_rdata         when s_io_mapper_rd_en = '1' else							-- Mapper segment registers
	     sd_data_dout           when sd_data_rd_en = '1' else										-- SD_DATA
	     -- ------------------------------------------------------------------
	     -- Fallback for a read of THIS slot that no device above matched
	     -- (2026-08-18). Required by the U1_DIR change below: U1_DIR now
	     -- follows RD_n rather than the per-device read enables, so the
	     -- transceiver drives towards the MSX for the WHOLE read cycle. If D
	     -- were left at 'Z' for any part of that, U1 would push a floating
	     -- FPGA input onto the MSX data bus.
	     --
	     -- 0xFF is the correct value: an unpopulated area of a selected slot
	     -- reads as FF on real hardware, and while our slot is selected
	     -- nothing else is driving the bus. This also covers the window
	     -- before s_addr_valid rises (address still being captured) and the
	     -- SD_DATA case where the bridge has not yet produced a byte - in
	     -- both, the Z80 is either still in T1/T2 or held in /WAIT, so it
	     -- never latches the placeholder.
	     -- ------------------------------------------------------------------
	     x"FF"                  when s_sltsl_en = '1' and RD_n = '0' else
	     (others => 'Z');

	-- ------------------------------------------------------------------------
	-- U1 transceiver control.
	--
	-- REDESIGNED (2026-08-18) after comparing against three working MSX FPGA
	-- projects. Ours was the ONLY one whose data-bus DIRECTION depended on
	-- which internal device won the read mux:
	--
	--   WonderTANG (fpga/src/top.v):
	--     assign datadir = ((~sltsl_n_w || busdir_cs_w) && ~rd_n_w) ? 0 : 1;
	--
	-- i.e. "our slot is selected AND /RD is low", and nothing else. One clean
	-- transition per bus cycle, aligned to /RD.
	--
	-- Ours keyed off six per-device enables, and one of them is DATA
	-- DEPENDENT - sdcard_bridge's sd_rd_en additionally requires
	-- (rx_ready_q = '1' or acc_served_q = '1'), so for an SD_DATA read the
	-- direction only turned around once the bridge had produced a byte:
	-- mid-cycle, after /WAIT released, at a different moment every access.
	--
	-- That is what the previous two revisions were both failing to fix. The
	-- version before last flipped U1_DIR combinationally while the protective
	-- u1_dir_hold/U1OE_n sequencing was registered, so the buffer was still
	-- enabled for up to 20ns with the direction already reversed. The version
	-- after that registered U1_DIR to cure the race - but that only DELAYED a
	-- mid-cycle, data-dependent transition instead of removing it, and on the
	-- SD path (where the turnaround happens late in the cycle anyway) the
	-- extra 40ns of direction delay plus 60ns of buffer-off broke SD reads
	-- outright: ROM still loaded, NEXTOR.SYS never did.
	--
	-- Now the direction simply follows /RD. It changes once per cycle, at a
	-- predictable time, and there is no turnaround to protect - so the whole
	-- u1_dir_hold mechanism is gone rather than being made to work.
	--
	-- The companion requirement is in the D mux above: because U1 now drives
	-- towards the MSX for the WHOLE read cycle, D must never be 'Z' during
	-- one, hence the 0xFF fallback for reads of this slot that match no
	-- device.
	-- ------------------------------------------------------------------------
	-- U1OE_n: enable the buffer for every access path that reads OR writes D
	-- - see the feedback_u1oe_n_per_access_path memory (this exact class of
	-- bug has been found twice in this project). s_sltsl_en alone covers every
	-- memory-space path (ROM, RAM, SD register window, FFFF), since all of
	-- them require SLTSL_n asserted with SW(9)='0'; the mapper I/O ports use
	-- their raw (unqualified) enables so U1 is listening for the FULL
	-- RD_n/WR_n-low window, not just the part after the glitch filter settles.
	U1OE_n <= '0' when s_sltsl_en = '1'        else
	          '0' when s_io_mapper_rd_en = '1' else
	          '0' when s_io_mapper_wr_en = '1' else
	          '1';

	-- U1_DIR: '0' = drive toward MSX (FPGA->MSX), '1' = listen from MSX
	-- (MSX->FPGA) - CORRECTED polarity, see header note (MegaROM_ASCII16's
	-- real-hardware milestone found this backwards in every earlier version of
	-- this file). Default '1' (listen) covers every write path and idle.
	U1_DIR <= '0' when s_sltsl_en = '1' and RD_n = '0'        else
	          '0' when s_io_mapper_rd_en = '1'                else	-- already /RD-qualified
	          '1';

	-- BUSDIR_n: only /IORQ-based reads need it (MSX Technical Data Book
	-- 1.6.2) - ordinary /SLTSL memory reads (ROM, RAM, SD/timer registers,
	-- FFFF) do not. Never tri-stated - always actively driven.
	BUSDIR_n <= '0' when s_io_mapper_rd_en = '1' else '1';

	-- ------------------------------------------------------------------------
	-- Debug display (2026-08-12, XESS SD core pivot). ROM/RAM sub-slot
	-- access is CONFIRMED working on real hardware; the display now
	-- surfaces the ported XESS SdCardCtrl core's own state, since its
	-- init sequence (CMD0/CMD8/ACMD41) runs automatically from reset -
	-- independent of whether the Nextor driver ever does anything - so
	-- this is informative even before any software runs:
	--   HEX3:HEX2:HEX1:HEX0 = SdCardCtrl's error_o (16 bits) - 0000 means
	--     no error. Non-zero after a moment past reset means CMD0/CMD8/
	--     ACMD41 failed - the value is the SD card's own R1/R7 response
	--     byte (low byte = init-phase error; high byte = write-phase
	--     error, only set once a block write is attempted).
	-- LEDG(9)/(8) = sticky "ROM/RAM sub-slot was ever genuinely read"
	--   latches (unchanged from before this pivot).
	-- LEDG(7 downto 4) = live slot-expander outputs (active-high here for
	--   legibility, unchanged from before this pivot).
	-- LEDG(3) = sticky "SD register window was ever accessed by the CPU"
	--   latch - confirms the driver is at least reaching the hardware.
	-- LEDG(2) = sticky "SdCardCtrl init done" latch - lit once the core
	--   has reached WAIT_FOR_HOST_RW at least once (CMD0/CMD8/ACMD41
	--   succeeded). The single most important bit to check first: if this
	--   is OFF, the card never even finished identification, independent
	--   of anything the driver does.
	-- LEDG(1) = SdCardCtrl busy_o, live (currently mid-operation).
	-- LEDG(0) = bridge-level WAIT_n timeout flag (see sdcard_bridge.vhd) -
	--   lit if a byte-level handshake with SdCardCtrl ever timed out
	--   without the WAIT_n hang this timeout exists to prevent.
	-- ------------------------------------------------------------------------
	-- DIAGNOSTIC REPURPOSE (2026-08-13): the error code has read 0000 on every
	-- real-hardware test, so it is spending 4 digits to say nothing. The open
	-- question now is whether DEV_RW's sector-read loop runs at all, and if so
	-- what the card actually returns - dbg_sd_ever_accessed cannot answer that
	-- (it is sticky and already set by DRV_INIT's own SD_CMD write).
	--   HEX3:HEX2 = last byte received from the card (dbg_sd_last_rx)
	--   HEX1:HEX0 = count of COMPLETED SD_DATA byte transfers, wrapping
	-- Reading HEX1:HEX0 = 00 means the byte loop never ran (DEV_RW was never
	-- called, or bailed at its health check) - a driver/kernel problem.
	-- Anything else means bytes genuinely moved, and HEX3:HEX2 shows the last
	-- one: after a successful sector-0 read that should be AA, the second half
	-- of the 55 AA boot signature at offsets 510/511.
	-- Error/timeout are still visible on LEDG(1)/LEDG(0).
	-- DIAGNOSTIC (2026-08-15): show SdCardCtrl's ERROR CODE next to transfer
	-- progress. Real hardware is now returning last_rx = 0xFF, and the bridge
	-- only ever produces 0xFF deliberately in one place: the never-stall guard,
	-- which fires when the core has LATCHED AN ERROR. So the core is telling us
	-- why it failed and nothing was displaying it.
	--   HEX3:HEX2 = error_o(7 downto 0) - non-zero means the core faulted
	--   HEX1:HEX0 = completed SD_DATA byte transfers (wraps at 256)
	-- error_o(15 downto 8) is still readable by software at SD_ERRHI.
	-- SW(5)=1: show the exp_slot REJECTED-WINDOW counter (see exp_rej_o).
	-- ffffstress.rom reports how many subslot writes were LOST; this shows
	-- how many windows opened and were then discarded by the length filter.
	-- Equal -> the filter is the cause. Near zero -> the window never opened,
	-- so the fault is upstream in ffff / s_addr_valid / address capture.

	-- ----------------------------------------------------------------------------
	-- 10. DISPLAY (HEX / LED)
	-- ----------------------------------------------------------------------------
	HEXDIGIT0 <= bist_errors(3 downto 0)   when SW(4) = '1' else dbg_sd_data_cnt(3 downto 0);
	HEXDIGIT1 <= bist_errors(7 downto 4)   when SW(4) = '1' else dbg_sd_data_cnt(7 downto 4);
	-- HEX3:HEX2 now shows SD_DEBUG (register 9) - the last trace marker the
	-- driver wrote. The error code has read 00 on every recent run, whereas
	-- the open question is which driver entry point Nextor reaches, and a
	-- print-based trace cannot answer that safely (CHPUT is only valid while
	-- page 0 holds the BIOS). Error/timeout remain on LEDG(1)/LEDG(0), and
	-- the full error word is still readable at SD_ERRLO/SD_ERRHI.
	-- HEX3:HEX2 now shows exp_slot's SUBSLOT REGISTER. The SD read path has
	-- been proven reliable (64 consecutive sector reads, zero failures), so
	-- the intermittent corruption is downstream - and every sector Nextor
	-- reads is stored in THIS cart's mapper RAM, reachable only through the
	-- subslot routing this register controls. Expect a stable, sensible value
	-- (each 2-bit field selects a subslot per page); garbage or a value that
	-- changes when it should not is the fault.
	HEXDIGIT2 <= bist_errors(11 downto 8)  when SW(4) = '1' else dbg_exp_reg(3 downto 0);
	HEXDIGIT3 <= bist_errors(15 downto 12) when SW(4) = '1' else dbg_exp_reg(7 downto 4);

	LEDG(9)          <= bist_done when SW(4) = '1' else s_rom_subslot_ever_q;
	LEDG(8)          <= '1' when (SW(4) = '1' and bist_done = '1' and bist_errors = x"0000") else
	                    '0' when SW(4) = '1'                                                else
	                    s_ram_subslot_ever_q;
	LEDG(7 downto 4) <= not slt_exp_n;
	LEDG(3)          <= dbg_sd_ever_accessed;
	LEDG(2)          <= dbg_sd_init_done;
	LEDG(1)          <= dbg_sd_busy;
	LEDG(0)          <= dbg_sd_timeout;

	-- Interface for the 7-segment display
	DISPHEX0 : decoder_7seg PORT MAP (
			NUMBER		=>	HEXDIGIT0,
			HEX_DISP		=>	HEX0
		);

	DISPHEX1 : decoder_7seg PORT MAP (
			NUMBER		=>	HEXDIGIT1,
			HEX_DISP		=>	HEX1
	);

	DISPHEX2 : decoder_7seg PORT MAP (
			NUMBER		=>	HEXDIGIT2,
			HEX_DISP		=>	HEX2
	);

	DISPHEX3 : decoder_7seg PORT MAP (
			NUMBER		=>	HEXDIGIT3,
			HEX_DISP		=>	HEX3
	);

end bevioural;

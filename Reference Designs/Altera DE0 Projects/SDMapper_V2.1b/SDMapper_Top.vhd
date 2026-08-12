-- MSX_DE0/DE1 FPGA Interface
-- Ronivon Costa @ 2023 - 2026
--
-- MSXDOS2 (actually it has Nextor Operating System in the Flash) is one of the many Reference Designs
-- I created for the MSX FPGA Interface.
-- MSX_FPGA_Interface is an interface that allows MSX computers to connect to the mentioned FPGA development boards,
-- safely (provides the needed signal level shifting between 3.3V and 5V).
-- This connection makes it possible to use the development boards as generic peripherals.
-- --------------------------------------------------------------------------------------------------------------------------------------
-- Acknowledgment:
--
-- Most of this core was re-used from the amazing MSX SD Mapper V2, by Fabio Belavenuto - https://github.com/fbelavenuto/msxsdmapperv2
-- I had to make many changes to make it work with the MSX FPGA Interface and the Terasic DE0/DE1 boards.
-- --------------------------------------------------------------------------------------------------------------------------------------
--
-- INTEGRATION (2026-08-11): FULL DESIGN RESTORED
-- --------------------------------------------------------------------------------------------------------------------------------------
-- This file replaces the "SIMPLIFIED TEST VARIANT" that had stripped this
-- design down to a single non-expanded ROM-only slot (see git history / the
-- SDMapper_V2.1b_DE0_noexpslot branch for that variant and why it existed:
-- real-hardware debugging of "SDMapper - Boots Nextor Some Times" found the
-- ROM sub-slot enable never coincided with a genuine read).
--
-- This version re-integrates full MSX secondary-slot expansion, gluing
-- together three independently-developed and independently-tested reference
-- designs for this same MSX_FPGA_Hat rev 2.1b interface board:
--   -> ROM sub-slot: the ASCII16 Flash-boot logic already present in this
--      file (itself derived from MegaROM_ASCII16/MSX_FPGA_Top.vhd, which has
--      a real-hardware-confirmed boot MILESTONE dated today), hard-locked to
--      flashbase 0x000000 (Nextor) instead of MegaROM_ASCII16's SW-selectable
--      game catalog - this board only ever boots Nextor from that offset.
--   -> RAM sub-slot: the standard MSX Memory Mapper (512KB, DE0 SRAM addon)
--      from MemoryMapper/MSX_FPGA_Top.vhd, itself real-hardware-tested on a
--      Canon V-8/V-9 today (see project_memorymapper_hardware_test memory).
--   -> Slot expansion + SD card: exp_slot.vhd and spi.vhd (both already
--      living in this directory, both already carrying documented stability
--      fixes for the exact "combinational signal used as a clock" hazard
--      class that caused earlier hardware flakiness) + the SD status/control/
--      timer register protocol from "SDMapper - Boots Nextor Some Times",
--      trimmed from that design's 2-SD-card-slot layout down to this board's
--      single onboard microSD (SD1 only - this entity has no SD2_* ports).
--
-- CRITICAL FIX CARRIED FORWARD FROM MegaROM_ASCII16's MILESTONE: this file
-- (and the DE1 "Boots Nextor Some Times" predecessor it was ported from) had
-- U1_DIR backwards - '1' was treated as "drive toward the MSX bus". Real
-- hardware testing on MegaROM_ASCII16 today (OUT &H5A,170 -> INP(&H5A)=170,
-- confirmed round-trip only after flipping the polarity) established the
-- opposite: DIR=1 means MSX->FPGA (listen), DIR=0 means FPGA->MSX (drive).
-- Every U1_DIR expression in this file uses the CORRECTED polarity. Given
-- this same board/connector/chip (U1, a 74LVC245) is shared by all three
-- source designs, the earlier "ROM sub-slot enable never coincided with a
-- genuine read" symptom may well have been this exact bug wearing a
-- different disguise - worth keeping in mind during real-hardware bring-up
-- of this integrated version.
--
-- Also carried forward: the "continuous re-latch of D WHILE a qualified
-- write window holds" fix (MegaROM_ASCII16's documented real-hardware bug -
-- garbage bank registers from sampling D on a delayed edge after WR_n had
-- already risen and the Z80 released the bus). Every register write in this
-- file that used to sample D on a synchronized falling edge (ROM bank
-- switch, SD card slot-select, timer load) now shares one glitch-filtered
-- qualifier (s_cart_write_qualified) and re-latches continuously instead.
--
-- STATUS: compiled against this integration's own logic only - NOT YET
-- programmed onto real hardware. The historical bug this design is meant to
-- finally resolve was never conclusively root-caused before the strip-down;
-- treat the LEDG/HEX debug bits below (in particular LEDG(9), the sticky
-- "ROM sub-slot was ever genuinely read" latch) as the first thing to check
-- on a scope/logic analyzer during bring-up.
-- --------------------------------------------------------------------------------------------------------------------------------------
--
-- HOW TO USE THIS BOARD
-- --------------------------------------------------------------------------------------------------------------------------------------
-- Switches (SW):
--   SW(9)    - Board mode select:
--                '0' = SDMapper mode (Nextor + Memory Mapper enabled - this
--                      file's whole design). This cartridge responds to
--                      /SLTSL-based memory access (ROM, RAM/mapper, and the
--                      slot-expansion register at FFFF) AND the mapper I/O
--                      ports (FC-FF) are decoded.
--                '1' = MegaROM emulation mode (RESERVED FOR FUTURE USE - not
--                      implemented in this file yet). SDMapper (ROM, RAM/
--                      mapper, mapper I/O ports, the FFFF slot-expansion
--                      register) is entirely disabled/silent on the bus in
--                      this mode, freeing it up for a future MegaROM
--                      emulation core (see MegaROM_ASCII16/MSX_FPGA_Top.vhd)
--                      to be merged into this same file and taken live here.
--   SW(8)    - Unused/free (RAM/mapper is gated by SW(9) alone, same as ROM
--              and SD - see SW(9) above).
--   SW(2)    - SD card 1 (onboard microSD) write-protect flag, reported to
--              software via the status register.
--   SW(0)    - SD card 1 (onboard microSD) present flag. This board has no
--              physical card-detect sensing, so presence is set manually.
--
-- Pushbuttons (KEY):
--   KEY(0)   - Manual reset. Combined with the MSX's own RESET_n line - either
--              one being asserted forces a full reset of this design.
--   KEY(2:1) - Unused (DE0 has only 3 buttons).
--
-- Memory map (within this cartridge's /SLTSL-selected space, SDMapper mode
-- only - SW(9)='0'):
--   ROM sub-slot (exp_slot subslot 0 - the default/reset subslot for every
--   page, so Nextor's kernel is visible immediately after reset with no FFFF
--   write needed):
--     4000-7FFF   - Bank 1 window. Flash-backed, base 0x000000 (Nextor).
--       6000-67FF, 7000-77FF - Bank-switch registers (write-only; reads in
--                               this range still return normal ROM data).
--       7B00-7EFF             - SD card raw SPI data register. Only visible
--                               when rom_bank1_q = 7 (bank 1 switched to
--                               segment 7 to reach the SD hardware window).
--       7FF0                  - SD card control/status register.
--       7FF1                  - Timer register.
--     8000-BFFF   - Bank 2 window. Only Flash-backed when rom_bank2_q >= 8.
--   RAM sub-slot: pages 0, 2, 3 always reach RAM (no ROM ever contends for
--   them - see s_sltsl_ram_en's comment); page 1 arbitrates between ROM
--   sub-slot 0 (default) and RAM sub-slot 1 via the FFFF register, same as
--   the ROM sub-slot above. Each page's RAM is addressed via its own
--   segment register - see I/O ports below.
--   FFFF        - Slot-expansion sub-slot select register (intercepted
--                 regardless of which sub-slot would otherwise be visible).
--
-- I/O ports (global - not slot-scoped, per msx.org/wiki/Memory_Mapper; gated
-- by SW(9)='0' i.e. SDMapper mode, same convention as the standalone
-- MemoryMapper reference just inverted to match this board's mode switch):
--   FC-FF       - Standard MSX memory-mapper segment registers, one per page.
-- --------------------------------------------------------------------------------------------------------------------------------------
--
-- CLOCK DOMAINS
-- --------------------------------------------------------------------------------------------------------------------------------------
-- CLOCK_50 (50MHz, raw board oscillator, no PLL) drives everything in this
-- file EXCEPT the spi.vhd instantiation: the address-bus capture state
-- machine, every synchronizer/glitch-filter, exp_slot's clock, the mapper/
-- ROM-bank/SD-select/timer registers.
--
-- clock_i (25MHz, generated from CLOCK_50 via Clock_25MHz) drives ONLY the
-- spi.vhd component. spi.vhd's SPI state machine toggles SCLK once per
-- clock_i edge, so its frequency directly sets the SD card's SPI clock rate
-- (~12.5MHz here). spi.vhd already synchronizes its CPU-facing inputs
-- internally on its own clock_i, so this split introduces no new
-- clock-domain-crossing hazard.
-- --------------------------------------------------------------------------------------------------------------------------------------
--
-- ADDRESS BUS MULTIPLEXING
-- --------------------------------------------------------------------------------------------------------------------------------------
-- The MSX_FPGA_Hat interface board has too few FPGA-side GPIO pins to present the
-- full 16-bit MSX address bus at once. The low byte (A0-A7, via level-shifter U2)
-- and high byte (A8-A15, via level-shifter U3) share the same 8 physical FPGA
-- pins (port A_MUX below), each buffer independently gated by its own output
-- enable (U2OE_n, U3OE_n). Only one of the two must ever be enabled at a time.
--
-- This file reconstructs the full address internally as the registered signal
-- s_A, via a small CLOCK_50-synchronous state machine that:
--   1) Waits for a synchronized falling edge on (MREQ_n and IORQ_n) - i.e. the
--      start of any new bus cycle, memory or I/O. By Z80 timing, the address is
--      already valid and stable by the time either of these assert.
--   2) Enables U2 (low byte), waits one CLOCK_50 period for the buffer to settle,
--      then captures A_MUX into s_A(7 downto 0).
--   3) Disables U2, enables U3 (high byte), waits one CLOCK_50 period, then
--      captures A_MUX into s_A(15 downto 8).
--   4) Returns to idle with both buffers disabled, until the next trigger.
-- A one-cycle guard state with both buffers disabled sits between steps 2 and 3
-- so the two output-enables are never asserted anywhere near the same instant,
-- even accounting for small routing/propagation skew between them.
--
-- addr_capture_trigger preempts this state machine from ANY state (not just
-- idle) so a new bus cycle's trigger is never silently dropped while a
-- previous, now-superseded capture is still in progress.
-- --------------------------------------------------------------------------------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;

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
	signal s_sltsl_dis_n	: std_logic;
	signal s_spi_wait_n_o	: std_logic;

	-- ------------------------------------------------------------------------
	-- Address bus reconstruction (see "ADDRESS BUS MULTIPLEXING" note above)
	-- Runs on CLOCK_50.
	-- ------------------------------------------------------------------------
	signal s_A				: std_logic_vector(15 downto 0) := (others => '0');

	signal s_bus_req_n		: std_logic;
	signal bus_req_meta, bus_req_sync, bus_req_sync_d : std_logic;
	signal addr_capture_trigger : std_logic;

	type addr_capture_state_t is (S_IDLE, S_LOW_EN, S_LOW_CAP, S_GUARD, S_HIGH_EN, S_HIGH_CAP);
	signal addr_capture_state : addr_capture_state_t := S_IDLE;

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
	-- SD card / SPI / status / timer registers (single physical SD card slot
	-- on this DE0 board - see header note). Ported from "SDMapper - Boots
	-- Nextor Some Times"/SDMapper_Top.vhd, trimmed from its 2-slot layout.
	-- ------------------------------------------------------------------------
	signal clock_i			: std_logic := '0';	-- 25MHz, feeds ONLY spi.vhd - see "CLOCK DOMAINS" note above
	signal regs_cs_s		: std_logic;
	signal spi_cs_s		: std_logic;
	signal status_s		: std_logic_vector(7 downto 0);
	signal spi_ctrl_rd_s	: std_logic;
	signal sd_sel_q		: std_logic_vector(1 downto 0) := (others => '0');
	signal sd_chg_q		: std_logic := '0';
	signal sd_chg_s		: std_logic := '0';

	signal spi_data		: std_logic_vector(7 downto 0);
	signal spi_read		: std_logic;
	signal s_sd_clk		: std_logic;
	signal s_sd_mosi		: std_logic;
	signal s_sd_miso		: std_logic;

	signal tmr_cnt_q		: std_logic_vector(15 downto 0) := (others => '0');
	signal tmr_wr_s		: std_logic;
	signal tmr_rd_s		: std_logic;

	-- Synchronizer + edge detector for the SD status/control register read
	-- strobe (spi_ctrl_rd_s): rising edge latches the "changed" flag for the
	-- CPU to read, falling edge clears the flag once the CPU has finished.
	signal spi_ctrl_rd_meta, spi_ctrl_rd_sync, spi_ctrl_rd_sync_d : std_logic;
	signal spi_ctrl_rd_rising_pulse, spi_ctrl_rd_falling_pulse    : std_logic;

	-- ------------------------------------------------------------------------
	-- RAM sub-slot: standard MSX Memory Mapper (512KB), ported verbatim from
	-- MemoryMapper/MSX_FPGA_Top.vhd (real-hardware-tested on a Canon V-8/V-9
	-- today - see project_memorymapper_hardware_test memory). Reset defaults
	-- (3,2,1,0 for page0..page3) and register semantics unchanged.
	-- ------------------------------------------------------------------------
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

	signal s_io_mapper_rd_dur_cnt   : std_logic_vector(3 downto 0) := (others => '0');
	signal s_io_mapper_wr_dur_cnt   : std_logic_vector(3 downto 0) := (others => '0');
	signal s_io_mapper_rd_qualified : std_logic := '0';
	signal s_io_mapper_wr_qualified : std_logic := '0';

	signal s_mapper_rdata : std_logic_vector(7 downto 0);

	-- SD SPI diagnostics (2026-08-11 bring-up): mapper/ROM sub-slots are now
	-- confirmed working on real hardware, so the debug display below is
	-- repurposed for the still-open SD card investigation - last byte sent
	-- to and received from the card via the raw 7B00-7EFF SPI window, plus
	-- a sticky "was that window ever accessed at all" latch.
	signal s_spi_last_tx_q : std_logic_vector(7 downto 0) := (others => '0');
	signal s_spi_last_rx_q : std_logic_vector(7 downto 0) := (others => '0');
	signal s_spi_ever_accessed_q : std_logic := '0';

	-- Memory (SLTSL_n, RAM sub-slot-gated) access - raw/immediate decode,
	-- same timing rationale as the ROM sub-slot's own memory access.
	signal s_mem_rd_en : std_logic;
	signal s_mem_wr_en : std_logic;

	signal s_mem_page_seg  : std_logic_vector(4 downto 0);
	signal s_sram_full_addr : std_logic_vector(18 downto 0);	-- segment(4:0) & s_A(13:0) = 19 bits = 512K

begin

	-- Inverted here to compensate for the Q2 open-collector driver stage on
	-- the MSX_FPGA_Hat board, which inverts whatever level the FPGA drives.
	WAIT_n <= not s_spi_wait_n_o;

	-- Reset circuit
	s_reset <= not (KEY(0) and RESET_n);
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
			elsif addr_capture_trigger = '1' then
				-- Preemption always disables both OEs explicitly first,
				-- guaranteeing at least one dead cycle before S_LOW_EN's own
				-- branch re-enables U2 - avoids bus contention if a new cycle
				-- starts mid-capture.
				addr_capture_state <= S_LOW_EN;
				U2OE_n <= '1';
				U3OE_n <= '1';
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
						addr_capture_state <= S_IDLE;
					when others =>
						addr_capture_state <= S_IDLE;
				end case;
			end if;
		end if;
	end process;

	-- ------------------------------------------------------------------------
	-- Slot expansion
	-- ------------------------------------------------------------------------
	s_sltsl_en    <= (not SLTSL_n) when SW(9) = '0' else '0';		-- SDMapper (Nextor+Mapper) enabled only when SW(9)='0' - see SW(9) note above
	s_ffff_slt    <= '1' when s_A = x"FFFF" else '0';
	s_sltsl_rom_en <= (not slt_exp_n(0)) when SW(9) = '0' else '0';

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
	-- No separate SW(8) gate: RAM/mapper is gated by SW(9) only, same as ROM
	-- and SD (all three are one "SDMapper mode" enable - see SW(9) note
	-- above). SW(8) is unused/free by this design.
	s_sltsl_ram_en <= '1' when s_sltsl_en = '1' and
	                       (s_A(15 downto 14) /= "01" or slt_exp_n(1) = '0')
	                  else '0';

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
		exp_n			=> slt_exp_n
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

	-- Excludes the SD SPI data window and the SD/timer registers, both of
	-- which live inside bank 1's address range - Flash must not drive its
	-- outputs while those are being accessed instead.
	FL_CE_N <=
		'0'	when s_A(15 downto 14) = "01" and s_sltsl_rom_en = '1' and RD_n = '0' and spi_cs_s = '0' and regs_cs_s = '0'	else
		'0'	when s_A(15 downto 14) = "10" and s_sltsl_rom_en = '1' and rom_bank2_q(3) = '1'					else		-- Only if bank > 7
		'1';

	-- FL_ADDR carries address bits [22:1] of the flash's byte-mode address
	-- space; bit 0 (A-1) goes out on FL_DQ15_AM1 instead (see entity comment).
	FL_ADDR <= s_rom_a(22 downto 1);
	FL_DQ15_AM1 <= s_rom_a(0);

	regs_cs_s <= '1' when s_sltsl_rom_en = '1' and (s_A = x"7FF0" or s_A = x"7FF1") else '0';
	spi_cs_s	<= '1'  when s_sltsl_rom_en = '1' and rom_bank1_q = "111" and	s_A >= x"7B00" and s_A < x"7F00" else
	            '0';

	-- ------------------------------------------------------------------------
	-- Shared glitch-filtered write qualifier for ROM sub-slot register
	-- writes (bank switch, SD slot-select, timer load) - see declaration
	-- above for the rationale.
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

	-- ROM bank-switch registers + SD card slot-select: continuously re-latch
	-- D while s_cart_write_qualified holds (see header note on the
	-- MegaROM_ASCII16 bug this avoids), rather than sampling once on a
	-- delayed edge.
	i_ROM_Banks: process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				rom_bank1_q <= (others => '0');
				rom_bank2_q <= (others => '0');
				sd_sel_q    <= (others => '0');
			elsif s_cart_write_qualified = '1' then
				if s_A >= x"6000" and s_A <= x"67FF" then
					rom_bank1_q <= D(2 downto 0);
				elsif s_A >= x"7000" and s_A <= x"77FF" then
					rom_bank2_q <= D(3 downto 0);
				elsif s_A = x"7FF0" then
					sd_sel_q <= D(1 downto 0);
				end if;
			end if;
		end if;
	end process;

	-- Timer register: reloads every cycle while qualified (idempotent while
	-- D is stable throughout the write window), counts down to zero otherwise.
	--
	-- BUG FIX (2026-08-12, real hardware: "Card Failed!" persisted even
	-- after the WAIT_n/pull-up/status_s fixes). Root cause, found by reading
	-- the proven Nextor driver (msxsdmapperv2/driver/DRIVER.ASM): its
	-- WAIT_RESP_NO_FF/WAIT_RESP_FE polling loops (used while waiting for a
	-- response during the CMD0/CMD8/ACMD41 exchange) time a single unit as
	-- "ld a,255; ld (TIMERREG),a ; 2.6mS" - i.e. writing 255 to this
	-- register's upper byte (auto-filling the lower byte to 0xFF, giving a
	-- 65535-count countdown) is DOCUMENTED to take 2.6ms, which only holds
	-- if this counter is clocked at 25MHz (65535 / 0.0026s =~ 25.2MHz) -
	-- exactly matching the proven reference sdmapper.vhd's own timer
	-- process, which is clocked by "clock_i" (25MHz), NOT the raw 50MHz
	-- board oscillator. This process used CLOCK_50 instead, so every
	-- timeout unit only took ~1.3ms in reality - the driver's already-tight
	-- CMDTIMEOUT budget (2 units =~ 5.2ms intended) was silently cut to
	-- ~2.6ms, which could easily be too short for some cards/adapters to
	-- answer within, causing a premature "Card Failed!" even though the
	-- card would have responded given the real intended time budget.
	-- Fixed by clocking this process from clock_i (already generated
	-- elsewhere in this file for spi.vhd) instead of CLOCK_50.
	tmr_wr_s <= '1' when s_cart_write_qualified = '1' and s_A = x"7FF1" else '0';
	tmr_rd_s <= '1' when s_sltsl_rom_en = '1' and RD_n = '0' and s_A = x"7FF1" else '0';

	process (clock_i)
	begin
		if rising_edge(clock_i) then
			if tmr_wr_s = '1' then
				tmr_cnt_q(15 downto 8) <= D;
				tmr_cnt_q( 7 downto 0) <= (others => '1');
			elsif tmr_cnt_q /= 0 then
				tmr_cnt_q <= tmr_cnt_q - 1;
			end if;
		end if;
	end process;

	-- ------------------------------------------------------------------------
	-- SD card status/control register (raw/immediate read decode - not
	-- glitch-filtered, matches every other bus-driving read in this file).
	-- Status byte layout, see "HOW TO USE THIS BOARD" above:
	--   If no SD card is selected (sd_sel_q="00"): b7-b2=0, b1-b0=switch status.
	--   If card 1 selected (sd_sel_q="01"): b2=write-protect, b1=not present,
	--     b0=changed-since-last-read.
	--   If card 2 selected (sd_sel_q="10"): this board has no second SD slot -
	--     always reports write-protected/not-present/changed.
	-- ------------------------------------------------------------------------
	spi_ctrl_rd_s <= '1' when s_sltsl_rom_en = '1' and RD_n = '0' and s_A = X"7FF0"	else '0';

	-- BUG FIX (2026-08-12, real hardware: Nextor's boot banner reported
	-- "Slot Expander & Mem. Mapper disabled" and "Development driver
	-- selected" even though SDMapper mode was genuinely active). Root
	-- cause, found in the proven reference driver
	-- (msxsdmapperv2/driver/DRIVER.ASM): this b1:b0 pair is read directly
	-- by Nextor's kernel at boot as SPISTATUS (#7FF0) and interpreted with
	-- a FIXED polarity hardcoded in the driver - IF_RAM (bit0): "1 =
	-- interface RAM/mapper enabled"; IF_DRVER (bit1): "1 = Main driver, 0 =
	-- Dev driver". On the real Belavenuto hardware this bit pair is wired
	-- straight from raw switches (sw_i(1:0)), where sw_i(0)='1' also
	-- happens to be that hardware's own "cart enabled" polarity - so a
	-- direct passthrough was correct there. Our SW(9) was later inverted
	-- (SW(9)='0' means SDMapper mode enabled - see SW(9) header note) to
	-- satisfy a different requirement (reserving SW(9)='1' for a future
	-- MegaROM mode), but this status readout was never updated to match,
	-- so it kept reporting raw SW(9) - backwards relative to what the
	-- driver's hardcoded IF_RAM polarity expects. Fixed by reporting the
	-- correct semantic value (not SW(9)) instead of the raw switch level.
	-- This bit is informational only in the current driver (only feeds the
	-- boot banner text, confirmed by inspecting every IF_M_RAM/IF_M_DRVER
	-- use site) - fixing it corrects the misleading message but is not
	-- expected to change SD card access behavior on its own.
	--
	-- SW(7) (IF_DRVER, bit1) inverted too per user direction (2026-08-12) -
	-- SW(7)='0' now reports "Main driver", '1' reports "Development
	-- driver" (was the other way around). Also informational-only.
	status_s	<= "000000" & (not SW(7)) & (not SW(9))          when sd_sel_q = "00" else
					"00000" & (not SW(2)) & (not SW(0)) & sd_chg_s  when sd_sel_q = "01" else
					"00000" & '1' & '1' & '1'                        when sd_sel_q = "10" else
					(others => '-');

	-- ------------------------------------------------------------------------
	-- Synchronizer + edge detector for the SD status/control read strobe.
	-- ------------------------------------------------------------------------
	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			spi_ctrl_rd_meta   <= spi_ctrl_rd_s;
			spi_ctrl_rd_sync   <= spi_ctrl_rd_meta;
			spi_ctrl_rd_sync_d <= spi_ctrl_rd_sync;
		end if;
	end process;

	spi_ctrl_rd_rising_pulse  <= spi_ctrl_rd_sync and not spi_ctrl_rd_sync_d;
	spi_ctrl_rd_falling_pulse <= spi_ctrl_rd_sync_d and not spi_ctrl_rd_sync;

	-- Disk-change flip-flop (card 1 only - this board has no card 2).
	process (CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				sd_chg_q <= '0';
			elsif SW(0) = '0' then		-- card not present -> mark changed
				sd_chg_q <= '1';
			elsif spi_ctrl_rd_falling_pulse = '1' and sd_sel_q = "01" then
				sd_chg_q <= '0';
			end if;
		end if;
	end process;

	process (CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				sd_chg_s <= '0';
			elsif spi_ctrl_rd_rising_pulse = '1' then
				sd_chg_s <= sd_chg_q;
			end if;
		end if;
	end process;

	-- Generate the 25MHz clock_i for the SPI component ONLY - see "CLOCK
	-- DOMAINS" note at the top of this file.
	clock_25mhz_inst : clock_25mhz PORT MAP (
		inclk0   => CLOCK_50,
		c0       => clock_i
	);

	-- SPI interface to the SD card
	--
	-- EXPERIMENT (2026-08-12): swapped from work.spi to work.spi2 - see
	-- spi2.vhd header for full rationale. Same register protocol/driver,
	-- different (counter-based, not flag-based) internal WAIT-generation
	-- mechanism. If this doesn't fix "Card Failed!" either, revert this one
	-- line back to "entity work.spi" before trying anything else - no other
	-- part of this file needs to change either way, the two entities share
	-- an identical port list.
	portaspi: entity work.spi2
	port map (
		clock_i		=> clock_i,
		reset_n_i	=> s_reset_n,
		-- CPU interface
		cs_i			=> spi_cs_s,
		data_bus_io	=> D,
		wr_n_i		=> WR_n,
		rd_n_i		=> RD_n,
		wait_n_o		=> s_spi_wait_n_o,
		-- SD card interface
		spi_sclk_o	=> s_sd_clk,
		spi_mosi_o	=> s_sd_mosi,
		spi_miso_i	=> s_sd_miso,
		-- extra signals added for MSX_FPGA_Interface
		spi_dout		=> spi_data,
		spi_rd_en	=> spi_read
	);

	-- Onboard microSD (single physical card - see header note)
	SD1_CS   <= '0' when sd_sel_q = "01" else '1';
	SD1_SCK  <= s_sd_clk;
	SD1_MOSI <= s_sd_mosi;
	s_sd_miso <= SD1_MISO when sd_sel_q = "01" else '1';	-- idle/no-card-selected default (SPI MISO idles high)

	-- ------------------------------------------------------------------------
	-- RAM sub-slot: standard MSX Memory Mapper (512KB) - logic ported
	-- verbatim from MemoryMapper/MSX_FPGA_Top.vhd (see declarations above).
	-- ------------------------------------------------------------------------
	s_io_mapper_en    <= '1' when SW(9) = '0' and IORQ_n = '0' and M1_n = '1' and s_A(7 downto 2) = "111111" else '0';
	s_io_mapper_rd_en <= '1' when s_io_mapper_en = '1' and RD_n = '0' else '0';
	s_io_mapper_wr_en <= '1' when s_io_mapper_en = '1' and WR_n = '0' else '0';

	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				s_io_mapper_rd_dur_cnt   <= (others => '0');
				s_io_mapper_wr_dur_cnt   <= (others => '0');
				s_io_mapper_rd_qualified <= '0';
				s_io_mapper_wr_qualified <= '0';
			else
				if s_io_mapper_rd_en = '1' then
					if s_io_mapper_rd_dur_cnt < MIN_PULSE_CYCLES then
						s_io_mapper_rd_dur_cnt <= s_io_mapper_rd_dur_cnt + 1;
					end if;
					if s_io_mapper_rd_dur_cnt >= MIN_PULSE_CYCLES then
						s_io_mapper_rd_qualified <= '1';
					end if;
				else
					s_io_mapper_rd_dur_cnt   <= (others => '0');
					s_io_mapper_rd_qualified <= '0';
				end if;

				if s_io_mapper_wr_en = '1' then
					if s_io_mapper_wr_dur_cnt < MIN_PULSE_CYCLES then
						s_io_mapper_wr_dur_cnt <= s_io_mapper_wr_dur_cnt + 1;
					end if;
					if s_io_mapper_wr_dur_cnt >= MIN_PULSE_CYCLES then
						s_io_mapper_wr_qualified <= '1';
					end if;
				else
					s_io_mapper_wr_dur_cnt   <= (others => '0');
					s_io_mapper_wr_qualified <= '0';
				end if;
			end if;
		end if;
	end process;

	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				reg_page0_q <= "00011";
				reg_page1_q <= "00010";
				reg_page2_q <= "00001";
				reg_page3_q <= "00000";
			elsif s_io_mapper_wr_qualified = '1' then
				case s_A(1 downto 0) is
					when "00"   => reg_page0_q <= D(4 downto 0);
					when "01"   => reg_page1_q <= D(4 downto 0);
					when "10"   => reg_page2_q <= D(4 downto 0);
					when others => reg_page3_q <= D(4 downto 0);
				end case;
			end if;
		end if;
	end process;

	s_mapper_rdata <= "111" & reg_page0_q when s_A(1 downto 0) = "00" else
	                   "111" & reg_page1_q when s_A(1 downto 0) = "01" else
	                   "111" & reg_page2_q when s_A(1 downto 0) = "10" else
	                   "111" & reg_page3_q;

	-- SD SPI diagnostics: latch the last byte written to / read from the
	-- raw SPI data window, for display on HEX0-3 (see LEDG/HEXDIGIT
	-- assignments below). Not glitch-filtered - fine for a display latch,
	-- doesn't need to be precise to the exact cycle.
	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				s_spi_last_tx_q       <= (others => '0');
				s_spi_last_rx_q       <= (others => '0');
				s_spi_ever_accessed_q <= '0';
			else
				if spi_cs_s = '1' and WR_n = '0' then
					s_spi_last_tx_q       <= D;
					s_spi_ever_accessed_q <= '1';
				end if;
				if spi_read = '1' then
					s_spi_last_rx_q       <= spi_data;
					s_spi_ever_accessed_q <= '1';
				end if;
			end if;
		end if;
	end process;

	-- Memory (RAM sub-slot) access - raw/immediate decode.
	s_mem_rd_en <= '1' when s_sltsl_ram_en = '1' and RD_n = '0' else '0';
	s_mem_wr_en <= '1' when s_sltsl_ram_en = '1' and WR_n = '0' else '0';

	s_mem_page_seg <= reg_page0_q when s_A(15 downto 14) = "00" else
	                   reg_page1_q when s_A(15 downto 14) = "01" else
	                   reg_page2_q when s_A(15 downto 14) = "10" else
	                   reg_page3_q;

	s_sram_full_addr <= s_mem_page_seg & s_A(13 downto 0);	-- 5 + 14 = 19 bits = 512K

	SRAM_ADDR <= s_sram_full_addr(17 downto 0);
	SRAM_UB_N <= not s_sram_full_addr(18);
	SRAM_LB_N <= s_sram_full_addr(18);
	SRAM_CE_N <= not s_sltsl_ram_en;
	SRAM_OE_N <= RD_n;
	SRAM_WE_N <= WR_n;

	SRAM_DQ <= D when s_mem_wr_en = '1' else (others => 'Z');

	-- ------------------------------------------------------------------------
	-- Load the MSX bus with data from whichever device in this core is
	-- currently selected. Single driver for D (VHDL doesn't allow two
	-- unconditional concurrent drivers) - the listed priority never actually
	-- matters in practice since MREQ_n/IORQ_n are mutually exclusive on a
	-- real Z80 bus cycle and the memory-space windows below don't overlap.
	-- ------------------------------------------------------------------------
	D <= status_s               when spi_ctrl_rd_s = '1' else										-- SD card status/control
	     tmr_cnt_q(15 downto 8) when tmr_rd_s = '1' else											-- Timer
	     s_expn_q               when s_sltsl_en = '1' and s_ffff_slt = '1' and RD_n = '0' and spi_cs_s = '0' else	-- Slot expansion register
	     FL_DQ(7 downto 0)      when s_sltsl_rom_en = '1' and RD_n = '0' and spi_cs_s = '0' else	-- ROM / Flash
	     SRAM_DQ                when s_mem_rd_en = '1' else										-- RAM / Mapper
	     s_mapper_rdata         when s_io_mapper_rd_qualified = '1' else							-- Mapper segment registers
	     spi_data               when spi_read = '1' else											-- Raw SD SPI data
	     (others => 'Z');

	-- U1OE_n: covers every access path that reads OR writes D - see
	-- feedback_u1oe_n_per_access_path memory (this exact class of bug has
	-- been found twice already in this project). s_sltsl_en alone covers
	-- every memory-space path (ROM, RAM, SD/timer registers, FFFF) since all
	-- of them require SLTSL_n asserted with SW(9)='0' (SDMapper mode); the mapper I/O ports
	-- use their raw (unqualified) enables so U1 is listening for the FULL
	-- WR_n/RD_n-low window, not just the part after the glitch filter settles.
	U1OE_n <= '0' when s_sltsl_en = '1'        else
	          '0' when s_io_mapper_rd_en = '1' else
	          '0' when s_io_mapper_wr_en = '1' else
	          '1';

	-- U1_DIR: '0' = drive toward MSX (FPGA->MSX), '1' = listen from MSX
	-- (MSX->FPGA) - CORRECTED polarity, see header note (MegaROM_ASCII16's
	-- real-hardware milestone found this backwards in every earlier version
	-- of this file). Default '1' (listen) covers every write path and idle.
	U1_DIR <= '0' when spi_ctrl_rd_s = '1' else
	          '0' when tmr_rd_s = '1' else
	          '0' when s_sltsl_en = '1' and s_ffff_slt = '1' and RD_n = '0' and spi_cs_s = '0' else
	          '0' when s_sltsl_rom_en = '1' and RD_n = '0' and spi_cs_s = '0' else
	          '0' when s_mem_rd_en = '1' else
	          '0' when s_io_mapper_rd_qualified = '1' else
	          '0' when spi_read = '1' else
	          '1';

	-- BUSDIR_n: only /IORQ-based reads need it (MSX Technical Data Book
	-- 1.6.2) - ordinary /SLTSL memory reads (ROM, RAM, SD/timer registers,
	-- FFFF) do not. Never tri-stated - always actively driven.
	BUSDIR_n <= '0' when s_io_mapper_rd_qualified = '1' else '1';

	-- ------------------------------------------------------------------------
	-- Debug display. ROM/RAM sub-slot access (previously shown on HEX) is
	-- CONFIRMED working on real hardware as of 2026-08-11 - the display is
	-- repurposed for the still-open SD SPI investigation:
	--   HEX1:HEX0 = last byte RECEIVED from the SD card (spi_data/spi_dout)
	--   HEX3:HEX2 = last byte SENT to the SD card
	-- LEDG(9)/(8) = sticky "sub-slot was ever genuinely read" latches.
	-- LEDG(7 downto 4) show the live slot-expander outputs (active-high here
	-- for legibility). LEDG(3) = sticky "SD SPI window was ever accessed"
	-- latch - confirms Nextor's kernel is at least reaching the hardware
	-- window at all, independent of whether the card itself responds.
	-- ------------------------------------------------------------------------
	HEXDIGIT0 <= s_spi_last_rx_q(3 downto 0);
	HEXDIGIT1 <= s_spi_last_rx_q(7 downto 4);
	HEXDIGIT2 <= s_spi_last_tx_q(3 downto 0);
	HEXDIGIT3 <= s_spi_last_tx_q(7 downto 4);

	LEDG(9)          <= s_rom_subslot_ever_q;
	LEDG(8)          <= s_ram_subslot_ever_q;
	LEDG(7 downto 4) <= not slt_exp_n;
	LEDG(3)          <= s_spi_ever_accessed_q;
	LEDG(2)          <= s_sltsl_ram_en;
	LEDG(1)          <= s_sltsl_rom_en;
	LEDG(0)          <= s_sltsl_en;

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

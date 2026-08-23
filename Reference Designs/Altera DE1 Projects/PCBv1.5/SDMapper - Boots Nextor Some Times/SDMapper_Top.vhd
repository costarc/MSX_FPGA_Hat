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
--
-- Notable parts I changed include:
--  -> ROM address decoding, where I prefer using a more natural "mathematical" language rather than "bit" language
--  -> SD Card signal assignments - I added some additional signals to the top-level and drive the SD card signals from there.
--  -> The 25MHz clock for the SPI is created from the internal 50MHz clock in the DE0/DE1
--  -> Many more, check the comments throughout the code.
-- --------------------------------------------------------------------------------------------------------------------------------------
--
-- HOW TO USE THIS BOARD
-- --------------------------------------------------------------------------------------------------------------------------------------
-- Switches (SW):
--   SW(9)    - Master cart-emulation enable. Must be '1' for this cartridge to
--              respond to /SLTSL-based memory access (ROM, RAM/mapper, and the
--              slot-expansion register at FFFF). When '0', this cartridge stays
--              silent on the memory bus.
--              NOTE: the mapper I/O ports (FC-FF) are currently NOT gated by this
--              switch - see "Known caveats" below.
--   SW(8)    - RAM/mapper sub-slot enable. Combined with SW(9) (via the slot
--              expander) to enable the SRAM-backed memory mapper sub-slot.
--   SW(7)    - Dev ROM / Main ROM selector. Exposed to software via the status
--              register bit 0 when no SD card slot is selected (see status_s).
--              Not used by this file's own hardware decoding.
--   SW(3:2)  - Write-protect flags for SD card slot 2 / slot 1 respectively,
--              reported to software via the status register.
--   SW(1:0)  - Card-present flags for SD card slot 2 / slot 1 respectively. This
--              board has no physical card-detect sensing, so presence is set
--              manually with these switches.
--
-- Pushbuttons (KEY):
--   KEY(0)   - Manual reset. Combined with the MSX's own RESET_n line - either one
--              being asserted forces a full reset of this design.
--   KEY(3:1) - Unused.
--
-- Memory map (within this cartridge's /SLTSL-selected space, when SW(9) = '1'):
--   ROM/Flash sub-slot (rom_bank1_q / rom_bank2_q select the visible 16KB segment):
--     4000-7FFF   - Bank 1 window. Always Flash-backed when this sub-slot is active.
--       6000-67FF, 7000-77FF - Bank-switch registers (write-only; reads in this
--                               range still return normal ROM data).
--       7B00-7EFF             - SD card raw SPI data register. Only visible when
--                               rom_bank1_q = 7 (i.e. bank 1 must be switched to
--                               segment 7 to reach the SD card hardware).
--       7FF0                  - SD card control/status register.
--       7FF1                  - Timer register.
--     8000-BFFF   - Bank 2 window. Only Flash-backed when rom_bank2_q >= 8
--                   (bit 3 set); otherwise unmapped.
--     0000-3FFF, C000-FFFF - Not Flash-backed by this design (standard for
--                             ASCII16-style mappers, which only use two of the
--                             four 16KB pages).
--   RAM/mapper sub-slot: all four 16KB pages are supported, each addressed via
--   its own segment register (s_fc/s_fd/s_fe/s_ff - see I/O ports below).
--   FFFF        - Slot-expansion sub-slot select register (intercepted regardless
--                 of which sub-slot would otherwise be visible there).
--
-- I/O ports (independent of SW(9) - see caveat below):
--   FC-FF       - Standard MSX memory-mapper segment registers, one per 16KB page.
--
-- Known caveats:
--   - Mapper I/O ports FC-FF remain live on the bus regardless of SW(9). On a host
--     that already has its own memory mapper (e.g. a Zemmix), this can cause
--     read-side bus contention, since both devices will drive the data bus at the
--     same time. If this board is ever used alongside another mapper-equipped
--     host, gate s_iorq_r / s_iorq_w with SW(9) as well.
-- --------------------------------------------------------------------------------------------------------------------------------------
--
-- CLOCK DOMAINS (this revision)
-- --------------------------------------------------------------------------------------------------------------------------------------
-- Two separate clocks are used in this design, deliberately kept independent:
--
--   CLOCK_50 (50MHz, raw board oscillator, no PLL) drives everything in this
--   top-level file EXCEPT the spi.vhd instantiation: the address-bus capture
--   state machine, every synchronizer, the mapper/ROM-bank/SD-select/disk-change
--   registers, the timer, and exp_slot's clock. This was moved from the slower
--   PLL-derived clock_i specifically to shrink the address-capture latency (see
--   below), since ordinary ROM/RAM reads get no /WAIT insertion and therefore
--   have no slack to spare.
--
--   clock_i (25MHz, generated from CLOCK_50 via clock_25mhz_inst) drives ONLY
--   the spi.vhd component. This is intentionally NOT changed to CLOCK_50: the
--   SPI state machine toggles its SCLK output once per clock_i edge, so its
--   frequency directly sets the SD card's SPI clock rate (currently ~12.5MHz).
--   Feeding it CLOCK_50 instead would silently double that to ~25MHz, which
--   risks exceeding safe SPI-mode timing on some SD cards - so the two clocks
--   are kept deliberately separate. spi.vhd already treats all of its CPU-facing
--   inputs (cs_i, wr_n_i, rd_n_i) as asynchronous and synchronizes them
--   internally on its own clock_i, so this split introduces no new
--   clock-domain-crossing hazard between the two domains.
-- --------------------------------------------------------------------------------------------------------------------------------------
--
-- ADDRESS BUS MULTIPLEXING (this revision)
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
-- Every decode condition in this file that used to reference the raw address
-- port "A" now reads the latched s_A register instead.
--
-- Timing budget: worst case, s_A is fully updated ~5 CLOCK_50 cycles (~100ns at
-- 50MHz) after MREQ_n/IORQ_n asserts - half the latency of the previous
-- clock_i-based version. This is still new, previously-untested territory for
-- this design - verify on real hardware (e.g. scope U2OE_n/U3OE_n and confirm
-- s_A settles well before RD_n/WR_n's data window closes, and confirm FL_DQ is
-- valid in time) before relying on it.
-- --------------------------------------------------------------------------------------------------------------------------------------
--
-- STABILITY FIXES (previous revisions):
-- 1) Every register that used to be clocked directly off a combinational bus-decode
--    signal (e.g. "elsif falling_edge(rom_bank_wr_s)") has been changed to a real
--    synchronous register, qualified by a synchronized/edge-detected pulse derived
--    from that same decode signal. This avoids glitches caused by real-world skew
--    between address/WR/IORQ signals on actual Z80 hardware. Applied to:
--      - mapper segment registers (s_fc/s_fd/s_fe/s_ff)
--      - ROM bank registers (rom_bank1_q/rom_bank2_q)
--      - SD card slot-select register (sd_sel_q)
--      - SD card disk-change flags (sd_chg_q, sd_chg_s)
-- 2) BUSDIR_n / U1OE_n were reviewed against https://www.msx.org/wiki/Hardware_Design
--    and confirmed correct as originally written: BUSDIR is only required for I/O
--    (/IORQ) reads (mapper ports FC-FF here), not for ordinary /SLTSL memory reads.
-- 3) WAIT_n and INT_n are both inverted at the top-level boundary to compensate for
--    open-collector NPN driver stages (Q2, Q1) on the MSX_FPGA_Hat board, which
--    invert whatever level the FPGA drives before it reaches the real MSX bus.
-- 4) regs_cs_s was narrowed from "A >= x7FF0" (which incorrectly covered the whole
--    7FF0-FFFF range) to an exact match on the two real registers (7FF0, 7FF1), so
--    the remaining ROM bytes at 7FF2-7FFF are no longer blocked from being read.
-- 5) s_sd_miso now has a defined default ('1', idle-high) instead of an incomplete
--    conditional assignment, removing an unsafe inferred latch on that signal.
-- 6) The manual reset button (SW1) was removed from the interface board - it was
--    wired directly onto the shared, system-wide MSX /RESET line, so pressing it
--    reset the whole MSX rather than just this design (KEY(0) already provides a
--    properly-scoped local reset).
-- 7) The /CS2 and /RFSH signals, which shared a single FPGA pin, are now selected
--    by a physical jumper (JP1) instead of both being wired live at once - this
--    was a genuine contention risk, since the /CS2 buffer's output-enable was
--    hard-wired always-active and could never be switched off in software.
-- --------------------------------------------------------------------------------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;

Entity SDMapper_TOP is
port (
    CLOCK_24:	  	in std_logic_vector(1 downto 0);		-- 24 MHz
    CLOCK_27:		in std_logic_vector(1 downto 0);		--	27 MHz
    CLOCK_50:		in std_logic;								--	50 MHz
    EXT_CLOCK:		in std_logic;								--	External Clock

    KEY:				in std_logic_vector(3 downto 0);		--	Pushbutton[3:0]

    SW:				in std_logic_vector(9 downto 0);		--	Toggle Switch[9:0]

    HEX0:				out std_logic_vector(6 downto 0);	--	Seven Segment Digit 0
    HEX1:				out std_logic_vector(6 downto 0);	--	Seven Segment Digit 1
    HEX2:				out std_logic_vector(6 downto 0);	--	Seven Segment Digit 2
    HEX3:				out std_logic_vector(6 downto 0);	--	Seven Segment Digit 3

    LEDG:				out std_logic_vector(7 downto 0);	--	LED Green[7:0]
    LEDR:				out std_logic_vector(9 downto 0);	--	LED Red[9:0]

    UART_TXD:		out std_logic;								--	UART Transmitter
    UART_RXD:		in std_logic;								--	UART Receiver

    DRAM_DQ:			inout std_logic_vector(15 downto 0);--	SDRAM Data bus 16 Bits
    DRAM_ADDR:		out std_logic_vector(11 downto 0);	--	SDRAM Address bus 12 Bits
    DRAM_LDQM:		out std_logic;								--	SDRAM Low-byte Data Mask
    DRAM_UDQM:		out std_logic;								--	SDRAM High-byte Data Mask
    DRAM_WE_N:		out std_logic;								--	SDRAM Write Enable
    DRAM_CAS_N:		out std_logic;								--	SDRAM Column Address Strobe
    DRAM_RAS_N:		out std_logic;								--	SDRAM Row Address Strobe
    DRAM_CS_N:		out std_logic;								--	SDRAM Chip Select
    DRAM_BA_0:		out std_logic;								--	SDRAM Bank Address 0
    DRAM_BA_1:		out std_logic;								--	SDRAM Bank Address 0
    DRAM_CLK:		out std_logic;								--	SDRAM Clock
    DRAM_CKE:		out std_logic;								--	SDRAM Clock Enable

    FL_DQ:			inout std_logic_vector(7 downto 0);	--	FLASH Data bus 8 Bits
    FL_ADDR:			out std_logic_vector(21 downto 0);	--	FLASH Address bus 22 Bits
    FL_WE_N:			out std_logic;								--	FLASH Write Enable
    FL_RST_N:		out std_logic;								--	FLASH Reset
    FL_OE_N:			out std_logic;								--	FLASH Output Enable
    FL_CE_N:			out std_logic;								--	FLASH Chip Enable

    SRAM_DQ:			inout std_logic_vector(15 downto 0);--	SRAM Data bus 16 Bits
    SRAM_ADDR:		out std_logic_vector(17 downto 0);	--	SRAM Address bus 18 Bits
    SRAM_UB_N:		out std_logic;								--	SRAM High-byte Data Mask
    SRAM_LB_N:		out std_logic;								--	SRAM Low-byte Data Mask
    SRAM_WE_N:		out std_logic;								--	SRAM Write Enable
    SRAM_CE_N:		out std_logic;								--	SRAM Chip Enable
    SRAM_OE_N:		out std_logic;								--	SRAM Output Enable

    I2C_SDAT:		inout std_logic;							--	I2C Data
    I2C_SCLK:		out std_logic;								--	I2C Clock

    PS2_DAT:			in std_logic;							--	PS2 Data
    PS2_CLK:			in std_logic;							--	PS2 Clock

    TDI:				in std_logic;  							-- CPLD -> FPGA (data in)
    TCK:				in std_logic;  							-- CPLD -> FPGA (clk)
    TCS:				in std_logic;  							-- CPLD -> FPGA (CS)
    TDO:				out std_logic; 							-- FPGA -> CPLD (data out)

    VGA_HS:			out std_logic;								--	VGA H_SYNC
    VGA_VS:			out std_logic;								--	VGA V_SYNC
    VGA_R:   		out std_logic_vector(3 downto 0);	--	VGA Red[3:0]
    VGA_G:	 		out std_logic_vector(3 downto 0);	--	VGA Green[3:0]
    VGA_B:   		out std_logic_vector(3 downto 0);	--	VGA Blue[3:0]

    AUD_ADCLRCK:	inout std_logic;							--	Audio CODEC ADC LR Clock
    AUD_ADCDAT:		in std_logic;								--	Audio CODEC ADC Data
    AUD_DACLRCK:	inout std_logic;							--	Audio CODEC DAC LR Clock
    AUD_DACDAT:		out std_logic;								--	Audio CODEC DAC Data
    AUD_BCLK:		inout std_logic;							--	Audio CODEC Bit-Stream Clock
    AUD_XCK:			out std_logic;								--	Audio CODEC Chip Clock

    SD1_CS:			out std_logic;							--
    SD1_SCK:		out std_logic;							--
    SD1_MOSI: 		out std_logic;							--
    SD1_MISO: 		in std_logic;							--

    -- GPIO_0:			inout std_logic_vector(35 downto 0);--	GPIO Connection 0
    SD2_CS:			out std_logic;							--
    SD2_SCK:		out std_logic;							--
    SD2_MOSI: 		out std_logic;						--	--
    SD2_MISO: 		in std_logic;							--

    -- MSX Bus
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
	signal s_spi_wait_n_o: std_logic;
	signal s_sltsl_en		: std_logic;
	signal spi_data		: std_logic_vector(7 downto 0);
	signal spi_read		: std_logic;

	-- Flash ASCII16
	signal rom_bank_wr_s	: std_logic;
	signal rom_bank1_q	: std_logic_vector(2 downto 0);
	signal rom_bank2_q	: std_logic_vector(3 downto 0);
	signal s_flashbase	: std_logic_vector(23 downto 0);
	signal s_rom_a			: std_logic_vector(31 downto 0);
	signal s_sltsl_rom_en	: std_logic;

	-- MSX-DOS & Nextor & SDCard
	signal clock_i			: std_logic := '0';	-- 25MHz, feeds ONLY spi.vhd - see "CLOCK DOMAINS" note above
	signal sd_wp_i			: std_logic_vector(1 downto 0);
	signal sd_pres_n_i	: std_logic_vector(1 downto 0);
	signal regs_cs_s		: std_logic;

	-- SPI port
	signal spi_cs_s		: std_logic;
	signal sd_chg_q		: std_logic_vector(1 downto 0);
	signal sd_chg_s		: std_logic_vector(1 downto 0);
	signal status_s		: std_logic_vector(7 downto 0);
	signal spi_ctrl_wr_s	: std_logic;
	signal spi_ctrl_rd_s	: std_logic;
	signal sd_sel_q		: std_logic_vector(1 downto 0);

	-- Timer
	signal tmr_cnt_q		: std_logic_vector(15 downto 0);
	signal tmr_wr_s		: std_logic;
	signal tmr_rd_s		: std_logic;

	signal s_sd_cs			: std_logic;
	signal s_sd_clk		: std_logic;
	signal s_sd_mosi		: std_logic;
	signal s_sd_miso		: std_logic;

	-- Mapper
	signal s_io_addr 			: std_logic_vector(7 downto 0);
	signal s_fc					: std_logic_vector(4 downto 0) := "00011";
	signal s_fd					: std_logic_vector(4 downto 0) := "00010";
	signal s_fe					: std_logic_vector(4 downto 0) := "00001";
	signal s_ff					: std_logic_vector(4 downto 0) := "00000";
	signal s_iorq_r			: std_logic;
	signal s_iorq_w			: std_logic;
	signal s_iorq_r_reg		: std_logic;
	signal s_iorq_w_reg		: std_logic;
	signal s_mapper_reg_w	: std_logic;
	signal s_sltsl_ram_en	: std_logic;

	signal s_SRAM_ADDR		: std_logic_vector(20 downto 0);
	signal s_ffff_slt			: std_logic;
	signal slt_exp_n			: std_logic_vector(3 downto 0);
	signal s_expn_q			: std_logic_vector(7 downto 0);

	-- ------------------------------------------------------------------------
	-- Address bus reconstruction (see "ADDRESS BUS MULTIPLEXING" note above)
	-- Runs on CLOCK_50 - see "CLOCK DOMAINS" note above.
	-- ------------------------------------------------------------------------
	signal s_A				: std_logic_vector(15 downto 0) := (others => '0');

	signal s_bus_req_n		: std_logic;	-- combinational: '0' whenever MREQ_n or IORQ_n is active
	signal bus_req_meta, bus_req_sync, bus_req_sync_d : std_logic;
	signal addr_capture_trigger : std_logic;	-- one CLOCK_50-wide pulse: start of a new bus cycle

	type addr_capture_state_t is (S_IDLE, S_LOW_EN, S_LOW_CAP, S_GUARD, S_HIGH_EN, S_HIGH_CAP);
	signal addr_capture_state : addr_capture_state_t := S_IDLE;

	-- ------------------------------------------------------------------------
	-- Synchronizer / edge-detector signals for every bus-decoded write/read
	-- strobe that used to clock a register directly. All are 3-stage chains
	-- on CLOCK_50: stage "meta" absorbs metastability, "sync" is the resolved
	-- value safe to use, "sync_d" is one cycle behind sync for edge detection.
	-- ------------------------------------------------------------------------

	-- WR_n synchronizer, used to qualify the ROM-bank-switch write
	signal wr_n_meta, wr_n_sync, wr_n_sync_d           : std_logic;
	signal wr_falling_pulse                            : std_logic;

	-- Mapper segment register write strobe (s_iorq_w_reg)
	signal s_iorq_w_reg_meta, s_iorq_w_reg_sync, s_iorq_w_reg_sync_d : std_logic;
	signal s_iorq_w_reg_falling_pulse                  : std_logic;

	-- SD card slot-select register write strobe (spi_ctrl_wr_s)
	signal spi_ctrl_wr_meta, spi_ctrl_wr_sync, spi_ctrl_wr_sync_d : std_logic;
	signal spi_ctrl_wr_falling_pulse                   : std_logic;

	-- SD card status/control register read strobe (spi_ctrl_rd_s) - used both
	-- edges: rising edge latches the "changed" flags for the CPU to read,
	-- falling edge (end of the read cycle) clears the flag that was just read.
	signal spi_ctrl_rd_meta, spi_ctrl_rd_sync, spi_ctrl_rd_sync_d : std_logic;
	signal spi_ctrl_rd_rising_pulse, spi_ctrl_rd_falling_pulse    : std_logic;

begin

	-- Inverted here to compensate for the Q2 open-collector driver stage on the
	-- MSX_FPGA_Hat board, which inverts whatever level the FPGA drives.
	WAIT_n <= not s_spi_wait_n_o;

	-- Reset circuit
	s_reset <= not (KEY(0) and RESET_n);
	INT_n <= '0';  -- inverted due to the Q1 open-collector stage in the interface
   U4OE_n <= '0';
	
	-- Some cool lights flashing while you play games with your real MSX and DE1 as disk drives.
	-- Also used for debugging.
	LEDG <= s_reset & slt_exp_n & s_ffff_slt & s_sltsl_ram_en & s_sltsl_rom_en;
	LEDR <= s_reset & spi_cs_s & s_spi_wait_n_o & regs_cs_s & sd_sel_q & not sd_wp_i & not sd_pres_n_i;
	HEXDIGIT0 <= s_fc(3 downto 0);
	HEXDIGIT1 <= s_fd(3 downto 0);
	HEXDIGIT2 <= '0'&rom_bank1_q(2 downto 0);
	HEXDIGIT3 <= rom_bank2_q(3 downto 0);

	-- ------------------------------------------------------------------------
	-- Address bus capture: synchronize the "new bus cycle starting" trigger
	-- (falling edge of MREQ_n or IORQ_n), then run the low/high byte capture
	-- state machine, on CLOCK_50. See "ADDRESS BUS MULTIPLEXING" note at the
	-- top of this file for the full explanation.
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
			else
				case addr_capture_state is
					when S_IDLE =>
						U2OE_n <= '1';
						U3OE_n <= '1';
						if addr_capture_trigger = '1' then
							addr_capture_state <= S_LOW_EN;
						end if;
					when S_LOW_EN =>
						U2OE_n <= '0';		-- enable low address byte (A0-A7)
						U3OE_n <= '1';
						addr_capture_state <= S_LOW_CAP;
					when S_LOW_CAP =>
						-- U2 has had a full CLOCK_50 period to settle (>>4x its
						-- worst-case propagation delay) - safe to capture now.
						s_A(7 downto 0) <= A_MUX;
						addr_capture_state <= S_GUARD;
					when S_GUARD =>
						-- Both buffers disabled for one full cycle before
						-- enabling the other, so U2OE_n/U3OE_n are never both
						-- asserted near the same instant even with routing skew.
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

	-- Generic output signals to DE1
	-- BUSDIR is only required by the MSX standard for /IORQ-based reads (this
	-- cartridge's mapper ports FC-FF). Ordinary /SLTSL memory reads (ROM, SRAM,
	-- slot-expansion register) do not need it - confirmed against
	-- https://www.msx.org/wiki/Hardware_Design.
	BUSDIR_n <= not s_iorq_r_reg;
	s_sltsl_en <= (not SLTSL_n) when SW(9) = '1' else '0';		-- Will only enable cart emulation if SW(9) is '1'
	s_sltsl_rom_en <= not slt_exp_n(0) when SW(9) = '1' else '0';
	s_sltsl_ram_en <= not slt_exp_n(1) when SW(8) = '1' else '0';

	-- Enable output in U1 (74LVC245)
	U1OE_n <= not (s_sltsl_en or s_iorq_r_reg or s_iorq_w_reg);

	U1_DIR <= '1' when spi_ctrl_rd_s = '1' else
          '1' when tmr_rd_s = '1' else
          '1' when s_sltsl_en = '1' and s_ffff_slt = '1' and RD_n = '0' and spi_cs_s = '0' else
          '1' when s_sltsl_rom_en = '1' and RD_n = '0' and spi_cs_s = '0' else
          '1' when s_sltsl_ram_en = '1' and RD_n = '0' else
          '1' when s_iorq_r_reg = '1' else
          '1' when spi_read = '1' else
          '0';
			 
	-- Detect access to slots - to be used with the slot expander
	s_ffff_slt    <= '1' when s_A = x"FFFF" else '0';

	-- Mapper
	-- M1_n = '1' correctly differentiates I/O reads from interrupt-acknowledge
	-- cycles, per https://www.msx.org/wiki/Hardware_Design.
	s_iorq_r		<= '1' when RD_n = '0' and  IORQ_n = '0' and M1_n = '1' else '0';
	s_iorq_w		<= '1' when WR_n = '0' and  IORQ_n = '0' and M1_n = '1' else '0';
	s_io_addr	<= s_A(7 downto 0);
	s_iorq_r_reg <= '1' when s_iorq_r = '1' and (s_io_addr = x"FC" or s_io_addr = x"FD" or s_io_addr = x"FE" or s_io_addr = x"FF") else '0';
	s_iorq_w_reg <= '1' when s_iorq_w = '1' and (s_io_addr = x"FC" or s_io_addr = x"FD" or s_io_addr = x"FE" or s_io_addr = x"FF") else '0';


	-- FlashRAM physical pins - Mapper will be in expanded subslot 1
	SRAM_CE_N <= not s_sltsl_ram_en;
	SRAM_OE_N <= '0';
	SRAM_WE_N <= WR_n;
	SRAM_ADDR <= s_SRAM_ADDR(17 downto 0);
	SRAM_UB_N <= not s_SRAM_ADDR(18);
	SRAM_LB_N <= s_SRAM_ADDR(18);
	SRAM_DQ(7 downto 0)  <= D when s_sltsl_ram_en = '1' and WR_n = '0' and s_SRAM_ADDR(18) = '0' else (others => 'Z');
	SRAM_DQ(15 downto 8) <= D when s_sltsl_ram_en = '1' and WR_n = '0' and s_SRAM_ADDR(18) = '1' else (others => 'Z');

	s_SRAM_ADDR <= (s_fc * x"4000") + ("00" & s_A(13 downto 0)) when s_A(15 downto 14) = "00" else
               (s_fd * x"4000") + ("00" & s_A(13 downto 0)) when s_A(15 downto 14) = "01" else
               (s_fe * x"4000") + ("00" & s_A(13 downto 0)) when s_A(15 downto 14) = "10" else
               (s_ff * x"4000") + ("00" & s_A(13 downto 0));

	-- ------------------------------------------------------------------------
	-- Synchronizer + edge detector for the mapper I/O write strobe.
	-- ------------------------------------------------------------------------
	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			s_iorq_w_reg_meta   <= s_iorq_w_reg;
			s_iorq_w_reg_sync   <= s_iorq_w_reg_meta;
			s_iorq_w_reg_sync_d <= s_iorq_w_reg_sync;
		end if;
	end process;

	s_iorq_w_reg_falling_pulse <= s_iorq_w_reg_sync_d and not s_iorq_w_reg_sync;

	-- Mapper segment registers (FC/FD/FE/FF) - fully synchronous
	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				s_fc <= "00011";
				s_fd <= "00010";
				s_fe <= "00001";
				s_ff <= "00000";
			elsif s_iorq_w_reg_falling_pulse = '1' then
				case s_io_addr is
					when x"FC" => s_fc <= D(4 downto 0);
					when x"FD" => s_fd <= D(4 downto 0);
					when x"FE" => s_fe <= D(4 downto 0);
					when x"FF" => s_ff <= D(4 downto 0);
					when others => null;
				end case;
			end if;
		end if;
	end process;

	-- -- End of Mapper Implementation

	-- FlashRAM (ROM) constant control signals
	FL_RST_N <= '1';
	FL_OE_N <= RD_n;

	-- Bank write - detects writes in the ranges 6000h-67FFh and 7000h-77FFh
	rom_bank_wr_s <= '1' when s_sltsl_rom_en = '1' and WR_n = '0' and ((s_A >= x"6000" and s_A <= x"67FF") OR (s_A >= x"7000" and s_A <= x"77FF")) else  '0';

	s_flashbase <= x"000000";		-- FlashRAM address for the Nextor Operating System

	-- Checks the address being accessed. Mirrors memory as per information in https://www.msx.org/wiki/MegaROM_Mappers#ASCII16_.28ASCII.29
	s_rom_a(23 downto 0) <= s_flashbase + (rom_bank1_q(2 downto 0) & s_A(13 downto 0)) when s_sltsl_rom_en = '1' and (s_A(15 downto 14) = "01" or s_A(15 downto 14) = "11") else		-- Bank1
                           s_flashbase + (rom_bank2_q(3 downto 0) & s_A(13 downto 0)) when s_sltsl_rom_en = '1' and (s_A(15 downto 14) = "10" or s_A(15 downto 14) = "00") else		-- Bank2:
	                        (others => '-');

   FL_CE_N <= -- Excludes the SPI range and the registers range
		'0'	when s_A(15 downto 14) = "01" and s_sltsl_rom_en = '1' and RD_n = '0' and spi_cs_s = '0' and regs_cs_s = '0'	else
		'0'	when s_A(15 downto 14) = "10" and s_sltsl_rom_en = '1' and rom_bank2_q(3) = '1'					else		-- Only if bank > 7
		'1';

   regs_cs_s <= '1' when s_sltsl_rom_en = '1' and (s_A = x"7FF0" or s_A = x"7FF1") else '0';

	FL_ADDR <= s_rom_a(21 downto 0);

	-- Load the MSX bus with data from the devices in this core.
	-- Note that data to/from the SD Card is loaded inside the SPI component, not here.
	D <=
	     status_s	when spi_ctrl_rd_s = '1' else																			-- SD Card
        tmr_cnt_q(15 downto 8) when tmr_rd_s = '1' else 																-- SD Card
		  s_expn_q when s_sltsl_en = '1' and s_ffff_slt = '1' and RD_n = '0' and spi_cs_s = '0' else								-- Slot Select expansion
		  FL_DQ when s_sltsl_rom_en = '1' and RD_n = '0' and spi_cs_s = '0' else								-- FlashRAM / ROM
		  SRAM_DQ(7 downto 0) when s_sltsl_ram_en = '1' and RD_n = '0' and s_SRAM_ADDR(18) = '0' else	-- SRAM / Mapper
	     SRAM_DQ(15 downto 8) when s_sltsl_ram_en = '1' and RD_n = '0' and s_SRAM_ADDR(18) = '1' else	-- SRAM / Mapper
		  "111" & s_fc when s_iorq_r = '1' and s_io_addr = x"FC" else												-- SRAM / Mapper
		  "111" & s_fd when s_iorq_r = '1' and s_io_addr = x"FD" else												-- SRAM / Mapper
		  "111" & s_fe when s_iorq_r = '1' and s_io_addr = x"FE" else												-- SRAM / Mapper
		  "111" & s_ff when s_iorq_r = '1' and s_io_addr = x"FF" else												-- SRAM / Mapper
		  spi_data when spi_read = '1' else
		  (others => 'Z');

	-- Status flags - see "HOW TO USE THIS BOARD" above for the switch meanings.
	-- If no SD card is selected:
	--   b7-b2 : always 0
	--   b1-b0 : switch status (see SW(7), SW(9) above)
	-- If any SD card is selected:
	--   b7-b3 : always 0
	--   b2    : 1 = write protection enabled for the selected SD card slot
	--   b1    : 0 = SD card present on the selected slot
	--   b0    : 1 = SD card on the selected slot changed since the last read
	sd_pres_n_i <= not SW(1 downto 0);		-- SW1/SW0 is the flag for "SD card inserted"
	sd_wp_i <= not SW(3 downto 2);			-- SW3/SW2 is the write-protect flag for the SD cards

	status_s	<= "000000" & SW(7) & SW(9) when sd_sel_q = "00"	else															-- No SD selected
					"00000" & sd_wp_i(0) & sd_pres_n_i(0) & sd_chg_s(0) when sd_sel_q = "01" else		-- SD 1 selected
					"00000" & sd_wp_i(1) & sd_pres_n_i(1) & sd_chg_s(1) when sd_sel_q = "10" else		-- SD 2 selected
					(others => '-');

	spi_ctrl_wr_s <= '1' when s_sltsl_rom_en = '1' and WR_n = '0' and s_A = X"7FF0"	else '0';
	spi_ctrl_rd_s <= '1' when s_sltsl_rom_en = '1' and RD_n = '0' and s_A = X"7FF0"	else '0';

	spi_cs_s	<= '1'  when s_sltsl_rom_en = '1' and rom_bank1_q = "111" and	s_A >= x"7B00" and s_A < x"7F00" else
	            '0';
	tmr_wr_s <= '1' when s_sltsl_rom_en = '1' and WR_n = '0' and s_A = x"7FF1" else '0';
	tmr_rd_s <= '1' when s_sltsl_rom_en = '1' and RD_n = '0' and s_A = x"7FF1" else '0';

	-- ------------------------------------------------------------------------
	-- Synchronizer + edge detector for the SD status/control register read
	-- strobe (spi_ctrl_rd_s). Both edges are used:
	--  - rising edge  -> latch the current "changed" flags for the CPU to read
	--  - falling edge -> clear the flag that was just presented, once the CPU
	--                    has finished the read cycle
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

	-- Disk-change flip-flops
	process (CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				sd_chg_q(0) <= '0';
			elsif sd_pres_n_i(0) = '1' then
				sd_chg_q(0) <= '1';
			elsif spi_ctrl_rd_falling_pulse = '1' and sd_sel_q = "01" then
				sd_chg_q(0) <= '0';
			end if;
		end if;
	end process;

	process (CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				sd_chg_q(1) <= '0';
			elsif sd_pres_n_i(1) = '1' then
				sd_chg_q(1) <= '1';
			elsif spi_ctrl_rd_falling_pulse = '1' and sd_sel_q = "10" then
				sd_chg_q(1) <= '0';
			end if;
		end if;
	end process;

	process (CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				sd_chg_s <= (others => '0');
			elsif spi_ctrl_rd_rising_pulse = '1' then
				sd_chg_s <= sd_chg_q;
			end if;
		end if;
	end process;

	-- Timer
	process (CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if tmr_wr_s = '1' then
				tmr_cnt_q(15 downto 8) <= D;
				tmr_cnt_q( 7 downto 0) <= (others => '1');
			elsif tmr_cnt_q /= 0 then
				tmr_cnt_q <= tmr_cnt_q - 1;
			end if;
		end if;
	end process;

	-- ------------------------------------------------------------------------
	-- Synchronizer + edge detector for the SD card slot-select write strobe.
	-- ------------------------------------------------------------------------
	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			spi_ctrl_wr_meta   <= spi_ctrl_wr_s;
			spi_ctrl_wr_sync   <= spi_ctrl_wr_meta;
			spi_ctrl_wr_sync_d <= spi_ctrl_wr_sync;
		end if;
	end process;

	spi_ctrl_wr_falling_pulse <= spi_ctrl_wr_sync_d and not spi_ctrl_wr_sync;

	-- SPI control register write
	process (CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				sd_sel_q <= "00";
			elsif spi_ctrl_wr_falling_pulse = '1' then
				sd_sel_q <= D(1 downto 0);
			end if;
		end if;
	end process;

	-- ------------------------------------------------------------------------
	-- Synchronize WR_n into the clock domain and detect its falling edge.
	-- Used to qualify the ROM bank-switch write (rom_bank_wr_s is now a pure
	-- combinational level/decode, no longer a clock).
	-- ------------------------------------------------------------------------
	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			wr_n_meta   <= WR_n;       -- stage 1: absorbs metastability
			wr_n_sync   <= wr_n_meta;  -- stage 2: resolved, safe to use
			wr_n_sync_d <= wr_n_sync;  -- stage 3: previous value, for edge detect
		end if;
	end process;

	wr_falling_pulse <= wr_n_sync_d and not wr_n_sync;  -- one CLOCK_50-wide pulse

	i_ROM_Banks: process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				rom_bank1_q <= (others => '0');
				rom_bank2_q <= (others => '0');
			elsif wr_falling_pulse = '1' and rom_bank_wr_s = '1' then
				case s_A(12) is
					when '0' => rom_bank1_q <= D(2 downto 0);
					when '1' => rom_bank2_q <= D(3 downto 0);
					when others => null;
				end case;
			end if;
		end if;
	end process;

	-- Generate the 25MHz clock_i for the SPI component ONLY - see "CLOCK
	-- DOMAINS" note at the top of this file for why this is kept separate
	-- from CLOCK_50, which drives everything else in this file.
    clock_25mhz_inst : clock_25mhz PORT MAP (
        inclk0   => CLOCK_50,
        c0       => clock_i
    );

	-- SPI interface to the SD cards
	portaspi: entity work.spi
	port map (
		clock_i			=> clock_i,
		reset_n_i		=> not s_reset,
		-- CPU interface
		cs_i				=> spi_cs_s,
		data_bus_io		=> D,
		wr_n_i			=> WR_n,
		rd_n_i			=> RD_n,
		wait_n_o			=> s_spi_wait_n_o, -- inverted at the WAIT_n <= not s_spi_wait_n_o assignment above, to compensate for the Q2 transistor stage in the interface
		-- SD card interface
		spi_sclk_o		=> s_sd_clk,
		spi_mosi_o		=> s_sd_mosi, --SD_CMD,
		spi_miso_i		=> s_sd_miso,  --SD_DAT
		-- extra signals added for MSX_FPGA_Interface
		spi_dout			=>	spi_data,
		spi_rd_en		=> spi_read
	);

	-- Signals to drive the SD cards
	-- SD card slot 1 is the SD card socket on the DE1 board itself
	SD1_CS	<= '0' when sd_sel_q(0) = '1' else '1';
	SD1_SCK	<= s_sd_clk;
	SD1_MOSI	<= s_sd_mosi;
	s_sd_miso <= SD1_MISO when sd_sel_q(0) = '1' else
             SD2_MISO when sd_sel_q(1) = '1' else
             '1';  -- idle/no-card-selected default (SPI MISO idles high)

	-- SD card slot 2 is an optional second SD card connected to GPIO_0
	SD2_CS	<= '0' when sd_sel_q(1) = '1' else '1';
	SD2_SCK	<= s_sd_clk;
	SD2_MOSI	<= s_sd_mosi;

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

	-- Slot expander instantiation - clocked from CLOCK_50 (see "CLOCK DOMAINS"
	-- note above). exp_slot's formal port is still named clock_i, only the
	-- actual signal fed into it has changed.
	exp: entity work.exp_slot
	port map (
		clock_i		=> CLOCK_50,
		reset_n		=> not s_reset,
		sltsl_n		=> not s_sltsl_en,
		cpu_rd_n		=> RD_n,
		cpu_wr_n		=> WR_n,
		ffff			=> s_ffff_slt,
		cpu_a			=> s_A(15 downto 14),
		cpu_d			=> D,
		cpu_q			=> s_expn_q,
		exp_n			=> slt_exp_n
	);

	FL_WE_N <= '1';  -- permanently disabled: never write to the shared Flash
	I2C_SDAT		<= 'Z';
   AUD_ADCLRCK	<= 'Z';
   AUD_DACLRCK	<= 'Z';
   AUD_BCLK		<= 'Z';
   DRAM_DQ		<= (others => 'Z');
   SRAM_DQ		<= (others => 'Z');

end bevioural;

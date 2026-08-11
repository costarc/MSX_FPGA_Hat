library ieee ;
use ieee.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;

-- ==============================================================================
-- MILESTONE (2026-08-11): real Flash content read into the MSX end-to-end via
-- I/O port 0x5A, confirmed on real hardware byte-for-byte against the
-- independently-verified ROM in Flash: OUT &H5A,0 then five INP(&H5A) reads
-- returned 65,66,79,64,0 (0x41,0x42,0x4F,0x40,0x00). Root cause of the whole
-- earlier "MSX always reads 0xFF" saga was U1_DIR's polarity being backwards
-- (see project_msx_fpga_hat_v21b_bus_validation memory) - fixed here, and the
-- data-bus/register mechanism (Register5A_q, I/O read+write, memory write)
-- is now fully validated across every access path exercised in this file.
-- Followed by a confirmed real-hardware SLTSL_n boot of a plain ROM from
-- Flash - see the "MEMORY-MAPPED ROM BOOT" section further down.
--
-- SCOPE DECISION (2026-08-11): this file is a cartridge simulator for
-- GAMES ONLY. SDMAPPER.ROM (Nextor) and MDOS22V3.ROM (MSX-DOS2) below are
-- part of the historical DE1ROMs.bin layout but are deliberately never
-- targeted by this design's ROM catalog - they need the SD-card SPI
-- interface and RAM-based memory mapper (I/O ports FC-FF), which live
-- separately in the SDMapper_V2.1b project, not here. See the ROM catalog
-- comment near "MEMORY-MAPPED ROM BOOT" below for the actual game list.
-- ==============================================================================

-- Updated on 23/01/2023
-- ---------------------
-- Structure of the FLASH for this core to work:
-- --------------------------------------------------
-- #SD Mapper ROM(MSX-DOS/Nextor 128KB ROM): 0x00000
-- #------------------------------------------------
-- cat SDMAPPER.ROM > DE1ROMs.bin
-- 
-- #MSX-DOS 2.2v3 (64KB ROM):0x20000
-- #--------------------------------
-- cat MDOS22V3.ROM >> DE1ROMs.bin
-- 
-- #ASCII16 (256KB ROMs): 0x30000
-- #-----------------------------
-- cat XEVIOUS.ROM >> DE1ROMs.bin
-- cat FANZONE2.ROM >> DE1ROMs.bin
-- cat ISHTAR.ROM >> DE1ROMs.bin
-- cat ANDROGYN.ROM >> DE1ROMs.bin
-- 
-- #Konami8 (128KB ROMs) - 0x130000
-- #-------------------------------
-- cat NEMESIS.ROM >> DE1ROMs.bin
-- cat PENGUIN.ROM >> DE1ROMs.bin
-- cat USAS.ROM >> DE1ROMs.bin
-- cat MGEAR.ROM >> DE1ROMs.bin
-- 
-- #32KB ROM Games: 0x1b0000
-- #------------------------
-- cat CASTLE.ROM >> DE1ROMs.bin
-- cat ELEVATOR.ROM >> DE1ROMs.bin
-- cat GALAGA.ROM >> DE1ROMs.bin
-- cat GOONIES.ROM >>DE1ROMs.bin
-- cat GULKAVE.ROM >> DE1ROMs.bin
-- cat GYRODINE.ROM >> DE1ROMs.bin
-- cat LODERUN.ROM >> DE1ROMs.bin
-- cat ZANAC.ROM >> DE1ROMs.bin
-- cat ROAD.ROM >> DE1ROMs.bin
-- cat HRALLY.ROM >> DE1ROMs.bin
-- cat AVALANCH.ROM >> DE1ROMs.bin
-- cat FROGGER.ROM >> DE1ROMs.bin

Entity MSX_FPGA_Top is
port (
    CLOCK_50:		in std_logic;		--	50 MHz
    CLOCK_50_2:		in std_logic;								--	50 MHz
                    
    KEY:			in std_logic_vector(2 downto 0);		--	Pushbutton[3:0]             
    SW:			in std_logic_vector(9 downto 0);		--	Toggle Switch[9:0]
                    
    HEX0:			out std_logic_vector(6 downto 0);		--	Seven Segment Digit 0
    HEX1:			out std_logic_vector(6 downto 0);		--	Seven Segment Digit 1
    HEX2:			out std_logic_vector(6 downto 0);		--	Seven Segment Digit 2
    HEX3:			out std_logic_vector(6 downto 0);		--	Seven Segment Digit 3
    HEX0_DP:		out std_logic;
    HEX1_DP:		out std_logic;	
    HEX2_DP:		out std_logic;	
    HEX3_DP:		out std_logic;	
                    
    LEDG:			out std_logic_vector(9 downto 0);		--	LED Green[7:0]
                    
    UART_TXD:		out std_logic;							--	UART Transmitter
    UART_RXD:		in std_logic;							--	UART Receiver
    UART_CTS:		out std_logic;							--	UART Clear To Send
    UART_RTS:		in std_logic;							--	UART Request To Send
                 
    DRAM_DQ:		inout std_logic_vector(15 downto 0);	--	SDRAM Data bus 16 Bits
    DRAM_ADDR:		out std_logic_vector(12 downto 0);		--	SDRAM Address bus 13 Bits
    DRAM_LDQM:		out std_logic;							--	SDRAM Low-byte Data Mask 
    DRAM_UDQM:		out std_logic;							--	SDRAM High-byte Data Mask
    DRAM_WE_N:		out std_logic;							--	SDRAM Write Enable
    DRAM_CAS_N:		out std_logic;							--	SDRAM Column Address Strobe
    DRAM_RAS_N:		out std_logic;							--	SDRAM Row Address Strobe
    DRAM_CS_N:		out std_logic;							--	SDRAM Chip Select
    DRAM_BA_0:		out std_logic;							--	SDRAM Bank Address 0
    DRAM_BA_1:		out std_logic;							--	SDRAM Bank Address 0
    DRAM_CLK:		out std_logic;							--	SDRAM Clock
    DRAM_CKE:		out std_logic;							--	SDRAM Clock Enable
    														
    FL_DQ:			inout std_logic_vector(14 downto 0);	--	FLASH Data bus 15 Bits
    FL_DQ15_AM1:	inout std_logic;						--	FLASH Data bus Bit 15 or Address A-1
    FL_ADDR:		out std_logic_vector(21 downto 0);	--	FLASH Address bus 22 Bits
    FL_WE_N:		out std_logic;							--	FLASH Write Enable
    FL_RST_N:		out std_logic;							--	FLASH Reset
    FL_OE_N:		out std_logic;							--	FLASH Output Enable
    FL_CE_N:		out std_logic;							--	FLASH Chip Enable
    FL_WP_N:		out std_logic;							--	FLASH Hardware Write Protect
    FL_BYTE_N:		out std_logic;							--	FLASH Selects 8/16-bit mode
    FL_RY:			in std_logic;							--	FLASH Ready/Busy
       
    LCD_DATA:		inout std_logic_vector(7 downto 0);		-- LCD Data bus 8 bits
    LCD_BLON:		out std_logic;							-- LCD Back Light ON/OFF
    LCD_RW:			out std_logic;							-- CD Read/Write Select, 0 = Write, 1 = Read
    LCD_EN:			out std_logic;							-- LCD Enable
    LCD_RS:			out std_logic;							-- LCD Command/Data Select, 0 = Command, 1 = Data
    														
    SD_DAT:			inout std_logic;						--	SD Card Data
    SD_DAT3:		inout std_logic;						--	SD Card Data 3
    SD_CMD:			inout std_logic;						--	SD Card Command Signal
    SD_CLK:			out std_logic;							--	SD Card Clock
    SD_WP_N:		in std_logic;							--	SD Card Write Protect
    														
    PS2_KBDAT:		inout std_logic;		 				--	PS2 Data
    PS2_KBCLK:		inout std_logic;						--	PS2 Clock
    PS2_MSDAT:		inout std_logic;		 				--	PS2 Data
    PS2_MSCLK:		inout std_logic;						--	PS2 Clock
    														
    VGA_HS:			out std_logic;							--	VGA H_SYNC
    VGA_VS:			out std_logic;							--	VGA V_SYNC
    VGA_R:   		out std_logic_vector(3 downto 0);		--	VGA Red[3:0]
    VGA_G:	 		out std_logic_vector(3 downto 0);		--	VGA Green[3:0]
    VGA_B:   		out std_logic_vector(3 downto 0);		--	VGA Blue[3:0]    FL_CE_N:			out std_logic;								--	FLASH Chip Enable
    
    -- SRAM Addon Conencted to GPIO_0
    SRAM_DQ:		inout std_logic_vector(7 downto 0);--	SRAM Data bus 16 Bits
    SRAM_ADDR:		out std_logic_vector(17 downto 0);	--	SRAM Address bus 18 Bits
    SRAM_UB_N:		out std_logic;								--	SRAM High-byte Data Mask 
    SRAM_LB_N:		out std_logic;								--	SRAM Low-byte Data Mask 
    SRAM_WE_N:		out std_logic;								--	SRAM Write Enable
    SRAM_CE_N:		out std_logic;								--	SRAM Chip Enable
    SRAM_OE_N:		out std_logic;								--	SRAM Output Enable
    
    -- MSX Bus (GPIO_1 - MSX_FPGA_Hat rev 2.1b). This PCB revision physically
    -- time-multiplexes the 16-bit MSX address bus onto 8 shared FPGA pins
    -- via two 74LVC245 level-shifters (U2/U3, confirmed real chips in
    -- MSX_FPGA_Hat.net) - unlike the older PCB revision this project
    -- originally targeted (full 16-bit "A" port, direct pins - see the
    -- backed-up MSX_FPGA_Top_PCB_v2.0.qsf). A_MUX/U2OE_n/U3OE_n below and
    -- the address-mux capture state machine added in the architecture body
    -- reconstruct the full address as s_A, matching
    -- SDMapper_V2.1b/SDMapper_Top.vhd's approach for the same PCB.
    MSX_CLK:		in std_logic;
    A_MUX:			in std_logic_vector(7 downto 0);
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
    RESET_n:		in std_logic;
    SOUNDIN:		in std_logic;
    SOUNDOUT:		out std_logic;
    CS2_RFSH_n:		in std_logic;
    U1_DIR:			out std_logic;
    U1OE_n:			out std_logic;
    U2OE_n:			out std_logic;
    U3OE_n:			out std_logic;
    U4OE_n:			out std_logic);
end MSX_FPGA_Top;

architecture behavioural of MSX_FPGA_Top is

	component decoder_7seg
	port (
		NUMBER		: in   std_logic_vector(3 downto 0);
		HEX_DISP	: out  std_logic_vector(6 downto 0));
	end component;

	signal HEXDIGIT0		: std_logic_vector(3 downto 0);
	signal HEXDIGIT1		: std_logic_vector(3 downto 0);
	signal HEXDIGIT2		: std_logic_vector(3 downto 0);
	signal HEXDIGIT3		: std_logic_vector(3 downto 0);

	signal s_reset			: std_logic := '0';

	-- ------------------------------------------------------------------------
	-- Address bus reconstruction for v2.1b's time-multiplexed A_MUX bus (see
	-- entity comment above) - unchanged from previous testing, including
	-- the trigger-preemption fix (a new bus cycle always restarts this
	-- state machine, even mid-capture, so back-to-back Z80 M-cycles can't
	-- silently drop a capture and leave s_A stuck stale).
	-- ------------------------------------------------------------------------
	signal s_A				: std_logic_vector(15 downto 0) := (others => '0');

	signal s_bus_req_n		: std_logic;
	signal bus_req_meta, bus_req_sync, bus_req_sync_d : std_logic;
	signal addr_capture_trigger : std_logic;

	type addr_capture_state_t is (S_IDLE, S_LOW_EN, S_LOW_CAP, S_GUARD, S_HIGH_EN, S_HIGH_CAP);
	signal addr_capture_state : addr_capture_state_t := S_IDLE;

	-- ------------------------------------------------------------------------
	-- PURE BUS MONITOR (this test variant): no ROM/Flash/mapper/WAIT logic
	-- at all - just detect when s_A falls in 0xC000-0xDFFF, decode RD_n/WR_n
	-- ONLY while in that window, and display the address and the D-bus
	-- value live. Not gated by SLTSL_n/SW(9) at all - this watches ALL Z80
	-- bus activity in that range, regardless of which slot is selected,
	-- since page 3 is typically system RAM and sees constant traffic during
	-- normal MSX/BASIC operation - giving many real samples to directly
	-- validate whether s_A and the D-bus observation are trustworthy,
	-- decoupled from anything related to our own Flash-timing debugging.
	-- ------------------------------------------------------------------------
	signal s_addr_range_en	: std_logic;
	signal s_read_en		: std_logic;
	signal s_write_en		: std_logic;

	-- ------------------------------------------------------------------------
	-- Glitch filter: real-hardware measurement showed the write pulse at
	-- DABC lasts ~14 CLOCK_50 cycles (~280ns, matching a genuine Z80
	-- T-state), but a "read" was also seen lasting only ~4 cycles (~80ns)
	-- - far too short to be a real bus cycle, and it appeared identically
	-- whether or not a PEEK was ever issued. That's a real electrical
	-- glitch on RD_n around the write-to-idle bus transition, not a
	-- genuine memory read. s_read_qualified/s_write_qualified only assert
	-- once the raw signal has been continuously true for at least
	-- MIN_PULSE_CYCLES, rejecting anything shorter as noise.
	-- ------------------------------------------------------------------------
	signal s_read_dur_counter  : std_logic_vector(3 downto 0) := (others => '0');
	signal s_write_dur_counter : std_logic_vector(3 downto 0) := (others => '0');
	signal s_read_qualified    : std_logic := '0';
	signal s_write_qualified   : std_logic := '0';
	constant MIN_PULSE_CYCLES : integer := 8;	-- 8 * 20ns = 160ns - above the observed 80ns glitch, below a real ~280ns T-state

	-- BUG FIX: a real memory cycle lasts under a microsecond - thousands of
	-- times too fast for a human to see on a live, un-latched 7-segment
	-- display (this is why "PEEK/POKE didn't update HEX/LEDs" happened
	-- even if the address decode itself was working correctly). Each
	-- genuine event now re-arms a ~0.5s hold so it's visible long enough
	-- to read, then automatically clears and re-arms for the next one -
	-- no manual reset needed between repeated PEEK/POKE tests.
	signal s_hold_addr		: std_logic_vector(15 downto 0) := (others => '0');
	signal s_hold_is_write	: std_logic := '0';
	signal s_hold_counter	: integer range 0 to 25000000 := 0;

	-- REWORKED: LEDG(9) is now a true latch, not tied to the timed hold at
	-- all - it only changes on a genuine DABC access (poke -> on, peek ->
	-- off) and stays there indefinitely otherwise, so a single poke/peek
	-- is unmistakable rather than a faint, easy-to-miss timed blink.
	signal s_led9_latch : std_logic := '0';
	-- Companion reset-only-clear latch for reads, so both events are
	-- visible independently instead of one bit that cancels itself out.
	signal s_led8_latch : std_logic := '0';
	constant HOLD_CYCLES : integer := 25000000;	-- 25,000,000 * 20ns = 0.5s

	-- ------------------------------------------------------------------------
	-- Quantitative diagnostic: measure the actual DURATION (in CLOCK_50
	-- cycles) of the first read pulse and first write pulse detected at
	-- DABC, sticky-captured on each pulse's falling edge. A genuine Z80
	-- bus cycle should last roughly 14-60 cycles (one to a few T-states at
	-- 50MHz vs ~3.58MHz); a suspiciously short count (1-3 cycles) would be
	-- a real glitch on RD_n/WR_n, not a bug in the address decode - this
	-- settles that question directly rather than by inference.
	-- ------------------------------------------------------------------------
	signal s_read_active_counter  : std_logic_vector(7 downto 0) := (others => '0');
	signal s_write_active_counter : std_logic_vector(7 downto 0) := (others => '0');
	signal s_read_pulse_width     : std_logic_vector(7 downto 0) := (others => '0');
	signal s_write_pulse_width    : std_logic_vector(7 downto 0) := (others => '0');
	signal s_read_width_captured  : std_logic := '0';
	signal s_write_width_captured : std_logic := '0';
	signal s_read_en_d, s_write_en_d : std_logic := '0';

	-- ------------------------------------------------------------------------
	-- DATA BUS TEST (new, on top of the validated DABC tests above, which
	-- are unchanged): a minimal register to validate read/write control
	-- signals AND the data bus for the first time - everything above only
	-- ever watched the bus, it never drove data back onto it.
	--   - Write to memory address 0xD05A -> latch D onto Register5A_q.
	--   - Read I/O port 0x5A -> drive Register5A_q back onto D (the ONLY
	--     way Register5A_q's value can be observed from the MSX side).
	-- Register5A_q only ever changes on a genuine 0xD05A write - reusing
	-- the same address-mux s_A and the same glitch-filter discipline
	-- (MIN_PULSE_CYCLES) already validated for the DABC tests, applied to
	-- both the new write trigger and the new I/O-read trigger (the latter
	-- is what re-enables U1 - the first live bus-drive since the earlier
	-- U1-related RAM-corruption incident, so it gets the same qualification
	-- discipline rather than a raw, unfiltered enable).
	-- ------------------------------------------------------------------------
	signal Register5A_q : std_logic_vector(7 downto 0) := (others => '0');

	signal s_write_D05A_en        : std_logic;
	signal s_write_D05A_dur_cnt   : std_logic_vector(3 downto 0) := (others => '0');
	signal s_write_D05A_qualified : std_logic := '0';

	signal s_io_read_5A_en        : std_logic;
	signal s_io_read_5A_dur_cnt   : std_logic_vector(3 downto 0) := (others => '0');
	signal s_io_read_5A_qualified : std_logic := '0';

	-- Latched "was port 0x5A ever read" - same reset-only-clear technique
	-- as the earlier "slot ever selected" diagnostic, so a brief I/O read
	-- is visible on LEDG(8) even between glances at the board.
	signal s_io_read_5A_ever_q : std_logic := '0';

	-- ------------------------------------------------------------------------
	-- FLASH READ VIA I/O PORT (replaces the earlier 0x4000-0x4FFF
	-- memory-window attempt - that approach depended on SLTSL_n actually
	-- asserting for this cartridge's slot on page 1, which turned out to
	-- read whatever ROM/RAM the system already had mapped there instead.
	-- An I/O port has no such dependency: real RAM/ROM chips only respond
	-- to MREQ_n, never IORQ_n, so port 0x5A can never contend with them -
	-- exactly why the Register5A test's read side already worked reliably
	-- without any slot-selection concern.
	--
	--   - Write port 0x5A -> reset s_flash_ptr_q (the Flash address
	--     pointer) to 0x000000.
	--   - Read port 0x5A  -> drive Flash[s_flash_ptr_q] onto D, then
	--     increment s_flash_ptr_q by 1 - but only AFTER the read cycle has
	--     genuinely finished (on qualified-read's falling edge), so the
	--     pointer can't change mid-access and hand the CPU the wrong byte
	--     right before it samples. Repeated reads walk sequentially
	--     through Flash from address 0.
	-- ------------------------------------------------------------------------
	signal s_flash_ptr_q : std_logic_vector(23 downto 0) := (others => '0');

	signal s_io_5A_write_en        : std_logic;
	signal s_io_5A_write_dur_cnt   : std_logic_vector(3 downto 0) := (others => '0');
	signal s_io_5A_write_qualified : std_logic := '0';
	signal s_io_read_5A_qualified_d : std_logic := '0';

	-- Live displays, per user request: HEX0-3 show the pointer address
	-- (low 16 bits - enough to see it walking forward), LEDG(7:0) shows
	-- the last byte actually read from Flash. Replaces the earlier
	-- DABC-pulse-width HEX display and Register5A_q's LEDG(7:0) display -
	-- both underlying tests/latches are untouched, only what's SHOWN
	-- changes, since this is now the test in focus.
	signal s_flash_data_q : std_logic_vector(7 downto 0) := (others => '0');

	-- ------------------------------------------------------------------------
	-- MEMORY-MAPPED ROM BOOT (SLTSL_n / slot access) - the actual point of
	-- this whole session's work, now generalized from "one hardcoded plain
	-- 16KB ROM" to full MegaROM support: all standard mapper types, reading
	-- whichever real game the user has flashed into DE1ROMs.bin, selected
	-- live via SW rather than requiring a reprogram per game.
	--
	-- Deliberately RAW/immediate combinational decode throughout for
	-- everything that drives the live bus (no MIN_PULSE_CYCLES
	-- qualification, unlike Register5A_q/the I/O Flash pointer above) - a
	-- real Z80 memory read is only 3 T-states with no automatic wait state,
	-- tighter than an I/O read's 4 T-states, so the ~160ns qualification
	-- delay used above would eat into (or blow) the data-setup-before-
	-- RD_n-rising margin here. This exactly mirrors the proven pattern
	-- already working on real hardware in
	-- "SDMapper - Boots Nextor Some Times/SDMapper_Top.vhd" (its own
	-- s_sltsl_rom_en/FL_CE_N/FL_OE_N/D/U1OE_n/U1_DIR are all raw/immediate
	-- too - see that file's comments, cross-checked against
	-- msx.org/wiki/Hardware_Design). Bank-switch REGISTER WRITES are not
	-- bus-driving and not real-time-critical, so they DO reuse the
	-- MIN_PULSE_CYCLES glitch-filter discipline (one shared qualifier for
	-- all mapper types' writes, not 13 separate ones - see
	-- s_cart_write_qualified below).
	--
	-- SLTSL_n alone (no separate MREQ_n check) is sufficient: the MSX's
	-- primary slot decoder only ever asserts SLTSL_n for this slot during a
	-- genuine memory-request cycle - same reasoning already relied on by
	-- the proven DE1 reference. SW(9) gates cart emulation on/off (same
	-- convention as that reference) so the boot ROM can be physically
	-- disabled without reprogramming.
	--
	-- BUSDIR_n is deliberately left untouched by this whole section (still
	-- only driven for the I/O-port test below) - per the MSX Technical
	-- Data Book and the DE1 reference's own citation, ordinary /SLTSL
	-- memory reads do not require BUSDIR_n management, only /IORQ-based
	-- reads do.
	--
	-- ROM CATALOG: flash offsets taken directly from the header comment's
	-- documented DE1ROMs.bin layout. Mapper-type codes:
	--   "000" Plain 16KB (page 1 only, 0x4000-0x7FFF)      - unbanked
	--   "001" Plain 32KB (page 1+2, 0x4000-0xBFFF)          - unbanked
	--   "010" ASCII16    (2x16KB banks, regs @6000/@7000)
	--   "011" ASCII8     (4x8KB banks,  regs @6000/6800/7000/7800)
	--   "100" Konami4    (4x8KB banks, bank0 FIXED, regs anywhere in
	--                      6000-7FFF/8000-9FFF/A000-BFFF - whole page, no
	--                      SCC. Segment number is only D0-D3 (4 bits) -
	--                      verified via web search, real hardware ignores
	--                      D4-D7, and this design masks accordingly)
	--   "101" KonamiSCC  (4x8KB banks, regs @5000/7000/9000/B000 sub-ranges
	--                      - banking only, SCC sound chip NOT emulated.
	--                      Segment number is only D0-D5 (6 bits) - verified
	--                      via web search, masked accordingly; writing
	--                      0x3F to the 9000 register enables SCC audio on
	--                      real hardware, which isn't implemented here)
	-- All ranges/registers verified against multiple independent web
	-- sources (msx.org wiki MegaROM Mappers, generation-msx.nl per-game
	-- pages, bifi.msxnet.org), not just recalled from memory - this
	-- includes confirming NEMESIS/PENGUIN/USAS/MGEAR (the 4 catalog
	-- entries below) are ALL plain Konami-without-SCC, not a mix as
	-- originally guessed. SW(8)/SW(7 downto 5) below still let you
	-- override the mapper type live on real hardware without a reprogram,
	-- for any future catalog entry whose type turns out wrong.
	-- ------------------------------------------------------------------------
	signal s_sltsl_en  : std_logic;
	signal s_rom_rd_en : std_logic;	-- genuine ROM read: this slot selected (SW(9)=on), a page this mapper actually maps, real memory read
	signal s_rom_active : std_logic;	-- combinational: s_A currently falls in a page this mapper type maps (read OR write)

	signal s_rom_flashbase      : std_logic_vector(23 downto 0);
	signal s_rom_mapper_default : std_logic_vector(2 downto 0);
	signal s_rom_mapper_type    : std_logic_vector(2 downto 0);

	signal s_rom_relative_addr : std_logic_vector(23 downto 0);	-- address within the selected ROM, before adding s_rom_flashbase
	signal s_rom_byte_addr     : std_logic_vector(23 downto 0);	-- s_rom_flashbase + s_rom_relative_addr; bit0->FL_DQ15_AM1, bits(22:1)->FL_ADDR

	-- Bank-switch registers - one pair/quad per mapper type (see catalog
	-- comment above for each type's address map). Reset to 0 (segment 0),
	-- the conventional real-hardware default.
	signal s_a16_bank0_q  : std_logic_vector(7 downto 0) := (others => '0');	-- ASCII16: 0x4000-0x7FFF
	signal s_a16_bank1_q  : std_logic_vector(7 downto 0) := (others => '0');	-- ASCII16: 0x8000-0xBFFF
	signal s_a8_bank0_q   : std_logic_vector(7 downto 0) := (others => '0');	-- ASCII8:  0x4000-0x5FFF
	signal s_a8_bank1_q   : std_logic_vector(7 downto 0) := (others => '0');	-- ASCII8:  0x6000-0x7FFF
	signal s_a8_bank2_q   : std_logic_vector(7 downto 0) := (others => '0');	-- ASCII8:  0x8000-0x9FFF
	signal s_a8_bank3_q   : std_logic_vector(7 downto 0) := (others => '0');	-- ASCII8:  0xA000-0xBFFF
	signal s_k4_bank1_q   : std_logic_vector(7 downto 0) := (others => '0');	-- Konami4: 0x6000-0x7FFF (bank0 fixed=0)
	signal s_k4_bank2_q   : std_logic_vector(7 downto 0) := (others => '0');	-- Konami4: 0x8000-0x9FFF
	signal s_k4_bank3_q   : std_logic_vector(7 downto 0) := (others => '0');	-- Konami4: 0xA000-0xBFFF
	signal s_kscc_bank0_q : std_logic_vector(7 downto 0) := (others => '0');	-- KonamiSCC: 0x4000-0x5FFF
	signal s_kscc_bank1_q : std_logic_vector(7 downto 0) := (others => '0');	-- KonamiSCC: 0x6000-0x7FFF
	signal s_kscc_bank2_q : std_logic_vector(7 downto 0) := (others => '0');	-- KonamiSCC: 0x8000-0x9FFF
	signal s_kscc_bank3_q : std_logic_vector(7 downto 0) := (others => '0');	-- KonamiSCC: 0xA000-0xBFFF

	-- Shared bank-register write qualifier (see comment above): ANY write
	-- while this cart slot is selected, glitch-filtered the same way as
	-- every other write trigger in this file. The target address (s_A) is
	-- still fully valid/stable throughout the qualified window - a real
	-- Z80 write cycle holds the address stable for the whole WR_n pulse -
	-- so one shared qualifier safely serves every mapper type's registers.
	-- D is re-latched continuously WHILE qualified='1' (see the process
	-- below for why - this is what was actually buggy on real hardware).
	signal s_cart_write_en        : std_logic;
	signal s_cart_write_dur_cnt   : std_logic_vector(3 downto 0) := (others => '0');
	signal s_cart_write_qualified : std_logic := '0';

	-- Live debug display (temporary, ASCII16-focused): confirms on real
	-- hardware whether bank-register writes are landing at all, and with
	-- what value, instead of guessing further from code review alone.
	signal s_cart_write_ever_q : std_logic := '0';

begin

	s_reset <= not (KEY(0) and RESET_n);
	INT_n <= '0';		-- inverted due to the Q1 open-collector stage in the interface
	WAIT_n <= '0';		-- pure observer - never requests a wait
	-- BUSDIR_n is now driven further below, alongside U1OE_n/U1_DIR - see
	-- that comment for why (never tri-stated, per the user's proven MSXPi
	-- CPLD design: BUSDIR_n there is always actively driven, '0' or '1',
	-- never floating).
	SOUNDOUT <= '0';
	U4OE_n <= '0';		-- unused buffer on this variant - disabled

	-- U1OE_n/U1_DIR are now driven further below by the new data-bus test
	-- (the DABC tests above never touched D at all - U1 was permanently
	-- disabled for them, same reasoning as before: this is the first time
	-- this build drives D, and it's gated on the narrowly-qualified 0x5A
	-- I/O-read condition only, never on the broader/staler DABC signals
	-- that caused the earlier RAM-corruption incident).

	-- ------------------------------------------------------------------------
	-- Address bus capture: synchronize the "new bus cycle starting" trigger
	-- (falling edge of MREQ_n or IORQ_n), then run the low/high byte capture
	-- state machine, on CLOCK_50. See entity comment above for the full
	-- explanation - unchanged from previous testing, including the trigger-
	-- preemption fix.
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
				-- guaranteeing at least one dead cycle before S_LOW_EN's
				-- own branch re-enables U2 - avoids bus contention between
				-- U2/U3 if a new cycle starts mid-capture.
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

	-- BUG FIX: narrowed from the full 0xC000-0xDFFF range to EXACTLY
	-- 0xD000 - something else in the system (very likely a real BASIC/
	-- system variable, since it's a specific, consistently-repeating
	-- address, not noise) hits 0xCF17 far more often than once per 0.5s,
	-- so the broad range trigger kept re-arming the hold with THAT event
	-- and overwriting the user's own deliberate PEEK/POKE before it could
	-- be read. Narrowing to the exact address under test eliminates that
	-- interference entirely.
	s_addr_range_en <= '1' when s_A = x"DABC" else '0';
	s_read_en  <= '1' when s_addr_range_en = '1' and RD_n = '0' else '0';
	s_write_en <= '1' when s_addr_range_en = '1' and WR_n = '0' else '0';

	-- Glitch filter - see declaration above. Only asserts once the raw
	-- signal has been continuously true for MIN_PULSE_CYCLES; clears
	-- immediately the instant the raw signal drops (no need to stretch a
	-- pulse that's already long enough to be genuine).
	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				s_read_dur_counter  <= (others => '0');
				s_write_dur_counter <= (others => '0');
				s_read_qualified    <= '0';
				s_write_qualified   <= '0';
			else
				if s_read_en = '1' then
					if s_read_dur_counter < MIN_PULSE_CYCLES then
						s_read_dur_counter <= s_read_dur_counter + 1;
					end if;
					if s_read_dur_counter >= MIN_PULSE_CYCLES then
						s_read_qualified <= '1';
					end if;
				else
					s_read_dur_counter <= (others => '0');
					s_read_qualified   <= '0';
				end if;

				if s_write_en = '1' then
					if s_write_dur_counter < MIN_PULSE_CYCLES then
						s_write_dur_counter <= s_write_dur_counter + 1;
					end if;
					if s_write_dur_counter >= MIN_PULSE_CYCLES then
						s_write_qualified <= '1';
					end if;
				else
					s_write_dur_counter <= (others => '0');
					s_write_qualified   <= '0';
				end if;
			end if;
		end if;
	end process;

	-- Pulse-stretcher: every genuine event re-arms the hold, so a human can
	-- actually see it - see declaration above.
	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				s_hold_addr     <= (others => '0');
				s_hold_is_write <= '0';
				s_hold_counter  <= 0;
			elsif s_read_qualified = '1' or s_write_qualified = '1' then
				s_hold_addr     <= s_A;
				s_hold_is_write <= s_write_qualified;
				s_hold_counter  <= HOLD_CYCLES;
			elsif s_hold_counter > 0 then
				s_hold_counter <= s_hold_counter - 1;
			end if;
		end if;
	end process;

	-- Pulse-width measurement - see declaration above. Sticky on each
	-- pulse's falling edge, first occurrence only.
	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				s_read_active_counter  <= (others => '0');
				s_write_active_counter <= (others => '0');
				s_read_pulse_width     <= (others => '0');
				s_write_pulse_width    <= (others => '0');
				s_read_width_captured  <= '0';
				s_write_width_captured <= '0';
				s_read_en_d  <= '0';
				s_write_en_d <= '0';
			else
				s_read_en_d  <= s_read_en;
				s_write_en_d <= s_write_en;

				if s_read_en = '1' then
					if s_read_active_counter /= x"FF" then
						s_read_active_counter <= s_read_active_counter + 1;
					end if;
				else
					s_read_active_counter <= (others => '0');
				end if;
				if s_read_en_d = '1' and s_read_en = '0' and s_read_width_captured = '0' then
					s_read_pulse_width    <= s_read_active_counter;
					s_read_width_captured <= '1';
				end if;

				if s_write_en = '1' then
					if s_write_active_counter /= x"FF" then
						s_write_active_counter <= s_write_active_counter + 1;
					end if;
				else
					s_write_active_counter <= (others => '0');
				end if;
				if s_write_en_d = '1' and s_write_en = '0' and s_write_width_captured = '0' then
					s_write_pulse_width    <= s_write_active_counter;
					s_write_width_captured <= '1';
				end if;
			end if;
		end if;
	end process;

	-- HEX3:HEX2 show the first WRITE pulse's width, HEX1:HEX0 show the
	-- first READ pulse's width, both in CLOCK_50 cycles (hex, e.g. "1E" =
	-- 30 cycles = 600ns). Replaces the address-hold display for this
	-- specific quantitative diagnostic - the address decode itself is
	-- already independently confirmed working.
	-- SUPERSEDED for this debug pass: shows the live ASCII16 bank register
	-- values instead of the Flash I/O-pointer test (that mechanism is
	-- unchanged, just not displayed right now) - HEX1:HEX0 = s_a16_bank0_q
	-- (segment currently mapped at 0x4000-0x7FFF), HEX3:HEX2 =
	-- s_a16_bank1_q (segment at 0x8000-0xBFFF). Directly answers "is the
	-- write path landing at all, and with what value" on real hardware,
	-- rather than guessing further from code review. If these never move
	-- off "00" while Xevious runs, the write path is still broken; if they
	-- show a plausible-looking segment number (small, changing) but the
	-- screen is still garbage, the bug is in the READ-side bank-to-
	-- flash-address math instead.
	HEXDIGIT0 <= s_a16_bank0_q(3 downto 0);
	HEXDIGIT1 <= s_a16_bank0_q(7 downto 4);
	HEXDIGIT2 <= s_a16_bank1_q(3 downto 0);
	HEXDIGIT3 <= s_a16_bank1_q(7 downto 4);

	-- s_led9_latch/the DABC poke-vs-peek test is superseded by the above -
	-- left computing (harmless) but no longer displayed.

	-- Latched "was a cart bank-register write ever qualified" - same
	-- reset-only-clear technique as s_io_read_5A_ever_q above, so a brief
	-- write is visible on LEDG(9) even between glances at the board.
	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				s_cart_write_ever_q <= '0';
			elsif s_cart_write_qualified = '1' then
				s_cart_write_ever_q <= '1';
			end if;
		end if;
	end process;

	LEDG(9) <= s_cart_write_ever_q;

	-- ------------------------------------------------------------------------
	-- DATA BUS TEST logic - see declarations above.
	-- ------------------------------------------------------------------------

	-- Write trigger: exact address 0xD05A, real WR_n.
	s_write_D05A_en <= '1' when s_A = x"D05A" and WR_n = '0' else '0';

	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				s_write_D05A_dur_cnt   <= (others => '0');
				s_write_D05A_qualified <= '0';
			else
				if s_write_D05A_en = '1' then
					if s_write_D05A_dur_cnt < MIN_PULSE_CYCLES then
						s_write_D05A_dur_cnt <= s_write_D05A_dur_cnt + 1;
					end if;
					if s_write_D05A_dur_cnt >= MIN_PULSE_CYCLES then
						s_write_D05A_qualified <= '1';
					end if;
				else
					s_write_D05A_dur_cnt   <= (others => '0');
					s_write_D05A_qualified <= '0';
				end if;
			end if;
		end if;
	end process;

	-- Register5A_q: re-latches D continuously while the qualified write
	-- holds, settling on the value present during the access (same fix as
	-- the earlier Flash-diagnostic capture - never sample on a delayed
	-- edge after the access has already ended). Reset-only-clear
	-- otherwise: it must NOT change on anything except a genuine 0xD05A
	-- write, per the test's whole point.
	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				Register5A_q <= (others => '0');
			elsif s_write_D05A_qualified = '1' then
				Register5A_q <= D;
			end if;
		end if;
	end process;

	-- Read trigger: I/O port 0x5A. M1_n='1' excludes interrupt-acknowledge
	-- cycles, which also assert IORQ_n (see MSX Technical Data Book /
	-- msx.org Hardware Design wiki) - same check already proven in
	-- SDMapper_V2.1b/SDMapper_Top.vhd's own I/O decode.
	s_io_read_5A_en <= '1' when IORQ_n = '0' and RD_n = '0' and M1_n = '1' and s_A(7 downto 0) = x"5A" else '0';

	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				s_io_read_5A_dur_cnt   <= (others => '0');
				s_io_read_5A_qualified <= '0';
			else
				if s_io_read_5A_en = '1' then
					if s_io_read_5A_dur_cnt < MIN_PULSE_CYCLES then
						s_io_read_5A_dur_cnt <= s_io_read_5A_dur_cnt + 1;
					end if;
					if s_io_read_5A_dur_cnt >= MIN_PULSE_CYCLES then
						s_io_read_5A_qualified <= '1';
					end if;
				else
					s_io_read_5A_dur_cnt   <= (others => '0');
					s_io_read_5A_qualified <= '0';
				end if;
			end if;
		end if;
	end process;

	-- Latched "was port 0x5A ever read" - confirms the I/O decode path
	-- fires at all, independent of what it returns.
	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				s_io_read_5A_ever_q <= '0';
			elsif s_io_read_5A_qualified = '1' then
				s_io_read_5A_ever_q <= '1';
			end if;
		end if;
	end process;

	LEDG(8)          <= s_io_read_5A_ever_q;
	LEDG(7 downto 0) <= s_flash_data_q;	-- live view of the last byte read from Flash (Register5A_q's own latch is unchanged, just no longer displayed)

	-- ------------------------------------------------------------------------
	-- FLASH READ VIA I/O PORT logic - see declarations above.
	-- ------------------------------------------------------------------------

	-- Write trigger: same port 0x5A, WR_n instead of RD_n. Any write
	-- resets the pointer - the value written doesn't matter.
	s_io_5A_write_en <= '1' when IORQ_n = '0' and WR_n = '0' and M1_n = '1' and s_A(7 downto 0) = x"5A" else '0';

	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				s_io_5A_write_dur_cnt   <= (others => '0');
				s_io_5A_write_qualified <= '0';
			else
				if s_io_5A_write_en = '1' then
					if s_io_5A_write_dur_cnt < MIN_PULSE_CYCLES then
						s_io_5A_write_dur_cnt <= s_io_5A_write_dur_cnt + 1;
					end if;
					if s_io_5A_write_dur_cnt >= MIN_PULSE_CYCLES then
						s_io_5A_write_qualified <= '1';
					end if;
				else
					s_io_5A_write_dur_cnt   <= (others => '0');
					s_io_5A_write_qualified <= '0';
				end if;
			end if;
		end if;
	end process;

	-- s_flash_ptr_q: reset to 0 on a qualified write; incremented on a
	-- qualified READ's falling edge (i.e. once the read has genuinely
	-- finished) so the address driving FL_ADDR/FL_DQ15_AM1 stays fixed for
	-- the entire access - incrementing any earlier (e.g. on the rising
	-- edge) would change the byte FL_DQ presents partway through the same
	-- read, right before the CPU samples it.
	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				s_flash_ptr_q            <= (others => '0');
				s_io_read_5A_qualified_d <= '0';
			else
				s_io_read_5A_qualified_d <= s_io_read_5A_qualified;
				if s_io_5A_write_qualified = '1' then
					s_flash_ptr_q <= (others => '0');
				elsif s_io_read_5A_qualified_d = '1' and s_io_read_5A_qualified = '0' then
					s_flash_ptr_q <= s_flash_ptr_q + 1;
				end if;
			end if;
		end if;
	end process;

	-- ------------------------------------------------------------------------
	-- MEMORY-MAPPED ROM BOOT logic - see declarations above.
	-- ------------------------------------------------------------------------
	s_sltsl_en  <= (not SLTSL_n) when SW(9) = '1' else '0';
	s_rom_rd_en <= '1' when s_sltsl_en = '1' and s_rom_active = '1' and RD_n = '0' else '0';

	-- ROM catalog: cartridge-simulator, GAMES ONLY - SDMAPPER.ROM (Nextor)
	-- and MDOS22V3.ROM (MSX-DOS2) at Flash 0x00000/0x20000 are deliberately
	-- never pointed at by any entry here (per user direction: this design
	-- ignores them entirely - they need the SD-card SPI + RAM-mapper
	-- hardware implemented separately in the SDMapper_V2.1b project, not
	-- this Flash-only cartridge simulator).
	--
	-- Flat, gap-free binary index (0-19), NOT the confusing one-hot-ish
	-- scheme in the original DE1ROMs_Guide.txt readme - all 20 flash
	-- offsets below were independently VERIFIED (not guessed) by scanning
	-- the real Reference Designs/DE1ROMs.bin for MSX ROM header
	-- signatures (0x41,0x42) - every one lands exactly on a real header at
	-- the round-number "reserved slot" offset. Exception: entries 18/19
	-- (AVALANCH/FROGGER) are absent from the CURRENT DE1ROMs.bin (it's
	-- only 0x1FE000 bytes - ends mid-way through slot 17/HRALLY) - they'll
	-- read blank Flash until that file is rebuilt with those two appended.
	--
	-- SW(4 downto 0) selects the game, SW(8)/SW(7 downto 5) optionally
	-- override the guessed mapper type live - see the big comment above
	-- for the mapper-type code table.
	process(SW)
	begin
		case SW(4 downto 0) is
			when "00000" => s_rom_flashbase <= x"030000"; s_rom_mapper_default <= "010"; -- [0] XEVIOUS (ASCII16)
			when "00001" => s_rom_flashbase <= x"070000"; s_rom_mapper_default <= "010"; -- [1] FANZONE2 / Fan Zone (ASCII16)
			when "00010" => s_rom_flashbase <= x"0B0000"; s_rom_mapper_default <= "010"; -- [2] ISHTAR (ASCII16)
			when "00011" => s_rom_flashbase <= x"0F0000"; s_rom_mapper_default <= "010"; -- [3] ANDROGYN (ASCII16)
			when "00100" => s_rom_flashbase <= x"130000"; s_rom_mapper_default <= "100"; -- [4] NEMESIS / Gradius (Konami, no SCC - confirmed via web search, not a guess)
			when "00101" => s_rom_flashbase <= x"150000"; s_rom_mapper_default <= "100"; -- [5] PENGUIN / Penguin Adventure (Konami, no SCC - confirmed, Konami never made an SCC version of this game)
			when "00110" => s_rom_flashbase <= x"170000"; s_rom_mapper_default <= "100"; -- [6] USAS (Konami, no SCC - confirmed)
			when "00111" => s_rom_flashbase <= x"190000"; s_rom_mapper_default <= "100"; -- [7] MGEAR / Metal Gear (Konami, no SCC - confirmed)
			when "01000" => s_rom_flashbase <= x"1B0000"; s_rom_mapper_default <= "001"; -- [8] CASTLE / Castle Excellent (plain 32KB)
			when "01001" => s_rom_flashbase <= x"1B8000"; s_rom_mapper_default <= "001"; -- [9] ELEVATOR / Elevator Action (plain 32KB)
			when "01010" => s_rom_flashbase <= x"1C0000"; s_rom_mapper_default <= "001"; -- [10] GALAGA (plain 32KB)
			when "01011" => s_rom_flashbase <= x"1C8000"; s_rom_mapper_default <= "001"; -- [11] GOONIES / The Goonies (plain 32KB)
			when "01100" => s_rom_flashbase <= x"1D0000"; s_rom_mapper_default <= "001"; -- [12] GULKAVE (plain 32KB)
			when "01101" => s_rom_flashbase <= x"1D8000"; s_rom_mapper_default <= "001"; -- [13] GYRODINE (plain 32KB)
			when "01110" => s_rom_flashbase <= x"1E0000"; s_rom_mapper_default <= "001"; -- [14] LODERUN / Lode Runner (plain 32KB)
			when "01111" => s_rom_flashbase <= x"1E8000"; s_rom_mapper_default <= "001"; -- [15] ZANAC (plain 32KB)
			when "10000" => s_rom_flashbase <= x"1F0000"; s_rom_mapper_default <= "001"; -- [16] ROAD / Road Fighter (plain 32KB)
			when "10001" => s_rom_flashbase <= x"1F8000"; s_rom_mapper_default <= "001"; -- [17] HRALLY / Hyper Rally (plain 32KB, may be truncated in current DE1ROMs.bin)
			when "10010" => s_rom_flashbase <= x"200000"; s_rom_mapper_default <= "001"; -- [18] AVALANCH / Avalanche (plain 32KB, NOT in current DE1ROMs.bin yet)
			when "10011" => s_rom_flashbase <= x"208000"; s_rom_mapper_default <= "001"; -- [19] FROGGER (plain 32KB, NOT in current DE1ROMs.bin yet)
			when others  => s_rom_flashbase <= x"030000"; s_rom_mapper_default <= "010"; -- unused codes 20-31: default to XEVIOUS
		end case;
	end process;

	s_rom_mapper_type <= SW(7 downto 5) when SW(8) = '1' else s_rom_mapper_default;

	-- Per-mapper-type address decode: for the page(s) this mapper type
	-- actually maps at the CURRENT s_A, compute the ROM-relative address
	-- (bank register, if any, concatenated with the in-page offset - safe
	-- because every page boundary involved is aligned to its own page
	-- size, so straight bit-slicing of s_A gives the correct in-page
	-- offset with no subtraction needed, EXCEPT plain 32KB: 0x4000 is not
	-- 32KB-aligned, so that branch flips s_A(14) instead - see the big
	-- comment above for the full derivation). Combinational, no clock -
	-- this feeds straight into FL_ADDR/FL_DQ15_AM1 below, which must stay
	-- immediate per the timing note above.
	process(s_rom_mapper_type, s_A, s_a16_bank0_q, s_a16_bank1_q,
	        s_a8_bank0_q, s_a8_bank1_q, s_a8_bank2_q, s_a8_bank3_q,
	        s_k4_bank1_q, s_k4_bank2_q, s_k4_bank3_q,
	        s_kscc_bank0_q, s_kscc_bank1_q, s_kscc_bank2_q, s_kscc_bank3_q)
	begin
		s_rom_relative_addr <= (others => '0');
		s_rom_active         <= '0';
		case s_rom_mapper_type is
			when "000" =>	-- Plain 16KB: page 1 only, unbanked
				if s_A(15 downto 14) = "01" then
					s_rom_relative_addr <= "0000000000" & s_A(13 downto 0);
					s_rom_active         <= '1';
				end if;
			when "001" =>	-- Plain 32KB: page 1+2, unbanked
				if s_A(15 downto 14) = "01" or s_A(15 downto 14) = "10" then
					s_rom_relative_addr <= "000000000" & (not s_A(14)) & s_A(13 downto 0);
					s_rom_active         <= '1';
				end if;
			when "010" =>	-- ASCII16: 2x16KB banks
				if s_A(15 downto 14) = "01" then
					s_rom_relative_addr <= "00" & s_a16_bank0_q & s_A(13 downto 0);
					s_rom_active         <= '1';
				elsif s_A(15 downto 14) = "10" then
					s_rom_relative_addr <= "00" & s_a16_bank1_q & s_A(13 downto 0);
					s_rom_active         <= '1';
				end if;
			when "011" =>	-- ASCII8: 4x8KB banks
				if s_A >= x"4000" and s_A <= x"5FFF" then
					s_rom_relative_addr <= "000" & s_a8_bank0_q & s_A(12 downto 0);
					s_rom_active         <= '1';
				elsif s_A >= x"6000" and s_A <= x"7FFF" then
					s_rom_relative_addr <= "000" & s_a8_bank1_q & s_A(12 downto 0);
					s_rom_active         <= '1';
				elsif s_A >= x"8000" and s_A <= x"9FFF" then
					s_rom_relative_addr <= "000" & s_a8_bank2_q & s_A(12 downto 0);
					s_rom_active         <= '1';
				elsif s_A >= x"A000" and s_A <= x"BFFF" then
					s_rom_relative_addr <= "000" & s_a8_bank3_q & s_A(12 downto 0);
					s_rom_active         <= '1';
				end if;
			when "100" =>	-- Konami4: 4x8KB banks, bank0 fixed = 0, no SCC
				-- BIT WIDTH (verified via web search, not guessed): real
				-- Konami-without-SCC hardware only decodes D0-D3 (4 bits) of
				-- the written byte as the segment number - bits 4-7 are
				-- unused/ignored by the real 74LS670-based mapper. Masking
				-- here matters even though the register itself is 8 bits
				-- wide: if a game's write happens to leave any of the top 4
				-- bits set (very common - real hardware silently drops
				-- them, so games don't bother clearing them), using the
				-- FULL unmasked byte would compute a wildly out-of-range
				-- Flash address instead of the intended small segment
				-- number - exactly the kind of bug that looks like garbage/
				-- crash on real hardware.
				if s_A >= x"4000" and s_A <= x"5FFF" then
					s_rom_relative_addr <= "000" & x"00" & s_A(12 downto 0);
					s_rom_active         <= '1';
				elsif s_A >= x"6000" and s_A <= x"7FFF" then
					s_rom_relative_addr <= "000" & "0000" & s_k4_bank1_q(3 downto 0) & s_A(12 downto 0);
					s_rom_active         <= '1';
				elsif s_A >= x"8000" and s_A <= x"9FFF" then
					s_rom_relative_addr <= "000" & "0000" & s_k4_bank2_q(3 downto 0) & s_A(12 downto 0);
					s_rom_active         <= '1';
				elsif s_A >= x"A000" and s_A <= x"BFFF" then
					s_rom_relative_addr <= "000" & "0000" & s_k4_bank3_q(3 downto 0) & s_A(12 downto 0);
					s_rom_active         <= '1';
				end if;
			when "101" =>	-- KonamiSCC: 4x8KB banks, banking only (no SCC audio)
				-- BIT WIDTH (verified via web search): real Konami-SCC
				-- hardware only decodes D0-D5 (6 bits) as the segment
				-- number - bits 6-7 are unused (writing 0x3F to the 0x9000
				-- register specifically enables SCC audio mapping at
				-- 0x9800-0x9FFF, which this design does not implement -
				-- reads there will return whatever Flash data the masked
				-- segment number happens to select instead of SCC chip
				-- registers). Same masking rationale as Konami4 above.
				if s_A >= x"4000" and s_A <= x"5FFF" then
					s_rom_relative_addr <= "000" & "00" & s_kscc_bank0_q(5 downto 0) & s_A(12 downto 0);
					s_rom_active         <= '1';
				elsif s_A >= x"6000" and s_A <= x"7FFF" then
					s_rom_relative_addr <= "000" & "00" & s_kscc_bank1_q(5 downto 0) & s_A(12 downto 0);
					s_rom_active         <= '1';
				elsif s_A >= x"8000" and s_A <= x"9FFF" then
					s_rom_relative_addr <= "000" & "00" & s_kscc_bank2_q(5 downto 0) & s_A(12 downto 0);
					s_rom_active         <= '1';
				elsif s_A >= x"A000" and s_A <= x"BFFF" then
					s_rom_relative_addr <= "000" & "00" & s_kscc_bank3_q(5 downto 0) & s_A(12 downto 0);
					s_rom_active         <= '1';
				end if;
			when others =>
				null;
		end case;
	end process;

	s_rom_byte_addr <= s_rom_flashbase + s_rom_relative_addr;

	-- Bank-switch register writes: one shared glitch-filtered qualifier
	-- (see declaration above) covering every mapper type's registers.
	s_cart_write_en <= '1' when s_sltsl_en = '1' and WR_n = '0' else '0';

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

	-- BUG FIX (real hardware: MegaROM games started but showed garbage
	-- screens once bank-switched content should have loaded, while plain
	-- unbanked ROMs - which never write bank registers - loaded fine).
	-- Root cause: this process originally sampled D on the FALLING EDGE of
	-- s_cart_write_qualified (a "write has finished" one-shot, 1-2
	-- CLOCK_50 cycles / 20-40ns AFTER the real WR_n rising edge). The Z80
	-- releases the data bus very shortly after WR_n rises, so by the time
	-- that delayed sample fired, D was likely already floating/stale -
	-- capturing near-random noise into the bank registers instead of the
	-- game's real segment number. Register5A_q and s_flash_data_q
	-- elsewhere in this file never had this bug because they use the
	-- OPPOSITE, correct technique: re-latch D CONTINUOUSLY every cycle
	-- WHILE qualified='1' (D is guaranteed valid for the whole WR_n-low
	-- window), letting it settle on the right value rather than sampling
	-- once after the window has already started closing. Switched to that
	-- same proven pattern here - s_cart_write_qualified_d/the falling-edge
	-- check are no longer needed.
	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				s_a16_bank0_q  <= (others => '0');
				s_a16_bank1_q  <= (others => '0');
				s_a8_bank0_q   <= (others => '0');
				s_a8_bank1_q   <= (others => '0');
				s_a8_bank2_q   <= (others => '0');
				s_a8_bank3_q   <= (others => '0');
				s_k4_bank1_q   <= (others => '0');
				s_k4_bank2_q   <= (others => '0');
				s_k4_bank3_q   <= (others => '0');
				s_kscc_bank0_q <= (others => '0');
				s_kscc_bank1_q <= (others => '0');
				s_kscc_bank2_q <= (others => '0');
				s_kscc_bank3_q <= (others => '0');
			else
				if s_cart_write_qualified = '1' then
					case s_rom_mapper_type is
						when "010" =>	-- ASCII16
							if s_A >= x"6000" and s_A <= x"67FF" then
								s_a16_bank0_q <= D;
							elsif s_A >= x"7000" and s_A <= x"77FF" then
								s_a16_bank1_q <= D;
							end if;
						when "011" =>	-- ASCII8
							if s_A >= x"6000" and s_A <= x"67FF" then
								s_a8_bank0_q <= D;
							elsif s_A >= x"6800" and s_A <= x"6FFF" then
								s_a8_bank1_q <= D;
							elsif s_A >= x"7000" and s_A <= x"77FF" then
								s_a8_bank2_q <= D;
							elsif s_A >= x"7800" and s_A <= x"7FFF" then
								s_a8_bank3_q <= D;
							end if;
						when "100" =>	-- Konami4 (bank0 fixed, no register)
							if s_A >= x"6000" and s_A <= x"7FFF" then
								s_k4_bank1_q <= D;
							elsif s_A >= x"8000" and s_A <= x"9FFF" then
								s_k4_bank2_q <= D;
							elsif s_A >= x"A000" and s_A <= x"BFFF" then
								s_k4_bank3_q <= D;
							end if;
						when "101" =>	-- KonamiSCC
							if s_A >= x"5000" and s_A <= x"57FF" then
								s_kscc_bank0_q <= D;
							elsif s_A >= x"7000" and s_A <= x"77FF" then
								s_kscc_bank1_q <= D;
							elsif s_A >= x"9000" and s_A <= x"97FF" then
								s_kscc_bank2_q <= D;
							elsif s_A >= x"B000" and s_A <= x"B7FF" then
								s_kscc_bank3_q <= D;
							end if;
						when others =>
							null;	-- plain 16KB/32KB: no bank registers
					end case;
				end if;
			end if;
		end if;
	end process;

	-- Real Flash chip in byte mode: DQ15/A-1 becomes the extra low
	-- address bit, FL_ADDR carries the rest - same convention used (and
	-- independently verified pin-correct against the DE0 User Manual)
	-- during the earlier Flash-boot attempt. FL_CE_N/FL_OE_N are gated on
	-- the RAW (unqualified) read enable, matching the proven DE1
	-- reference's own Flash timing - only the I/O-pointer path's decision
	-- to trust/drive the result onto D (below) waits for qualification;
	-- the ROM-boot path never does (see the timing note above).
	--
	-- ROM boot takes priority in each of these shared-driver expressions,
	-- but the two paths can never actually contend for the bus: IORQ_n and
	-- MREQ_n are mutually exclusive on a real Z80 bus cycle, and
	-- s_io_read_5A_en/s_rom_rd_en are gated on IORQ_n='0' and SLTSL_n='0'
	-- (a memory-request-only signal) respectively.
	FL_DQ15_AM1 <= s_rom_byte_addr(0)          when s_rom_rd_en = '1' else s_flash_ptr_q(0);
	FL_ADDR     <= s_rom_byte_addr(22 downto 1) when s_rom_rd_en = '1' else s_flash_ptr_q(22 downto 1);
	FL_WE_N     <= '1';	-- never write to Flash
	FL_CE_N     <= '0' when s_rom_rd_en = '1' else
	               '0' when s_io_read_5A_en = '1' else
	               '1';
	FL_OE_N     <= RD_n;

	-- Drive the Flash byte back onto D - ROM boot uses the raw s_rom_rd_en
	-- (see timing note above), the I/O pointer test still uses its own
	-- qualified signal, unchanged. Single driver for D (and for
	-- U1OE_n/U1_DIR below), since VHDL doesn't allow two separate
	-- unconditional concurrent assignments to the same signal.
	D <= FL_DQ(7 downto 0) when s_rom_rd_en = '1' else
	     FL_DQ(7 downto 0) when s_io_read_5A_qualified = '1' else
	     (others => 'Z');
	-- BUG FIX (real hardware: bank registers were latching floating/garbage
	-- values - e.g. 0x5E/0xDF, then 0x00/0x70 on a subsequent reset - never
	-- anything traceable to a real intended segment number). Root cause:
	-- this chain only ever enabled U1 for READS. It never had a branch for
	-- s_cart_write_en, so U1 stayed disabled (both sides isolated, per the
	-- 74245 truth table) during every single MegaROM bank-switch WRITE -
	-- D was completely floating whenever the bank-register capture process
	-- sampled it. This is the exact same class of bug already found once
	-- this session for Register5A_q's memory-write path ("each access path
	-- needs its own explicit U1 enable, the fix doesn't propagate
	-- automatically" - see project_msx_fpga_hat_v21b_bus_validation memory)
	-- - just not re-applied here when this new write path was added.
	-- Raw/immediate s_cart_write_en (not the glitch-filtered qualified
	-- version) is used here, matching every other real-time bus-driving
	-- enable in this file - U1 must be listening for the FULL WR_n-low
	-- window, not just the part after the glitch filter has settled.
	U1OE_n <= '0' when s_rom_rd_en = '1' else
	          '0' when s_io_read_5A_qualified = '1' else
	          '0' when s_cart_write_en = '1' else
	          '1';
	-- POLARITY FIX (lesson learned on megarom_databus_register_test): read
	-- MSX_FPGA_Hat.net directly - U1's A-side (pins 2-9) wires to CONN1,
	-- the real MSX cartridge edge connector; U1's B-side (pins 11-18)
	-- wires to IDC1, the FPGA GPIO header. Standard 74245 truth table:
	-- DIR=HIGH means A->B (A input, B output). So DIR=1 means MSX->FPGA
	-- (listen), DIR=0 means FPGA->MSX (drive) - the opposite of what this
	-- design (and every other attempt) originally assumed. Confirmed on
	-- real hardware: OUT &H5A,170 -> INP(&H5A) = 170, a perfect round
	-- trip, only after flipping this polarity. Applies equally to the ROM
	-- boot path - same chip, same direction convention.
	U1_DIR <= '0' when s_rom_rd_en = '1' else
	          '0' when s_io_read_5A_qualified = '1' else
	          '1';
	-- Never tri-stated (see note near the top) - forced low while
	-- actively sending data to the CPU on an I/O read (MSX Technical Data
	-- Book 1.6.2), a definite '1' otherwise. Deliberately NOT extended to
	-- the ROM boot path - ordinary /SLTSL memory reads don't need BUSDIR_n
	-- per the MSX Technical Data Book and the proven DE1 SDMapper
	-- reference (msx.org/wiki/Hardware_Design) - only /IORQ-based reads do.
	BUSDIR_n <= '0' when s_io_read_5A_qualified = '1' else '1';

	-- s_flash_data_q: re-latches FL_DQ continuously while the qualified
	-- read holds, same settle-during-access technique as Register5A_q -
	-- holds the last byte actually read from Flash for display.
	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				s_flash_data_q <= (others => '0');
			elsif s_io_read_5A_qualified = '1' then
				s_flash_data_q <= FL_DQ(7 downto 0);
			end if;
		end if;
	end process;

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

	-- FL_WE_N/FL_CE_N/FL_OE_N/FL_ADDR/FL_DQ15_AM1 are now driven above by
	-- the Flash read window. Everything else below is still NOT USED in
	-- this test variant - tied to safe, inactive constants.
	FL_RST_N <= not s_reset;
	FL_BYTE_N <= '0';
	FL_WP_N <= '0';
	SD_DAT <= 'Z';
	DRAM_DQ <= (others => 'Z');
	SRAM_DQ <= (others => 'Z');
	SRAM_ADDR <= (others => '0');
	SRAM_UB_N <= '1';
	SRAM_LB_N <= '1';
	SRAM_WE_N <= '1';
	SRAM_CE_N <= '1';
	SRAM_OE_N <= '1';

end behavioural;

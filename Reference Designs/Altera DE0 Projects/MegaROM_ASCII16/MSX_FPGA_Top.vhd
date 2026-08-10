library ieee ;
use ieee.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;

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
	-- FLASH READ WINDOW (new): reading MSX memory 0x4000-0x4FFF (start of
	-- page 1, the standard cartridge ROM window - moved here from an
	-- initial 0x9000 attempt, since page 2 is BASIC's own workspace RAM,
	-- where our SLTSL_n would never assert while BASIC is running) returns
	-- real Flash content, linearly mapped from Flash offset 0x000000
	-- (address - 0x4000). Unlike the Register5A test above (which used an
	-- I/O port for its read side specifically to avoid ever contending
	-- with real memory), this IS a memory-mapped read in a range real
	-- system RAM/ROM also normally occupies - so it's gated on SLTSL_n
	-- (this cartridge's slot actually selected), unlike every other test
	-- in this file, to avoid fighting the real memory device for the bus
	-- on every
	-- ordinary BASIC memory access to that page.
	-- ------------------------------------------------------------------------
	signal s_sltsl_en : std_logic;

	signal s_flash_read_en        : std_logic;
	signal s_flash_read_dur_cnt   : std_logic_vector(3 downto 0) := (others => '0');
	signal s_flash_read_qualified : std_logic := '0';
	signal s_flash_a : std_logic_vector(23 downto 0);

begin

	s_reset <= not (KEY(0) and RESET_n);
	INT_n <= '0';		-- inverted due to the Q1 open-collector stage in the interface
	WAIT_n <= '0';		-- pure observer - never requests a wait
	BUSDIR_n <= 'Z';	-- tri-stated: we never send data outside normal memory access (see MSX Technical Data Book 1.6.2)
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
	HEXDIGIT0 <= s_read_pulse_width(3 downto 0);
	HEXDIGIT1 <= s_read_pulse_width(7 downto 4);
	HEXDIGIT2 <= s_write_pulse_width(3 downto 0);
	HEXDIGIT3 <= s_write_pulse_width(7 downto 4);

	-- Toggling latch, no reset-only behavior: poke -> on, peek -> off,
	-- unaffected otherwise. Both directions are independently proven
	-- reliable now (via the earlier reset-only-clear diagnostic) - if this
	-- still appears to "go off" shortly after a poke with no explicit
	-- PEEK, that's a genuine read of DABC happening elsewhere in the real
	-- system, not a decode bug.
	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				s_led9_latch <= '0';
			elsif s_write_qualified = '1' then
				s_led9_latch <= '1';
			elsif s_read_qualified = '1' then
				s_led9_latch <= '0';
			end if;
		end if;
	end process;

	LEDG(9) <= s_led9_latch;

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
	-- fires at all, independent of Register5A_q's actual value.
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
	LEDG(7 downto 0) <= Register5A_q;	-- live view of the latched register value

	-- ------------------------------------------------------------------------
	-- FLASH READ WINDOW logic - see declarations above.
	-- ------------------------------------------------------------------------
	s_sltsl_en <= not SLTSL_n;

	-- 0x4000-0x4FFF (start of page 1, the standard MSX cartridge ROM
	-- window) instead of 0x9000 - page 2 is where BASIC's own workspace
	-- RAM lives, so SLTSL_n for our slot would never assert there while
	-- BASIC is running; page 1 is where SLTSL_n was already confirmed to
	-- genuinely assert (the earlier "slot ever selected" diagnostic).
	s_flash_read_en <= '1' when s_sltsl_en = '1' and RD_n = '0' and s_A >= x"4000" and s_A <= x"4FFF" else '0';

	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				s_flash_read_dur_cnt   <= (others => '0');
				s_flash_read_qualified <= '0';
			else
				if s_flash_read_en = '1' then
					if s_flash_read_dur_cnt < MIN_PULSE_CYCLES then
						s_flash_read_dur_cnt <= s_flash_read_dur_cnt + 1;
					end if;
					if s_flash_read_dur_cnt >= MIN_PULSE_CYCLES then
						s_flash_read_qualified <= '1';
					end if;
				else
					s_flash_read_dur_cnt   <= (others => '0');
					s_flash_read_qualified <= '0';
				end if;
			end if;
		end if;
	end process;

	-- Linear map: Flash offset = MSX address - 0x4000, so it still reads
	-- relative to Flash address 0x000000 as requested.
	s_flash_a <= x"000000" + ("00000000" & (s_A - x"4000")) when s_flash_read_en = '1' else (others => '0');

	-- Real Flash chip in byte mode: DQ15/A-1 becomes the extra low
	-- address bit, FL_ADDR carries the rest - same convention used (and
	-- independently verified pin-correct against the DE0 User Manual)
	-- during the earlier Flash-boot attempt.
	FL_DQ15_AM1 <= s_flash_a(0);
	FL_ADDR     <= s_flash_a(22 downto 1);
	FL_WE_N     <= '1';	-- never write to Flash
	FL_CE_N     <= not s_flash_read_en;
	FL_OE_N     <= RD_n;

	-- Drive Register5A_q OR the Flash byte back onto D, depending on
	-- which qualified condition is active - single merged driver for D
	-- (and for U1OE_n/U1_DIR below), since VHDL doesn't allow two
	-- separate unconditional concurrent assignments to the same signal.
	D      <= Register5A_q      when s_io_read_5A_qualified = '1' else
	          FL_DQ(7 downto 0) when s_flash_read_qualified = '1' else
	          (others => 'Z');
	U1OE_n <= not (s_io_read_5A_qualified or s_flash_read_qualified);
	U1_DIR <= '1' when (s_io_read_5A_qualified = '1' or s_flash_read_qualified = '1') else '0';

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

-- MSX_FPGA_Hat - Standard MSX Memory Mapper (512KB), DE0 (Cyclone III EP3C16F484C6)
-- Ronivon Costa @ 2026
--
-- ==============================================================================
-- STATUS (2026-08-11): compiles/fits/programs clean (Quartus 13.0sp1, 111/15,408
-- LE, 0 embedded memory bits, 0 errors) and got a first real-hardware pass on a
-- Canon V-8/V-9: FRE(0) increase confirmed, and PEEK/POKE + segment-switch via
-- port FEh (page 2, 8000h-BFFFh - the only page THIS machine routes to the
-- cartridge slot, see project_memorymapper_hardware_test memory) round-tripped
-- correctly for the segments tried. NOT YET VERIFIED:
--   - Ports FCh/FDh/FFh (pages 0/1/3) - untested on real hardware at all (Canon
--     V-8/V-9 hardwires those pages away from the cartridge slot, so a
--     different/expanded-slot machine is needed to exercise them).
--   - Full 32-segment range - only a couple of segments spot-checked so far,
--     not all 32, and not near the SRAM_UB_N/SRAM_LB_N bank-boundary segment
--     (15/16) where a bank-select wiring mistake would most likely show up.
--   - Data integrity under sustained/adversarial use (e.g. BASIC program
--     actually running out of mapped RAM across multiple segments at once,
--     rapid segment switching, power-cycle behavior) - only manual PEEK/POKE
--     spot checks done so far, no automated/soak test.
--   - Only JTAG SRAM-mode programmed (volatile) so far - never written to the
--     EPCS4 configuration flash, so untested whether it survives a normal
--     power-on boot without the USB-Blaster attached.
-- ==============================================================================
-- SCOPE: a standalone, NON-EXPANDED primary slot whose entire content is a
-- standard MSX Memory Mapper backed by the DE0 SRAM addon board (ISSI
-- IS61LV25616AL, 512KB total: 2x256KB banks selected by SRAM_UB_N/SRAM_LB_N,
-- sharing an 18-bit address bus and an 8-bit data bus - see
-- "Hardware Interface/DE0_Addon_Board/README.txt"). No ROM, no secondary/
-- sub-slot register, no SD card.
--
-- WHY NO SLOT EXPANSION: MSX I/O ports (IORQ_n-based, including the mapper's
-- own FCh-FFh control ports) are NOT slot-scoped at all - only memory-space
-- access (0000h-FFFFh, gated by SLTSL_n) goes through the primary/secondary
-- slot mechanism. A Memory Mapper only needs (1) SLTSL_n to gate its RAM into
-- the CPU's address space, exactly like any plain ROM cartridge, and (2) the
-- FCh-FFh ports decoded off IORQ_n alone. Neither requires a secondary-slot
-- register. This also sidesteps the unresolved sub-slot-select bug documented
-- in SDMapper_V2.1b/SDMapper_Top.vhd's header (that design's exp_slot.vhd
-- combined a ROM sub-slot with a RAM sub-slot in one expanded primary slot -
-- not needed here since there's no ROM to combine with).
--
-- PROVENANCE:
--  -> Bus interface (time-multiplexed A_MUX address capture, per-path
--     U1OE_n/U1_DIR wiring, MIN_PULSE_CYCLES glitch-filter discipline, raw/
--     immediate decode for bus-timing-critical memory access vs qualified/
--     filtered decode for register writes, continuous re-latch of D "while
--     qualified" instead of sampling on a delayed edge) is copied verbatim
--     in technique from "MegaROM_ASCII16/MSX_FPGA_Top.vhd", the proven,
--     real-hardware-booted v2.1b reference for this same interface board.
--     See project_msx_fpga_hat_v21b_bus_validation memory for the real-
--     hardware incidents that established each of these rules.
--  -> Memory Mapper register semantics (5-bit segment registers for 32x16KB
--     segments = 512KB, FCh/FDh/FEh/FFh <-> page0/1/2/3, port decode
--     A(7 downto 2)="111111", reset defaults 3/2/1/0 for page0/1/2/3,
--     BUSDIR_n asserted only during a mapper-port READ) is taken from
--     C:\Users\roniv\Dev\github\msxsdmapperv2\CPLD\src\mapper.vhd - a
--     proven, working MSX Memory Mapper design (Fabio Belavenuto, MSX SD
--     Mapper V2 project) - and cross-checked against msx.org/wiki/Memory_Mapper.
--     That CPLD design clocks its bank registers directly off a raw
--     combinational signal (rising_edge(mp_wr_s)), which is the exact
--     clock-glitch hazard this project's own exp_slot.vhd was fixed to
--     avoid - so the VALUES/PORT MAP are reused here, but re-implemented
--     with this project's own CLOCK_50-synchronous, glitch-filtered
--     technique instead of that raw-combinational-clock pattern.
--
-- MEMORY MAP (this cartridge's /SLTSL-selected space):
--   0000-3FFF (page 0) - one 16KB SRAM segment, selected by port FCh
--   4000-7FFF (page 1) - one 16KB SRAM segment, selected by port FDh
--   8000-BFFF (page 2) - one 16KB SRAM segment, selected by port FEh
--   C000-FFFF (page 3) - one 16KB SRAM segment, selected by port FFh
-- Each port is a 5-bit register (segments 0-31, 512KB/16KB=32); reading a
-- port back returns "111" & the 5-bit segment number. Segment-register
-- writes are NOT gated by SLTSL_n/SW(9) - per msx.org/wiki/Memory_Mapper,
-- "writing to ports FCh-FFh selects mapper blocks for all mappers in the
-- system simultaneously", so this design always keeps its own registers in
-- sync with the global mapper writes, same as real hardware.
--
-- SW(9) is this board's own on/off switch (same convention as MegaROM_ASCII16
-- /MegaRAM): when off, SLTSL_n is never asserted and the mapper I/O ports are
-- not decoded, so the board stays fully off the bus.
-- ==============================================================================

library ieee ;
use ieee.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;

Entity MSX_FPGA_Top is
port (
    CLOCK_50:		in std_logic;								--	50 MHz

    KEY:			in std_logic_vector(2 downto 0);		--	Pushbutton[2:0] (DE0 has 3 buttons)
    SW:				in std_logic_vector(9 downto 0);		--	Toggle Switch[9:0] - SW(9) = cartridge on/off

    HEX0:			out std_logic_vector(6 downto 0);		--	Seven Segment Digit 0
    HEX1:			out std_logic_vector(6 downto 0);		--	Seven Segment Digit 1
    HEX2:			out std_logic_vector(6 downto 0);		--	Seven Segment Digit 2
    HEX3:			out std_logic_vector(6 downto 0);		--	Seven Segment Digit 3

    LEDG:			out std_logic_vector(9 downto 0);		--	LED Green[9:0]

    -- DE0 SRAM addon board (GPIO_0) - the mapper's 512KB backing store.
    SRAM_DQ:		inout std_logic_vector(7 downto 0);	--	SRAM Data bus 8 Bits (shared low/high byte, see SRAM_UB_N/LB_N)
    SRAM_ADDR:		out std_logic_vector(17 downto 0);	--	SRAM Address bus 18 Bits
    SRAM_UB_N:		out std_logic;								--	SRAM High-byte Data Mask (bank select)
    SRAM_LB_N:		out std_logic;								--	SRAM Low-byte Data Mask (bank select)
    SRAM_WE_N:		out std_logic;								--	SRAM Write Enable
    SRAM_CE_N:		out std_logic;								--	SRAM Chip Enable
    SRAM_OE_N:		out std_logic;								--	SRAM Output Enable

    -- MSX Bus (GPIO_1 - MSX_FPGA_Hat rev 2.1b, verified pin-by-pin against
    -- MegaROM_ASCII16/MSX_FPGA_Top.qsf and SDMapper_V2.1b/SDMapper.qsf, which
    -- carry byte-for-byte identical PIN_xx assignments for every signal below).
    MSX_CLK:		in std_logic;
    A_MUX:			in std_logic_vector(7 downto 0);	-- Shared, time-multiplexed address byte (low via U2, high via U3)
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
	-- Address bus reconstruction for v2.1b's time-multiplexed A_MUX bus -
	-- copied verbatim (technique) from MegaROM_ASCII16/MSX_FPGA_Top.vhd /
	-- SDMapper_V2.1b/SDMapper_Top.vhd, including the trigger-preemption fix
	-- (a new bus cycle always restarts this state machine, even mid-capture).
	-- ------------------------------------------------------------------------
	signal s_A				: std_logic_vector(15 downto 0) := (others => '0');

	signal s_bus_req_n		: std_logic;
	signal bus_req_meta, bus_req_sync, bus_req_sync_d : std_logic;
	signal addr_capture_trigger : std_logic;

	type addr_capture_state_t is (S_IDLE, S_LOW_EN, S_LOW_CAP, S_GUARD, S_HIGH_EN, S_HIGH_CAP);
	signal addr_capture_state : addr_capture_state_t := S_IDLE;

	-- Glitch filter - see MegaROM_ASCII16/MSX_FPGA_Top.vhd for the real-
	-- hardware measurement (~80ns electrical glitch vs a genuine ~280ns
	-- T-state) that established this threshold. Applied only to the mapper
	-- I/O-port accesses below (register reads/writes, not bus-timing
	-- critical); memory (SLTSL_n) access stays raw/immediate - a real Z80
	-- memory read/write is only 3 T-states with no automatic wait state,
	-- tighter than this ~160ns qualification delay could tolerate.
	constant MIN_PULSE_CYCLES : integer := 8;	-- 8 * 20ns = 160ns

	-- ------------------------------------------------------------------------
	-- Memory Mapper: 4 page registers (segment 0-31 each, 16KB/segment,
	-- 32 segments = 512KB total = the DE0 SRAM addon's full capacity). Reset
	-- defaults (3,2,1,0 for page0..page3) match the proven reference design
	-- (msxsdmapperv2/CPLD/src/mapper.vhd) rather than an arbitrary guess.
	-- ------------------------------------------------------------------------
	signal reg_page0_q : std_logic_vector(4 downto 0) := "00011";
	signal reg_page1_q : std_logic_vector(4 downto 0) := "00010";
	signal reg_page2_q : std_logic_vector(4 downto 0) := "00001";
	signal reg_page3_q : std_logic_vector(4 downto 0) := "00000";

	-- Mapper I/O port decode (FCh-FFh, A(7 downto 2)="111111", A(1 downto 0)
	-- selects which of the 4 registers - verified against
	-- msxsdmapperv2/CPLD/src/sdmapper.vhd's iomapper_s decode and
	-- msx.org/wiki/Memory_Mapper). NOT gated by SLTSL_n/s_sltsl_en - see
	-- header note: mapper port writes are global, not slot-scoped.
	signal s_io_mapper_en    : std_logic;
	signal s_io_mapper_rd_en : std_logic;
	signal s_io_mapper_wr_en : std_logic;

	signal s_io_mapper_rd_dur_cnt   : std_logic_vector(3 downto 0) := (others => '0');
	signal s_io_mapper_wr_dur_cnt   : std_logic_vector(3 downto 0) := (others => '0');
	signal s_io_mapper_rd_qualified : std_logic := '0';
	signal s_io_mapper_wr_qualified : std_logic := '0';

	signal s_mapper_rdata : std_logic_vector(7 downto 0);

	-- Sticky "was a mapper register ever written" - same reset-only-clear
	-- diagnostic technique proven in MegaROM_ASCII16 for first hardware bring-up.
	signal s_mapper_write_ever_q : std_logic := '0';

	-- ------------------------------------------------------------------------
	-- Memory (SLTSL_n) access - raw/immediate decode, same timing rationale
	-- as MegaROM_ASCII16's ROM-boot path (see that file's header note).
	-- ------------------------------------------------------------------------
	signal s_sltsl_en  : std_logic;
	signal s_mem_rd_en : std_logic;
	signal s_mem_wr_en : std_logic;

	signal s_mem_page_seg  : std_logic_vector(4 downto 0);	-- segment mapped at the CPU's current page (s_A(15:14))
	signal s_sram_full_addr : std_logic_vector(18 downto 0);	-- segment(4:0) & s_A(13:0) = 19 bits = 512K

begin

	s_reset <= not (KEY(0) and RESET_n);
	INT_n <= '0';		-- inverted due to the Q1 open-collector stage in the interface
	WAIT_n <= '0';		-- this mapper never needs a wait state
	SOUNDOUT <= '0';
	U4OE_n <= '0';		-- unused buffer on this variant - disabled

	-- ------------------------------------------------------------------------
	-- Address bus capture (unchanged technique - see declarations above).
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
	-- Mapper I/O port decode (FCh-FFh) - global, not SLTSL_n-gated (see
	-- header note). M1_n='1' excludes interrupt-acknowledge cycles (which
	-- also assert IORQ_n), same check already proven in this project's other
	-- I/O-port work.
	-- ------------------------------------------------------------------------
	s_io_mapper_en    <= '1' when SW(9) = '1' and IORQ_n = '0' and M1_n = '1' and s_A(7 downto 2) = "111111" else '0';
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

	-- Page-register write: re-latches D(4 downto 0) CONTINUOUSLY while
	-- qualified (not a delayed falling-edge sample) - this is the exact
	-- technique that fixed a real garbage-bank-register bug on real hardware
	-- in MegaROM_ASCII16 (see that file's "BUG FIX" comment on
	-- s_cart_write_qualified). Reset defaults per mapper.vhd (see header).
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

	-- Register readback: unused bits 7:5 read as '1' (defined value, since
	-- this design drives all 8 D lines through U1 - no floating bits left to
	-- pull-ups/other logic, unlike the CPLD reference which only drove D(4:0)).
	s_mapper_rdata <= "111" & reg_page0_q when s_A(1 downto 0) = "00" else
	                   "111" & reg_page1_q when s_A(1 downto 0) = "01" else
	                   "111" & reg_page2_q when s_A(1 downto 0) = "10" else
	                   "111" & reg_page3_q;

	process(CLOCK_50)
	begin
		if rising_edge(CLOCK_50) then
			if s_reset = '1' then
				s_mapper_write_ever_q <= '0';
			elsif s_io_mapper_wr_qualified = '1' then
				s_mapper_write_ever_q <= '1';
			end if;
		end if;
	end process;

	-- ------------------------------------------------------------------------
	-- Memory (SLTSL_n) access - raw/immediate decode (see declarations above).
	-- ------------------------------------------------------------------------
	s_sltsl_en  <= (not SLTSL_n) when SW(9) = '1' else '0';
	s_mem_rd_en <= '1' when s_sltsl_en = '1' and RD_n = '0' else '0';
	s_mem_wr_en <= '1' when s_sltsl_en = '1' and WR_n = '0' else '0';

	s_mem_page_seg <= reg_page0_q when s_A(15 downto 14) = "00" else
	                   reg_page1_q when s_A(15 downto 14) = "01" else
	                   reg_page2_q when s_A(15 downto 14) = "10" else
	                   reg_page3_q;

	s_sram_full_addr <= s_mem_page_seg & s_A(13 downto 0);	-- 5 + 14 = 19 bits = 512K

	SRAM_ADDR <= s_sram_full_addr(17 downto 0);
	SRAM_UB_N <= not s_sram_full_addr(18);
	SRAM_LB_N <= s_sram_full_addr(18);
	SRAM_CE_N <= not s_sltsl_en;	-- matches mapper.vhd's sram_cs_n_o <= sltsl_n_i
	SRAM_OE_N <= RD_n;
	SRAM_WE_N <= WR_n;				-- matches mapper.vhd's sram_we_n_o <= cpu_wr_n_i

	SRAM_DQ <= D when s_mem_wr_en = '1' else (others => 'Z');

	-- Single driver for D (VHDL doesn't allow two unconditional concurrent
	-- drivers) - memory read takes priority, but SLTSL_n and IORQ_n are
	-- mutually exclusive on a real Z80 bus cycle, so the two paths never
	-- actually contend.
	D <= SRAM_DQ         when s_mem_rd_en = '1'          else
	     s_mapper_rdata  when s_io_mapper_rd_qualified = '1' else
	     (others => 'Z');

	-- U1OE_n: every access path that reads OR writes D needs its own
	-- explicit branch here - see feedback_u1oe_n_per_access_path memory
	-- (this exact class of bug was found twice already in this project).
	U1OE_n <= '0' when s_mem_rd_en = '1'             else
	          '0' when s_mem_wr_en = '1'             else
	          '0' when s_io_mapper_rd_qualified = '1' else
	          '0' when s_io_mapper_wr_en = '1'        else
	          '1';

	-- U1_DIR: '0' = drive toward MSX (FPGA->MSX), '1' = listen from MSX
	-- (MSX->FPGA) - polarity verified against the real MSX_FPGA_Hat.net
	-- netlist, see project_msx_fpga_hat_v21b_bus_validation memory. Default
	-- '1' (listen) covers both write paths and idle.
	U1_DIR <= '0' when s_mem_rd_en = '1'             else
	          '0' when s_io_mapper_rd_qualified = '1' else
	          '1';

	-- BUSDIR_n: only /IORQ-based reads need it (MSX Technical Data Book
	-- 1.6.2; matches mapper.vhd's busdir_n_o <= not mp_rd_s). Never tri-
	-- stated - always actively driven, per the proven MSXPi CPLD convention.
	BUSDIR_n <= '0' when s_io_mapper_rd_qualified = '1' else '1';

	-- ------------------------------------------------------------------------
	-- Debug display: HEX1:HEX0 = page1 segment (4000-7FFF), HEX3:HEX2 =
	-- page3 segment (C000-FFFF) - the two pages MSX-DOS2/BASIC touch most.
	-- LEDG(0) = live slot-select, LEDG(1)/(2) = live mapper write/read,
	-- LEDG(9) = sticky "mapper register ever written" (first hardware
	-- bring-up diagnostic, same technique as MegaROM_ASCII16's LEDG(9)).
	-- ------------------------------------------------------------------------
	HEXDIGIT0 <= reg_page1_q(3 downto 0);
	HEXDIGIT1 <= "000" & reg_page1_q(4);
	HEXDIGIT2 <= reg_page3_q(3 downto 0);
	HEXDIGIT3 <= "000" & reg_page3_q(4);

	LEDG(9)          <= s_mapper_write_ever_q;
	LEDG(8 downto 3) <= (others => '0');
	LEDG(2)          <= s_io_mapper_rd_qualified;
	LEDG(1)          <= s_io_mapper_wr_qualified;
	LEDG(0)          <= s_sltsl_en;

	DISPHEX0 : decoder_7seg PORT MAP (
		NUMBER		=>	HEXDIGIT0,
		HEX_DISP	=>	HEX0
	);

	DISPHEX1 : decoder_7seg PORT MAP (
		NUMBER		=>	HEXDIGIT1,
		HEX_DISP	=>	HEX1
	);

	DISPHEX2 : decoder_7seg PORT MAP (
		NUMBER		=>	HEXDIGIT2,
		HEX_DISP	=>	HEX2
	);

	DISPHEX3 : decoder_7seg PORT MAP (
		NUMBER		=>	HEXDIGIT3,
		HEX_DISP	=>	HEX3
	);

end behavioural;

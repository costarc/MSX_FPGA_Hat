library ieee ;
use ieee.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;

-- Updated on 23/01/2024
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

Entity MultiCart is
port (
	CLOCK_50:		in std_logic;		--	50 MHz
	CLOCK_50_2:		in std_logic;		--	50 MHz
					
	KEY:				in std_logic_vector(2 downto 0);		--	Pushbutton[3:0]				
	SW:				in std_logic_vector(9 downto 0);		--	Toggle Switch[9:0]
					
	HEX0:				out std_logic_vector(6 downto 0);		--	Seven Segment Digit 0
	HEX1:				out std_logic_vector(6 downto 0);		--	Seven Segment Digit 1
	HEX2:				out std_logic_vector(6 downto 0);		--	Seven Segment Digit 2
	HEX3:				out std_logic_vector(6 downto 0);		--	Seven Segment Digit 3
	HEX0_DP:			out std_logic;
	HEX1_DP:			out std_logic;	
	HEX2_DP:			out std_logic;	
	HEX3_DP:			out std_logic;	
					
	LEDG:				out std_logic_vector(9 downto 0);		--	LED Green[7:0]
					
	UART_TXD:		out std_logic;							--	UART Transmitter
	UART_RXD:		in std_logic;							--	UART Receiver
	UART_CTS:		out std_logic;							--	UART Clear To Send
	UART_RTS:		in std_logic;							--	UART Request To Send
				 
	DRAM_DQ:			inout std_logic_vector(15 downto 0);	--	SDRAM Data bus 16 Bits
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
	FL_ADDR:			out std_logic_vector(21 downto 0);	--	FLASH Address bus 22 Bits
	FL_WE_N:			out std_logic;							--	FLASH Write Enable
	FL_RST_N:		out std_logic;							--	FLASH Reset
	FL_OE_N:			out std_logic;							--	FLASH Output Enable
	FL_CE_N:			out std_logic;							--	FLASH Chip Enable
	FL_WP_N:			out std_logic;							--	FLASH Hardware Write Protect
	FL_BYTE_N:		out std_logic;							--	FLASH Selects 8/16-bit mode
	FL_RY:			in std_logic;							--	FLASH Ready/Busy
	   
	LCD_DATA:		inout std_logic_vector(7 downto 0);		-- LCD Data bus 8 bits
	LCD_BLON:		out std_logic;							-- LCD Back Light ON/OFF
	LCD_RW:			out std_logic;							-- CD Read/Write Select, 0 = Write, 1 = Read
	LCD_EN:			out std_logic;							-- LCD Enable
	LCD_RS:			out std_logic;							-- LCD Command/Data Select, 0 = Command, 1 = Data
															
	SD_CS:			inout std_logic;						--	SD Card Data 3
	SD_CLK:			out std_logic;							--	SD Card Clock
	SD_MISO:			inout std_logic;						--	SD Card Data
	SD_MOSI:			inout std_logic;						--	SD Card Command Signal
	SD_WP_N:			in std_logic;							--	SD Card Write Protect
															
	PS2_KBDAT:		inout std_logic;						--	PS2 Data
	PS2_KBCLK:		inout std_logic;						--	PS2 Clock
	PS2_MSDAT:		inout std_logic;						--	PS2 Data
	PS2_MSCLK:		inout std_logic;						--	PS2 Clock
															
	VGA_HS:			out std_logic;							--	VGA H_SYNC
	VGA_VS:			out std_logic;							--	VGA V_SYNC
	VGA_R:			out std_logic_vector(3 downto 0);		--	VGA Red[3:0]
	VGA_G:			out std_logic_vector(3 downto 0);		--	VGA Green[3:0]
	VGA_B:			out std_logic_vector(3 downto 0);		--	VGA Blue[3:0]	 FL_CE_N:			out std_logic;								--	FLASH Chip Enable
	
	-- SRAM Addon Conencted to GPIO_0
	SRAM_DQ:			inout std_logic_vector(7 downto 0);	--	SRAM Data bus 16 Bits
	SRAM_ADDR:		out std_logic_vector(17 downto 0);	--	SRAM Address bus 18 Bits
	SRAM_UB_N:		out std_logic;								--	SRAM High-byte Data Mask 
	SRAM_LB_N:		out std_logic;								--	SRAM Low-byte Data Mask 
	SRAM_WE_N:		out std_logic;								--	SRAM Write Enable
	SRAM_CE_N:		out std_logic;								--	SRAM Chip Enable
	SRAM_OE_N:		out std_logic;								--	SRAM Output Enable
	
	GPIO0_P1:		in std_logic;
	GPIO0_P3:		in std_logic;
	GPIO0_P21:		out std_logic;
	GPIO0_P22:		inout std_logic;
	GPIO0_P24:		inout std_logic;
	 
	-- MSX FPGA HAT Control signals
	U1_DIR:			out std_logic;
	U1_OE_n:			out std_logic;
	U2_OE_n:			out std_logic;
	U3_OE_n:			out std_logic;
	U4_OE_n:			out std_logic;
	AUDIO:			out std_logic;
	SOUND:			out std_logic;
	
	--MSX Bus
	A0_8:				in std_logic;		-- MSX Address Bus is shared between high/low bytes in the interface
	A1_9:				in std_logic;
	A2_10:			in std_logic;
	A3_11:			in std_logic;
	A4_12:			in std_logic;
	A5_13:			in std_logic;
	A6_14:			in std_logic;
	A7_15:			in std_logic;
	D:					inout std_logic_vector(7 downto 0);
	RD_n:				in std_logic;
	WR_n:				in std_logic;
	MREQ_n:			in std_logic;
	IORQ_n:			in std_logic;
	SLTSL_n:			in std_logic;
	CS1_n:			in std_logic;
	CS2_n:			in std_logic;
	BUSDIR_n:		out std_logic;
	M1_n:				in std_logic;
	INT_n:			out std_logic;
	RESET_n:			in std_logic;
	WAIT_n:			out std_logic;
	MSXCLK:			in std_logic); 
end MultiCart;

architecture behavioural of MultiCart is
		
	signal HEXDIGIT0			: std_logic_vector(3 downto 0);
	signal HEXDIGIT1			: std_logic_vector(3 downto 0);
	signal HEXDIGIT2			: std_logic_vector(3 downto 0);
	signal HEXDIGIT3			: std_logic_vector(3 downto 0);
	
	signal A					: std_logic_vector(15 downto 0);
	signal reset_s				: std_logic := '0';
	signal slten_s				: std_logic;
	signal mreq_s				: std_logic;
	signal romq_s				: std_logic_vector(7 downto 0);
	signal rombaseaddress_s	: std_logic_vector(23 downto 0);	
	signal romaddress_s 		: std_logic_vector(23 downto 0);
	
	signal ledgclock_s		: std_logic;
	signal address_ready_s	: std_logic;
	
begin
  
-- --------------------------------Common Signals & assertions ------------------------------------------

	DRAM_DQ		<= (others => 'Z');
	SRAM_DQ		<= (others => 'Z');
	WAIT_n	<= 'Z';
	INT_n	<= 'Z';
	BUSDIR_n <= 'Z';
	
	HEXDIGIT0 <= SW(3 DOWNTO 0);
	HEXDIGIT1 <= "000" & SW(4);
	HEXDIGIT2 <= "0000";
	HEXDIGIT3 <= "0000";
	LEDG(9) <= SW(9);
	LEDG(4 downto 0) <= SW(4 downto 0); 
	LEDG(5) <= slten_s;
	LEDG(6) <= mreq_s;
	LEDG(7) <= ledgclock_s;
	
	-- SW9 enables the MultiCart feature
	slten_s	<= '1' when SLTSL_n = '0' and SW(9) ='1' else '0';
	
	-- Memory access only when not in M1 cycle
	mreq_s	<= '1' when MREQ_n = '0' and M1_n = '1' else '0';


	--process(MSXCLK)
	--begin
	--	if rising_edge(MSXCLK) then
	--		ledgclock_s <= not ledgclock_s;
	--	end if;
	--end process;

	-- Perform memory read only when the A bus is fully decoded
	process(address_ready_s)
	begin
		if rising_edge(address_ready_s) then
			-- Perform actions when address_ready goes high (indicating address is ready)
			-- For example, read the address or perform some logic
			ledgclock_s <= not ledgclock_s;
		end if;
	end process;	
 
    uut: entity work.msxaddressbus
        Port map (
            CLOCK_50 => CLOCK_50,
            slten_s  => slten_s,
            A0_8     => A0_8,
            A1_9     => A1_9,
            A2_10    => A2_10,
            A3_11    => A3_11,
            A4_12    => A4_12,
            A5_13    => A5_13,
            A6_14    => A6_14,
            A7_15    => A7_15,
            A        => A,
            U2_OE_n  => U2_OE_n,
            U3_OE_n  => U3_OE_n,
				address_ready => address_ready_s
        );

--
end behavioural;

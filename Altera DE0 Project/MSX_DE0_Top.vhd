library ieee ;
use ieee.std_logic_1164.all;
use IEEE.std_logic_unsigned.all; 

Entity MSX_DE0_Top is
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
	FL_ADDR:			out std_logic_vector(21 downto 0);		--	FLASH Address bus 22 Bits
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
	VGA_B:   		out std_logic_vector(3 downto 0);		--	VGA Blue[3:0]
															
	GPIO_0:			inout std_logic_vector(31 downto 0);	--	GPIO Connection 0
	GPIO0_CLKIN:	in std_logic_vector(1 downto 0);		-- GPIO Connection 0 Clock In Bus
	GPIO0_CLKOUT:	out std_logic_vector(1 downto 0);		-- GPIO Connection 0 Clock Out Bus

	-- MSX Bus
	A:					in std_logic_vector(15 downto 0);
	D:					inout std_logic_vector(7 downto 0);
	RD_n:				in std_logic;
	WR_n:				in std_logic;
	MREQ_n:			in std_logic;
	IORQ_n:			in std_logic;
	SLTSL_n:			in std_logic;
	CS1_n:			in std_logic;
	CS2_OR_CS12:	in std_logic;
	BUSDIR_n:		out std_logic;
	M1_n:				in std_logic;
	INT_n:			out std_logic;
	CLK_OR_RST:		in std_logic;
	WAIT_n:			out std_logic); 
	 

end MSX_DE0_Top;

architecture rtl of MSX_DE0_Top is
	component decoder_7seg
	port (
		NUMBER		: in   std_logic_vector(3 downto 0);
		HEX_DISP	: out  std_logic_vector(6 downto 0));
	end component;
	
	signal HEX_DISP0	: std_logic_vector(6 downto 0);
	signal HEX_DISP1	: std_logic_vector(6 downto 0);
	signal HEX_DISP2	: std_logic_vector(6 downto 0);
	signal HEX_DISP3	: std_logic_vector(6 downto 0);
	signal NUMBER0		: std_logic_vector(3 downto 0);
	signal NUMBER1		: std_logic_vector(3 downto 0);	
	signal NUMBER2		: std_logic_vector(3 downto 0);
	signal NUMBER3		: std_logic_vector(3 downto 0);
	
	signal s_msx_a : std_logic_vector(15 downto 0);
	signal s_msx_d : std_logic_vector(7 downto 0);
	signal s_mreq: std_logic;
	signal s_iorq_r: std_logic;
	signal s_iorq_w: std_logic;
	signal s_busd_en: std_logic;
	signal s_iorq_r_reg: std_logic;
	signal s_iorq_w_reg: std_logic;
	signal s_reset: std_logic := '0';
	
	-- signals for cartridge emulation
	signal s_rom_en : std_logic;
	signal s_rom_d : std_logic_vector(7 downto 0);
	signal s_rom_a : std_logic_vector(21 downto 0);
	signal s_cart_en: std_logic;
	
	-- signals for I/O Device Emulation
	signal s_reg56: std_logic_vector(7 downto 0) := x"CD";
	signal s_msxpi_en: std_logic;
	
begin

	--------------------------------------------------------------------------------
	-- Note about GPIO Clock pins
	-- GPIO0_CLKOUT:
	-- 	GPIO0_CLKOUT(0) and GPIO1_CLKOUT(0) can be used as Output Pins
	-- 	GPIO0_CLKOUT(1) and GPIO1_CLKOUT(1) does not seem to work, must not be used
	-- 
	-- GPIO1_CLKIN:
	-- 	GPIO0_CLKIN(1 .. 0) and GPIO1_CLKIN(1 .. 0) can be used as Input
	--------------------------------------------------------------------------------

	-- Cartridge Emulation
	s_cart_en <= SW(9);  -- Will only enable Cart emulaiton if SW(9) is '1'
	FL_WE_N <= '1';
	FL_RST_N <= '1';
	FL_CE_N <= not s_rom_en;
	FL_ADDR <= s_rom_a;
	FL_OE_N <= RD_n;
	s_rom_a <= ((A - x"4000") + (SW(5 downto 0) * x"2000"));
	s_rom_en  <= '1' when (SLTSL_n = '0' and s_cart_en ='1') else '0';
	
	-- I/O Device Emulation - MSXPi port 0x56 is used to write/read a Register
	s_iorq_r_reg <= '1' when A = x"56" and s_iorq_r = '1' else '0';
	s_iorq_w_reg <= '1' when A = x"56" and s_iorq_w = '1' else '0';
	s_msxpi_en <= '1' when (s_iorq_r_reg = '1' or s_iorq_w_reg = '1') else '0';
	
	-- Auxiliary Generic control signals
   s_iorq_r <= '1' when RD_n = '0' and  IORQ_n = '0' else '0';
	s_iorq_w <= '1' when WR_n = '0' and  IORQ_n = '0' else '0';
	s_mreq <= '1' when RD_n = '0' and  MREQ_n = '0' and M1_n = '1' else '0';
	s_msx_a <= A when s_busd_en = '1';	 
   s_busd_en <= '1' when s_rom_en = '1' or s_msxpi_en = '1' else '0';
	 
	-- Output signals to DE1
	INT_n  <= 'Z';
	WAIT_n <= 'Z';
	BUSDIR_n <= not s_busd_en;	
	D <=	FL_DQ(7 downto 0) when s_rom_en = '1' else               -- MSX reads data from FLASH RAM - Emulation of Cartridges
	 		s_reg56 when s_iorq_r_reg = '1' else         -- MSX read Register on port 0x56
	 		(others => 'Z'); 
	 	 
	process(s_iorq_w_reg)
	begin
	if s_reset = '1' then
		s_reg56 <= x"00";
	elsif rising_edge(s_iorq_w_reg) then
		s_reg56 <= D;
	end if;
	end process;
	
	-- Display the current Memory Address in the 7 segment display
	NUMBER0 <= s_reg56(3 downto 0);
	NUMBER1 <= s_reg56(7 downto 4);
	NUMBER2 <= s_msx_a(3 downto 0);
	NUMBER3 <= s_msx_a(7 downto 4);
	HEX0 <= HEX_DISP0;
	HEX1 <= HEX_DISP1;
	HEX2 <= HEX_DISP2;
	HEX3 <= HEX_DISP3;
	
	LEDG <= "00"& SLTSL_n & CS1_n & CS2_OR_CS12 & MREQ_n & IORQ_n & RD_n & wr_n & s_msxpi_en;
	
	DISPHEX0 : decoder_7seg PORT MAP (
			NUMBER			=>	NUMBER0,
			HEX_DISP		=>	HEX_DISP0
		);		
	
	DISPHEX1 : decoder_7seg PORT MAP (
			NUMBER			=>	NUMBER1,
			HEX_DISP		=>	HEX_DISP1
		);		
	
	DISPHEX2 : decoder_7seg PORT MAP (
			NUMBER			=>	NUMBER2,
			HEX_DISP		=>	HEX_DISP2
		);		
	
	DISPHEX3 : decoder_7seg PORT MAP (
			NUMBER			=>	NUMBER3,
			HEX_DISP		=>	HEX_DISP3
		);
	
	HEX0_DP <= '0';
	HEX1_DP <= '0';
	HEX2_DP <= '0';
	HEX3_DP <= '0';
	
	SD_DAT		<= 'Z';
	DRAM_DQ		<= (others => 'Z');
	FL_DQ			<= (others => 'Z');
	GPIO_0		<= (others => 'Z');
	GPIO0_CLKOUT<= (others => 'Z');

end rtl;
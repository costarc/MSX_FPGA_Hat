library ieee ;
use ieee.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;

Entity MSXPi_Top is
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
    FL_ADDR:		out std_logic_vector(21 downto 0);		--	FLASH Address bus 22 Bits
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
    SRAM_ADDR:		inout std_logic_vector(17 downto 0);	--	SRAM Address bus 18 Bits
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
	 
    -- MSX Bus & MSX FPGA Hat signals
	 U1OE_n:				out std_logic;
    A:					in std_logic_vector(15 downto 0);
    D:					inout std_logic_vector(7 downto 0);
    RD_n:				in std_logic;
    WR_n:				in std_logic;
    MREQ_n:				in std_logic;
    IORQ_n:				in std_logic;
    SLTSL_n:			in std_logic;
    CS_n:				in std_logic;
    BUSDIR_n:			out std_logic;
    M1_n:				in std_logic;
    INT_n:				out std_logic;
    RESET_n:			in std_logic;
    WAIT_n:				out std_logic);  
end MSXPi_Top;

architecture bevioural of MSXPi_Top is
	
	component decoder_7seg
	port (
		NUMBER				: in   std_logic_vector(3 downto 0);
		HEX_DISP				: out  std_logic_vector(6 downto 0));
	end component;

	signal HEXDIGIT0		: std_logic_vector(3 downto 0);
	signal HEXDIGIT1		: std_logic_vector(3 downto 0);
	signal HEXDIGIT2		: std_logic_vector(3 downto 0);
	signal HEXDIGIT3		: std_logic_vector(3 downto 0);
	
	signal s_reset			: std_logic := '0';
		
	-- signals for cartridge emulation / mapper / slot expansion
	signal s_sltsl_en		: std_logic;
	signal s_io_addr 		: std_logic_vector(7 downto 0);
	signal s_fc				: std_logic_vector(4 downto 0) := "00011";
	signal s_fd				: std_logic_vector(4 downto 0) := "00010";
	signal s_fe				: std_logic_vector(4 downto 0) := "00001";
	signal s_ff				: std_logic_vector(4 downto 0) := "00000";
	signal s_iorq_en		: std_logic;
	signal s_iorq_r		: std_logic;
	signal s_iorq_w		: std_logic;
	signal s_iorq_r_reg	: std_logic;
	signal s_iorq_w_reg	: std_logic;
	signal s_mapper_reg_w: std_logic;
	signal s_SRAM_ADDR	:	std_logic_vector(20 downto 0);	
	signal s_segment		: std_logic_vector(20 downto 0);
	signal s_ffff_slt		: std_logic;
	signal slt_exp_n		: std_logic_vector(3 downto 0);
	signal s_expn_q		: std_logic_vector(7 downto 0);
	
	-- MSXPi signals - will be assigned to/from SRAM signals since they have double function
	signal SPI_CS  		: std_logic;
	signal SPI_SCLK		: std_logic;
	signal SPI_MOSI		: std_logic;
	signal SPI_MISO		: std_logic;
	signal SPI_RDY 		: std_logic;
   signal s_msxpi_en		: std_logic;
		
begin

	s_reset		<= not (KEY(0) and RESET_n);
	LEDG			<= SPI_RDY & SPI_SCLK & SPI_MOSI & SPI_MISO & "00000" & s_msxpi_en;
	
	-- Output signals to DE1
	INT_n			<= 'Z';
	
	-- These signals are driven by MSXPi component
	--WAIT_n		<= 'Z';
   --BUSDIR_n <= not s_msxpi_en; 
		
	U1OE_n <= not s_msxpi_en;
	
    -- Auxiliary Generic control signals
	s_iorq_en	<= '1' when IORQ_n = '0' and M1_n = '1' else '0';
	s_iorq_r		<= '1' when RD_n = '0' and s_iorq_en = '1' else '0';
	s_iorq_w		<= '1' when WR_n = '0' and s_iorq_en = '1'  else '0';
	
	-- MSXPi2 Implementation
	-- Remap GPIO signals to MSXPi - Default GPIO0 mapping is for SRAM Add-On, here pins are remapped for MSXPi signals
	SRAM_CE_n <= '1';   --  Disable SRAM to allow Raspberry Pi to use the BUS
	
	-- MSXPi2 (FULL BUS) PinOut
	--RPI_A(0) <= SRAM_DQ(0);
	--RPI_A(1) <= SRAM_DQ(1);
	--RPI_A(2) <= SRAM_DQ(2);
	--RPI_A(3) <= SRAM_DQ(3);
	--RPI_A(4) <= SRAM_DQ(4);
	--RPI_A(5) <= SRAM_DQ(5);
	--RPI_A(6) <= SRAM_DQ(6);
	--RPI_A(7) <= SRAM_DQ(7);
	--RPI_A(8) <= SRAM_ADDR(8);
	--RPI_A(9) <= SRAM_ADDR(9);
	--RPI_A(10) <= SRAM_ADDR(10);
	--RPI_A(11) <= SRAM_ADDR(11);
	--RPI_A(12) <= SRAM_ADDR(12);
	--RPI_A(13) <= SRAM_ADDR(13);
	--RPI_A(14) <= SRAM_ADDR(14);
	--RPI_A(15) <= SRAM_ADDR(15);
	--RPI_DQ(0) <= SRAM_DQ(0);
	--RPI_DQ(1) <= SRAM_DQ(1);
	--RPI_DQ(2) <= SRAM_DQ(2);
	--RPI_DQ(3) <= SRAM_DQ(3);
	--RPI_DQ(4) <= SRAM_DQ(4);
	--RPI_DQ(5) <= SRAM_DQ(5);
	--RPI_DQ(6) <= SRAM_DQ(6);
	--RPI_DQ(7) <= SRAM_DQ(7);
	--RPI_IORQ <= IORQ_n;
	--RPI_MREQ <= SRAM_ADDR(17);
	--RPI_WR <= SRAM_ADDR(6);
	--RPI_RD <= SRAM_ADDR(5);
	--RPI_SLTSL <= SRAM_ADDR(16);
   --RPI_ACK <= GPIO0_P1;
   --RPI_WAIT <= GPIO0_P3;
	--RPI_M1 <= GPIO0_P22;
	--RPI_RESET <= SRAM_UB_N;
	--RPI_En <= GPIO0_P21;

   -- MSXPi (SPI Bus) Assignment
	-- Assign double-function pins (these are used by SRAM Addon and MSXPi)
	SRAM_ADDR(8) <= SPI_CS;
	SPI_SCLK <= SRAM_ADDR(6);
	SRAM_WE_N <= SPI_MOSI;
	SPI_MISO <= SRAM_DQ(4);
	SPI_RDY <= GPIO0_P22;
	s_msxpi_en <= '1' when s_iorq_en = '1' and (A(7 downto 0) = x"56" or A(7 downto 0) = x"57" or A(7 downto 0) = x"5A") else '0';
		
	-- Display the current Memory Address in the 7 segment display
	HEXDIGIT0 <= s_SRAM_ADDR(7 downto 4);
	HEXDIGIT1 <= s_SRAM_ADDR(11 downto 8);
	HEXDIGIT2 <= s_SRAM_ADDR(15 downto 12);
	HEXDIGIT3 <= s_SRAM_ADDR(19 downto 16);
		
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
	
	i_msxpi: entity work.MSXPi
	port map (
		D           => D,
		A           => A(7 downto 0),
		IORQ_n      => IORQ_n,
		RD_n        => RD_n,
		WR_n        => WR_n,
		BUSDIR_n    => BUSDIR_n,
		WAIT_n      => WAIT_n,
		--
		SPI_CS      => SPI_CS,
		SPI_SCLK    => SPI_SCLK,
		SPI_MOSI    => SPI_MOSI,
		SPI_MISO    => SPI_MOSI,
		SPI_RDY     => SPI_MOSI
	);

	SD_DAT	<= 'Z';
	DRAM_DQ	<= (others => 'Z');
	FL_DQ		<= (others => 'Z');
	
end bevioural;

library ieee ;
use ieee.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;

Entity MSX_DE1_Top is
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
    							
    SD_DAT:			inout std_logic;							--	SD Card Data
    SD_DAT3:			inout std_logic;							--	SD Card Data 3
    SD_CMD:			inout std_logic;							--	SD Card Command Signal
    SD_CLK:			out std_logic;								--	SD Card Clock
    							
    I2C_SDAT:		inout std_logic;							--	I2C Data
    I2C_SCLK:		out std_logic;								--	I2C Clock
    							
    PS2_DAT:			in std_logic;		 						--	PS2 Data
    PS2_CLK:			in std_logic;								--	PS2 Clock
    							
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
                    
    GPIO_0:			inout std_logic_vector(35 downto 0);--	GPIO Connection 0
    
    -- MSX Bus
    A:					in std_logic_vector(15 downto 0);
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
    MSX_CLK:			in std_logic;
    WAIT_n:			out std_logic); 
end MSX_DE1_Top;

architecture rtl of MSX_DE1_Top is

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
	 signal s_mreq_reg: std_logic;
	 signal s_iorq_r_reg: std_logic;
	 signal s_iorq_w_reg: std_logic;
	 
	 -- signals for cartridge emulation
	 signal s_rom_cs : std_logic;
	 signal s_rom_d : std_logic_vector(7 downto 0);
	 signal s_rom_a : std_logic_vector(21 downto 0);
	 signal s_cart_en: std_logic;

begin

	-- Cartridge Emulation
	 s_cart_en <= SW(9);  -- Will only enable Cart emulaiton if SW(9) is '1'
	 FL_WE_N <= '1';
	 FL_RST_N <= '1';
	 FL_CE_N <= not s_mreq_reg;
	 FL_ADDR <= s_rom_a;
	 FL_OE_N <= RD_n;
	 s_rom_a <= ((A - x"4000") + (SW(5 downto 0) * x"2000"));
	 s_mreq_reg <= '1' when SLTSL_n = '0' and s_cart_en ='1' else '0';
	 
	 -- Generic control signals
    s_iorq_r <= '1' when RD_n = '0' and  IORQ_n = '0' else '0';
	 s_iorq_w <= '1' when WR_n = '0' and  IORQ_n = '0' else '0';
	 s_mreq <= '1' when RD_n = '0' and  MREQ_n = '0' and M1_n = '1' else '0';
	 s_msx_a <= A when s_mreq_reg = '1';
    s_iorq_r_reg <= '1' when A = x"56" and s_iorq_r = '1' else '0';
	 s_iorq_w_reg <= '1' when A = x"56" and s_iorq_w = '1' else '0';
	 
	 -- I/O Ports Control and Register
	 
	 D <=	FL_DQ when s_mreq_reg = '1' else             -- MSX reads data from FLASH RAM - Emulation of Cartridges
	 		s_msx_d when s_iorq_r_reg = '1' else         -- MSX read Register on port 0x56
	 		(others => 'Z');
	 
	 -- Create a Register updated over I/O port 0x56
	 process(s_iorq_w_reg)
	 begin
	 if rising_edge(s_iorq_w_reg) then
	 	s_msx_d <= D;
	 end if;
	 end process;

-- Display the current Memory Address in the 7 segment display
    NUMBER0 <= s_msx_a(3 downto 0);
    NUMBER1 <= s_msx_a(7 downto 4);
    NUMBER2 <= s_msx_a(11 downto 8);
    NUMBER3 <= s_msx_a(15 downto 12);
    
    LEDG <= s_msx_a(5 downto 0) & s_msx_d(1 downto 0);
    LEDR <= s_msx_a(15 downto 6);
    
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
    
    		
    SD_DAT		<= 'Z';
    I2C_SDAT		<= 'Z';
    AUD_ADCLRCK	<= 'Z';
    AUD_DACLRCK	<= 'Z';
    AUD_BCLK		<= 'Z';
    DRAM_DQ		<= (others => 'Z');
    FL_DQ			<= (others => 'Z');
    SRAM_DQ		<= (others => 'Z');
    GPIO_0		<= (others => 'Z');

-- MSX signals
	 INT_n			<= 'Z';
	 
	 HEX0 <= HEX_DISP0;
	 HEX1 <= HEX_DISP1;
	 HEX2 <= HEX_DISP2;
	 HEX3 <= HEX_DISP3;
	 
	 WAIT_n <= 'Z';
	
end rtl;

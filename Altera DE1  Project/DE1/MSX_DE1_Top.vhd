library ieee ;
use ieee.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;

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
                    
    SRAM_DQ:		inout std_logic_vector(15 downto 0);--	SRAM Data bus 16 Bits
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
	
	component C_74HC30 is
	port (
		D: in std_logic_vector(7 downto 0);
		Y: out std_logic);
	end component;

	component C_74HC670D is
	port (
		D: in std_logic_vector(3 downto 0);
		Q: out std_logic_vector(3 downto 0);
		RA: std_logic;
		RB: std_logic;
		WA: std_logic;
		WB: std_logic;
		WE_n: std_logic;
		RE_n: std_logic);
	end component;

	component C_74HC138 is
	port (
		A: in std_logic_vector(2 downto 0);
		E1_n: in std_logic;
		E2_n: in std_logic;
		E3: in std_logic;
		Y: out std_logic_vector(7 downto 0));
	end component;
	
	component C_74HC139 is
	port (
		A1 : in std_logic_vector(1 downto 0);
		A2 : in std_logic_vector(1 downto 0);
		Y1: out std_logic_vector(3 downto 0);
		Y2: out std_logic_vector(3 downto 0);
		E1: in std_logic;
		E2: in std_logic);
	end component;

	component C_74HC257 is
	port (
		I1: in std_logic_vector(1 downto 0);
		Y1: out std_logic;
		I2: in std_logic_vector(1 downto 0);
		Y2: out std_logic;
		I3: in std_logic_vector(1 downto 0);
		Y3: out std_logic;
		I4: in std_logic_vector(1 downto 0);
		Y4: out std_logic;
		S: in std_logic;
		OE_n: in std_logic);
	end component;

	component C_74HC373WM is
	port (
		D: in std_logic_vector(7 downto 0);
		Q: out std_logic_vector(7 downto 0);
		LE: in std_logic;
		OE_n: in std_logic);
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
	
	-- signals for I/O Device Emulation / Test Only
	signal s_reg56: std_logic_vector(7 downto 0) := x"CD";
	signal s_msxpi_en: std_logic;
	
	-- signals for simple memory mapper in the primary slot
	signal s_mapper_en: std_logic;
	
	-- signals for the mapper external components
	signal s_74hc30_y: std_logic;
	signal s_74hc257_Y1: std_logic;
	signal s_74hc257_y2: std_logic;
	signal s_74hc670_1_q: std_logic_vector(3 downto 0);
	signal s_74hc670_2_q: std_logic_vector(3 downto 0);
	signal s_74hc138_y: std_logic_vector(7 downto 0);
	signal s_74hc139_y1: std_logic_vector(3 downto 0);
	signal s_74hc139_y2: std_logic_vector(3 downto 0);
	signal s_74hc373_q: std_logic_vector(7 downto 0);
	
begin
	
   LEDG <= s_74hc670_2_q(3 downto 1) & s_74hc138_y(0) & "0000";
   LEDR <= s_74hc139_y2(0) & '1' & s_74hc373_q;
	
	WAIT_n <= 'Z';
	
	-- Memory Mapper - 256KB using DE1 SRAM Lower Bytes only
	-- LEDR <= A(9 downto 0) when s_74hc138_y(0) = '0';
	-- s_mapper_en <= '1' when (SLTSL_n = '0' and s_cart_en ='0') else '0';
	SRAM_WE_N <= WR_n;
	SRAM_DQ(7 downto 0) <= D when A(0) = '0' and WR_n = '0' and s_74hc138_y(0) = '0' else (others => 'Z');
	SRAM_DQ(15 downto 8) <= D when A(0) = '1' and WR_n = '0' and s_74hc138_y(0) = '0' else (others => 'Z');
	SRAM_ADDR <= s_74hc670_1_q(3 downto 0) & A(13 downto 0);	
	SRAM_UB_N <= not A(0);						
	SRAM_LB_N <= A(0);								
	SRAM_CE_N <= s_74hc138_y(0); -- when s_mapper_en = '1' else '1';								
	SRAM_OE_N <= RD_n;								
	
	D <= s_74hc373_q when s_74hc139_y2(0) = '0' else
	     -- SRAM_DQ(7 downto 0)  when A(0) = '0' and RD_n = '0' and s_74hc138_y(0) = '0' else
		  -- SRAM_DQ(15 downto 8) when A(0) = '1' and RD_n = '0' and s_74hc138_y(0) = '0' else
       (others => 'Z'); 
	 	 
   -- Display the current Memory Address in the 7 segment display
   NUMBER0 <= s_reg56(3 downto 0);
   NUMBER1 <= s_reg56(7 downto 4);
   NUMBER2 <= s_msx_a(3 downto 0);
   NUMBER3 <= s_msx_a(7 downto 4);
  
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
   
   i_74HC30 : C_74HC30 Port Map (D => "11" & A(7 downto 2), Y => s_74hc30_y);
	i_74HC138 : C_74HC138 Port Map (A => s_74hc670_2_q(3 downto 1), E1_n => SLTSL_n, E2_n => SLTSL_n, E3 => '1', Y => s_74HC138_Y);
	i_74HC139 : C_74HC139 Port Map (E1=> s_74hc30_y, E2=> s_74hc30_y, A1 => IORQ_n & WR_n, A2 => IORQ_n & RD_n,Y1 => s_74hc139_y1, Y2 => s_74hc139_y2); 
	i_74HC257 : C_74HC257 Port Map (S => s_74hc139_y2(0), OE_n => '0', I1 => A(0) & A(14), I2 => A(1) & A(15), i3 => "00", I4 => "00", Y1 => s_74hc257_y1, Y2 => s_74hc257_y2, Y3 => open, Y4 => open);
   i_74HC373WM : C_74HC373WM Port Map (LE => '1', OE_n => s_74hc139_y2(0), D => s_74hc670_2_q & s_74hc670_1_q, Q => s_74hc373_q);
   i1_74HC670D : C_74HC670D Port Map (D => s_msx_d(3 downto 0), Q => s_74hc670_1_q, RA => s_74hc257_y1, RB => s_74hc257_y2, WA => A(0), WB => A(1), WE_n => s_74hc139_y1(0), RE_n => '0');
	i2_74HC670D : C_74HC670D Port Map (D => s_msx_d(7 downto 4), Q => s_74hc670_2_q, RA => s_74hc257_y1, RB => s_74hc257_y2, WA => A(0), WB => A(1), WE_n => s_74hc139_y1(0), RE_n => '0');
 
   SD_DAT		<= 'Z';
   I2C_SDAT		<= 'Z';
   AUD_ADCLRCK	<= 'Z';
   AUD_DACLRCK	<= 'Z';
   AUD_BCLK		<= 'Z';
   DRAM_DQ		<= (others => 'Z');
   FL_DQ			<= (others => 'Z');
   SRAM_DQ		<= (others => 'Z');
   GPIO_0		<= (others => 'Z');
	 
	HEX0 <= HEX_DISP0;
	HEX1 <= HEX_DISP1;
	HEX2 <= HEX_DISP2;
	HEX3 <= HEX_DISP3;
	 	
end rtl;

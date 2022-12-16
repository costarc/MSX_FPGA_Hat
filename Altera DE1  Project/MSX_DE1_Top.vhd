library ieee ;
use ieee.std_logic_1164.all; 

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

signal Seven_Segment0 : std_logic_vector(6 downto 0);
signal Seven_Segment1 : std_logic_vector(6 downto 0);
signal Seven_Segment2 : std_logic_vector(6 downto 0);
signal Seven_Segment3 : std_logic_vector(6 downto 0);

signal BCDin0 : std_logic_vector(3 downto 0);
signal BCDin1 : std_logic_vector(3 downto 0);
signal BCDin2 : std_logic_vector(3 downto 0);
signal BCDin3 : std_logic_vector(3 downto 0);

signal msx_a : std_logic_vector(15 downto 0);
signal msx_d : std_logic_vector(7 downto 0);

begin

msx_d <= D when A(7 downto 0) = x"94" and WR_n = '0' and RD_n = '1' and IORQ_n = '0';
D <= msx_d when A(7 downto 0) = x"94" and WR_n = '1' and RD_n = '0' and  IORQ_n = '0' else
     KEY & "1111" when A(7 downto 0) = x"95" and WR_n = '1' and RD_n = '0' and  IORQ_n = '0' else "ZZZZZZZZ";

msx_a <= A when A > x"9500" AND A < x"9FFF";

HEX0 <= Seven_Segment0;
HEX1 <= Seven_Segment1;
HEX2 <= Seven_Segment2;
HEX3 <= Seven_Segment3;

BCDin0 <= msx_a(3 downto 0);
BCDin1 <= msx_a(7 downto 4);
BCDin2 <= msx_a(11 downto 8);
BCDin3 <= msx_a(15 downto 12);

LEDG <= msx_d;
LEDR <= SLTSL_n & IORQ_n & msx_d;

SD_DAT		<= 'Z';
I2C_SDAT		<= 'Z';
AUD_ADCLRCK	<= 'Z';
AUD_DACLRCK	<= 'Z';
AUD_BCLK		<= 'Z';
DRAM_DQ		<= (others => 'Z');
FL_DQ			<= (others => 'Z');
SRAM_DQ		<= (others => 'Z');
GPIO_0		<= (others => 'Z');

-- MSX Interfacing starts here
D				<= (others => 'Z');
WAIT_n		<= 'Z';
INT_n			<= 'Z';
BUSDIR_n		<= 'Z';

-- 7SEG using Combinatinal Logic
-- A <= B0 OR B2 OR (B1 AND B3) OR (NOT B1 AND NOT B3);
-- B <= (NOT B1) OR (NOT B2 AND NOT B3) OR (B2 AND B3);
-- C <= B1 OR NOT B2 OR B3;
-- D <= (NOT B1 AND NOT B3) OR (B2 AND NOT B3) OR (B1 AND NOT B2 AND B3) OR (NOT B1 AND B2) OR B0;
-- E <= (NOT B1 AND NOT B3) OR (B2 AND NOT B3);
-- F <= B0 OR (NOT B2 AND NOT B3) OR (B1 AND NOT B2) OR (B1 AND NOT B3);
-- G <= B0 OR (B1 AND NOT B2) OR ( NOT B1 AND B2) OR (B2 AND NOT B3);


process(BCDin0)
begin
 
case BCDin0 is
when "0000" =>
	Seven_Segment0 <= "0000001"; -- 0
when "0001" =>
	Seven_Segment0 <= "1001111"; -- 1
when "0010" =>
	Seven_Segment0 <= "0010010"; -- 2
when "0011" =>
	Seven_Segment0 <= "0000110"; -- 3
when "0100" =>
	Seven_Segment0 <= "1001100"; -- 4
when "0101" =>
	Seven_Segment0 <= "0100100"; -- 5
when "0110" =>
	Seven_Segment0 <= "0100000"; -- 6
when "0111" =>
	Seven_Segment0 <= "0001111"; -- 7
when "1000" =>
	Seven_Segment0 <= "0000000"; -- 8
when "1001" =>
	Seven_Segment0 <= "0000100"; -- 9
when others =>
	Seven_Segment0 <= "1111111"; -- null
end case;
end process;

process(BCDin1)
begin
 
case BCDin1 is
when "0000" =>
	Seven_Segment1 <= "0000001"; -- 0
when "0001" =>
	Seven_Segment1 <= "1001111"; -- 1
when "0010" =>
	Seven_Segment1 <= "0010010"; -- 2
when "0011" =>
	Seven_Segment1 <= "0000110"; -- 3
when "0100" =>
	Seven_Segment1 <= "1001100"; -- 4
when "0101" =>
	Seven_Segment1 <= "0100100"; -- 5
when "0110" =>
	Seven_Segment1 <= "0100000"; -- 6
when "0111" =>
	Seven_Segment1 <= "0001111"; -- 7
when "1000" =>
	Seven_Segment1 <= "0000000"; -- 8
when "1001" =>
	Seven_Segment1 <= "0000100"; -- 9
when others =>
	Seven_Segment1 <= "1111111"; -- null
end case;
end process;

process(BCDin2)
begin
 
case BCDin2 is
when "0000" =>
	Seven_Segment2 <= "0000001"; -- 0
when "0001" =>
	Seven_Segment2 <= "1001111"; -- 1
when "0010" =>
	Seven_Segment2 <= "0010010"; -- 2
when "0011" =>
	Seven_Segment2 <= "0000110"; -- 3
when "0100" =>
	Seven_Segment2 <= "1001100"; -- 4
when "0101" =>
	Seven_Segment2 <= "0100100"; -- 5
when "0110" =>
	Seven_Segment2 <= "0100000"; -- 6
when "0111" =>
	Seven_Segment2 <= "0001111"; -- 7
when "1000" =>
	Seven_Segment2 <= "0000000"; -- 8
when "1001" =>
	Seven_Segment2 <= "0000100"; -- 9
when others =>
	Seven_Segment2 <= "1111111"; -- null
end case;
end process;

process(BCDin3)
begin
 
case BCDin2 is
when "0000" =>
	Seven_Segment3 <= "0000001"; -- 0
when "0001" =>
	Seven_Segment3 <= "1001111"; -- 1
when "0010" =>
	Seven_Segment3 <= "0010010"; -- 2
when "0011" =>
	Seven_Segment3 <= "0000110"; -- 3
when "0100" =>
	Seven_Segment3 <= "1001100"; -- 4
when "0101" =>
	Seven_Segment3 <= "0100100"; -- 5
when "0110" =>
	Seven_Segment3 <= "0100000"; -- 6
when "0111" =>
	Seven_Segment3 <= "0001111"; -- 7
when "1000" =>
	Seven_Segment3 <= "0000000"; -- 8
when "1001" =>
	Seven_Segment3 <= "0000100"; -- 9
when others =>
	Seven_Segment3 <= "1111111"; -- null
end case;
end process;

end rtl;

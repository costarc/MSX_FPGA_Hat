-- --------------------------------------------------------------------------------------
-- MSX_DE0/DE1 FPGA Interface
-- --------------------------------------------------------------------------------------
-- MIT License
-- 
-- Copyright (c) 2024 Ronivon Costa
-- 
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
-- 
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
-- 
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
-- --------------------------------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;

Entity MegaROM_Top is
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
    SD_DAT3:		inout std_logic;						--	SD Card Data 3
    SD_CMD:			inout std_logic;							--	SD Card Command Signal
    SD_CLK:			out std_logic;								--	SD Card Clock
    							
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
                    
    GPIO_0:			inout std_logic_vector(35 downto 0);--	GPIO Connection 0
    
    -- MSX Bus
    A:					in std_logic_vector(15 downto 0);
    D:					inout std_logic_vector(7 downto 0);
    RD_n:				in std_logic;
    WR_n:				in std_logic;
    MREQ_n:			in std_logic;
    IORQ_n:			in std_logic;
    SLTSL_n:			in std_logic;
    U1OE_n:			out std_logic;
    CS_n:			in std_logic;
    BUSDIR_n:		out std_logic;
    M1_n:				in std_logic;
    INT_n:			out std_logic;
    RESET_n:			in std_logic;
    WAIT_n:			out std_logic); 
end MegaROM_Top;

architecture bevioural of MegaROM_Top is
	
	
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
	signal s_wait_n		: std_logic := '1';
	signal s_int_n			: std_logic := '1';
	
	-- signals for cartridge emulation
	signal s_sltsl_en		: std_logic;
	signal s_mreq			: std_logic;
	signal s_rom_a			: std_logic_vector(23 downto 0);
	
	-- Flash ASCII16
	signal rom_bank_wr_s	: std_logic;
	signal rom_bank1_q	: std_logic_vector(7 downto 0);
	signal rom_bank2_q	: std_logic_vector(7 downto 0);
	
	signal s_flashbase	: std_logic_vector(23 downto 0);
	
begin
  
-- --------------------------------Common Signals & assertions ------------------------------------------
	-- Cartridge Emulation using FlashRAM
	
	LEDG(7 downto 0) <= s_reset & s_sltsl_en & "000000";

	-- Reset circuit
	-- The process implements a "pull-up" to WAIT_n signal to avoid it floating
    -- during a reset, which causes teh computer to freeze
	s_reset 	<= not (KEY(0) and RESET_n);
	WAIT_n 	<= s_wait_n;
	INT_n  	<= s_int_n;
	BUSDIR_n <= 'Z';
	
	s_sltsl_en	<= '1' when SLTSL_n = '0' and SW(9) ='1' else '0';	-- 1 when this slot is selected
	s_mreq		<= '1' when RD_n = '0' and  MREQ_n = '0' else '0';
	
	U1OE_n 		<= not (s_sltsl_en); -- Enable BUS in U1 at the interface
													
	D <= FL_DQ(7 downto 0) when s_sltsl_en = '1' and s_mreq = '1' else	-- MSX reads data from FLASH RAM - Emulation of Cartridges
		  (others => 'Z'); 
		  
	FL_WE_N <= '1';
	FL_RST_N <= not s_reset;
	FL_CE_N <= not s_sltsl_en;
	FL_OE_N <= RD_n;
	
	-- Checks address being access. Mirrors memory as per information in https://www.msx.org/wiki/MegaROM_Mappers#ASCII16_.28ASCII.29
	s_rom_a(23 downto 0) <= s_flashbase + (rom_bank1_q(7 downto 0) & A(13 downto 0)) when s_sltsl_en = '1' and (A(15 downto 14) = "01" or A(15 downto 14) = "11") else		-- Bank1
                           s_flashbase + (rom_bank2_q(7 downto 0) & A(13 downto 0)) when s_sltsl_en = '1' and (A(15 downto 14) = "10" or A(15 downto 14) = "00") else		-- Bank2:
	                        (others => '-');
	
	-- The FLASHRAM is shared with other cores. This register allows to define a specific address in the flash
	-- where the roms for this cores is written.
	-- ROMs for this core starts at postion 0x0000 and each ROM has 256KB
	s_flashbase <= x"020000" when SW(0) = '1' else
	               x"01FFFF" when SW(1) = '1' else
						x"010000" when SW(2) = '1' else
						x"000000";

	D <= FL_DQ(7 downto 0) when s_sltsl_en = '1' and s_mreq = '1' else  -- MSX reads data from FLASH RAM - Emulation of Cartridges
         (others => 'Z');

	rom_bank_wr_s <= '1' when s_sltsl_en = '1' and WR_n = '0' and ((A >= x"6000" and A <= x"67FF") OR (A >= x"7000" and A <= x"77FF")) else  '0';
	
	process (s_reset, rom_bank_wr_s)
	begin
		if s_reset = '1' then
			rom_bank1_q		<= (others => '0');
			rom_bank2_q		<= (others => '0');
		elsif falling_edge(rom_bank_wr_s) then
			case A(12) is
				when '0'   =>
					rom_bank1_q		<= D;
				when '1'   =>
					rom_bank2_q		<= D;
				when others =>
					null;
			end case;
		end if;
	end process;
	
	HEXDIGIT0 <= s_rom_a(3 downto 0) when A >= x"4000" and A < x"C000";
	HEXDIGIT1 <= s_rom_a(7 downto 4) when A >= x"4000" and A < x"C000";
	HEXDIGIT2 <= s_rom_a(11 downto 8) when A >= x"4000" and A < x"C000";
	HEXDIGIT3 <= s_rom_a(15 downto 12) when A >= x"4000" and A < x"C000";
	
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
	
-- --------------------------------------- DE0 Only -----------------------------------------------------
	--FL_DQ15_AM1 <= s_rom_a(0);			-- input for the LSB (A-1) address function for the flash in Byte mode
	--FL_ADDR 	<= s_rom_a(22 downto 1);
	--
	--FL_BYTE_N 	<= '0';    				-- Set flashram to Byte mode
	--FL_WP_N 	<= '0';	
	--SD_DAT		<= 'Z';
	--DRAM_DQ		<= (others => 'Z');
	--SRAM_DQ		<= (others => 'Z');

-- --------------------------------------- DE1 Only -----------------------------------------------------
	FL_ADDR 	<= s_rom_a(21 downto 0);
   SD_DAT		<= 'Z';
   I2C_SDAT	<= 'Z';
   AUD_ADCLRCK<= 'Z';
   AUD_DACLRCK<= 'Z';
   AUD_BCLK	<= 'Z';
   DRAM_DQ		<= (others => 'Z');
   FL_DQ		<= (others => 'Z');
   SRAM_DQ		<= (others => 'Z');
   GPIO_0		<= (others => 'Z');
	 
-- ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
	
end bevioural;

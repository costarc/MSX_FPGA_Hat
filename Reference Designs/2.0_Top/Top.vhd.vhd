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

Entity Top is
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

    SD_MISO:        inout std_logic;               --  MISO    -  SD_DAT  - SD Card Data
    SD_CS:          inout std_logic;               --  CS      -  SD_DAT3 - SD Card Data 3
    SD_MOSI:        inout std_logic;               --  MOSI    -  SD_CMD  - SD Card Command Signal
    SD_CLK:         out std_logic;                 --  CLOCK   -  SD_CLK  - SD Card Clock
    SD_WP_N:        in std_logic;                  --  SD Card - Write Protect
     
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
    							
	-- Interface control signals
	U1_DIR:			    out std_logic;
	U1_OE_n:			out std_logic;
	U2_OE_n:			out std_logic;
	U3_OE_n:			out std_logic;
	U4_OE_n:			out std_logic;
	AudioOut			out std_logic;
	-- MSX Bus signals
    pA:                 in std_logic_vector(7 downto 0);
    pD:					inout std_logic_vector(7 downto 0);
    pRD_n:				in std_logic;
    pWR_n:				in std_logic;
    pMREQ_n:            in std_logic;
    pIORQ_n:            in std_logic;
    pSLTSL_n:			in std_logic;
    pCS1_n:				in std_logic;
	pCS2_n:				in std_logic;
    pBUSDIR_n:			out std_logic;
    pM1_n:				in std_logic;
    pINT_n:				out std_logic;
    pRESET_n:			in std_logic;
    pWAIT_n:            out std_logic;
	pCLOCK				in std_logic;
	pSOUND              out std_logic); 
end Top;

architecture behavioural of Top is
	
	component decoder_7seg
	port (
		NUMBER		        : in   std_logic_vector(3 downto 0);
		HEX_DISP	        : out  std_logic_vector(6 downto 0));
	end component;
	
	signal HEXDIGIT0		: std_logic_vector(3 downto 0);
	signal HEXDIGIT1		: std_logic_vector(3 downto 0);
	signal HEXDIGIT2		: std_logic_vector(3 downto 0);
	signal HEXDIGIT3		: std_logic_vector(3 downto 0);
	
	signal s_reset			: std_logic := '0';
	signal s_wait_n		    : std_logic := '1';
	signal s_int_n			: std_logic := '1';
	
	-- signals for cartridge emulation
	signal s_sltsl_en		: std_logic;
	signal s_mreq			: std_logic;
	signal s_rom_a			: std_logic_vector(23 downto 0);
	
	-- Flash ASCII16
	signal rom_bank_wr_s	: std_logic;
	signal rom_bank1_q	    : std_logic_vector(7 downto 0);
	signal rom_bank2_q	    : std_logic_vector(7 downto 0);
	
	signal s_flashbase	: std_logic_vector(23 downto 0);

    -- MSX BUS Signals - to be used in the designs since they are demultiplexed
	signal busDemuxState    : std_logic := "00";
	signal busDataType      : std_logic := '0';
	signal U2_en            : std_logic := '1';
	signal U3_en            : std_logic := '0';
    signal A                : std_logic;
    signal D                : std_logic;
    signal RD_n             : std_logic;
    signal WR_n             : std_logic;
    signal MREQ_n           : std_logic;
    signal IORQ_n           : std_logic;
    signal SLTSL_n          : std_logic
    signal CS1_n            : std_logic;
	signal CS2_n            : std_logic;
    signal BUSDIR_n         : std_logic;
    signal M1_n             : std_logic;
    signal INT_n            : std_logic;
    signal RESET_n          : std_logic;
    signal WAIT_n           : std_logic;
	signal CLOCK            : std_logic;
	
begin
  
-- --------------------------------Common Signals & assertions ------------------------------------------
	
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
	
	
--------------------------------- Common design to demux the MSX Bus  -----------------------------------------

U2_OE_n <= not U2_en;
U3_OE_n <= not U3_en;

process (pCLOCK, pRESET_n, busMuxReady)
begin
    if pRESET_n = '0' then
	    busDemuxState <= "00";
		U2_en <= '1';
		U3_en <= '0';
    elsif rising_edge(pCLOCK) then
		if pSLTSL_n = '0' then 
			if busDemuxState = "00" then
			    busDemuxState <= "01";
	            U2_en <= '1';
	            U3_en <= '0';
			elsif busDemuxState = "01" then
			    busDemuxState <= "10";
	            U2_en <= '0';
	            U3_en <= '1';
			else 
			    busDemuxState <= "00";
	            U2_en <= '1';
	            U3_en <= '0';			
			end if;
        end if;
	end if;
end process;

process (busDemuxState)
begin
    if pRESET_n = '0' then
        busMuxReady <= '0';
    	RESET_n <= '0';
    elsif busDemuxState = "01" then
        A(7 downto 0) <= pA;
    	RD_n     <= pRD_n;
    	WR_n     <= pWR_n;
    	MREQ_n   <= pMREQ_n;
    	IORQ_n   <= pIORQ_n;
    	SLTSL_n  <= pSLTSL_n;
    	CS1_n    <= pCS1_n;
    	CS2_n    <= pCS2_n;
    	M1_n     <= pM1_n;
    	RESET_n  <= pRESET_n;
    	CLOCK    <= pCLOCK;
    elsif busDemuxState = "10" then
        A(15 downto 8) <= pA;
		busMuxReady <= '1';
    end if;
end process

-- --------------------------------------- DE0 - Use this -----------------------------------------------------
	FL_DQ15_AM1 <= s_rom_a(0);			-- input for the LSB (A-1) address function for the flash in Byte mode
	FL_ADDR     <= s_rom_a(22 downto 1);
	
	FL_BYTE_N 	<= '0';    				-- Set flashram to Byte mode
	FL_WP_N     <= '0';	
	DRAM_DQ		<= (others => 'Z');
	SRAM_DQ		<= (others => 'Z');

-- --------------------------------------- DE1 - Use this -----------------------------------------------------
    --FL_ADDR 	<= s_rom_a(21 downto 0);
    --SD_DAT		<= 'Z';
    --I2C_SDAT	<= 'Z';
    --AUD_ADCLRCK<= 'Z';
    --AUD_DACLRCK<= 'Z';
    --AUD_BCLK	<= 'Z';
    --DRAM_DQ		<= (others => 'Z');
    --FL_DQ		<= (others => 'Z');
    --SRAM_DQ		<= (others => 'Z');
    --GPIO_0		<= (others => 'Z');
    -- ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
	
end behavioural;

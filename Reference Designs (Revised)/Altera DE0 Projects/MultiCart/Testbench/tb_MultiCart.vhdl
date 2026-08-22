library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_MultiCart is
end tb_MultiCart;

architecture Behavioral of tb_MultiCart is

    -- Constants
    constant CLOCK_PERIOD_50 : time := 20 ns; -- 50 MHz clock

    -- DUT signals
    signal CLOCK_50, CLOCK_50_2 : std_logic := '0';
    signal KEY                 : std_logic_vector(2 downto 0) := (others => '0');
    signal SW                  : std_logic_vector(9 downto 0) := (others => '0');
    signal HEX0, HEX1, HEX2, HEX3 : std_logic_vector(6 downto 0);
    signal HEX0_DP, HEX1_DP, HEX2_DP, HEX3_DP : std_logic;
    signal LEDG                : std_logic_vector(9 downto 0);
    signal UART_TXD            : std_logic;
    signal UART_RXD            : std_logic := '1';
    signal UART_CTS            : std_logic;
    signal UART_RTS            : std_logic := '1';
    signal DRAM_DQ             : std_logic_vector(15 downto 0);
    signal DRAM_ADDR           : std_logic_vector(12 downto 0);
    signal DRAM_LDQM, DRAM_UDQM, DRAM_WE_N, DRAM_CAS_N, DRAM_RAS_N, DRAM_CS_N : std_logic;
    signal DRAM_BA_0, DRAM_BA_1, DRAM_CLK, DRAM_CKE : std_logic;
    signal FL_DQ               : std_logic_vector(14 downto 0);
    signal FL_DQ15_AM1         : std_logic;
    signal FL_ADDR             : std_logic_vector(21 downto 0);
    signal FL_WE_N, FL_RST_N, FL_OE_N, FL_CE_N, FL_WP_N, FL_BYTE_N, FL_RY : std_logic;
    signal LCD_DATA            : std_logic_vector(7 downto 0);
    signal LCD_BLON, LCD_RW, LCD_EN, LCD_RS : std_logic;
    signal SD_CS, SD_CLK, SD_MISO, SD_MOSI, SD_WP_N : std_logic;
    signal PS2_KBDAT, PS2_KBCLK, PS2_MSDAT, PS2_MSCLK : std_logic;
    signal VGA_HS, VGA_VS : std_logic;
    signal VGA_R, VGA_G, VGA_B : std_logic_vector(3 downto 0);
    signal SRAM_DQ             : std_logic_vector(7 downto 0);
    signal SRAM_ADDR           : std_logic_vector(17 downto 0);
    signal SRAM_UB_N, SRAM_LB_N, SRAM_WE_N, SRAM_CE_N, SRAM_OE_N : std_logic;
    signal GPIO0_P1, GPIO0_P3, GPIO0_P21 : std_logic := '0';
    signal GPIO0_P22, GPIO0_P24 : std_logic := 'Z';
    signal U1_DIR, U1_OE_n, U2_OE_n, U3_OE_n, U4_OE_n, AUDIO, SOUND : std_logic;
    signal A0_8, A1_9, A2_10, A3_11, A4_12, A5_13, A6_14, A7_15 : std_logic := '0';
    signal D                   : std_logic_vector(7 downto 0) := (others => 'Z');
    signal RD_n, WR_n, MREQ_n, IORQ_n, SLTSL_n, CS1_n, CS2_n : std_logic := '1';
    signal BUSDIR_n, M1_n, INT_n, RESET_n, WAIT_n, MSXCLK : std_logic := '1';

    -- Component instantiation
    component MultiCart
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
	MSXCLK:			in std_logic
        );
    end component;

begin

    -- DUT instantiation
    uut: MultiCart
        port map (
	CLOCK_50                         =>		CLOCK_50      , 
	CLOCK_50_2                         =>	CLOCK_50_2     ,	
					                        				
	KEY                         =>			KEY            ,
	SW                         =>			SW             	,
					                        				
	HEX0                         =>			HEX0           ,
	HEX1                         =>			HEX1           ,
	HEX2                         =>			HEX2           ,
	HEX3                         =>			HEX3           ,
	HEX0_DP                         =>		HEX0_DP        ,
	HEX1_DP                         =>		HEX1_DP        ,
	HEX2_DP                         =>		HEX2_DP        ,
	HEX3_DP                         =>		HEX3_DP        ,
					                        				
	LEDG                         =>			LEDG           ,
					                        				
	UART_TXD                         =>		UART_TXD       ,
	UART_RXD                         =>		UART_RXD       ,
	UART_CTS                         =>		UART_CTS       ,
	UART_RTS                         =>		UART_RTS       ,
				                            			 
	DRAM_DQ                         =>		DRAM_DQ        ,
	DRAM_ADDR                         =>	DRAM_ADDR      	,
	DRAM_LDQM                         =>	DRAM_LDQM      	,
	DRAM_UDQM                         =>	DRAM_UDQM      	,
	DRAM_WE_N                         =>	DRAM_WE_N      	,
	DRAM_CAS_N                         =>	DRAM_CAS_N     	,
	DRAM_RAS_N                         =>	DRAM_RAS_N     	,
	DRAM_CS_N                         =>	DRAM_CS_N      	,
	DRAM_BA_0                         =>	DRAM_BA_0      	,
	DRAM_BA_1                         =>	DRAM_BA_1      	,
	DRAM_CLK                         =>		DRAM_CLK       ,
	DRAM_CKE                         =>		DRAM_CKE       ,
					                        				
	FL_DQ                         =>		FL_DQ          	,
	FL_DQ15_AM1                         =>	FL_DQ15_AM1    ,
	FL_ADDR                         =>		FL_ADDR        ,
	FL_WE_N                         =>		FL_WE_N        ,
	FL_RST_N                         =>		FL_RST_N       ,
	FL_OE_N                         =>		FL_OE_N        ,
	FL_CE_N                         =>		FL_CE_N        ,
	FL_WP_N                         =>		FL_WP_N        ,
	FL_BYTE_N                         =>	FL_BYTE_N      	,
	FL_RY                         =>		FL_RY          	,
	                                           
	LCD_DATA                         =>		LCD_DATA       ,
	LCD_BLON                         =>		LCD_BLON       ,
	LCD_RW                         =>		LCD_RW         	,
	LCD_EN                         =>		LCD_EN         	,
	LCD_RS                         =>		LCD_RS         	,
					                        				
	SD_CS                         =>		SD_CS          	,
	SD_CLK                         =>		SD_CLK         	,
	SD_MISO                         =>		SD_MISO        ,
	SD_MOSI                         =>		SD_MOSI        ,
	SD_WP_N                         =>		SD_WP_N        ,
					                        				
	PS2_KBDAT                         =>	PS2_KBDAT      	,
	PS2_KBCLK                         =>	PS2_KBCLK      	,
	PS2_MSDAT                         =>	PS2_MSDAT      	,
	PS2_MSCLK                         =>	PS2_MSCLK      	,
					                        				
	VGA_HS                         =>		VGA_HS         	,
	VGA_VS                         =>		VGA_VS         	,
	VGA_R                         =>		VGA_R          	,
	VGA_G                         =>		VGA_G          	,
	VGA_B                         =>		VGA_B          	,
	                                        
	SRAM_DQ                         =>		SRAM_DQ        ,
	SRAM_ADDR                         =>	SRAM_ADDR      	,
	SRAM_UB_N                         =>	SRAM_UB_N      	,
	SRAM_LB_N                         =>	SRAM_LB_N      	,
	SRAM_WE_N                         =>	SRAM_WE_N      	,
	SRAM_CE_N                         =>	SRAM_CE_N      	,
	SRAM_OE_N                         =>	SRAM_OE_N      	,
	                                        
	GPIO0_P1                         =>		GPIO0_P1       ,
	GPIO0_P3                         =>		GPIO0_P3       ,
	GPIO0_P21                         =>	GPIO0_P21      	,
	GPIO0_P22                         =>	GPIO0_P22      	,
	GPIO0_P24                         =>	GPIO0_P24      	,
	                                         
	U1_DIR                         =>		U1_DIR         	,
	U1_OE_n                         =>		U1_OE_n        ,
	U2_OE_n                         =>		U2_OE_n        ,
	U3_OE_n                         =>		U3_OE_n        ,
	U4_OE_n                         =>		U4_OE_n        ,
	AUDIO                         =>		AUDIO          	,
	SOUND                         =>		SOUND          	,
	                                        
	A0_8                         =>			A0_8           ,
	A1_9                         =>			A1_9           ,
	A2_10                         =>		A2_10          	,
	A3_11                         =>		A3_11          	,
	A4_12                         =>		A4_12          	,
	A5_13                         =>		A5_13          	,
	A6_14                         =>		A6_14          	,
	A7_15                         =>		A7_15          	,
	D                         =>			D              	,
	RD_n                         =>			RD_n           ,
	WR_n                         =>			WR_n           ,
	MREQ_n                         =>		MREQ_n         	,
	IORQ_n                         =>		IORQ_n         	,
	SLTSL_n                         =>		SLTSL_n        ,
	CS1_n                         =>		CS1_n          	,
	CS2_n                         =>		CS2_n          	,
	BUSDIR_n                         =>		BUSDIR_n       ,
	M1_n                         =>			M1_n           ,
	INT_n                         =>		INT_n          	,
	RESET_n                         =>		RESET_n        ,
	WAIT_n                         =>		WAIT_n         	,
	MSXCLK                         =>		MSXCLK         	
        );

    -- Clock generation
    CLOCK_GEN_50: process
    begin
        while true loop
            CLOCK_50 <= '0';
            wait for CLOCK_PERIOD_50 / 2;
            CLOCK_50 <= '1';
            wait for CLOCK_PERIOD_50 / 2;
        end loop;
    end process;

    -- Test stimulus
    stimulus: process
    begin
        -- Reset the system
        SW <= "0000000000";
		SLTSL_n <= '1';
        wait for CLOCK_PERIOD_50 * 10;

        -- Enable the MultiCart feature
		SLTSL_n <= '0';
        SW(9) <= '1'; -- Enable MultiCart
        wait for CLOCK_PERIOD_50 * 10;

        -- Complete simulation
        wait for CLOCK_PERIOD_50 * 200;
        report "Simulation completed" severity failure;
    end process;

end Behavioral;

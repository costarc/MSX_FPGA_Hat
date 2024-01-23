library ieee ;
use ieee.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;

Entity MSX_FPGA_Top is
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
    FL_ADDR:		out std_logic_vector(21 downto 0);	--	FLASH Address bus 22 Bits
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
	 
    -- MSX Bus
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
end MSX_FPGA_Top;

architecture behavioural of MSX_FPGA_Top is
	component FlashRAM
	port (
		-- Flash core signals
		en:				in std_logic := '0'; 					-- default is disabled
		reset:			in std_logic;								-- reset enable High / "1"
		rw:				in std_logic := '0'; 					-- default is read
		d_bus:			inout	std_logic_vector(7 downto 0);
		a_bus:			in std_logic_vector(23 downto 0);
		-- FLASH physical signals
		FL_DQ:			inout std_logic_vector(14 downto 0);--	FLASH Data bus 15 Bits
		FL_DQ15_AM1:	inout std_logic;							--	FLASH Data bus Bit 15 or Address A-1
		FL_ADDR:			out std_logic_vector(21 downto 0);	--	FLASH Address bus 22 Bits
		FL_WE_N:			out std_logic;								--	FLASH Write Enable
		FL_RST_N:		out std_logic;								--	FLASH Reset
		FL_OE_N:			out std_logic;								--	FLASH Output Enable
		FL_CE_N:			out std_logic;								--	FLASH Chip Enable
		FL_WP_N:			out std_logic;								--	FLASH Hardware Write Protect
		FL_BYTE_N:		out std_logic;								--	FLASH Selects 8/16-bit mode
		FL_RY:			in std_logic);								--	FLASH Ready/Busy
	end component;
	
	component decoder_7seg
	port (
		NUMBER			: in   std_logic_vector(3 downto 0);
		HEX_DISP			: out  std_logic_vector(6 downto 0));
	end component;	
	
	component clk_slow 
	port (
		inclk0			: IN STD_LOGIC;
		c0					: OUT STD_LOGIC);
	end component;
	
	signal HEXDIGIT0	: std_logic_vector(3 downto 0);
	signal HEXDIGIT1	: std_logic_vector(3 downto 0);
	signal HEXDIGIT2	: std_logic_vector(3 downto 0);
	signal HEXDIGIT3	: std_logic_vector(3 downto 0);
	
	-- signals for clocked components
	signal s_msx_clk		: std_logic;
	signal s_msx_clk_div	: std_logic_vector(31 downto 0) := "00000000000000000000000000000001";
	signal s_msx_clk_div2: std_logic_vector(7 downto 0) := "00000001";
	signal s_rw				: std_logic;
	signal s_led_clk		: std_logic;
	signal s_reset			: std_logic := '0';
	signal s_wait_n		: std_logic := '1';
	signal s_int_n			: std_logic := '1';
	signal s_busdir_n		: std_logic := '1';
	signal s_sltsl_en		: std_logic;
	signal s_rom_en			: std_logic;
	signal s_rom_q			: std_logic_vector(7 downto 0);
	signal s_flashbase	: std_logic_vector(23 downto 0);	
	signal s_rom_a			: std_logic_vector(23 downto 0);
	
begin
	
	HEXDIGIT0 <= s_rom_a(3 downto 0) when A >= x"4000" and A < x"C000";
	HEXDIGIT1 <= s_rom_a(7 downto 4) when A >= x"4000" and A < x"C000";
	HEXDIGIT2 <= s_rom_a(11 downto 8) when A >= x"4000" and A < x"C000";
	HEXDIGIT3 <= s_rom_a(15 downto 12) when A >= x"4000" and A < x"C000";

	
	s_msx_clk <= RESET_n;    -- msx clock & reset signals shares same gpio - use DIP switch in the cart to select CLOCK signal
	s_reset <= not KEY(0);
	WAIT_n 	<= s_wait_n;
	INT_n  	<= s_int_n;
	BUSDIR_n <= 'Z';

	LEDG(9) <= SW(9);
	LEDG(8) <= s_reset;
	LEDG(7) <= s_sltsl_en;
	LEDG(6) <= s_rom_en;
	
	s_sltsl_en	<= '1' when SLTSL_n = '0' and SW(9) ='1' else '0';	-- 1 when this slot is selected
	U1OE_n 		<= not s_sltsl_en; -- Enable BUS in U1 at the interface
	
	-- Enable ROM access
	s_rom_a <= s_flashbase + (A - x"4000");
	s_flashbase <= x"1A0000" + (SW(5 downto 0) * x"2000"); -- Unbanked ROMS start at 0x1A0000. SW used to switch ROMs
	s_rw <= RD_n;
	process(s_msx_clk, s_sltsl_en, RD_n, MREQ_n)
	begin
		if rising_edge(s_msx_clk) then
			if RD_n = '0' and MREQ_n = '0' and s_sltsl_en = '1' then
				s_rom_en <= '1';
			else
				s_rom_en <= '0';
			end if;
		end if;
	end process;

	flash_inst: FlashRAM PORT MAP (
		en					=>	s_rom_en,
		reset				=>	s_reset,
		rw					=>	s_rw,
		d_bus				=>	D,
		a_bus				=>	s_rom_a,
		FL_DQ				=>	FL_DQ,
		FL_DQ15_AM1		=>	FL_DQ15_AM1,
		FL_ADDR			=>	FL_ADDR,
		FL_WE_N			=>	FL_WE_N,
		FL_RST_N			=>	FL_RST_N,
		FL_OE_N			=>	FL_OE_N,
		FL_CE_N			=>	FL_CE_N,
		FL_WP_N			=>	FL_WP_N,
		FL_BYTE_N		=>	FL_BYTE_N,
		FL_RY				=>	FL_RY
	);
	
	
	process(s_led_clk)
	variable ledg_reg : std_logic := '0';
	begin
		if rising_edge(s_led_clk) then
			s_msx_clk_div(31 downto 1) <= s_msx_clk_div(30 downto 0);
			if s_msx_clk_div(31) = '1' then
				s_msx_clk_div <= "00000000000000000000000000000001";
				s_msx_clk_div2(7 downto 1) <= s_msx_clk_div2(6 downto 0);
				if s_msx_clk_div2(7) = '1' then 
					s_msx_clk_div2 <= "00000001";
					ledg_reg := not ledg_reg;
				end if;
			end if;
		end if;
		
		LEDG(0) <= ledg_reg;
		
	end process;
	

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

	
	clk_slow_inst : clk_slow PORT MAP (
		inclk0	 => s_msx_clk,
		c0	 			=> s_led_clk
	);

	SD_DAT		<= 'Z';
	DRAM_DQ		<= (others => 'Z');	
	SRAM_DQ		<= (others => 'Z');
	SRAM_CE_N	<= '1';
	
end behavioural;

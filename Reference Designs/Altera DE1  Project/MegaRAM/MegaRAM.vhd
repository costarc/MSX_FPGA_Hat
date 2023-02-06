library ieee ;
use ieee.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;

Entity MegaRAM is
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
    CS2_n:			in std_logic;
    BUSDIR_n:		out std_logic;
    M1_n:				in std_logic;
    INT_n:			out std_logic;
    MSX_CLK:			in std_logic;
    WAIT_n:			out std_logic); 
end MegaRAM;

architecture bevioural of MegaRAM is
	
	component decoder_7seg
	port (
		NUMBER		: in   std_logic_vector(3 downto 0);
		HEX_DISP	: out  std_logic_vector(6 downto 0));
	end component;

	signal HEXDIGIT0		: std_logic_vector(3 downto 0);
	signal HEXDIGIT1		: std_logic_vector(3 downto 0);
	signal HEXDIGIT2		: std_logic_vector(3 downto 0);
	signal HEXDIGIT3		: std_logic_vector(3 downto 0);
	
	-- signals for cartridge emulation
	signal s_sltsl_en			: std_logic;
	signal s_busd_en			: std_logic;
	signal s_io_addr 			: std_logic_vector(7 downto 0);
	signal s_mgram4			: std_logic_vector(7 downto 0) := "00000000";
	signal s_mgram6			: std_logic_vector(7 downto 0) := "00000001";
	signal s_mgram8			: std_logic_vector(7 downto 0) := "00000010";
	signal s_mgrama			: std_logic_vector(7 downto 0) := "00000011";
	signal s_mreq				: std_logic;
	signal s_iorq_r			: std_logic;
	signal s_iorq_w			: std_logic;
	signal s_iorq_r_reg		: std_logic;
	signal s_iorq_w_reg		: std_logic;
	signal s_mapper_reg_w	: std_logic;
	
	signal s_SRAM_ADDR:	std_logic_vector(23 downto 0);	
	signal s_reset	: std_logic := '0';
	signal s_segment: std_logic_vector(20 downto 0);
	signal ffff				: std_logic;
	signal slt_exp_n		: std_logic_vector(3 downto 0);
	
	signal s_mgram_we		: std_logic;
	signal s_mgram_reg_en: std_logic;
	signal s_mgram_mem_en: std_logic;
	
begin

	s_reset	<= not KEY(0);
	LEDR		<= s_mgram_we & s_iorq_w & s_mgram4(1 downto 0) & s_mgram6(1 downto 0) & s_mgram8(1 downto 0) & s_mgrama(1 downto 0);
   LEDG		<= slt_exp_n & '0' & ffff & '0' & s_reset;
	
	-- Output signals to DE1
	INT_n			<= 'Z';
	WAIT_n		<= 'Z';

	BUSDIR_n <= not s_iorq_r;
		
	U1OE_n <= not (s_sltsl_en or s_iorq_r or s_iorq_w);
	
    -- Auxiliary Generic control signals
	s_iorq_r		<= '1' when A(7 downto 0) = x"8E" and RD_n = '0' and  IORQ_n = '0' and M1_n = '1' else '0';
	s_iorq_w		<= '1' when A(7 downto 0) = x"8E" and WR_n = '0' and  IORQ_n = '0' and M1_n = '1' else '0';
	s_mreq		<= '1' when RD_n = '0' and  MREQ_n = '0' else '0';
	s_sltsl_en	<= '1' when SLTSL_n = '0' and SW(9) ='1' else '0';
   
	-- Mapper implementation								
	SRAM_CE_N <= not s_sltsl_en;--slt_exp_n(0);								
	SRAM_OE_N <= '0';	
	SRAM_WE_N <= WR_n; --'0' when s_mgram_mem_en = '1' and Wr_n = '0' else '1';
	SRAM_ADDR <= s_SRAM_ADDR(17 downto 0);
	SRAM_UB_N <= not s_SRAM_ADDR(18);						
	SRAM_LB_N <= s_SRAM_ADDR(18);
	
	SRAM_DQ(7 downto 0)  <= D when s_SRAM_ADDR(18) = '0' and WR_n = '0' and s_mgram_we = '1' else (others => 'Z');
	SRAM_DQ(15 downto 8) <= D when s_SRAM_ADDR(18) = '1' and WR_n = '0' and s_mgram_we = '1' else (others => 'Z');
					 
	s_SRAM_ADDR <= (s_mgram4 * x"2000") + A - x"4000" when A < x"6000" else
						(s_mgram6 * x"2000") + A - x"6000" when A < x"8000" else
						(s_mgram8 * x"2000") + A - x"8000" when A < x"A000" else
						(s_mgrama * x"2000") + A - x"A000" when A < x"C000";
		
	D <= SRAM_DQ(7 downto 0)  when s_SRAM_ADDR(18) = '0' and RD_n = '0' and s_sltsl_en = '1' else
	     SRAM_DQ(15 downto 8) when s_SRAM_ADDR(18) = '1' and RD_n = '0' and s_sltsl_en = '1' else
		  (others => 'Z');
	
	-- Prepare MegaRAM for bank switching
	s_mgram_mem_en <= '1' when s_mgram_we = '1' and s_sltsl_en = '1' else '0';
	s_mgram_reg_en <= '1' when s_mgram_we = '0' and s_sltsl_en = '1' and Wr_n = '0' else '0';
	
	process (s_reset, s_iorq_w,s_iorq_r)
	begin
		if s_reset = '1' or s_iorq_w = '1' then
			s_mgram_we <= '0';								-- Disable Write-Access to Megaram / Enable Registry access
		elsif falling_edge(s_iorq_r) then	
			s_mgram_we <= '1';								-- Enable Write-access to MegaRAM
		end if;
	end process;
	
	process(s_mgram_reg_en,s_reset)
	begin
		if s_reset = '1' then
			s_mgram4 <= "00000000";
			s_mgram6 <= "00000001";
			s_mgram8 <= "00000010";
			s_mgrama <= "00000011";
		elsif falling_edge(s_mgram_reg_en) then
			case A is
				when x"4000" => s_mgram4 <= D;
				when x"6000" => s_mgram6 <= D;
				when x"8000" => s_mgram8 <= D;
				when x"A000" => s_mgrama <= D;
				when others => null;
			end case ;
		end if;
	end process;
	
	-- Display the current Memory Address in the 7 segment display
	HEXDIGIT0 <= s_mgram4(3 downto 0);
	HEXDIGIT1 <= s_mgram6(3 downto 0);
	HEXDIGIT2 <= s_mgram8(3 downto 0);
	HEXDIGIT3 <= s_mgrama(3 downto 0);
		
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
		
		SD_DAT		<= 'Z';
		I2C_SDAT	<= 'Z';
		AUD_ADCLRCK	<= 'Z';
		AUD_DACLRCK	<= 'Z';
		AUD_BCLK	<= 'Z';
		DRAM_DQ		<= (others => 'Z');
		FL_DQ		<= (others => 'Z');
		GPIO_0		<= (others => 'Z');
	
	ffff    <= '1' when A = x"FFFF" else '0';
	-- Expansor de slot
	exp: entity work.exp_slot
	port map (
		reset_n		=> not s_reset,
		sltsl_n		=> not s_sltsl_en,
		cpu_rd_n		=> RD_n,
		cpu_wr_n		=> WR_n,
		ffff			=> ffff,
		cpu_a			=> A(15 downto 14),
		cpu_d			=> D,
		exp_n			=> slt_exp_n
	);
	
end bevioural;

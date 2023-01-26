library ieee ;
use ieee.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;

Entity MSX_DE1_SDCard is
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
end MSX_DE1_SDCard;

architecture behavioral of MSX_DE1_SDCard is

	component decoder_7seg
	port (
		NUMBER		: in   std_logic_vector(3 downto 0);
		HEX_DISP		: out  std_logic_vector(6 downto 0));
	end component;

	signal HEXDIGIT0		: std_logic_vector(3 downto 0);
	signal HEXDIGIT1		: std_logic_vector(3 downto 0);
	signal HEXDIGIT2		: std_logic_vector(3 downto 0);
	signal HEXDIGIT3		: std_logic_vector(3 downto 0);
	
	signal s_wait_n		: std_logic;
	signal s_mreq			: std_logic;
	signal s_iorq_r		: std_logic;
	signal s_iorq_w		: std_logic;
	signal s_busd_en		: std_logic;
	signal s_iorq_r_reg	: std_logic;
	signal s_iorq_w_reg	: std_logic;
	signal s_io_cs			: std_logic;
	signal s_d_bus_out	: std_logic;
	signal s_reset			: std_logic := '0';
	signal s_reset2		: std_logic := '0';
	
	-- Regs
	signal regs_cs_s		: std_logic;

	-- SD Card
	signal s_sd_pres		: std_logic;		
	signal s_d_wprot		: std_logic;		
						
	signal s_sd_rd			: std_logic;
	signal s_sd_rd_m		: std_logic;		
	signal s_sd_q			: std_logic_vector(7 downto 0);
	signal s_sd_q_avail		: std_logic;		
	signal s_sd_q_taken		: std_logic;		
							
	signal s_sd_wr			: std_logic;
	signal s_sd_wr_m		: std_logic;		
	signal s_sd_d			: std_logic_vector(7 downto 0);
	signal s_sd_d_avail		: std_logic;		
	signal s_sd_d_taken		: std_logic;		
							
	signal s_sd_a			: std_logic_vector(31 downto 0);
	signal s_sd_count		: std_logic_vector(7 downto 0);		
							
	signal s_sd_error		: std_logic;		
	signal s_sd_busy		: std_logic;		
	signal s_sd_error_code	: std_logic_vector(2 downto 0);		
							
	signal s_sd_type		: std_logic_vector(1 downto 0);		
	signal s_sd_fsm			: std_logic_vector(7 downto 0);	

	signal s_reg56_a			: std_logic_vector(7 downto 0);
	signal s_reg56_d		: std_logic_vector(7 downto 0);
	
	-- debug signals
	signal s_iorq_r_sd_reg	: std_logic;
	signal s_iorq_r_sd_fsm	: std_logic;
	signal s_ledr_counter	: std_logic_vector(31 downto 0);
	
begin

	-- I/O Device Emulation
	s_iorq_r_reg <= '1' when A(7 downto 0) = x"56" and s_iorq_r = '1' else '0';
	s_iorq_w_reg <= '1' when A(7 downto 0) = x"56" and s_iorq_w = '1' else '0';
	s_iorq_r <= '1' when RD_n = '0' and  IORQ_n = '0' and M1_n = '1' else '0';
	s_iorq_w <= '1' when WR_n = '0' and  IORQ_n = '0' and M1_n = '1' else '0';
	s_d_bus_out <= '1' when (s_iorq_r_reg = '1' or s_iorq_r_sd_fsm = '1' or s_iorq_r_sd_reg = '1') else
                  '0';
	BUSDIR_n <= '0' when s_d_bus_out = '1' else '0';
	INT_n  <= 'Z';	
	WAIT_n	<= 'Z';				 --	when wait_n_s = '1'	else '0';	
	--s_reset <= NOT KEY(0) and s_reset2;			-- Reset is KEY0
	
	-- Display the current Memory Address in the 7 segment display
	HEXDIGIT0 <= s_reg56_d(3 downto 0);
	HEXDIGIT1 <= s_reg56_d(7 downto 4);
	HEXDIGIT2 <= s_reg56_a(3 downto 0);
	HEXDIGIT3 <= s_reg56_a(7 downto 4);

-- -------------------------------------------------------------------
	-- Debug
	process(CLOCK_50)
	begin
		if s_reset = '1' then
			s_ledr_counter <= x"00000000";
		elsif rising_edge(CLOCK_50) then
			s_ledr_counter <= s_ledr_counter + 1;
		end if;
	end process;
	
	LEDR <= s_ledr_counter(31 downto 22);
	
	LEDG <= s_sd_busy & s_sd_error & s_sd_error_code & s_sd_q_avail & s_sd_type;
	
	s_sd_a <= x"00000000";
	s_iorq_r_sd_reg <= '1' when A(7 downto 0) = x"5A" and s_iorq_r = '1' else '0'; 
	s_iorq_r_sd_fsm <= '1' when A(7 downto 0) = x"57" and s_iorq_r = '1' else '0'; 

	-- FF: RESET
	-- 1A: READ
	-- 1B: DATA TAKEN
	
	s_sd_rd <= '1' when s_iorq_w_reg = '1' and s_sd_busy = '0' and D = x"01" else '0';
	s_sd_q_taken <= '1' when s_iorq_w_reg = '1' and D = x"02" else '0';
		
	-- SD Card
	s_sd_pres <= '1';
	s_d_wprot <= '1';

	D <=	(s_sd_busy & s_sd_error & s_sd_error_code & s_sd_q_avail & s_sd_type) when s_iorq_r_reg = '1' else
			s_sd_q when s_sd_q_avail = '1' and s_iorq_r_sd_reg = '1' else
			s_sd_fsm when s_iorq_r_sd_fsm = '1' else
			(others => 'Z'); 
	
	process(s_iorq_w_reg, s_reset)
	begin
		if s_reset = '1' then
			s_reset <= '0';
		elsif falling_edge(s_iorq_w_reg) then
			if D = x"FF" then 
				s_reset  <= '1';
				s_reg56_a <= x"00";
				s_reg56_d <= x"00";
			else
				s_reg56_a <= A(7 downto 0);
				s_reg56_d <= D;
			end if;
		end if;
	end process;
	 
-- -------------------------------------------------------------------

		
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

	i_sd_control: entity work.sd_controller
	port map (
	cs 					=> SD_DAT3,
	mosi 					=> SD_CMD,
	miso 					=> SD_DAT,
	sclk 					=> SD_CLK,
	card_present 		=> s_sd_pres,
	card_write_prot	=> s_d_wprot,

	rd 					=> s_sd_rd,
	rd_multiple 		=> s_sd_rd_m,
	dout 					=> s_sd_q,
	dout_avail			=> s_sd_q_avail,
	dout_taken 			=> s_sd_d_taken,
	
	wr						=> s_sd_wr,
	wr_multiple 		=> s_sd_wr_m,
	din 					=> s_sd_d,
	din_valid 			=> s_sd_d_avail,
	din_taken 			=> s_sd_d_taken,
	
	addr 					=> s_sd_a,
	erase_count 		=> s_sd_count,

	sd_error 			=> s_sd_error,
	sd_busy 				=> s_sd_busy,
	sd_error_code  	=> s_sd_error_code,
	
	
	reset					=> s_reset,
	clk					=> CLOCK_50,
	
	sd_type 				=> s_sd_type,
	sd_fsm 				=> s_sd_fsm
);


end behavioral;

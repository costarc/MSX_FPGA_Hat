library ieee ;
use ieee.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;

Entity MemoryMapper512K_Top is
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
    SRAM_ADDR:		out std_logic_vector(17 downto 0);	--	SRAM Address bus 18 Bits
    SRAM_UB_N:		out std_logic;								--	SRAM High-byte Data Mask 
    SRAM_LB_N:		out std_logic;								--	SRAM Low-byte Data Mask 
    SRAM_WE_N:		out std_logic;								--	SRAM Write Enable
    SRAM_CE_N:		out std_logic;								--	SRAM Chip Enable
    SRAM_OE_N:		out std_logic;								--	SRAM Output Enable
    							
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
end MemoryMapper512K_Top;

architecture behavioural of MemoryMapper512K_Top is
	
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
	signal s_fc					: std_logic_vector(4 downto 0) := "00011";
	signal s_fd					: std_logic_vector(4 downto 0) := "00010";
	signal s_fe					: std_logic_vector(4 downto 0) := "00001";
	signal s_ff					: std_logic_vector(4 downto 0) := "00000";
	signal s_mreq				: std_logic;
	signal s_iorq_en			: std_logic;
	signal s_iorq_r			: std_logic;
	signal s_iorq_w			: std_logic;
	signal s_iorq_r_reg		: std_logic;
	signal s_iorq_w_reg		: std_logic;
	signal s_mapper_reg_w	: std_logic;
	
	signal s_SRAM_ADDR		: std_logic_vector(20 downto 0);	
	signal s_reset				: std_logic := '0';
	signal s_wait_n			: std_logic := '1';
	signal s_segment			: std_logic_vector(20 downto 0);
	signal s_ffff_slt			: std_logic;
	signal slt_exp_n			: std_logic_vector(3 downto 0);
	signal s_expn_q			: std_logic_vector(7 downto 0);
	signal ram_q				: std_logic_vector(7 downto 0);
	
begin

	LEDG <= s_reset & s_mapper_reg_w & s_fc(1 downto 0) & s_fd(1 downto 0) & s_fe(1 downto 0) & s_ff(1 downto 0);

	-- Reset circuit
	-- The process implements a "pull-up" to WAIT_n signal to avoid it floating
    -- during a reset, which causes teh computer to freeze
	s_reset 	<= not (KEY(0) and RESET_n);
	WAIT_n 	<= s_wait_n;
	INT_n  	<= 'Z'; -- when (not (s_sltsl_en or s_iorq_r_reg or s_iorq_w_reg) = '1') else 'Z';
	BUSDIR_n <= not s_iorq_r_reg;
	process(s_reset)
	begin
	if s_reset = '1' then
		s_wait_n <= '1';
	else
		s_wait_n <= 'Z';
	end if;
	end process;

	U1OE_n <= not (s_sltsl_en or s_iorq_r_reg or s_iorq_w_reg);
	
    -- Auxiliary Generic control signals
    -- Auxiliary Generic control signals
	s_iorq_en	<= '1' when IORQ_n = '0' and M1_n = '1' else '0';
	s_iorq_r		<= '1' when RD_n = '0' and s_iorq_en = '1' else '0';
	s_iorq_w		<= '1' when WR_n = '0' and s_iorq_en = '1'  else '0';
	s_mreq		<= '1' when RD_n = '0' and  MREQ_n = '0' else '0';
	s_sltsl_en	<= '1' when SLTSL_n = '0' and SW(9) ='1' else '0';
	
	s_io_addr	<= A(7 downto 0);
	s_iorq_r_reg <= '1' when s_iorq_r = '1' and (s_io_addr = x"FC" or s_io_addr = x"FD" or s_io_addr = x"FE" or s_io_addr = x"FF") else '0';
	s_iorq_w_reg <= '1' when s_iorq_w = '1' and (s_io_addr = x"FC" or s_io_addr = x"FD" or s_io_addr = x"FE" or s_io_addr = x"FF") else '0';
	
	-- Mapper implementation								
	SRAM_CE_N <= slt_exp_n(0);								
	SRAM_OE_N <= '0';	
	SRAM_WE_N <= WR_n;
	SRAM_ADDR <= s_SRAM_ADDR(17 downto 0);
	SRAM_UB_N <= not s_SRAM_ADDR(18);						
	SRAM_LB_N <= s_SRAM_ADDR(18);
	
	--SRAM_DQ  <= D when slt_exp_n(0) = '0' and WR_n = '0' else (others => 'Z');
					 
	s_SRAM_ADDR <= (s_fc * x"4000") + A when A < x"4000" else
						(s_fd * x"4000") + A - x"4000" when A < x"8000" else
						(s_fe * x"4000") + A - x"8000" when A < x"c000" else
						(s_ff * x"4000") + A - x"C000";
		
	D <= s_expn_q when SLTSL_n = '0' and s_ffff_slt = '1' and RD_n = '0' else -- Slot Select expansion
	     ram_q when slt_exp_n(0) = '0' and s_mreq = '1' else
		  "111" & s_fc when s_iorq_r = '1' and s_io_addr = x"FC" else
		  "111" & s_fd when s_iorq_r = '1' and s_io_addr = x"FD" else
		  "111" & s_fe when s_iorq_r = '1' and s_io_addr = x"FE" else
		  "111" & s_ff when s_iorq_r = '1' and s_io_addr = x"FF" else
		  (others => 'Z');
	
	process(s_iorq_w_reg)
	begin
		if s_reset = '1' then
			s_fc <= "00011";
			s_fd <= "00010";
			s_fe <= "00001";
			s_ff <= "00000";
		elsif falling_edge(s_iorq_w_reg) then
			case s_io_addr is
					when x"FC" => s_fc <= D(4 downto 0);
					when x"FD" => s_fd <= D(4 downto 0);
					when x"FE" => s_fe <= D(4 downto 0);
					when x"FF" => s_ff <= D(4 downto 0);
					when others => null;
			end case ;
		end if;
	end process;
	
	-- Display the current Memory Address in the 7 segment display
	HEXDIGIT0 <= s_fc(3 downto 0);
	HEXDIGIT1 <= s_fd(3 downto 0);
	HEXDIGIT2 <= s_fe(3 downto 0);
	HEXDIGIT3 <= s_ff(3 downto 0);
		
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
		DRAM_DQ		<= (others => 'Z');
		FL_DQ		<= (others => 'Z');
	
	s_ffff_slt    <= '1' when A = x"FFFF" else '0';
	-- Expansor de slot
	exp: entity work.exp_slot
	port map (
		reset_n		=> not s_reset,
		sltsl_n		=> not s_sltsl_en,
		cpu_rd_n		=> RD_n,
		cpu_wr_n		=> WR_n,
		ffff			=> s_ffff_slt,
		cpu_a			=> A(15 downto 14),
		cpu_d			=> D,
		cpu_q			=> s_expn_q,
		exp_n			=> slt_exp_n
	);

	ram: entity work.ram
	port map(
		cs		=> not slt_exp_n(0),
		wr		=> not WR_n,
		A		=> s_SRAM_ADDR(15 downto 0),
		D		=> D,
		Q		=> ram_q
	);
	
end behavioural;

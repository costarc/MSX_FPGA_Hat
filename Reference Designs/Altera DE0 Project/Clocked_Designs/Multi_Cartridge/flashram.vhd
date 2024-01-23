library ieee ;
use ieee.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;

Entity FlashRAM is
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
    FL_ADDR:		out std_logic_vector(21 downto 0);	--	FLASH Address bus 22 Bits
    FL_WE_N:		out std_logic;								--	FLASH Write Enable
    FL_RST_N:		out std_logic;								--	FLASH Reset
    FL_OE_N:		out std_logic;								--	FLASH Output Enable
    FL_CE_N:		out std_logic;								--	FLASH Chip Enable
    FL_WP_N:		out std_logic;								--	FLASH Hardware Write Protect
    FL_BYTE_N:		out std_logic;								--	FLASH Selects 8/16-bit mode
    FL_RY:			in std_logic);								--	FLASH Ready/Busy
end FlashRAM;

architecture behavioural of FlashRAM is
	begin
	FL_DQ15_AM1 <= a_bus(0);			-- input for the LSB (A-1) address function for the flash in Byte mode
	FL_ADDR 	<= a_bus(22 downto 1);
	FL_WE_N <= '1';
	FL_RST_N <= not reset;
	FL_CE_N <= not en;
	FL_OE_N <= rw;
	FL_BYTE_N 	<= '0';    				-- Set flashram to Byte mode
	FL_WP_N 	<= '0';	   				-- Set flashram to Byte mode

	process(en, reset)
	begin
	if en = '1' then
		d_bus <= FL_DQ(7 downto 0);
	else
		d_bus <= "ZZZZZZZZ";
	end if;
	end process;
	
end behavioural;

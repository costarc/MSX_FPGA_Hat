library ieee ;
use ieee.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;

Entity SRAM512X8 is
port (
                    
    -- SRAM512X8 Input Signals
    A:		in std_logic_vector(18 downto 0);
    D:		in std_logic_vector(7 downto 0);
    Q:		out std_logic_vector(7 downto 0);
    WE_n: in std_logic;								
    CE_n: in std_logic;								
    DE_Model: in std_logic;									-- 0 = DE0 Addon/ 1 = DE1
    -- DE1 SRAM Signals
    SRAM_DQ:		inout std_logic_vector(15 downto 0);--	SRAM Data bus 16 Bits
    SRAM_ADDR:		out std_logic_vector(17 downto 0);	--	SRAM Address bus 18 Bits
    SRAM_UB_N:		out std_logic;								--	SRAM High-byte Data Mask 
    SRAM_LB_N:		out std_logic;								--	SRAM Low-byte Data Mask 
    SRAM_WE_N:		out std_logic;								--	SRAM Write Enable
    SRAM_CE_N:		out std_logic;								--	SRAM Chip Enable
    SRAM_OE_N:		out std_logic);							--	SRAM Output Enable
end SRAM512X8;

architecture rtl of SRAM512X8 is
	
begin

	SRAM_WE_N <= WE_n;
	SRAM_ADDR <= A(17 downto 0);
	SRAM_UB_N <= not A(18);						
	SRAM_LB_N <= A(18);								
	SRAM_CE_N <= CE_n;								
	SRAM_OE_N <= '0';								
	
	writeSRAM:process(WE_n)
	begin
		if WE_n = '0' then
			if DE_Model = '1' and  A(18) = '1' then
				SRAM_DQ(15 downto 8) <= D;
			else
				SRAM_DQ(7 downto 0) <= D;
			end if;
		else
			SRAM_DQ <= (others => 'Z');
		end if;	
	end process;

	readSRAM:process(CE_n)
	begin
		if falling_edge(CE_n) then
			if WE_n = '1' then
				if DE_Model = '1' and  A(18) = '1' then
					Q <= SRAM_DQ(15 downto 8);
				else
					Q <= SRAM_DQ(7 downto 0);
				end if; 
			end if;
		end if;
	end process;
	
	-- End of SRAM Implementation --	 	
end rtl;

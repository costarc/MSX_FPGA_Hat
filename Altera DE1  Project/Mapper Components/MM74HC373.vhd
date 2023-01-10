library ieee ;
use ieee.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;

Entity C_74HC373WM is
port (
	D: in std_logic_vector(7 downto 0);
	Q: out std_logic_vector(7 downto 0);
	LE: in std_logic;
	OE_n: in std_logic);
end c_74HC373WM;

Architecture behaviour of C_74HC373WM is

	signal s_q0: std_logic_vector(7 downto 0);

begin

	Q <= D when OE_n = '0' and LE = '1' else
		 s_q0 when OE_n = '0' and LE = '0' else
		 "ZZZZZZZZ" when OE_n = '1';
		 
	process(LE)
	begin
		if falling_edge(LE) then
			s_q0 <= D;
		end if;
	end process;
	
end behaviour;

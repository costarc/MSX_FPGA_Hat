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

   signal s_latch: std_logic_vector(7 downto 0);
	signal s_D:  std_logic_vector(7 downto 0);
	signal s_Q:  std_logic_vector(7 downto 0);
	signal s_LE:  std_logic;
	signal s_OE_n:  std_logic;
	
begin

	-- Implementation of 74HC373
	s_LE <= LE;
	s_OE_n <= OE_n;
	s_D <= D;
	Q <= s_Q;
	
	-- s_OE_n <= SW(9);
	-- s_LE <= SW(8);
	-- s_D <= SW(7 downto 0);
	-- LEDG <= s_Q;
	process(s_LE, s_OE_n)
	begin
		if s_OE_n = '1' then
			s_Q <= (others => 'Z');
		elsif s_LE = '1' then
			s_latch <= s_D;
			s_Q <= s_latch;
		else
			s_Q <= s_latch;
		end if;
	end process;
			  	
	-- End of 74HC373 Implementation
	
end behaviour;

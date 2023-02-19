library IEEE;
use IEEE.std_logic_1164.all;
use ieee.numeric_std.all;

entity ram is
	port(
		cs		: in std_logic;
		wr		: in std_logic;
		A		: in std_logic_vector(15 downto 0);
		D		: in std_logic_vector(7 downto 0);
		Q		: out std_logic_vector(7 downto 0)
	);
end ram;

architecture rtl of ram is
type ram is array (0 to 32767) of std_logic_vector(7 downto 0);
signal mapper : ram;

begin
process (cs)
	begin
	if rising_edge(cs) then
		if wr = '1' then
			mapper(to_integer(unsigned(A))) <= D;
		else
			Q <= mapper(to_integer(unsigned(A)));
		end if;
	end if;
end process;
end;


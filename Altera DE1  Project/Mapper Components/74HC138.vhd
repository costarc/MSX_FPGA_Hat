library ieee ;
use ieee.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;

Entity 74HC670D is
port (
	D: in std_logic_vector(3 downto 0);
	Q: in std_logic_vector(3 downto 0);
	A: in std_logic_vector(1 downto 0);
	RA: std_logic;
	RB: std_logic;
	GW: std_logic;
	GR: std_logic;
end 74HC670D;

Architecture rtl of 74HC670D is

signal D: std_logic_vector(3 downto 0);
signal Q: std_logic_vector(3 downto 0);
signal A: std_logic_vector(1 downto 0);

begin


process

end rtl;

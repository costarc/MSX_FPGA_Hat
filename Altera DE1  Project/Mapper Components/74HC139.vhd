library ieee ;
use ieee.std_logic_1164.all;

Entity C_74HC139 is
port (
    E1: in std_log;
	I1: in std_logic_vector(1 downto 0);
	Y1: out std_logic_vector(3 downto 0);
	
	E2: in std_log;
	I2: in std_logic_vector(1 downto 0);
	Y2: out std_logic_vector(3 downto 0));
end C_74HC139;

Architecture behaviour of C_74HC139 is

	signal s_and1: std_logic;
	signal s_and2: std_logic;
	signal s_and3: std_logic;
	signal s_and4: std_logic;
	signal s_and5: std_logic;
	signal s_and6: std_logic;
	signal s_and7: std_logic;
	signal s_and8: std_logic;
	signal s_SnorS: std_logic;
	
begin

	s_nand1 <= ((not I1(0) and ;

	
	
	Y1 <= s_and1 or s_and2 when OE_n = '0' else 'Z';
	Y2 <= s_and3 or s_and4 when OE_n = '0' else 'Z';
	Y3 <= s_and5 or s_and6 when OE_n = '0' else 'Z';
	Y4 <= s_and7 or s_and8 when OE_n = '0' else 'Z';
	
end behaviour;

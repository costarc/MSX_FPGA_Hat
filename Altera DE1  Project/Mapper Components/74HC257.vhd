library ieee ;
use ieee.std_logic_1164.all;

Entity C_74HC257 is
port (
	I1: in std_logic_vector(1 downto 0);
	Y1: out std_logic;
	I2: in std_logic_vector(1 downto 0);
	Y2: out std_logic;
	I3: in std_logic_vector(1 downto 0);
	Y3: out std_logic;
	I4: in std_logic_vector(1 downto 0);
	Y4: out std_logic;
	S: in std_logic;
	OE_n: in std_logic);
end C_74HC257;

Architecture behaviour of C_74HC257 is

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

	s_SnorS <= S nor S;
	
	s_and1 <= I1(0) and (not S);
	s_and2 <= I1(1) and s_SnorS;
	s_and3 <= I2(0) and (not S);
	s_and4 <= I2(1) and s_SnorS;
	s_and5 <= I3(0) and (not S);
	s_and6 <= I3(1) and s_SnorS;
	s_and7 <= I4(0) and (not S);
	s_and8 <= I4(1) and s_SnorS;
	
	Y1 <= s_and1 or s_and2 when OE_n = '0' else 'Z';
	Y2 <= s_and3 or s_and4 when OE_n = '0' else 'Z';
	Y3 <= s_and5 or s_and6 when OE_n = '0' else 'Z';
	Y4 <= s_and7 or s_and8 when OE_n = '0' else 'Z';
	
end behaviour;

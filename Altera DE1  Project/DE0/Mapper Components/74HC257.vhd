library ieee ;
use ieee.std_logic_1164.all;

Entity C_74HC257 is
port (
	I1: in std_logic_vector(1 downto 0);
	I3: in std_logic_vector(1 downto 0);
	I2: in std_logic_vector(1 downto 0);
	I4: in std_logic_vector(1 downto 0);
	Y1: out std_logic;
	Y2: out std_logic;
	Y3: out std_logic;
	Y4: out std_logic;
	S: in std_logic;
	OE_n: in std_logic);
end C_74HC257;

Architecture behaviour of C_74HC257 is

	signal s_I1: std_logic_vector(1 downto 0);
	signal s_I2: std_logic_vector(1 downto 0);
	signal s_I3: std_logic_vector(1 downto 0);
	signal s_I4: std_logic_vector(1 downto 0);
	signal s_Y1: std_logic;
	signal s_Y2: std_logic;
	signal s_Y3: std_logic;
	signal s_Y4: std_logic;
	signal s_S: std_logic;
	signal s_OE_n: std_logic;
	
begin

	-- Implementation of 74HC257
	s_S <= S;
	s_OE_n <= OE_n;
	s_I1 <= I1;
	s_I2 <= I2;
	s_I3 <= I3;
	s_I4 <= I4;
	Y1 <= s_Y1;
	Y2 <= s_Y2;
	Y3 <= s_Y3;
	Y4 <= s_Y4;
		
	-- s_OE_n <= SW(9);
	-- s_S <= SW(8);
	-- 
	-- s_I1 <= SW(0) & SW(1);
	-- LEDG(0) <= s_Y1;
	-- 
	-- s_I2 <= SW(2) & SW(3);
	-- LEDG(1) <= s_Y2;
	-- 
	-- s_I3 <= SW(4) & SW(5);
	-- LEDG(2) <= s_Y3;
	-- 
	-- s_I4 <= SW(6) & SW(7);
	-- LEDG(3) <= s_Y4;
	
	s_Y1 <= s_I1(1) when s_OE_n = '0' and s_S = '1' else
           s_I1(0) when s_OE_n = '0' and s_S = '0' else
			  'Z' when s_OE_n = '1';

	s_Y2 <= s_I2(1) when s_OE_n = '0' and s_S = '1' else
           s_I2(0) when s_OE_n = '0' and s_S = '0' else
			  'Z' when s_OE_n = '1';
			 
	s_Y3 <= s_I3(1) when s_OE_n = '0' and s_S = '1' else
           s_I3(0) when s_OE_n = '0' and s_S = '0' else
			  'Z' when s_OE_n = '1';
			 
	s_Y4 <= s_I4(1) when s_OE_n = '0' and s_S = '1' else
           s_I4(0) when s_OE_n = '0' and s_S = '0' else
			  'Z' when s_OE_n = '1';
			  	
	-- End of 74HC257 Implementation
end behaviour;

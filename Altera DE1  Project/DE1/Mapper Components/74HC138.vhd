library ieee ;
use ieee.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;

Entity C_74HC138 is
port (
	A: in std_logic_vector(2 downto 0);
	E1_n: in std_logic;
	E2_n: in std_logic;
	E3: in std_logic;
	Y: out std_logic_vector(7 downto 0));
end C_74HC138;

Architecture rtl of C_74HC138 is

	-- 74HC138 Pins
	signal s_A: std_logic_vector(2 downto 0);
	signal s_E1_n: std_logic;
	signal s_E2_n: std_logic;
	signal s_E3: std_logic;
	signal s_Y: std_logic_vector(7 downto 0);
	signal s_eand: std_logic;
	
begin

	-- 74HC138 Implementation
	s_A <= A;
	s_E1_n <= E1_n;
	s_E2_n <= E2_n;
	s_E3 <= E3;
	Y <= s_Y;
	
	-- s_A(0) <= SW(2);
	-- s_A(1) <= SW(1);
	-- s_A(2) <= SW(0);
	-- s_E1 <= SW(9);
	-- s_E2 <= SW(8);
	-- s_E3 <= SW(7);
	-- LEDG(0) <= s_Y(7);
	-- LEDG(1) <= s_Y(6);
	-- LEDG(2) <= s_Y(5);
	-- LEDG(3) <= s_Y(4);
	-- LEDG(4) <= s_Y(3);
	-- LEDG(5) <= s_Y(2);
	-- LEDG(6) <= s_Y(1);
	-- LEDG(7) <= s_Y(0);

	s_eand <= (((not s_E1_n) and (not(s_E2_n))) and s_E3);
	
	s_Y(0) <= not((((not s_A(0)) and (not s_A(1))) and (not s_A(2))) and (s_eand));
	s_Y(1) <= not((((s_A(0)) and (not s_A(1))) and (not s_A(2))) and (s_eand));
	s_Y(2) <= not((((not s_A(0)) and (s_A(1))) and (not s_A(2))) and (s_eand));
	s_Y(3) <= not((((s_A(0)) and (s_A(1))) and (not s_A(2))) and (s_eand));
	s_Y(4) <= not((((not s_A(0)) and (not s_A(1))) and (s_A(2))) and (s_eand));
	s_Y(5) <= not((((not s_A(1)) and (s_A(2))) and (s_A(0))) and (s_eand));
	s_Y(6) <= not((((not s_A(0)) and (s_A(2))) and (s_A(1))) and (s_eand));
	s_Y(7) <= not((((s_eand) and (s_A(1))) and (s_A(0))) and (s_A(2)));
	
	-- End of 74HC138 Implementation

end rtl;

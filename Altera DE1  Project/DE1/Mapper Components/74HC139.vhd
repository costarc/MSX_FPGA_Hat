library ieee ;
use ieee.std_logic_1164.all; 

Entity C_74HC139 is
port (
	A1: in std_logic_vector(1 downto 0);
	E1: in std_logic;
	Y1: out std_logic_vector(3 downto 0);
	A2: in std_logic_vector(1 downto 0);
	E2: in std_logic;
	Y2: out std_logic_vector(3 downto 0));
end C_74HC139;

architecture behaviour of C_74HC139 is

	-- 74HC139 Pins
	signal s_A1: std_logic_vector(1 downto 0);
	signal s_A2: std_logic_vector(1 downto 0);
	signal s_E1: std_logic;
	signal s_E2: std_logic;
	signal s_Y1: std_logic_vector(3 downto 0);
	signal s_Y2: std_logic_vector(3 downto 0);
	
begin

	-- 74HC139 Implementation
	
	s_A1 <= A1;
	s_E1 <= E1;
	Y1 <= s_Y1;
	
	s_A2 <= A2;
	s_E2 <= E2;
	Y2 <= s_Y2;
	
	-- s_A1(0) <= SW(1);
	-- s_A1(1) <= SW(0);
	-- s_E1 <= SW(9);
	-- LEDG(0) <= s_Y1(3);
	-- LEDG(1) <= s_Y1(2);
	-- LEDG(2) <= s_Y1(1);
	-- LEDG(3) <= s_Y1(0);
	-- 
	-- s_A2(0) <= SW(3);
	-- s_A2(1) <= SW(2);
	-- s_E2 <= SW(8);
	-- LEDG(4) <= s_Y2(3);
	-- LEDG(5) <= s_Y2(2);
	-- LEDG(6) <= s_Y2(1);
	-- LEDG(7) <= s_Y2(0);
	
	
	process(s_E1)
	begin
		if s_E1 = '1' then
			s_Y1 <= "1111";
		else
			case s_A1 is
				when "00"   => s_Y1 <= "1110";
				when "01"   => s_Y1 <= "1101";
				when "10"   => s_Y1 <= "1011";
				when others => s_Y1 <= "0111"; 
			end case;
		end if;
	end process;

   process(s_E2)
	begin
		if s_E2 = '1' then
			s_Y2 <= "1111";
		else
			case s_A2 is
				when "00"   => s_Y2 <= "1110";
				when "01"   => s_Y2 <= "1101";
				when "10"   => s_Y2 <= "1011";
				when others => s_Y2 <= "0111"; 
			end case;
		end if;
	end process;
	
	-- End of 74HC139 Implementation

end behaviour;

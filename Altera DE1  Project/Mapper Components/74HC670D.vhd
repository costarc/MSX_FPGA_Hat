library ieee ;
use ieee.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;

Entity C_74HC670D is
port (
	D: in std_logic_vector(3 downto 0);
	Q: out std_logic_vector(3 downto 0);
	RA: in std_logic;
	RB: in std_logic;
	WA: in std_logic;
	WB: in std_logic;
	WE_n: in std_logic;
	RE_n: in std_logic);
end C_74HC670D;

Architecture rtl of C_74HC670D is

	signal s_D: std_logic_vector(3 downto 0);
	signal s_Q: std_logic_vector(3 downto 0);
	signal s_RA: std_logic;
	signal s_RB: std_logic;
	signal s_WA: std_logic;
	signal s_WB: std_logic;
	signal s_WE_n: std_logic;
	signal s_RE_n: std_logic;
	
	signal s_DREG: std_logic_vector(15 downto 0);
	
	signal s_ra_rb: std_logic_vector(1 downto 0);
	signal s_wa_wb: std_logic_vector(1 downto 0);
	
begin	
	-- Implementation of 74HC670
	Q		<= s_Q;
	s_D  	<= D;
	s_RA 	<= RA;
	s_RB 	<= RB;
	s_WA 	<= WA;
	s_WB 	<= WB;
	s_WE_n	<= WE_n;
	s_RE_n	<= RE_n;
	
	-- s_RE_n <= SW(9);
	-- s_WE_n <= SW(8);
	-- s_RA <= SW(7);
	-- s_RB <= SW(6);
	-- s_WA <= SW(5);
	-- s_WB <= SW(4);
	-- s_D <= SW(3 downto 0);
	-- LEDR <= SW;
	-- LEDG <= "0000" & s_Q;
	
	s_ra_rb <= S_RA & s_RB;
	s_wa_wb <= s_WA & s_WB;
			
	process(s_WE_n)
	begin
		if falling_edge(s_WE_n) then
			case s_wa_wb is
				when "00" => s_DREG(3 downto 0)     <= s_D;
				when "01" => s_DREG(7 downto 4)     <= s_D;
				when "10" => s_DREG(11 downto 8)    <= s_D;
				when others => s_DREG(15 downto 12) <= s_D;
			end case;
		end if;
	end process;
	
	process(s_RE_n)
	begin
		if s_RE_n = '0' then 
			case s_ra_rb is
				when "00" =>   s_Q <= s_DREG(3 downto 0);
				when "01" =>   s_Q <= s_DREG(7 downto 4);
				when "10" =>   s_Q <= s_DREG(11 downto 8);
				when others => s_Q <= s_DREG(15 downto 12);
			end case;
		else
			s_Q <= (others => 'Z');
		end if;
	end process;
	
	-- End of 74HC670 Implementation

end rtl;

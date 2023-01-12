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

	signal s_d: std_logic_vector(15 downto 0);
	signal s_ra_rb: std_logic_vector(1 downto 0);
	signal s_wa_wb: std_logic_vector(1 downto 0);

begin

   s_ra_rb <= RA & RB;
	s_wa_wb <= WA & WB;
	
	process(RE_n)
	begin
		if RE_n = '0' then 
			case s_ra_rb is
				when "00" =>   Q <= s_d(3 downto 0);
				when "01" =>   Q <= s_d(7 downto 4);
				when "10" =>   Q <= s_d(11 downto 8);
				when others => Q  <= s_d(15 downto 12);
			end case;
		else
			Q <= (others => 'Z');
		end if;
	end process;
			
	process(WE_n)
	begin
		if falling_edge(WE_n) then
			case s_wa_wb is
				when "00" => s_d(3 downto 0)     <= D;
				when "01" => s_d(7 downto 4)     <= D;
				when "10" => s_d(11 downto 8)    <= D;
				when others => s_d(15 downto 12) <= D;
			end case;
		end if;
	end process;

end rtl;

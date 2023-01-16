library ieee ;
use ieee.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;

Entity C_74HC670D is
port (
	D: in std_logic_vector(3 downto 0);
	Q: out std_logic_vector(3 downto 0);
	RA: std_logic;
	RB: std_logic;
	WA: std_logic;
	WB: std_logic;
	WE_n: std_logic;
	RE_n: std_logic);
end C_74HC670D;

Architecture rtl of C_74HC670D is

	signal s_d: std_logic_vector(15 downto 0);

begin

	process(RE_n)
	begin
		if RE_n = '0' then 
			case RA & RB is
				when "00" => Q(3 downto 0);
				when "00" => Q(7 downto 4);
				when "00" => Q(11 downto 8);
				when others => Q(15 downto 12);
			end case;
		else
			Q <= (others => 'Z');
		end if;
	end process;
			
	process(WE_n)
	begin
		if falling_edge(WE_n) then
			case WA & WB is
				when "00" => s_d(3 downto 0) <= D;
				when "01" => s_d(7 downto 4) <= D;
				when "10" => s_d(11 downto 8) <= D;
				when others => s_d(15 downto 12) <= D;
			end case;
		end if;
	end process;

process

end rtl;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ram is
	port
	(
		data	: in std_logic_vector(7 downto 0);
		addr	: in std_logic_vector(13 downto 0);
		we		: in std_logic := '1';
		clk	: in std_logic;
		q		: out std_logic_vector(7 downto 0)
	);
	
end entity;

architecture rtl of ram is

	-- Build a 2-D array type for the RAM
	subtype word_t is std_logic_vector(7 downto 0);
	type memory_t is array(0 downto 16383) of word_t;
	
	-- Declare the RAM signal.
	signal ram : memory_t;
	
	-- Register to hold the address
	signal addr_reg : std_logic_vector(13 downto 0);

begin

	process(clk)
	begin
		if(falling_edge(clk)) then
			if(we = '1') then
				ram(to_integer(unsigned(addr))) <= data;
			end if;
			
			-- Register the address for reading
			addr_reg <= addr;
		end if;
	
	end process;
	
	q <= ram(to_integer(unsigned(addr_reg)));
	
end rtl;
-- clock_25mhz_sim.vhd
--
-- SIMULATION-ONLY stand-in for clock_25mhz.vhd.
--
-- The real clock_25mhz.vhd wraps Altera's altpll megafunction, which has no
-- simulation model available to GHDL without manually compiling Altera's
-- proprietary sim libraries (shipped with Quartus under eda/sim_lib/).
--
-- This file has the exact same entity name and port interface, so it can be
-- substituted in for GHDL simulation builds without touching the DUT. DO NOT
-- use this for synthesis - keep using the real clock_25mhz.vhd (MegaWizard
-- output, instantiates the actual PLL hardware) for that.
--
-- How to use with GHDL: simply do NOT analyze the real clock_25mhz.vhd when
-- building your simulation - analyze this file instead, under the same
-- entity name "clock_25mhz". Keep both files in separate directories (e.g.
-- rtl/ and sim/) so your Quartus project and your GHDL scripts each only
-- ever see the one they're supposed to.
--
-- Behavior: divides inclk0 by 2, giving c0 a 50% duty cycle output at half
-- the input frequency (50MHz in -> 25MHz out), matching the real PLL's
-- steady-state output closely enough for functional (not timing-accurate)
-- simulation. No PLL lock delay is modeled - c0 starts toggling immediately,
-- which is fine for the logic-correctness checks this testbench performs.

library ieee;
use ieee.std_logic_1164.all;

entity clock_25mhz is
	port (
		inclk0 : in  std_logic := '0';
		c0     : out std_logic
	);
end entity;

architecture sim of clock_25mhz is
	signal c0_i : std_logic := '0';
begin

	process(inclk0)
	begin
		if rising_edge(inclk0) then
			c0_i <= not c0_i;
		end if;
	end process;

	c0 <= c0_i;

end architecture;

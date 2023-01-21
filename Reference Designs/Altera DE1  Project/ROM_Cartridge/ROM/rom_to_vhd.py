#!/cygdrive/c/Users/alpha/AppData/Local/Microsoft/WindowsApps/python3

import sys

fname = sys.argv[1]

#component=fname.split('.')[0]
component='rom'

print("library IEEE;")
print("use IEEE.std_logic_1164.all;")
print("use ieee.numeric_std.all;")
print("")
print("entity %s is" % component)
print("	port(")
print("		cs		: in std_logic;")
print("		A		: in std_logic_vector(15 downto 0);")
print("		D		: out std_logic_vector(7 downto 0)")
print("	);")
print("end %s;" % component)
print("")
print("architecture rtl of %s is" % component)
print("begin")
print("")
print("process (cs)")
print("begin")
print(" if rising_edge(cs) then")
print("	case A is")

addr = 0

f = open(fname,"rb")
byte = True
while byte:
    byte = f.read(1).hex()
    if (byte):
        print("             when x\"%.4x\" => D <= x\"%s\";" % (addr,byte))
        addr += 1
    
f.close()

print("             when others => D <= x\"00\";")
print("	end case;")
print(" end if;")
print("end process;")
print("end;")
print("")



ghdl -a -fsynopsys ../MultiCart.vhd 
ghdl -a -fsynopsys tb_MultiCart.vhdl
ghdl -e -fsynopsys tb_MultiCart
ghdl -r -fsynopsys tb_MultiCart --stop-time=200ns --vcd=waveform.vcd
gtkwave waveform.vcd

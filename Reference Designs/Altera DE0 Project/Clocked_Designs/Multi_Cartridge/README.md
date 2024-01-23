Design: Multi_Cartridge

Function: Demonstrate how to implement a game cartridge using

Features: 
 1. Implement a ROM using the external Flashram in the board
 2. Implement a ROM using the internal FPGA BlockRAM

Quick Start Guide
-----------------

1. Connect everything and turn on the DE board
2. Program the DE board with the .sof file
3. Move SW9 to UP position, and SW8 Down
4. Switch on the computer - should boot the game stored in the Flash RAM
5. Switch off the computer
6. Move SW9 to Down position, and SW8 UP
7. Switch on the computer - should boot the game stored in the BlockROM


Build Yourself
--------------
1. Using the Altera Control Panel, write a 8KB, 16KB or 32KB ROM game to the FLASH RAM (starting at address 0)
2. Use rom_to_vhd.py program (in the Tools directory) to convert a ROM to VHDL:
   cd Tools
   python rom_to_vhd.py GALAGA.ROM > rom.vhdl
3. Build the project
4. Program the .sof file to the board



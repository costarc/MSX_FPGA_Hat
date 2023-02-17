This is a SRAM Addon for Terasic DE0 development board.

This Add-on is a 8 bits data bus only, 2 x 256KB banks (the DE1 and other models has the same SRAM, but in a 16 bus width).

LB_n and UB_n enable the two banks (only one should be enabled at any time), because both banks shares the same GPIO pins in the DE0 board.

The Raspberry Pi GPIO header should only be used when CE_n is HIGH (1), which disables teh SRAM and keeps the bus free for the Raspberry Pi.



Change History
--------------

Rev 2
- Changed footprint for the capacitors from 0402 to 0603 size

Rev 1
- Changed the add-on PIN Header from standard DE0 to Raspberry Pi layout to support Raspberry Pi as an connected device

Rev 0
- Initial version
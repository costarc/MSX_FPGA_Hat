v2.0 (With a few changes taken from Wondertang!)
- Added multiplex for MSX signals (shared GPIOS) to allow most MSX signals into the DPGA
- Added Audio circuitry from Wondertang (Luis Antoniosi project)
- Changed the open collector outputs to use transistor (/WAIt & /INT)
- Completely changed the PIN assigments - no compatible with previous boards
v1.6 (never sent for fabrication)
- Removed /CS1, CS2, CS12, RFSH, SOUND
- Moded U1 DIR control to jumper (allow enable by /RD or FPGA pin)
- Changed /WAIT & /INT to open collector using transistor
v1.5
- Added pull-up to MSX Data bus lines
- Added missing ground to LM1117
- Fixed bug (changed to 5V) in pull up on wait/int/busdir signals 
v1.4
- Added pull-up to all bus lines input to FPGA (4 x resistor network)
- Added RESET button (reset the MSX)
v1.3
- Updated edge connector (footprint) again, as per MSX standard for edge connector measures
- Moved RFSH & SOUNDIN to Jumper J1 (& removed previous jumpers J3/J4)
- Routed soundin & added R10
- Update silk with new retro games pictures
v1.2
- Changed footprint of PCB to 64mm in the base of cartridge as it was way too tight to insert
- Adde schotky diodes to MSX Input isgnals (Intt/Wait) to have the effect of open collector to isolate these signals from the FPGA when not actively driving them
- Added option to use MSX to power the interface (converted 5V to 3.3v via LD117)
v1.1
- Removed unnecessary xnor gate and jumpers
- Added other jumper to select signals to present to FPGA due to liitations in GPIO pins
- Changed pinout layout to support also Terasic DE0 

v1.0
- Initial version for Terasic DE1
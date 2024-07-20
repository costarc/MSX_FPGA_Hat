# MSX_FPGA_Hat
A Cartridge interface that converts MSX 5v signal levels to 3v, exposing an IDC connector for external devices that operates at 3v level.

Interface for MSX computers with level shift conversion to 3.3v. Allow MSX to use FPGA development boards such as Terasic DE0 and DE1 as generic peripherals.

THIS IS WORKING IN PROGRESS. THE BOARD IS BEING TESTED, AND REFERENCE DESIGNS CREATED. ROM and RAM reference designs work well, but as of now I was not able to implement a stable SD Card interface.


# Technical Description of the Interface
The interface connects the computer BUS to the FPGA GPIOs, using the flat cable.
The interface should be connected to JP2 of DE1, which corresponds to GPIO_1. This is the GPIO used in all the reference designs in this project. To use JP1 (GPIO_0), all pins must be remapped for the projects.

Address and control signals always flow from the computer to the FPGA - the DIR and /OE signals in U2,U3,U4 and U5 are always asserted (pull-up for bus directoin (Pin 1) and grounded for /OE (pin 19).

For U1, the BUS direction is controlled by the computer read signal (RD_n) in MSX. When read operation is triggered (RD_n = 0), the directon of the data in U1 flows from the FPGA to the computer. At all other times, the data flows from the computer to the FPGA.

U1 has a pull-up in the /OE pin, to keep any output disabled until the FPGA drives this pin low, which should only occur when the FPGA is in fact requested by the computer. Keeping /OE high isolates the computer BUS from anythign happening in the FPGA, which is also important during the boot in the computer.

# Controlling Flow of Data in the Interface
The recommended method to drive the interace signals is as follows:

U1 bus direction (pin 1): no additional implementaton is required - this pin is controlled automatically by the computer according his operations. For example, in the MSX computer, when requesting data from the FPGA, this pin is asserted LOW by RD_n = 0, when sending data it is asserted HIGH because RD_n will be HIGH.

U1 /OE (Output Enable, pin 19): This pin should be put in LOW whenever the FPGA detects that it is being requested - for example, if a ROM is implemented in the FPGA, the address and slot decoding should detect and assert according the GPIO pin /C_U1_D_OE (name was meant to stand for "CI U1, computer Data bus, pin OE).

U2,U3,U4,U5 bus direction: also no need to be concerned - these CIs have fixed bus direction, and constantly asserted HIGH for data to flow from the 74lvc245 bus A to bus B. 
The interface has some pins being used to carry data from the FPG to the computer in these CIs, in which case the routing for such signals was made bringing in input from the GPIO to the bus A, and teh exit in the bus B reouted to the computer.

# Jumpers and Configurations

The limited number of GPIOs in the development board require that we do some compromises in the design.
Some of the less used signals were routed to jumpers, at which point they can be selected to be sent to the FPGA.

J1 allow to select one of /CS1, /CS2 and /CS12 to send to FPGA connector pin 3 (/C_CS_SLT).
J2 allow to select either CLOCK or /RESET signal to send to FPGA connector pin 1 (C_CLK_OR_RST).

# Other Important Considerations

The interface was designed to be compatible with Terasic DEn series of boards. However, these boards present some differences in the GPIOs funtionalities, where some bords (like DE1) have 36 generic I/O pins avaialable fo rinput/output functions, and others like DE0 have four pins dedicated to either input or outputs. This is the case of pins 1 and 3, whch are input only pins, and 19, 21 which are output only.
These differences were already considered in the reference designs, and these pins assigned to functions that will not case problems of limitations to the designs.
If you want to change the pin mapping in the FPGA designs, pay attention to these pins - do not assign functions opposite to the directon they actually work.

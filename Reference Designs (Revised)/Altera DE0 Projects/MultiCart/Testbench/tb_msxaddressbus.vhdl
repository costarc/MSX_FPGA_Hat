library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity tb_msxaddressbus is
-- No ports in a testbench entity
end tb_msxaddressbus;

architecture Behavioral of tb_msxaddressbus is
    -- Component Declaration for the Unit Under Test (UUT)
    component msxaddressbus is
        Port ( 
            CLOCK_50     : in STD_LOGIC;
            slten_s      : in STD_LOGIC;
            A0_8         : in STD_LOGIC;
            A1_9         : in STD_LOGIC;
            A2_10        : in STD_LOGIC;
            A3_11        : in STD_LOGIC;
            A4_12        : in STD_LOGIC;
            A5_13        : in STD_LOGIC;
            A6_14        : in STD_LOGIC;
            A7_15        : in STD_LOGIC;
            A            : out STD_LOGIC_VECTOR (15 downto 0);
            U2_OE_n      : out STD_LOGIC;
            U3_OE_n      : out STD_LOGIC;
            address_ready: out STD_LOGIC
        );
    end component;

    -- Signals for driving the UUT
    signal CLOCK_50     : STD_LOGIC := '0';
    signal slten_s      : STD_LOGIC := '0';
    signal A0_8         : STD_LOGIC := '0';
    signal A1_9         : STD_LOGIC := '0';
    signal A2_10        : STD_LOGIC := '0';
    signal A3_11        : STD_LOGIC := '0';
    signal A4_12        : STD_LOGIC := '0';
    signal A5_13        : STD_LOGIC := '0';
    signal A6_14        : STD_LOGIC := '0';
    signal A7_15        : STD_LOGIC := '0';
    signal A            : STD_LOGIC_VECTOR (15 downto 0);
    signal U2_OE_n      : STD_LOGIC;
    signal U3_OE_n      : STD_LOGIC;
    signal address_ready: STD_LOGIC;

    -- Clock period definition
    constant CLOCK_PERIOD : time := 20 ns; -- Define a 50 MHz clock period

begin

    -- Instantiate the Unit Under Test (UUT)
    uut: msxaddressbus Port map (
        CLOCK_50     => CLOCK_50,
        slten_s      => slten_s,
        A0_8         => A0_8,
        A1_9         => A1_9,
        A2_10        => A2_10,
        A3_11        => A3_11,
        A4_12        => A4_12,
        A5_13        => A5_13,
        A6_14        => A6_14,
        A7_15        => A7_15,
        A            => A,
        U2_OE_n      => U2_OE_n,
        U3_OE_n      => U3_OE_n,
        address_ready=> address_ready
    );

    -- Clock Generation Process
    clock_process: process
    begin
        while True loop
            CLOCK_50 <= '0';
            wait for CLOCK_PERIOD / 2;
            CLOCK_50 <= '1';
            wait for CLOCK_PERIOD / 2;
        end loop;
    end process;

process
begin
    -- Initialize signals
    slten_s <= '0';
    A0_8 <= '0'; A1_9 <= '1'; A2_10 <= '0'; A3_11 <= '1';
    A4_12 <= '0'; A5_13 <= '1'; A6_14 <= '0'; A7_15 <= '1';

    -- Wait for a few clock cycles
    wait for 3 * CLOCK_PERIOD;

    -- Trigger the state machine
    slten_s <= '1';
    wait for CLOCK_PERIOD; -- Let the FSM transition

    -- Reset the state machine
    slten_s <= '0';
    wait for 10 * CLOCK_PERIOD;

    -- Stop the simulation
    report "Simulation completed" severity failure;
end process;


end Behavioral;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity msxaddressbus is
    Port ( CLOCK_50 : in STD_LOGIC;
           slten_s  : in STD_LOGIC;
           A0_8     : in STD_LOGIC;
           A1_9     : in STD_LOGIC;
           A2_10    : in STD_LOGIC;
           A3_11    : in STD_LOGIC;
           A4_12    : in STD_LOGIC;
           A5_13    : in STD_LOGIC;
           A6_14    : in STD_LOGIC;
           A7_15    : in STD_LOGIC;
           A        : out STD_LOGIC_VECTOR (15 downto 0);
           U2_OE_n  : out STD_LOGIC;
           U3_OE_n  : out STD_LOGIC
           );
end msxaddressbus;

architecture Behavioral of msxaddressbus is
    type state_type is (IDLE, READ_LOW, READ_HIGH);
    signal current_state, next_state : state_type;
begin
    -- FSM: Combinational State Transition Logic
    process (CLOCK_50, slten_s, current_state)
    begin
        if rising_edge(CLOCK_50) then
            -- Handle state transitions based on current state and slten_s
            if current_state = IDLE and slten_s = '1' then
                next_state <= READ_LOW;
            elsif current_state = READ_LOW then
                next_state <= READ_HIGH; -- Transition to READ_HIGH
            elsif current_state = READ_HIGH then
                next_state <= IDLE; -- Return to IDLE
            end if;
        end if;
    end process;

    -- State Update Logic (Sequential)
    process (CLOCK_50)
    begin
        if rising_edge(CLOCK_50) then
            current_state <= next_state; -- Update current_state with next_state on rising edge of CLOCK_50
        end if;
    end process;

    -- Output Logic
    process (current_state, A0_8, A1_9, A2_10, A3_11, A4_12, A5_13, A6_14, A7_15)
    begin
        -- Default outputs
        A <= (others => '0');  -- Clear the address bus initially
        U2_OE_n <= '1'; -- Disable low-byte buffer by default
        U3_OE_n <= '1'; -- Disable high-byte buffer by default

        -- Output logic based on current state
        case current_state is
            when READ_LOW =>
                -- First enable low-byte buffer, then drive the data
                U2_OE_n <= '0'; -- Enable low-byte buffer
                A(7 downto 0) <= A7_15 & A6_14 & A5_13 & A4_12 & A3_11 & A2_10 & A1_9 & A0_8;

            when READ_HIGH =>
                -- First enable high-byte buffer, then drive the data
                U3_OE_n <= '0'; -- Enable high-byte buffer
                A(15 downto 8) <= A7_15 & A6_14 & A5_13 & A4_12 & A3_11 & A2_10 & A1_9 & A0_8;

            when others =>
                -- IDLE state or default: both buffers disabled
                U2_OE_n <= '1'; -- Disable low-byte buffer
                U3_OE_n <= '1'; -- Disable high-byte buffer
        end case;
    end process;

end Behavioral;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi_controller is
generic(
  N                     : integer := 8;      -- number of bit to serialize
  CLK_DIV               : integer := 100 );  -- input clock divider to generate output serial clock; o_sclk frequency = i_clk/(2*CLK_DIV)
 port (
  i_clk                       : in  std_logic;
  i_rstb                      : in  std_logic;
  i_tx_start                  : in  std_logic;  -- start TX on serial line
  o_tx_end                    : out std_logic;  -- TX data completed; o_data_parallel available
  o_wait_n                    : out std_logic;  -- wait state to Z80
  i_data_parallel             : in  std_logic_vector(N-1 downto 0);  -- data to sent
  o_data_parallel             : out std_logic_vector(N-1 downto 0);  -- received data
  o_sclk                      : out std_logic;
  o_ss                        : out std_logic;
  o_mosi                      : out std_logic;
  i_miso                      : in  std_logic);
end spi_controller;

architecture rtl of spi_controller is

type t_spi_controller_fsm is (
                          ST_RESET   ,
                          ST_TX_RX   ,
                          ST_END     );

signal r_counter_clock        : integer range 0 to CLK_DIV*2;
signal r_sclk_rise            : std_logic;
signal r_sclk_fall            : std_logic;
signal r_counter_clock_ena    : std_logic;

signal r_counter_data         : integer range 0 to N;
signal w_tc_counter_data      : std_logic;

signal r_st_present           : t_spi_controller_fsm;
signal w_st_next              : t_spi_controller_fsm;
signal r_tx_start             : std_logic;  -- start TX on serial line
signal r_tx_data              : std_logic_vector(N-1 downto 0);  -- data to sent
signal r_rx_data              : std_logic_vector(N-1 downto 0);  -- received data

begin

w_tc_counter_data  <= '0' when(r_counter_data>0) else '1';
--------------------------------------------------------------------
-- FSM
p_state : process(i_clk,i_rstb)
begin
  if(i_rstb='0') then
    r_st_present            <= ST_RESET;
  elsif(rising_edge(i_clk)) then
    r_st_present            <= w_st_next;
  end if;
end process p_state;

p_comb : process(
                 r_st_present                       ,
                 w_tc_counter_data                  ,
                 r_tx_start                         ,
                 r_sclk_rise                        ,
                 r_sclk_fall                         )
begin
  case r_st_present is
    when  ST_TX_RX      => 
      if (w_tc_counter_data='1') and (r_sclk_rise='1') then
			w_st_next  <= ST_END;
      else
			w_st_next  <= ST_TX_RX;
      end if;

    when  ST_END      => 
      if(r_sclk_fall='1') then
        w_st_next  <= ST_RESET;  
      else
        w_st_next  <= ST_END;  
      end if;

    when  others            =>  -- ST_RESET
      if(r_tx_start='1') then   w_st_next  <= ST_TX_RX ;
      else                      w_st_next  <= ST_RESET ;
      end if;
  end case;
end process p_comb;

p_state_out : process(i_clk,i_rstb)
begin
  if(i_rstb='0') then
    r_tx_start           <= '0';
    r_tx_data            <= (others=>'0');
    r_rx_data            <= (others=>'0');
    o_tx_end             <= '0';
    o_data_parallel      <= (others=>'0');
    
    r_counter_data       <= N-1;
    r_counter_clock_ena  <= '0';

    o_sclk               <= '1';
    o_ss                 <= '1';
    o_mosi               <= '1';
  elsif(rising_edge(i_clk)) then
    r_tx_start           <= i_tx_start;

    case r_st_present is
      when ST_TX_RX         =>
        o_wait_n             <= '1';
        o_tx_end             <= '0';
        r_counter_clock_ena  <= '1';
        if(r_sclk_rise='1') then
          o_sclk               <= '1';
          r_rx_data            <= r_rx_data(N-2 downto 0)&i_miso;
          if(r_counter_data>0) then
            r_counter_data       <= r_counter_data - 1;
          end if;
        elsif(r_sclk_fall='1') then
          o_sclk               <= '0';
          o_mosi               <= r_tx_data(N-1);
          r_tx_data            <= r_tx_data(N-2 downto 0)&'1';
        end if;
        o_ss                 <= '0';

      when ST_END          =>
		  o_wait_n             <= '0';
        o_tx_end             <= r_sclk_fall;
        o_data_parallel      <= r_rx_data;
        r_counter_data       <= N-1;
        r_counter_clock_ena  <= '1';
        o_ss                 <= '0';
      
      when others               =>  -- ST_RESET
		  o_wait_n             <= '1';
        r_tx_data            <= i_data_parallel;
        o_tx_end             <= '0';
        r_counter_data       <= N-1;
        r_counter_clock_ena  <= '0';
        o_sclk               <= '1';
        o_ss                 <= '1';
        o_mosi               <= '1';
    end case;
  end if;
end process p_state_out;


p_counter_clock : process(i_clk,i_rstb)
begin
  if(i_rstb='0') then
    r_counter_clock            <= 0;
    r_sclk_rise                <= '0';
    r_sclk_fall                <= '0';
  elsif(rising_edge(i_clk)) then
    if(r_counter_clock_ena='1') then  -- sclk = '1' by default 
      if(r_counter_clock=CLK_DIV-1) then  -- firse edge = fall
        r_counter_clock            <= r_counter_clock + 1;
        r_sclk_rise                <= '0';
        r_sclk_fall                <= '1';
      elsif(r_counter_clock=(CLK_DIV*2)-1) then
        r_counter_clock            <= 0;
        r_sclk_rise                <= '1';
        r_sclk_fall                <= '0';
      else
        r_counter_clock            <= r_counter_clock + 1;
        r_sclk_rise                <= '0';
        r_sclk_fall                <= '0';
      end if;
    else
      r_counter_clock            <= 0;
      r_sclk_rise                <= '0';
      r_sclk_fall                <= '0';
    end if;
  end if;
end process p_counter_clock;

end rtl;
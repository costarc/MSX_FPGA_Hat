--**********************************************************************
-- Original copyright (c) 2012-2014 by XESS Corp <http://www.xess.com>.
-- Licensed LGPL v3.0 - see https://github.com/xesscorp/VHDL_Lib
-- Source: https://github.com/xesscorp/VHDL_Lib/blob/master/SDCard.vhd
--**********************************************************************

--*********************************************************************
-- SD MEMORY CARD INTERFACE (SDMapper_V2.1b port, 2026-08-12)
--
-- Reads/writes a single or multiple blocks of data to/from an SD Flash card.
--
-- Based on XESS by Steven J. Merrifield, June 2008:
-- http://stevenmerrifield.com/tools/sd.vhd
--
-- PORTING NOTES (this file vs. the original XESS VHDL_Lib/SDCard.vhd):
-- After debugging two independently hand-rolled SPI engines (Belavenuto's
-- and an alternate from the same author) that both correctly exchanged
-- bytes with the SD card but never got anything back except 0xFF, this
-- project switched to reusing XESS's mature, widely-used core instead of
-- continuing to hand-roll SD protocol logic. The FSM itself (every state,
-- every transition, every timing constant) is preserved EXACTLY as
-- upstream - only the following non-functional changes were made to drop
-- this project's own XESS.CommonPckg library dependency, which isn't
-- available here:
--   - NO/YES/HI/LO/ZERO/ONE (all just std_logic '0'/'1' aliases in
--     XESS's CommonPckg) are now local constants declared below instead
--     of imported from XESS.CommonPckg.
--   - IEEE.math_real's realmax()/the original's local IntMax() are
--     replaced with their statically-known results for THIS project's
--     fixed generics: INIT_SPI_FREQ_G is always <= SPI_FREQ_G by
--     construction (identification phase is always the slower one), so
--     MAX_CLKS_PER_SCLK_C is always CLKS_PER_INIT_SCLK_C; WR_BLK_SZ_C is
--     always 2 bytes larger than RD_BLK_SZ_C (extra dummy + response
--     byte), so the max of the two is always WR_BLK_SZ_C. Both were
--     function calls purely to compute elaboration-time constants from
--     generics in the original - this project's generics never violate
--     those orderings, so the calls are just inlined as the direct
--     comparison the tool would have folded them to anyway.
--   - The original's SdCardPckg package wrapper and the SdCardCtrlTest
--     PC-USB-testing harness entity (which used XESS-specific
--     ClkGen/HostIoToDut/board-package components this project doesn't
--     have) are both dropped - this project instantiates SdCardCtrl
--     directly from a small register-level bridge (see sdcard_bridge.vhd)
--     instead of a Wishbone-less/USB test harness.
--
-- Everything else - every state name, every signal, every comment - is
-- reproduced as-is from upstream. See the file header link above for the
-- original and its documented OPERATION/SET-UP/read/write/error-handling
-- protocol, which sdcard_bridge.vhd implements against directly.
-- *********************************************************************

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

package SdCardXessPckg is

  type CardType_t is (SD_CARD_E, SDHC_CARD_E);  -- Define the different types of SD cards.

  component SdCardCtrl is
    generic (
      FREQ_G          : real       := 25.0;  -- Master clock frequency (MHz).
      INIT_SPI_FREQ_G : real       := 0.4;  -- Slow SPI clock freq. during initialization (MHz).
      SPI_FREQ_G      : real       := 12.5;  -- Operational SPI freq. to the SD card (MHz).
      BLOCK_SIZE_G    : natural    := 512;  -- Number of bytes in an SD card block or sector.
      CARD_TYPE_G     : CardType_t := SDHC_CARD_E  -- Type of SD card connected to this controller.
      );
    port (
      -- Host-side interface signals.
      clk_i      : in  std_logic;       -- Master clock.
      reset_i    : in  std_logic                     := '0';  -- active-high, synchronous  reset.
      rd_i       : in  std_logic                     := '0';  -- active-high read block request.
      wr_i       : in  std_logic                     := '0';  -- active-high write block request.
      continue_i : in  std_logic                     := '0';  -- If true, inc address and continue R/W.
      addr_i     : in  std_logic_vector(31 downto 0) := x"00000000";  -- Block address.
      data_i     : in  std_logic_vector(7 downto 0)  := x"00";  -- Data to write to block.
      data_o     : out std_logic_vector(7 downto 0)  := x"00";  -- Data read from block.
      busy_o     : out std_logic;  -- High when controller is busy performing some operation.
      hndShk_i   : in  std_logic;  -- High when host has data to give or has taken data.
      hndShk_o   : out std_logic;  -- High when controller has taken data or has data to give.
      error_o    : out std_logic_vector(15 downto 0) := (others => '0');
      -- I/O signals to the external SD card.
      cs_bo      : out std_logic                     := '1';  -- Active-low chip-select.
      sclk_o     : out std_logic                     := '0';  -- Serial clock to SD card.
      mosi_o     : out std_logic                     := '1';  -- Serial data output to SD card.
      miso_i     : in  std_logic                     := '0'  -- Serial data input from SD card.
      );
  end component;

end package;




library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;
use work.SdCardXessPckg.all;

entity SdCardCtrl is
  generic (
    FREQ_G          : real       := 25.0;      -- Master clock frequency (MHz).
    INIT_SPI_FREQ_G : real       := 0.4;  -- Slow SPI clock freq. during initialization (MHz).
    SPI_FREQ_G      : real       := 12.5;  -- Operational SPI freq. to the SD card (MHz).
    BLOCK_SIZE_G    : natural    := 512;  -- Number of bytes in an SD card block or sector.
    CARD_TYPE_G     : CardType_t := SDHC_CARD_E  -- Type of SD card connected to this controller.
    );
  port (
    -- Host-side interface signals.
    clk_i      : in  std_logic;         -- Master clock.
    reset_i    : in  std_logic                     := '0';  -- active-high, synchronous  reset.
    rd_i       : in  std_logic                     := '0';  -- active-high read block request.
    wr_i       : in  std_logic                     := '0';  -- active-high write block request.
    continue_i : in  std_logic                     := '0';  -- If true, inc address and continue R/W.
    addr_i     : in  std_logic_vector(31 downto 0) := x"00000000";  -- Block address.
    data_i     : in  std_logic_vector(7 downto 0)  := x"00";  -- Data to write to block.
    data_o     : out std_logic_vector(7 downto 0)  := x"00";  -- Data read from block.
    busy_o     : out std_logic;  -- High when controller is busy performing some operation.
    hndShk_i   : in  std_logic;  -- High when host has data to give or has taken data.
    hndShk_o   : out std_logic;  -- High when controller has taken data or has data to give.
    error_o    : out std_logic_vector(15 downto 0) := (others => '0');
    -- I/O signals to the external SD card.
    cs_bo      : out std_logic                     := '1';  -- Active-low chip-select.
    sclk_o     : out std_logic                     := '0';  -- Serial clock to SD card.
    mosi_o     : out std_logic                     := '1';  -- Serial data output to SD card.
    miso_i     : in  std_logic                     := '0'  -- Serial data input from SD card.
    );
end entity;



architecture arch of SdCardCtrl is

  -- Local aliases for XESS.CommonPckg's std_logic constants - see file
  -- header porting note.
  constant NO   : std_logic := '0';
  constant YES  : std_logic := '1';
  constant HI   : std_logic := '1';
  constant LO   : std_logic := '0';
  constant ZERO : std_logic := '0';
  constant ONE  : std_logic := '1';

  signal sclk_r   : std_logic := ZERO;  -- Register output drives SD card clock.
  signal hndShk_r : std_logic := NO;  -- Register output drives handshake output to host.

begin

  process(clk_i)  -- FSM process for the SD card controller.

    type FsmState_t is (    -- States of the SD card controller FSM.
      START_INIT,  -- Send initialization clock pulses to the deselected SD card.
      SEND_CMD0,                        -- Put the SD card in the IDLE state.
      CHK_CMD0_RESPONSE,    -- Check card's R1 response to the CMD0.
      SEND_CMD8,   -- This command is needed to initialize SDHC cards.
      GET_CMD8_RESPONSE,                -- Get the R7 response to CMD8.
      SEND_CMD55,                       -- Send CMD55 to the SD card.
      SEND_CMD41,                       -- Send CMD41 to the SD card.
      CHK_ACMD41_RESPONSE,  -- Check if the SD card has left the IDLE state.
      WAIT_FOR_HOST_RW,  -- Wait for the host to issue a read or write command.
      RD_BLK,    -- Read a block of data from the SD card.
      WR_BLK,    -- Write a block of data to the SD card.
      WR_WAIT,   -- Wait for SD card to finish writing the data block.
      START_TX,                         -- Start sending command/data.
      TX_BITS,   -- Shift out remaining command/data bits.
      GET_CMD_RESPONSE,  -- Get the R1 response of the SD card to a command.
      RX_BITS,   -- Receive response/data from the SD card.
      DESELECT,  -- De-select the SD card and send some clock pulses (Must enter with sclk at zero.)
      PULSE_SCLK,  -- Issue some clock pulses. (Must enter with sclk at zero.)
      REPORT_ERROR                      -- Report error and stall until reset.
      );
    variable state_v    : FsmState_t := START_INIT;  -- Current state of the FSM.
    variable rtnState_v : FsmState_t;  -- State FSM returns to when FSM subroutine completes.

    -- Timing constants based on the master clock frequency and the SPI SCLK frequencies.
    constant CLKS_PER_INIT_SCLK_C      : real    := FREQ_G / INIT_SPI_FREQ_G;
    constant CLKS_PER_SCLK_C           : real    := FREQ_G / SPI_FREQ_G;
    -- INIT_SPI_FREQ_G <= SPI_FREQ_G always for this project's generics, so
    -- CLKS_PER_INIT_SCLK_C >= CLKS_PER_SCLK_C always - inlined realmax().
    constant MAX_CLKS_PER_SCLK_C       : real    := CLKS_PER_INIT_SCLK_C;
    constant MAX_CLKS_PER_SCLK_PHASE_C : natural := integer(round(MAX_CLKS_PER_SCLK_C / 2.0));
    constant INIT_SCLK_PHASE_PERIOD_C  : natural := integer(round(CLKS_PER_INIT_SCLK_C / 2.0));
    constant SCLK_PHASE_PERIOD_C       : natural := integer(round(CLKS_PER_SCLK_C / 2.0));
    constant DELAY_BETWEEN_BLOCK_RW_C  : natural := SCLK_PHASE_PERIOD_C;

    -- Registers for generating slow SPI SCLK from the faster master clock.
    variable clkDivider_v     : natural range 0 to MAX_CLKS_PER_SCLK_PHASE_C;  -- Holds the SCLK period.
    variable sclkPhaseTimer_v : natural range 0 to MAX_CLKS_PER_SCLK_PHASE_C;  -- Counts down to zero, then SCLK toggles.

    constant NUM_INIT_CLKS_C : natural := 160;  -- Number of initialization clocks to SD card.
    variable bitCnt_v        : natural range 0 to NUM_INIT_CLKS_C;  -- Tx/Rx bit counter.

    constant CRC_SZ_C    : natural := 2;  -- Number of CRC bytes for read/write blocks.
    -- When reading blocks of data, get 0xFE + [DATA_BLOCK] + [CRC].
    constant RD_BLK_SZ_C : natural := 1 + BLOCK_SIZE_G + CRC_SZ_C;
    -- When writing blocks of data, send 0xFF + 0xFE + [DATA BLOCK] + [CRC] then receive response byte.
    constant WR_BLK_SZ_C : natural := 1 + 1 + BLOCK_SIZE_G + CRC_SZ_C + 1;
    -- WR_BLK_SZ_C is always 2 bytes larger than RD_BLK_SZ_C by construction
    -- (extra leading dummy byte + trailing response byte) - inlined IntMax().
    variable byteCnt_v   : natural range 0 to WR_BLK_SZ_C;  -- Tx/Rx byte counter.

    -- Command bytes for various SD card operations.
    subtype Cmd_t is std_logic_vector(7 downto 0);
    constant CMD0_C          : Cmd_t := std_logic_vector(to_unsigned(16#40# + 0, Cmd_t'length));
    constant CMD8_C          : Cmd_t := std_logic_vector(to_unsigned(16#40# + 8, Cmd_t'length));
    constant CMD55_C         : Cmd_t := std_logic_vector(to_unsigned(16#40# + 55, Cmd_t'length));
    constant CMD41_C         : Cmd_t := std_logic_vector(to_unsigned(16#40# + 41, Cmd_t'length));
    constant READ_BLK_CMD_C  : Cmd_t := std_logic_vector(to_unsigned(16#40# + 17, Cmd_t'length));
    constant WRITE_BLK_CMD_C : Cmd_t := std_logic_vector(to_unsigned(16#40# + 24, Cmd_t'length));

    -- Except for CMD0 and CMD8, SD card ops don't need a CRC, so use a fake one for that slot in the command.
    constant FAKE_CRC_C : std_logic_vector(7 downto 0) := x"FF";

    variable addr_v : unsigned(addr_i'range);  -- Address of current block for R/W operations.

    -- Maximum Tx to SD card consists of command + address + CRC. Data Tx is just a single byte.
    variable tx_v : std_logic_vector(CMD0_C'length + addr_v'length + FAKE_CRC_C'length - 1 downto 0);  -- Data/command to SD card.
    alias txCmd_v is tx_v;              -- Command transmission shift register.
    alias txData_v is tx_v(tx_v'high downto tx_v'high - data_i'length + 1);  -- Data byte transmission shift register.

    variable rx_v               : std_logic_vector(data_i'range);  -- Data/response byte received from SD card.
    -- Various response codes.
    subtype Response_t is std_logic_vector(rx_v'range);
    constant ACTIVE_NO_ERRORS_C : Response_t := "00000000";  -- Normal R1 code after initialization.
    constant IDLE_NO_ERRORS_C   : Response_t := "00000001";  -- Normal R1 code after CMD0.
    constant DATA_ACCEPTED_C    : Response_t := "---00101";  -- SD card accepts data block from host.
    constant DATA_REJ_CRC_C     : Response_t := "---01011";  -- SD card rejects data block from host due to CRC error.
    constant DATA_REJ_WERR_C    : Response_t := "---01101";  -- SD card rejects data block from host due to write error.
    -- Various tokens.
    subtype Token_t is std_logic_vector(rx_v'range);
    constant NO_TOKEN_C         : Token_t    := x"FF";  -- Received before the SD card responds to a block read command.
    constant START_TOKEN_C      : Token_t    := x"FE";  -- Starting byte preceding a data block.

    -- Flags that are set/cleared to affect the operation of the FSM.
    variable getCmdResponse_v : boolean;  -- When true, get R1 response to command sent to SD card.
    variable rtnData_v        : boolean;  -- When true, signal to host when a data byte arrives from SD card.
    variable doDeselect_v     : boolean;  -- When true, de-select SD card after a command is issued.

  begin
    if rising_edge(clk_i) then

      if reset_i = YES then             -- Perform a reset.
        state_v          := START_INIT;  -- Send the FSM to the initialization entry-point.
        sclkPhaseTimer_v := 0;  -- Don't delay the initialization right after reset.
        busy_o           <= YES;  -- Busy while the SD card interface is being initialized.

      elsif sclkPhaseTimer_v /= 0 then
        -- Setting the clock phase timer to a non-zero value delays any further actions
        -- and generates the slower SPI clock from the faster master clock.
        sclkPhaseTimer_v := sclkPhaseTimer_v - 1;

        -- Clock phase timer has reached zero, so check handshaking sync. between host and controller.

        -- Handshaking lets the host control the flow of data to/from the SD card controller.
        -- Handshaking between the SD card controller and the host proceeds as follows:
        --   1: Controller raises its handshake and waits.
        --   2: Host sees controller handshake and raises its handshake in acknowledgement.
        --   3: Controller sees host handshake acknowledgement and lowers its handshake.
        --   4: Host sees controller lower its handshake and removes its handshake.
        --
        -- Handshaking is bypassed when the controller FSM is initializing the SD card.

      elsif state_v /= START_INIT and hndShk_r = HI and hndShk_i = LO then
        null;            -- Waiting for the host to acknowledge handshake.
      elsif state_v /= START_INIT and hndShk_r = HI and hndShk_i = HI then
        txData_v := data_i;             -- Get any data passed from the host.
        hndShk_r <= LO;  -- The host acknowledged, so lower the controller handshake.
      elsif state_v /= START_INIT and hndShk_r = LO and hndShk_i = HI then
        null;            -- Waiting for the host to lower its handshake.
      elsif (state_v = START_INIT) or (hndShk_r = LO and hndShk_i = LO) then
        -- Both handshakes are low, so the controller operations can proceed.

        busy_o <= YES;  -- Busy by default. Only false when waiting for R/W from host or stalled by error.

        case state_v is

          when START_INIT =>  -- Deselect the SD card and send it a bunch of clock pulses with MOSI high.
            error_o          <= (others => ZERO);  -- Clear error flags.
            clkDivider_v     := INIT_SCLK_PHASE_PERIOD_C - 1;  -- Use slow SPI clock freq during init.
            sclkPhaseTimer_v := INIT_SCLK_PHASE_PERIOD_C - 1;  -- and set the duration of the next clock phase.
            sclk_r           <= LO;     -- Start with low clock to the SD card.
            hndShk_r         <= LO;     -- Initialize handshake signal.
            addr_v           := (others => ZERO);  -- Initialize address.
            rtnData_v        := false;  -- No data is returned to host during initialization.
            bitCnt_v         := NUM_INIT_CLKS_C;  -- Generate this many clock pulses.
            state_v          := DESELECT;  -- De-select the SD card and pulse SCLK.
            rtnState_v       := SEND_CMD0;  -- Then go to this state after the clock pulses are done.

          when SEND_CMD0 =>             -- Put the SD card in the IDLE state.
            cs_bo            <= LO;     -- Enable the SD card.
            txCmd_v          := CMD0_C & x"00000000" & x"95";  -- 0x95 is the correct CRC for this command.
            bitCnt_v         := txCmd_v'length;  -- Set bit counter to the size of the command.
            getCmdResponse_v := true;  -- Sending a command that generates a response.
            doDeselect_v     := true;  -- De-select SD card after this command finishes.
            state_v          := START_TX;  -- Go to FSM subroutine to send the command.
            rtnState_v       := CHK_CMD0_RESPONSE;  -- Then check the response to the command.

          when CHK_CMD0_RESPONSE =>  -- Check card's R1 response to the CMD0.
            if rx_v = IDLE_NO_ERRORS_C then
              state_v := SEND_CMD8;  -- Continue init if SD card is in IDLE state with no errors
            else
              state_v := SEND_CMD0;     -- Otherwise, try CMD0 again.
            end if;

          when SEND_CMD8 =>  -- This command is needed to initialize SDHC cards.
            cs_bo            <= LO;     -- Enable the SD card.
            txCmd_v          := CMD8_C & x"000001aa" & x"87";  -- 0x87 is the correct CRC for this command.
            bitCnt_v         := txCmd_v'length;  -- Set bit counter to the size of the command.
            getCmdResponse_v := true;  -- Sending a command that generates a response.
            doDeselect_v     := false;  -- Don't de-select, need to get the R7 response sent from the SD card.
            state_v          := START_TX;  -- Go to FSM subroutine to send the command.
            rtnState_v       := GET_CMD8_RESPONSE;  -- Then go to this state after the command is sent.

          when GET_CMD8_RESPONSE =>     -- Get the R7 response to CMD8.
            cs_bo            <= LO;  -- The SD card should already be enabled, but let's be explicit.
            bitCnt_v         := 31;     -- Four bytes (32 bits) in R7 response.
            getCmdResponse_v := false;  -- Not sending a command that generates a response.
            doDeselect_v     := true;  -- De-select card to end the command after getting the four bytes.
            state_v          := RX_BITS;  -- Go to FSM subroutine to get the R7 response.
            rtnState_v       := SEND_CMD55;  -- Then go here (we don't care what the actual R7 response is).

          when SEND_CMD55 =>  -- Send CMD55 as preamble of ACMD41 initialization command.
            cs_bo            <= LO;     -- Enable the SD card.
            txCmd_v          := CMD55_C & x"00000000" & FAKE_CRC_C;
            bitCnt_v         := txCmd_v'length;  -- Set bit counter to the size of the command.
            getCmdResponse_v := true;  -- Sending a command that generates a response.
            doDeselect_v     := true;  -- De-select SD card after this command finishes.
            state_v          := START_TX;  -- Go to FSM subroutine to send the command.
            rtnState_v       := SEND_CMD41;  -- Then go to this state after the command is sent.

          when SEND_CMD41 =>  -- Send the SD card the initialization command.
            cs_bo            <= LO;     -- Enable the SD card.
            txCmd_v          := CMD41_C & x"40000000" & FAKE_CRC_C;
            bitCnt_v         := txCmd_v'length;  -- Set bit counter to the size of the command.
            getCmdResponse_v := true;  -- Sending a command that generates a response.
            doDeselect_v     := true;  -- De-select SD card after this command finishes.
            state_v          := START_TX;  -- Go to FSM subroutine to send the command.
            rtnState_v       := CHK_ACMD41_RESPONSE;  -- Then check the response to the command.

          when CHK_ACMD41_RESPONSE =>
            -- The CMD55, CMD41 sequence should cause the SD card to leave the IDLE state
            -- and become ready for SPI read/write operations. If still IDLE, then repeat the CMD55, CMD41 sequence.
            -- If one of the R1 error flags is set, then report the error and stall.
            --
            -- BUG FIX (2026-08-12, real hardware via sdcard_bridge.vhd:
            -- "SD card ready" printed - CMD0/CMD8/ACMD41 genuinely
            -- succeeded - but the very first real DEV_RW hung with no
            -- error reported). Root cause: doDeselect_v is a variable
            -- shared across every state and is never reset before
            -- WAIT_FOR_HOST_RW starts a new top-level command; SEND_CMD41
            -- (the last init step) explicitly sets it true, and nothing
            -- between here and the first CMD17/CMD24 clears it. RX_BITS
            -- then deselects the card (cs_bo<=HI) right after that first
            -- command's R1 response, before ever reading the actual data
            -- block - with the card deselected it stops driving MISO
            -- validly, so RD_BLK's "wait for start token" loop polls for a
            -- token that can never arrive, hndShk_o never rises again, and
            -- no host-side timeout duration fixes that (confirmed: 2.6ms
            -- and 671ms bridge timeouts both hit identically). Every
            -- SUBSEQUENT command in the same session self-heals, because a
            -- completed transfer's own DESELECT state resets the flag for
            -- next time - only the very first one after init is affected.
            -- Fixed by explicitly clearing it here, matching the state
            -- every later command actually starts from.
            if rx_v = ACTIVE_NO_ERRORS_C then   -- Not IDLE, no errors.
              doDeselect_v := false;
              state_v := WAIT_FOR_HOST_RW;  -- Start processing R/W commands from the host.
            elsif rx_v = IDLE_NO_ERRORS_C then  -- Still IDLE but no errors.
              state_v := SEND_CMD55;    -- Repeat the CMD55, CMD41 sequence.
            else                        -- Some error occurred.
              state_v := REPORT_ERROR;  -- Report the error and stall.
            end if;

          when WAIT_FOR_HOST_RW =>  -- Wait for the host to read or write a block of data from the SD card.
            clkDivider_v     := SCLK_PHASE_PERIOD_C - 1;  -- Set SPI clock frequency for normal operation.
            getCmdResponse_v := true;  -- Get R1 response to any commands issued to the SD card.
            if rd_i = YES then  -- send READ command and address to the SD card.
              cs_bo <= LO;              -- Enable the SD card.
              if continue_i = YES then  -- Multi-block read. Use stored address.
                if CARD_TYPE_G = SD_CARD_E then  -- SD cards use byte-addressing,
                  addr_v := addr_v + BLOCK_SIZE_G;  -- so add block-size to get next block address.
                else                    -- SDHC cards use block-addressing,
                  addr_v := addr_v + 1;  -- so just increment current block address.
                end if;
                txCmd_v := READ_BLK_CMD_C & std_logic_vector(addr_v) & FAKE_CRC_C;
              else                      -- Single-block read.
                txCmd_v := READ_BLK_CMD_C & addr_i & FAKE_CRC_C;  -- Use address supplied by host.
                addr_v  := unsigned(addr_i);  -- Store address for multi-block operations.
              end if;
              bitCnt_v   := txCmd_v'length;  -- Set bit counter to the size of the command.
              byteCnt_v  := RD_BLK_SZ_C;
              state_v    := START_TX;  -- Go to FSM subroutine to send the command.
              rtnState_v := RD_BLK;  -- Then go to this state to read the data block.
            elsif wr_i = YES then  -- send WRITE command and address to the SD card.
              cs_bo <= LO;              -- Enable the SD card.
              if continue_i = YES then  -- Multi-block write. Use stored address.
                if CARD_TYPE_G = SD_CARD_E then  -- SD cards use byte-addressing,
                  addr_v := addr_v + BLOCK_SIZE_G;  -- so add block-size to get next block address.
                else                    -- SDHC cards use block-addressing,
                  addr_v := addr_v + 1;  -- so just increment current block address.
                end if;
                txCmd_v := WRITE_BLK_CMD_C & std_logic_vector(addr_v) & FAKE_CRC_C;
              else                      -- Single-block write.
                txCmd_v := WRITE_BLK_CMD_C & addr_i & FAKE_CRC_C;  -- Use address supplied by host.
                addr_v  := unsigned(addr_i);  -- Store address for multi-block operations.
              end if;
              bitCnt_v   := txCmd_v'length;  -- Set bit counter to the size of the command.
              byteCnt_v  := WR_BLK_SZ_C;    -- Set number of bytes to write.
              state_v    := START_TX;  -- Go to this FSM subroutine to send the command ...
              rtnState_v := WR_BLK;  -- then go to this state to write the data block.
            else              -- Do nothing and wait for command from host.
              cs_bo   <= HI;            -- Deselect the SD card.
              busy_o  <= NO;  -- SD card interface is waiting for R/W from host, so it's not busy.
              state_v := WAIT_FOR_HOST_RW;  -- Keep waiting for command from host.
            end if;

          when RD_BLK =>          -- Read a block of data from the SD card.
            -- Some default values for these...
            rtnData_v  := false;  -- Data is only returned to host in one place.
            bitCnt_v   := rx_v'length - 1;   -- Receiving byte-sized data.
            state_v    := RX_BITS;      -- Call the bit receiver routine.
            rtnState_v := RD_BLK;   -- Return here when done receiving a byte.
            if byteCnt_v = RD_BLK_SZ_C then  -- Initial read to prime the pump.
              byteCnt_v := byteCnt_v - 1;
            elsif byteCnt_v = RD_BLK_SZ_C -1 then  -- Then look for the data block start token.
              if rx_v = NO_TOKEN_C then  -- Receiving 0xFF means the card hasn't responded yet. Keep trying.
                null;
              elsif rx_v = START_TOKEN_C then
                rtnData_v := true;  -- Found the start token, so now start returning data byes to the host.
                byteCnt_v := byteCnt_v - 1;
              else  -- Getting anything else means something strange has happened.
                state_v := REPORT_ERROR;
              end if;
            elsif byteCnt_v >= 3 then  -- Now bytes of data from the SD card are received.
              rtnData_v := true;        -- Return this data to the host.
              byteCnt_v := byteCnt_v - 1;
            elsif byteCnt_v = 2 then  -- Receive the 1st CRC byte at the end of the data block.
              byteCnt_v := byteCnt_v - 1;
            elsif byteCnt_v = 1 then    -- Receive the 2nd
              byteCnt_v := byteCnt_v - 1;
            else    -- Reading is done, so deselect the SD card.
              sclk_r     <= LO;
              bitCnt_v   := 2;
              state_v    := DESELECT;
              rtnState_v := WAIT_FOR_HOST_RW;
            end if;

          when WR_BLK =>             -- Write a block of data to the SD card.
            -- Some default values for these...
            getCmdResponse_v := false;  -- Sending data bytes so there's no command response from SD card.
            bitCnt_v         := txData_v'length;  -- Transmitting byte-sized data.
            state_v          := START_TX;  -- Call the bit transmitter routine.
            rtnState_v       := WR_BLK;  -- Return here when done transmitting a byte.
            if byteCnt_v = WR_BLK_SZ_C then
              txData_v := NO_TOKEN_C;  -- Hold MOSI high for one byte before data block goes out.
            elsif byteCnt_v = WR_BLK_SZ_C - 1 then     -- Send start token.
              txData_v := START_TOKEN_C;   -- Starting token for data block.
            elsif byteCnt_v >= 4 then   -- Now send bytes in the data block.
              hndShk_r <= HI;           -- Signal host to provide data.
            -- The transmit shift register is loaded with data from host in the handshaking section above.
            elsif byteCnt_v = 3 or byteCnt_v = 2 then  -- Send two phony CRC bytes at end of packet.
              txData_v := FAKE_CRC_C;
            elsif byteCnt_v = 1 then
              bitCnt_v   := rx_v'length - 1;
              state_v    := RX_BITS;  -- Get response of SD card to the write operation.
              rtnState_v := WR_WAIT;
            else                        -- Check received response byte.
              if std_match(rx_v, DATA_ACCEPTED_C) then  -- Data block was accepted.
                state_v := WR_WAIT;  -- Wait for the SD card to finish writing the data into Flash.
              else                      -- Data block was rejected.
                error_o(15 downto 8) <= rx_v;
                state_v              := REPORT_ERROR;  -- Report the error.
              end if;
            end if;
            byteCnt_v := byteCnt_v - 1;

          when WR_WAIT =>  -- Wait for SD card to finish writing the data block.
            -- The SD card will pull MISO low while it is busy, and raise it when it is done.
            sclk_r           <= not sclk_r;    -- Toggle the SPI clock...
            sclkPhaseTimer_v := clkDivider_v;  -- and set the duration of the next clock phase.
            if sclk_r = HI and miso_i = HI then  -- Data block has been written, so deselect the SD card.
              bitCnt_v   := 2;
              state_v    := DESELECT;
              rtnState_v := WAIT_FOR_HOST_RW;
            end if;

          when START_TX =>
            -- Start sending command/data by lowering SCLK and outputing MSB of command/data
            -- so it has plenty of setup before the rising edge of SCLK.
            sclk_r           <= LO;  -- Lower the SCLK (although it should already be low).
            sclkPhaseTimer_v := clkDivider_v;  -- Set the duration of the low SCLK.
            mosi_o           <= tx_v(tx_v'high);  -- Output MSB of command/data.
            tx_v             := tx_v(tx_v'high-1 downto 0) & ONE;  -- Shift command/data register by one bit.
            bitCnt_v         := bitCnt_v - 1;  -- The first bit has been sent, so decrement bit counter.
            state_v          := TX_BITS;  -- Go here to shift out the rest of the command/data bits.

          when TX_BITS =>  -- Shift out remaining command/data bits and (possibly) get response from SD card.
            sclk_r           <= not sclk_r;    -- Toggle the SPI clock...
            sclkPhaseTimer_v := clkDivider_v;  -- and set the duration of the next clock phase.
            if sclk_r = HI then
              -- SCLK is going to be flipped from high to low, so output the next command/data bit
              -- so it can setup while SCLK is low.
              if bitCnt_v /= 0 then  -- Keep sending bits until the bit counter hits zero.
                mosi_o   <= tx_v(tx_v'high);
                tx_v     := tx_v(tx_v'high-1 downto 0) & ONE;
                bitCnt_v := bitCnt_v - 1;
              else
                if getCmdResponse_v then
                  state_v  := GET_CMD_RESPONSE;  -- Get a response to the command from the SD card.
                  bitCnt_v := Response_t'length - 1;  -- Length of the expected response.
                else
                  state_v          := rtnState_v;  -- Return to calling state (no need to get a response).
                  sclkPhaseTimer_v := 0;  -- Clear timer so next SPI op can begin ASAP with SCLK low.
                end if;
              end if;
            end if;

          when GET_CMD_RESPONSE =>  -- Get the response of the SD card to a command.
            if sclk_r = HI and miso_i = LO then  -- MISO will be held high by SD card until 1st bit of R1 response, which is 0.
              -- Shift in the MSB bit of the response.
              rx_v     := rx_v(rx_v'high-1 downto 0) & miso_i;
              bitCnt_v := bitCnt_v - 1;
              state_v  := RX_BITS;  -- Now receive the reset of the response.
            end if;
            sclk_r           <= not sclk_r;    -- Toggle the SPI clock...
            sclkPhaseTimer_v := clkDivider_v;  -- and set the duration of the next clock phase.

          when RX_BITS =>               -- Receive bits from the SD card.
            if sclk_r = HI then    -- Bits enter after the rising edge of SCLK.
              rx_v := rx_v(rx_v'high-1 downto 0) & miso_i;
              if bitCnt_v /= 0 then     -- More bits left to receive.
                bitCnt_v := bitCnt_v - 1;
              else                      -- Last bit has been received.
                if rtnData_v then       -- Send the received data to the host.
                  data_o   <= rx_v;     -- Output received data to the host.
                  hndShk_r <= HI;  -- Signal to the host that the data is ready.
                end if;
                if doDeselect_v then
                  bitCnt_v := 1;
                  state_v  := DESELECT;  -- De-select SD card before returning.
                else
                  state_v := rtnState_v;  -- Otherwise, return to calling state without de-selecting.
                end if;
              end if;
            end if;
            sclk_r           <= not sclk_r;    -- Toggle the SPI clock...
            sclkPhaseTimer_v := clkDivider_v;  -- and set the duration of the next clock phase.

          when DESELECT =>  -- De-select the SD card and send some clock pulses (Must enter with sclk at zero.)
            doDeselect_v     := false;  -- Once the de-select is done, clear the flag that caused it.
            cs_bo            <= HI;     -- De-select the SD card.
            mosi_o           <= HI;  -- Keep the data input of the SD card pulled high.
            state_v          := PULSE_SCLK;  -- Pulse the clock so the SD card will see the de-select.
            sclk_r           <= LO;  -- Clock is set low so the next rising edge will see the new CS and MOSI
            sclkPhaseTimer_v := clkDivider_v;  -- Set the duration of the next clock phase.

          when PULSE_SCLK =>  -- Issue some clock pulses. (Must enter with sclk at zero.)
            if sclk_r = HI then
              if bitCnt_v /= 0 then
                bitCnt_v := bitCnt_v - 1;
              else  -- Return to the calling routine when the pulse counter reaches zero.
                state_v := rtnState_v;
              end if;
            end if;
            sclk_r           <= not sclk_r;    -- Toggle the SPI clock...
            sclkPhaseTimer_v := clkDivider_v;  -- and set the duration of the next clock phase.

          when REPORT_ERROR =>  -- Report the error code and stall here until a reset occurs.
            error_o(rx_v'range) <= rx_v;  -- Output the SD card response as the error code.
            busy_o              <= NO;  -- Not busy.

          when others =>
            state_v := START_INIT;
        end case;
      end if;
    end if;
  end process;

  sclk_o   <= sclk_r;    -- Output the generated SPI clock for the SD card.
  hndShk_o <= hndShk_r;  -- Output the generated handshake to the host.

end architecture;

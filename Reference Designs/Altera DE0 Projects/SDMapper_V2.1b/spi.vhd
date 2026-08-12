library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi is
	port(
		clock_i			: in    std_logic;
		reset_n_i		: in    std_logic;
		-- CPU interface
		cs_i				: in    std_logic;
		data_bus_io		: inout std_logic_vector(7 downto 0);
		wr_n_i			: in    std_logic;
		rd_n_i			: in    std_logic;
		wait_n_o			: out   std_logic;
		-- SPI interface
		spi_sclk_o		: out   std_logic;
		spi_mosi_o		: out   std_logic;
		spi_miso_i		: in    std_logic;
		--
		spi_dout			: out		std_logic_vector(7 downto 0);
		spi_rd_en		: out 	std_logic
	);

end entity;

architecture Behavioral of spi is

	signal spi_data_q			: std_logic_vector(7 downto 0);
	-- State type of the SPI transfer state machine
	type   state_type_t is (s_idle, s_cleaning, s_running, s_done);
	signal state_s				: state_type_t;
	signal shift_reg_s		: std_logic_vector(8 downto 0);	-- Shift register
	signal spi_data_buf_s	: std_logic_vector(7 downto 0);	-- Buffer to hold data to be sent
	signal start_s				: std_logic;							-- Start transmission flag
	signal count_q				: unsigned(3 downto 0);				-- Number of bits transfered
	signal spi_clk_buf_s		: std_logic;							-- Buffered SPI clock
	signal spi_clk_out_s		: std_logic;							-- Buffered SPI clock output
	signal prev_spi_clk_s	: std_logic;							-- Previous SPI clock state
	signal ff_q, ff_clr_s	: std_logic;
	signal wait_n_s			: std_logic;

	-- ------------------------------------------------------------------------
	-- STABILITY FIX:
	-- The original design computed "spi_cs_s <= cs_i AND (rd_n_i='0' OR
	-- wr_n_i='0')" combinationally and clocked the R/W-port process directly
	-- off it ("elsif rising_edge(spi_cs_s)"). cs_i, rd_n_i and wr_n_i are
	-- asynchronous MSX bus signals with independent propagation delays; on
	-- real Z80 hardware this combinational expression can glitch, causing
	-- spurious/missed transaction starts. This is the same "combinational
	-- signal used as a clock" hazard found and fixed elsewhere in this
	-- project (mapper registers, ROM bank switch, SD slot select).
	--
	-- Fix: spi_cs_s is still computed the same way, but it is now only ever
	-- used as a DATA input into a synchronizer clocked by the real clock_i
	-- oscillator. The transaction start is derived from the rising edge of
	-- the *synchronized, glitch-free* signal instead.
	-- ------------------------------------------------------------------------
	--
	-- BUG FIX (2026-08-11, real hardware: Nextor reported "SD Card 1: Failed"
	-- - card presence detection worked, but every actual SPI transaction with
	-- the card did not). Root cause, confirmed via a dedicated GHDL
	-- testbench (sim/tb_spi.vhd) with direct FSM visibility: wait_n_s was
	-- only ever asserted low (busy) inside the "when s_running" branch under
	-- "if start_s = '1'" - but start_s is cleared (via ff_clr_s, asserted
	-- one cycle earlier during "when s_cleaning") exactly ONE cycle BEFORE
	-- state_s actually reaches s_running, so that condition can never be
	-- true. The 8-bit shift transfer itself (clock generation, shifting,
	-- state_s reaching s_done) completes correctly and on time regardless -
	-- only the CPU-facing wait_n_o output was ever wrong, permanently stuck
	-- high (idle/"never wait"). On real hardware this means the Z80 never
	-- actually pauses for the SPI transfer and always samples stale/garbage
	-- data on every access, which would make a real SD card look completely
	-- unresponsive to the protocol - matching the observed symptom exactly.
	-- Fix: wait_n_s is now driven directly off state_s (the authoritative
	-- "is a transfer in progress" signal) instead of the stale start_s flag -
	-- asserted low for the whole s_cleaning/s_running duration, released
	-- high again once s_done is reached and the result is ready to read.
	-- ------------------------------------------------------------------------
	signal spi_cs_s			: std_logic;
	signal spi_cs_meta, spi_cs_sync, spi_cs_sync_d	: std_logic;
	signal rd_n_meta, rd_n_sync								: std_logic;
	signal spi_cs_rising_pulse								: std_logic;

begin

	spi_cs_s <= '1' when cs_i = '1' and (rd_n_i = '0' or wr_n_i = '0')	else '0';

	-- flip-flop
	process(ff_clr_s, clock_i)
	begin
		if ff_clr_s = '1' then
			ff_q	<= '0';
		elsif rising_edge(clock_i) then
			ff_q	<= start_s;
		end if;
	end process;

	-- Data read
	-- data_bus_io <= spi_data_q	when cs_i = '1' and rd_n_i = '0'	else
	--					(others => 'Z');

	spi_dout <= spi_data_q	when cs_i = '1' and rd_n_i = '0';
	spi_rd_en <= '1' when cs_i = '1' and rd_n_i = '0' else '0';

	-- ------------------------------------------------------------------------
	-- Synchronize spi_cs_s and rd_n_i into the clock_i domain, in lock-step
	-- with each other, so both are aligned to the same clock edges when we
	-- act on them below. 3 stages on spi_cs_s: "meta" absorbs metastability,
	-- "sync" is the resolved/safe value, "sync_d" is one cycle behind it for
	-- edge detection. rd_n_i only needs 2 stages since we just need its
	-- settled value at the moment the pulse fires, not an edge on it.
	-- ------------------------------------------------------------------------
	process(clock_i)
	begin
		if rising_edge(clock_i) then
			spi_cs_meta   <= spi_cs_s;
			spi_cs_sync   <= spi_cs_meta;
			spi_cs_sync_d <= spi_cs_sync;

			rd_n_meta <= rd_n_i;
			rd_n_sync <= rd_n_meta;
		end if;
	end process;

	-- One clock_i-wide pulse marking the start of a genuine access
	spi_cs_rising_pulse <= spi_cs_sync and not spi_cs_sync_d;

	-- R/W port - now fully synchronous, triggered by the synchronized pulse
	-- instead of being clocked directly off spi_cs_s.
	process (clock_i)
	begin
		if rising_edge(clock_i) then
			if reset_n_i = '0' or ff_clr_s = '1' then
				spi_data_buf_s	<= (others => '1');
				start_s			<= '0';
			elsif spi_cs_rising_pulse = '1' then
				if rd_n_sync = '0' then
					spi_data_buf_s <= (others => '1');
				else
					spi_data_buf_s <= data_bus_io;
				end if;
				start_s <= '1';
			end if;
		end if;
	end process;

	--------------------------------------------------
	-- Essa parte lida com a porta SPI por hardware --
	--      Implementa um SPI Master Mode 0         --
	--------------------------------------------------

	-- SPI write
	process(clock_i, reset_n_i)
	begin		
		if reset_n_i = '0' then
			ff_clr_s <= '0';
		elsif rising_edge(clock_i) then

			prev_spi_clk_s <= spi_clk_buf_s;
			case state_s is

				when s_idle =>
					if ff_q = '1' then
						count_q     <= (others => '0');
						shift_reg_s <= spi_data_buf_s & '1';
						state_s     <= s_cleaning;
						ff_clr_s    <= '1';
					end if;
					wait_n_s	<= '1';

				when s_cleaning =>
					ff_clr_s	<= '0';
					state_s	<= s_running;
					wait_n_s	<= '0';

				when s_running =>
					wait_n_s	<= '0';
					if prev_spi_clk_s = '1' and spi_clk_buf_s = '0' then
						spi_clk_out_s <= '0';
						count_q       <= count_q + 1;
						shift_reg_s   <= shift_reg_s(7 downto 0) & spi_miso_i;
						if count_q = "0111" then
							state_s		<= s_done;
						end if;
					elsif prev_spi_clk_s = '0' and spi_clk_buf_s = '1' then
						spi_clk_out_s <= '1';
					end if;

				when s_done =>
					spi_data_q	<= shift_reg_s(7 downto 0);
					state_s		<= s_idle;
					wait_n_s		<= '1';

				when others =>
					null;
			end case;
		end if;
	end process;

	-- Generate SPI clock
	--
	-- REVERTED (2026-08-11): a clock-divider was briefly added here (dividing
	-- clock_i by 64, targeting SD-spec-compliant ~390.6kHz SCLK for the
	-- card's identification phase, reasoning that the previous fixed
	-- ~12.5MHz SCLK was ~31x over the spec's 100-400kHz identification-phase
	-- limit). That change caused a full system hang on real hardware (MSX
	-- froze before even showing the boot logo) - strictly worse than the
	-- prior "SD Card 1: Failed" result, which at least booted successfully.
	-- Since the WAIT_n fix alone (without this divider) was ALREADY
	-- confirmed on real hardware not to hang, and WAIT_n's Q2-inversion
	-- polarity was independently re-confirmed correct by reading
	-- Hardware Interface/MSX_FPGA_Hat.net directly (IDC1 pin5 "C_WAIT" ->
	-- U5 A7/B7 -> R8 -> Q2 base; Q2 emitter grounded, collector on the real
	-- /WAIT net - a Q2-HIGH-turns-transistor-ON open-collector inverter,
	-- matching the existing WAIT_n<=not(wait_n_o) convention), the clock
	-- speed theory - while plausible in principle - is not what's actually
	-- breaking this design, or at least holding WAIT_n for the resulting
	-- ~20.5us/byte (vs ~900ns/byte) causes a separate, worse real-hardware
	-- problem of its own (most likely explanation: Nextor's SD probing runs
	-- very early, before the boot banner, and either hits an internal
	-- timing assumption or the extended WAIT_n hold starves MSX DRAM
	-- refresh - not confirmed, just the leading theory). Reverted to the
	-- original fixed ~12.5MHz rate (divide clock_i by 2) pending a
	-- different diagnosis strategy for the still-open "SD Card 1: Failed"
	-- result - see the HEX/LEDG diagnostics added in SDMapper_Top.vhd
	-- (last SPI byte sent/received) for the next round of real evidence.
	spi_clock_gen : process(clock_i, reset_n_i)
	begin
		if reset_n_i = '0' then
			spi_clk_buf_s   <= '0';
		elsif rising_edge(clock_i) then
			if state_s = s_running then
				spi_clk_buf_s <= not spi_clk_buf_s;
			else
				spi_clk_buf_s <= '0';
			end if;
		end if;
	end process;

	spi_mosi_o <= shift_reg_s(8);
	spi_sclk_o <= spi_clk_out_s;
	wait_n_o	<= wait_n_s;

end architecture;

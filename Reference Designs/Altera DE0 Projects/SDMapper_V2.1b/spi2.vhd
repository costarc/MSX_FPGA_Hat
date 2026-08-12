-- SDMapper_V2.1b: ALTERNATE SPI engine, ported from Belavenuto's own
-- msxsdmapperv2/CPLD/src/spi2.vhd (same author/repo as spi.vhd, an
-- alternate/newer implementation sitting unused alongside the one we
-- originally ported).
--
-- WHY THIS FILE EXISTS (2026-08-12): spi.vhd's wait_n_s/start_s bug (stale
-- flag causing WAIT_n to never assert) was found and fixed, plus five other
-- real fixes (pull-ups, status_s polarity, timer clock domain, U1_DIR
-- polarity, WAIT_n inversion), yet "Card Failed!" still persists on real
-- hardware. The physical layer was cross-tested and ruled out (same
-- card+adapter works via an independent core on two different DE0 boards).
-- Before pivoting to a completely different SD protocol (MegaSD/ESE-RAM,
-- for which no driver source exists to verify against), this is a much
-- cheaper experiment: swap in Belavenuto's OWN alternate WAIT-generation
-- mechanism, still using the exact same register protocol/driver
-- (DRIVER.ASM, SPIDATA/SPICTRL/TIMERREG unchanged).
--
-- spi.vhd's wait_n_s is driven from a small explicit state machine
-- (s_idle/s_cleaning/s_running/s_done) gated by a "start_s" flag. spi2's
-- wait_n_s is driven from a free-running countdown (wait_cnt_q) that always
-- finishes a fixed number of cycles after the last bit shifts out,
-- independent of any flag - a structurally different mechanism that could
-- behave differently around edge cases spi.vhd's flag-based approach might
-- still be getting wrong even after the start_s fix.
--
-- ADAPTATION FROM THE ORIGINAL: only the CPU-interface plumbing was changed,
-- to match this project's own already-proven conventions (see spi.vhd's
-- "STABILITY FIX" comment for why):
--   - cs_i is synchronized into clock_i via the same 3-stage meta/sync/sync_d
--     treatment spi.vhd uses, instead of spi2's own raw/unsynchronized
--     port_en_s sampled directly into a 2-stage edge detector. The original
--     spi2.vhd samples a combinationally-derived async signal (from
--     independent cs_i/rd_n_i/wr_n_i inputs) with no synchronizer stage
--     first - exactly the "combinational signal used across clock domains"
--     hazard class spi.vhd's own header comment documents as already found
--     and fixed elsewhere in this project. Porting that same fix here keeps
--     this a true apples-to-apples test of ONLY the WAIT mechanism.
--   - data_bus_io is read-only here (spi_data_buf_s latches it at transfer
--     start), never driven directly - this project's top level owns D-bus
--     arbitration itself via its own single "D <= ..." mux (see
--     SDMapper_Top.vhd's "Load the MSX bus with data" comment), so this
--     component exposes spi_dout/spi_rd_en instead (same extra ports
--     spi.vhd already has), rather than driving data_bus_io as an inout the
--     way the original spi2.vhd does.
--   - The core transfer engine itself (shift_r/counter_s/sck_delayed_s/
--     wait_cnt_q) is preserved faithfully, including its ~clock_i-rate SCLK
--     (no /2 divider - counter_s(0) toggles every clock_i cycle, so SCLK
--     does too, roughly double spi.vhd's ~12.5MHz). This is Belavenuto's
--     own tested rate in his alternate design, not something introduced
--     here - not second-guessed, to keep this a faithful port.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spi2 is
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

architecture Behavioral of spi2 is

	-- CPU-interface synchronization (ported from spi.vhd's own proven fix)
	signal spi_cs_s			: std_logic;
	signal spi_cs_meta, spi_cs_sync, spi_cs_sync_d	: std_logic;
	signal rd_n_meta, rd_n_sync								: std_logic;
	signal spi_cs_rising_pulse								: std_logic;
	signal spi_data_buf_s	: std_logic_vector(7 downto 0);
	signal start_s				: std_logic;

	-- Transfer engine.
	--
	-- BUG FIX (2026-08-12, found by sim/tb_spi2.vhd): the ORIGINAL spi2.vhd
	-- split MISO-capture and MOSI-shift into two separate half-cycle
	-- actions, gated by a plain level-check on a once-registered "delayed
	-- SCK" signal. Every phase assignment tried (matching the original
	-- as-is, swapping which phase does which) either corrupted every READ
	-- (0x3C came back as 0x1E or 0x3D depending on the variant) or broke
	-- MOSI ordering on WRITEs - the split-action technique can't be
	-- phase-aligned to satisfy both directions from a single level check.
	-- Since SD responses are read data, this would have broken card access
	-- outright, worse than spi.vhd's now-fixed wait_n_s bug.
	--
	-- Fixed by dropping spi2's split-action technique entirely and reusing
	-- spi.vhd's own ALREADY-PROVEN engine structure instead (real edge
	-- detection via prev-vs-current comparison of an internal toggle
	-- signal, one COMBINED shift+capture action per bit, a separately
	-- registered/buffered SCLK output) - the one deliberate difference kept
	-- is WAIT release: wait_cnt_q counts down after the last bit instead of
	-- deasserting immediately on state_s reaching s_done, which is the
	-- actual mechanism this file exists to test (see file header).
	signal shift_r			: std_logic_vector(8 downto 0);
	signal port_r			: std_logic_vector(7 downto 0);
	signal busy_s			: std_logic := '0';
	signal count_q			: unsigned(3 downto 0) := (others => '0');	-- bits transferred so far (0-7)
	signal spi_clk_buf_s	: std_logic := '0';	-- internal toggle, one edge per SPI_DIV_MAX+1 clock_i cycles while busy
	signal spi_clk_out_s	: std_logic := '0';	-- externally-visible SCLK, registered one cycle behind spi_clk_buf_s
	signal wait_n_s		: std_logic := '1';
	signal wait_cnt_q		: unsigned(3 downto 0) := (others => '0');

	-- CLOCK DIVIDER (2026-08-12): with both spi.vhd and this now bit-
	-- verified-correct spi2 engine still getting "Card Failed!"/all-0xFF
	-- responses on real hardware, the remaining shared suspect is SCLK rate
	-- - both engines run SCLK at ~clock_i/2 (~12.5MHz) even during the SD
	-- card's identification phase (CMD0/CMD8/ACMD41), which the SD spec caps
	-- at 400kHz - roughly 30x over. A full spec-compliant /64 divider was
	-- tried once before (on the old, since-fixed spi.vhd) and caused a
	-- hard hang, but that attempt was confounded with a real WAIT_n bug
	-- that has since been fixed - not a clean test of the clock-rate theory
	-- on its own. This is a much more conservative middle ground: divide by
	-- 4 (toggle spi_clk_buf_s once every SPI_DIV_MAX+1=4 clock_i cycles
	-- instead of every cycle), giving SCLK ~= clock_i/8 (~3.1MHz) - still
	-- ~8x over spec but keeps WAIT_n hold times short (~1.3us/byte instead
	-- of the ~20.5us/byte the full /64 divider produced), to isolate
	-- whether ANY slowdown helps before considering something more drastic.
	--
	-- REVERTED (2026-08-12): real hardware test with SPI_DIV_MAX="11"
	-- (SCLK ~= clock_i/8) reached BASIC (same "Card Failed!" as the
	-- undivided rate - card still never responds) but then hung a few
	-- seconds later, a NEW regression not present at the undivided rate.
	-- This is consistent with the refresh-starvation risk flagged before
	-- testing - even at ~8x over spec (far short of the full /64 attempt's
	-- ~30x-under-spec-compliant rate), extending WAIT_n hold time appears to
	-- cause real instability on this hardware. SPI_DIV_MAX="00" (no
	-- division, matching spi.vhd's own ~12.5MHz) restores the known-stable
	-- (if still non-card-detecting) behaviour. Divider infrastructure kept
	-- in place in case a future, more targeted use is warranted, but not to
	-- be re-enabled without a specific new reason.
	signal div_cnt			: unsigned(1 downto 0) := (others => '0');
	constant SPI_DIV_MAX	: unsigned(1 downto 0) := "00";

begin

	spi_cs_s <= '1' when cs_i = '1' and (rd_n_i = '0' or wr_n_i = '0')	else '0';

	spi_dout  <= port_r when cs_i = '1' and rd_n_i = '0';
	spi_rd_en <= '1' when cs_i = '1' and rd_n_i = '0' else '0';

	-- Synchronize spi_cs_s/rd_n_i into clock_i, exactly as spi.vhd does.
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

	spi_cs_rising_pulse <= spi_cs_sync and not spi_cs_sync_d;

	-- Latch the byte to transmit (all-1s for a read, real data for a write)
	-- and pulse start_s for exactly one clock_i cycle on a genuine access.
	process (clock_i)
	begin
		if rising_edge(clock_i) then
			if reset_n_i = '0' then
				spi_data_buf_s	<= (others => '1');
				start_s			<= '0';
			elsif spi_cs_rising_pulse = '1' then
				if rd_n_sync = '0' then
					spi_data_buf_s <= (others => '1');
				else
					spi_data_buf_s <= data_bus_io;
				end if;
				start_s <= '1';
			else
				start_s <= '0';
			end if;
		end if;
	end process;

	-- Core engine: real falling/rising edge detection on the internal
	-- toggle signal (spi_clk_buf_s), combined shift+capture on the falling
	-- edge, separately-registered SCLK output - structure copied from
	-- spi.vhd's proven "SPI write" process, with wait_cnt_q (counter-based
	-- WAIT release) substituted for spi.vhd's state_s/s_done mechanism.
	process(clock_i, reset_n_i)
	begin
		if reset_n_i = '0' then
			shift_r			<= (others => '1');
			port_r			<= (others => '1');
			busy_s			<= '0';
			count_q			<= (others => '0');
			div_cnt			<= (others => '0');
			spi_clk_buf_s	<= '0';
			spi_clk_out_s	<= '0';
			wait_n_s			<= '1';
			wait_cnt_q		<= (others => '0');
		elsif rising_edge(clock_i) then
			if busy_s = '0' then
				port_r		<= shift_r(7 downto 0);
				shift_r(8)	<= '1';
				spi_clk_buf_s	<= '0';
				div_cnt			<= (others => '0');
				if wait_cnt_q /= 0 then
					wait_cnt_q	<= wait_cnt_q - 1;
				else
					wait_n_s		<= '1';
				end if;

				if start_s = '1' then
					shift_r   <= spi_data_buf_s & '1';
					count_q   <= (others => '0');
					busy_s    <= '1';
				end if;
			else
				wait_n_s		<= '0';
				wait_cnt_q	<= (others => '1');

				-- BUG FIX #3 (2026-08-12, found by sim/tb_spi2.vhd): comparing
				-- prev_spi_clk_s against spi_clk_buf_s as a level check only
				-- works as an edge detector if spi_clk_buf_s is guaranteed to
				-- change EVERY cycle (as it did before this divider existed) -
				-- with SPI_DIV_MAX gating the toggle to once every 4 cycles,
				-- prev_spi_clk_s and spi_clk_buf_s now hold their post-toggle
				-- values for the whole 4-cycle gap, so the old level check
				-- fired the shift+capture action on EVERY one of those cycles
				-- instead of once - count_q raced to "0111" in 4 back-to-back
				-- cycles instead of 8 real bit periods (confirmed via a
				-- temporary internal DBG report trace). Fixed by tying the
				-- shift+capture action directly to the toggle event itself
				-- (inside the branch that performs it, keyed off
				-- spi_clk_buf_s's PRE-toggle value), so it fires exactly once
				-- per actual edge regardless of divider rate.
				if div_cnt /= SPI_DIV_MAX then
					div_cnt <= div_cnt + 1;
				else
					div_cnt <= (others => '0');
					spi_clk_buf_s <= not spi_clk_buf_s;

					if spi_clk_buf_s = '1' then		-- about to fall (1 -> 0)
						spi_clk_out_s <= '0';
						shift_r       <= shift_r(7 downto 0) & spi_miso_i;
						if count_q = "0111" then
							busy_s <= '0';	-- 8th bit just captured
						else
							count_q <= count_q + 1;
						end if;
					else										-- about to rise (0 -> 1)
						spi_clk_out_s <= '1';
					end if;
				end if;
			end if;
		end if;
	end process;

	spi_mosi_o <= shift_r(8);
	spi_sclk_o <= spi_clk_out_s;
	wait_n_o	<= wait_n_s;

end architecture;

-- sdcard_bridge.vhd
--
-- Byte-level Z80-bus register bridge for the ported XESS SdCardCtrl core
-- (sdcard_xess.vhd). This is the ONLY new component the Nextor driver
-- talks to - it hides SdCardCtrl's handshake/block-level protocol behind
-- a simple set of poke/peek registers, the same style DRIVER.ASM's
-- SPIDATA/SPICTRL registers already used for the (now abandoned) raw-SPI
-- protocol, so the WAIT_n/CPU-interface plumbing follows this project's
-- own already-proven conventions (see spi.vhd's "STABILITY FIX" comment).
--
-- REGISTER MAP (all offsets from this bridge's base address - see
-- SDMapper_Top.vhd for where that lands in the Z80 address space):
--   0  SD_DATA   (R/W) - next byte to/from the SD card during an active
--                        block read/write. Every access here blocks the
--                        Z80 (WAIT_n) until SdCardCtrl's handshake
--                        completes for that byte, or until a bridge-level
--                        timeout gives up (see TIMEOUT_MAX_C below) -
--                        this timeout is NOT part of XESS's own design,
--                        it's added here because a WAIT_n that could get
--                        stuck asserted forever (e.g. if the SD card
--                        errors out mid-transfer and SdCardCtrl's FSM
--                        stalls in REPORT_ERROR without ever raising
--                        hndShk_o again) would hang the whole MSX, not
--                        just the driver.
--   1  SD_ADDR0  (W)   - block address bits 7:0
--   2  SD_ADDR1  (W)   - block address bits 15:8
--   3  SD_ADDR2  (W)   - block address bits 23:16
--   4  SD_ADDR3  (W)   - block address bits 31:24 (SDHC card, so this is
--                        a block/sector number, not a byte address)
--   5  SD_CMD    (W)   - bit7=1: pulse reset_i (re-run CMD0/CMD8/ACMD41
--                          init sequence from scratch)
--                        bit1=1: pulse wr_i (start a block WRITE using
--                          SD_ADDR0-3)
--                        bit0=1: pulse rd_i (start a block READ using
--                          SD_ADDR0-3)
--                        bit2  : continue_i, sampled together with the
--                          rd_i/wr_i pulse (multi-block sequential access)
--                        Only one of bit7/bit1/bit0 should be set per
--                        write; if more than one is set bit7 wins, then
--                        bit1, then bit0.
--   6  SD_STATUS (R)   - bit0: busy_o (SdCardCtrl is mid-operation)
--                        bit1: (error_o /= 0) - SdCardCtrl stalled on an
--                          error, needs a SD_CMD bit7 reset to recover
--                        bit2: card present (SW(0), same convention as
--                          the abandoned SPI design)
--                        bit3: write-protect (SW(2), same convention)
--                        bit4: sticky bridge-timeout flag (see SD_DATA) -
--                          cleared automatically on the next SD_CMD write
--   7  SD_ERRLO  (R)   - error_o(7 downto 0), for diagnostics
--   8  SD_ERRHI  (R)   - error_o(15 downto 8), for diagnostics
--
-- CLOCK DOMAIN: this whole bridge (and the SdCardCtrl instance it wraps)
-- runs on clock_i (25MHz) - same domain split rationale as spi.vhd/spi2.vhd
-- before it (see SDMapper_Top.vhd's "CLOCK DOMAINS" note). CPU-facing
-- inputs (cs_i, rd_n_i, wr_n_i) are synchronized into clock_i internally,
-- the same 3-stage meta/sync/sync_d technique already proven there.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.SdCardXessPckg.all;

entity sdcard_bridge is
	port (
		clock_i			: in    std_logic;		-- 25MHz
		reset_n_i		: in    std_logic;
		-- CPU interface
		cs_i				: in    std_logic;		-- asserted when the Z80 addresses this bridge's register range
		reg_addr_i		: in    std_logic_vector(3 downto 0);	-- register index (0-8), see map above
		-- Input-only, exactly like spi.vhd's own data_bus_i - this bridge
		-- never drives the MSX data bus itself, it only ever reads write
		-- data off it. The top level owns D-bus arbitration via its own
		-- single "D <= ..." mux (see SDMapper_Top.vhd), incorporating
		-- reg_dout/sd_dout below into that mux exactly like spi.vhd's own
		-- spi_dout/spi_rd_en - avoids any dual-driver ambiguity.
		data_bus_i		: in    std_logic_vector(7 downto 0);
		wr_n_i			: in    std_logic;
		rd_n_i			: in    std_logic;
		wait_n_o			: out   std_logic;
		card_present_i	: in    std_logic;		-- SW(0)
		write_protect_i: in    std_logic;		-- SW(2)
		-- Register-read data, for the top level's D-bus mux. reg_dout is
		-- the immediate/combinational content of SD_STATUS/SD_ERRLO/
		-- SD_ERRHI (top level qualifies when to actually mux it onto D,
		-- same as spi_ctrl_rd_s did before); sd_dout/sd_rd_en are the
		-- WAIT_n-gated SD_DATA register (same pattern spi.vhd's own
		-- spi_dout/spi_rd_en already used).
		reg_dout			: out   std_logic_vector(7 downto 0);
		sd_dout			: out   std_logic_vector(7 downto 0);
		sd_rd_en			: out   std_logic;
		-- SD card physical interface
		sd_cs_o			: out   std_logic;
		sd_sclk_o		: out   std_logic;
		sd_mosi_o		: out   std_logic;
		sd_miso_i		: in    std_logic;
		-- debug outputs for HEX/LEDG (see SDMapper_Top.vhd)
		dbg_busy_o				: out   std_logic;
		dbg_error_o				: out   std_logic_vector(15 downto 0);
		dbg_timeout_o			: out   std_logic;
		dbg_last_tx_o			: out   std_logic_vector(7 downto 0);
		dbg_last_rx_o			: out   std_logic_vector(7 downto 0);
		dbg_ever_accessed_o	: out   std_logic;
		dbg_init_done_o		: out   std_logic
	);
end entity;

architecture rtl of sdcard_bridge is

	-- ------------------------------------------------------------------
	-- SdCardCtrl instance signals
	-- ------------------------------------------------------------------
	signal xess_reset_s    : std_logic;
	signal xess_rd_s       : std_logic;
	signal xess_wr_s       : std_logic;
	signal xess_continue_s : std_logic;
	signal xess_addr_s     : std_logic_vector(31 downto 0);
	signal xess_data_i_s   : std_logic_vector(7 downto 0);
	signal xess_data_o_s   : std_logic_vector(7 downto 0);
	signal xess_busy_s     : std_logic;
	signal xess_hndshk_i_s : std_logic;
	signal xess_hndshk_o_s : std_logic;
	signal xess_error_s    : std_logic_vector(15 downto 0);

	-- ------------------------------------------------------------------
	-- CPU-interface synchronization (same technique as spi.vhd's own
	-- "STABILITY FIX" - cs_i is combinationally derived from async MSX
	-- bus signals at the top level, so it's synchronized here rather than
	-- used directly as an edge source).
	-- ------------------------------------------------------------------
	signal cs_meta, cs_sync, cs_sync_d : std_logic;
	signal rd_n_meta, rd_n_sync        : std_logic;
	signal wr_n_meta, wr_n_sync        : std_logic;
	signal reg_addr_meta, reg_addr_sync : std_logic_vector(3 downto 0);
	signal cs_rising_pulse              : std_logic;

	-- ------------------------------------------------------------------
	-- Address/command registers (written by the CPU)
	-- ------------------------------------------------------------------
	signal sd_addr0_q, sd_addr1_q, sd_addr2_q, sd_addr3_q : std_logic_vector(7 downto 0) := (others => '0');

	-- ------------------------------------------------------------------
	-- SD_DATA per-byte handshake state machine
	-- ------------------------------------------------------------------
	type handshake_state_t is (S_IDLE, S_WAIT_HNDSHK, S_ACK_HIGH, S_WAIT_LOW);
	signal handshake_state : handshake_state_t := S_IDLE;

	signal wait_n_s        : std_logic := '1';
	signal is_write_access : std_logic := '0';	-- latched direction of the CPU access that triggered this handshake
	signal data_o_reg      : std_logic_vector(7 downto 0) := (others => '0');	-- byte captured from the card, presented to the CPU on read
	signal sd_rd_en_s      : std_logic := '0';

	-- Bridge-level timeout: see file header - protects against WAIT_n
	-- getting stuck asserted forever if SdCardCtrl stalls mid-handshake.
	--
	-- WIDENED (2026-08-12, real hardware: first real success - "SD card
	-- ready" printed, meaning CMD0/CMD8/ACMD41 genuinely completed - but
	-- the MSX hung a few seconds later, LEDG(0)/dbg_timeout_o lit).
	-- Root cause: 16 bits (~2.6ms) was sized only for a single SPI byte
	-- transfer, but SdCardCtrl's own RD_BLK state polls the card
	-- internally for a start token (0xFE) after issuing CMD17/CMD24, and
	-- never raises hndShk_o at all while doing so (rtnData_v stays false
	-- until the token arrives) - a real card can legitimately take longer
	-- than 2.6ms to prepare that data. The old timeout fired mid-poll,
	-- handed back stale data, and the byte loop kept going regardless -
	-- 512 accumulated ~2.6ms timeouts per sector reads as "hangs after a
	-- few seconds", not a true infinite lock, but bad either way. 24 bits
	-- at 25MHz covers ~671ms - comfortably past realistic worst-case SD
	-- card response latency, while staying an occasional (once per block
	-- command, not once per byte) stall rather than the systematic
	-- per-byte slowdown that caused the earlier SCLK-divider hang.
	constant TIMEOUT_MAX_C : unsigned(23 downto 0) := (others => '1');
	signal timeout_cnt_q   : unsigned(23 downto 0) := (others => '0');
	signal timeout_flag_q  : std_logic := '0';

	-- ------------------------------------------------------------------
	-- Diagnostics
	-- ------------------------------------------------------------------
	signal last_tx_q       : std_logic_vector(7 downto 0) := (others => '0');
	signal last_rx_q       : std_logic_vector(7 downto 0) := (others => '0');
	signal ever_accessed_q : std_logic := '0';
	signal init_done_q     : std_logic := '0';	-- sticky: busy_o has gone low at least once (init finished)

	-- Register-read mux
	signal reg_rdata_s   : std_logic_vector(7 downto 0);
	signal error_flag_s  : std_logic;	-- '1' when xess_error_s /= 0 - kept as its own signal since
	                                    -- a boolean comparison can't be concatenated directly into a
	                                    -- std_logic_vector expression.

	-- SD_CMD bit7 (software reset pulse) - see file header register map.
	-- One-cycle pulse, ORed into SdCardCtrl's own reset_i alongside the
	-- bridge's hardware reset_n_i - lets the driver force SdCardCtrl back
	-- to START_INIT (re-running CMD0/CMD8/ACMD41) without a full MSX
	-- reset, matching SdCardCtrl's own documented error-recovery
	-- requirement ("you have to pulse reset_i to unfreeze").
	signal sw_reset_pulse_s : std_logic := '0';

begin

	-- ------------------------------------------------------------------
	-- Port the XESS core
	-- ------------------------------------------------------------------
	xess_reset_s <= (not reset_n_i) or sw_reset_pulse_s;

	process(clock_i)
	begin
		if rising_edge(clock_i) then
			if reset_n_i = '0' then
				sw_reset_pulse_s <= '0';
			elsif cs_rising_pulse = '1' and wr_n_sync = '0' and reg_addr_sync = "0101" and data_bus_i(7) = '1' then
				sw_reset_pulse_s <= '1';
			else
				sw_reset_pulse_s <= '0';
			end if;
		end if;
	end process;

	sdcard_ctrl_inst: entity work.SdCardCtrl
		generic map (
			FREQ_G          => 25.0,
			INIT_SPI_FREQ_G => 0.4,
			SPI_FREQ_G      => 12.5,
			BLOCK_SIZE_G    => 512,
			CARD_TYPE_G     => SDHC_CARD_E
		)
		port map (
			clk_i      => clock_i,
			reset_i    => xess_reset_s,
			rd_i       => xess_rd_s,
			wr_i       => xess_wr_s,
			continue_i => xess_continue_s,
			addr_i     => xess_addr_s,
			data_i     => xess_data_i_s,
			data_o     => xess_data_o_s,
			busy_o     => xess_busy_s,
			hndShk_i   => xess_hndshk_i_s,
			hndShk_o   => xess_hndshk_o_s,
			error_o    => xess_error_s,
			cs_bo      => sd_cs_o,
			sclk_o     => sd_sclk_o,
			mosi_o     => sd_mosi_o,
			miso_i     => sd_miso_i
		);

	xess_addr_s   <= sd_addr3_q & sd_addr2_q & sd_addr1_q & sd_addr0_q;
	xess_data_i_s <= data_bus_i;	-- read-only usage - only ever sampled by SdCardCtrl on its own handshake edge

	-- ------------------------------------------------------------------
	-- Synchronize CPU interface into clock_i, exactly as spi.vhd does.
	-- ------------------------------------------------------------------
	process(clock_i)
	begin
		if rising_edge(clock_i) then
			cs_meta   <= cs_i;
			cs_sync   <= cs_meta;
			cs_sync_d <= cs_sync;

			rd_n_meta <= rd_n_i;
			rd_n_sync <= rd_n_meta;

			wr_n_meta <= wr_n_i;
			wr_n_sync <= wr_n_meta;

			reg_addr_meta <= reg_addr_i;
			reg_addr_sync <= reg_addr_meta;
		end if;
	end process;

	cs_rising_pulse <= cs_sync and not cs_sync_d;

	-- ------------------------------------------------------------------
	-- Register writes: address/command registers, and triggering rd_i/
	-- wr_i/reset_i pulses. All single-cycle pulses derived from
	-- cs_rising_pulse, qualified by wr_n_sync='0' (a genuine write access)
	-- and the register index.
	-- ------------------------------------------------------------------
	xess_rd_s       <= '1' when cs_rising_pulse = '1' and wr_n_sync = '0' and reg_addr_sync = "0101" and data_bus_i(7) = '0' and data_bus_i(1) = '0' and data_bus_i(0) = '1' else '0';
	xess_wr_s       <= '1' when cs_rising_pulse = '1' and wr_n_sync = '0' and reg_addr_sync = "0101" and data_bus_i(7) = '0' and data_bus_i(1) = '1' else '0';
	xess_continue_s <= data_bus_i(2);

	process(clock_i)
	begin
		if rising_edge(clock_i) then
			if reset_n_i = '0' then
				sd_addr0_q <= (others => '0');
				sd_addr1_q <= (others => '0');
				sd_addr2_q <= (others => '0');
				sd_addr3_q <= (others => '0');
				ever_accessed_q <= '0';
			elsif cs_rising_pulse = '1' and wr_n_sync = '0' then
				ever_accessed_q <= '1';
				case reg_addr_sync is
					when "0001" => sd_addr0_q <= data_bus_i;
					when "0010" => sd_addr1_q <= data_bus_i;
					when "0011" => sd_addr2_q <= data_bus_i;
					when "0100" => sd_addr3_q <= data_bus_i;
					when others => null;	-- SD_DATA/SD_CMD handled by their own dedicated logic below
				end case;
			elsif cs_rising_pulse = '1' and rd_n_sync = '0' then
				ever_accessed_q <= '1';
			end if;
		end if;
	end process;

	-- ------------------------------------------------------------------
	-- SD_DATA handshake state machine - the heart of this bridge. See
	-- file header for the exact 4-step protocol this implements against
	-- (identical shape for both read and write, only the data direction
	-- differs).
	-- ------------------------------------------------------------------
	process(clock_i)
	begin
		if rising_edge(clock_i) then
			if reset_n_i = '0' then
				handshake_state  <= S_IDLE;
				wait_n_s         <= '1';
				xess_hndshk_i_s  <= '0';
				timeout_cnt_q    <= (others => '0');
				timeout_flag_q   <= '0';
				is_write_access  <= '0';
				data_o_reg       <= (others => '0');
				sd_rd_en_s       <= '0';
				last_tx_q        <= (others => '0');
				last_rx_q        <= (others => '0');
				init_done_q      <= '0';
			else
				sd_rd_en_s <= '0';	-- default: pulse only for exactly the cycle the CPU read completes

				-- Clear the sticky timeout flag whenever a new command is
				-- issued (SD_CMD write) - matches "you have to reset to
				-- unfreeze" but lets the driver observe the flag first.
				if cs_rising_pulse = '1' and wr_n_sync = '0' and reg_addr_sync = "0101" then
					timeout_flag_q <= '0';
				end if;

				if xess_busy_s = '0' then
					init_done_q <= '1';	-- sticky: SdCardCtrl has reached WAIT_FOR_HOST_RW at least once
				end if;

				case handshake_state is

					when S_IDLE =>
						wait_n_s <= '1';
						if cs_rising_pulse = '1' and reg_addr_sync = "0000" and (rd_n_sync = '0' or wr_n_sync = '0') then
							wait_n_s        <= '0';
							timeout_cnt_q   <= (others => '0');
							if wr_n_sync = '0' and rd_n_sync /= '0' then
								is_write_access <= '1';
							else
								is_write_access <= '0';
							end if;
							if wr_n_sync = '0' then
								last_tx_q <= data_bus_i;
							end if;
							handshake_state <= S_WAIT_HNDSHK;
						end if;

					when S_WAIT_HNDSHK =>
						if xess_hndshk_o_s = '1' then
							if is_write_access = '0' then
								data_o_reg <= xess_data_o_s;
								last_rx_q  <= xess_data_o_s;
							end if;
							handshake_state <= S_ACK_HIGH;
						elsif timeout_cnt_q = TIMEOUT_MAX_C then
							timeout_flag_q  <= '1';
							wait_n_s        <= '1';
							handshake_state <= S_IDLE;
						else
							timeout_cnt_q <= timeout_cnt_q + 1;
						end if;

					when S_ACK_HIGH =>
						xess_hndshk_i_s <= '1';
						handshake_state <= S_WAIT_LOW;

					when S_WAIT_LOW =>
						if xess_hndshk_o_s = '0' then
							xess_hndshk_i_s <= '0';
							wait_n_s        <= '1';
							if is_write_access = '0' then
								sd_rd_en_s <= '1';	-- one-cycle pulse marking data_o_reg valid for the D-bus mux
							end if;
							handshake_state <= S_IDLE;
						end if;

					when others =>
						handshake_state <= S_IDLE;

				end case;
			end if;
		end if;
	end process;

	sd_dout  <= data_o_reg;
	sd_rd_en <= sd_rd_en_s;

	-- ------------------------------------------------------------------
	-- Register reads: SD_STATUS/SD_ERRLO/SD_ERRHI. SD_DATA reads are
	-- handled by sd_dout/sd_rd_en above (through the top-level's D-bus
	-- mux, same convention spi.vhd already used).
	--
	-- Uses reg_addr_i directly (not the synchronized reg_addr_sync used
	-- by the write-trigger logic above): unlike cs_i (genuinely
	-- glitch-prone, combinationally derived from independent async MSX
	-- bus signals), reg_addr_i is just address bits already registered/
	-- settled by the top-level's address-capture FSM well before SLTSL_n/
	-- RD_n assert - matches how every other raw combinational read decode
	-- in this project treats s_A (no extra resync stage needed).
	-- ------------------------------------------------------------------
	error_flag_s <= '1' when xess_error_s /= x"0000" else '0';

	reg_rdata_s <= "000" & timeout_flag_q & write_protect_i & card_present_i & error_flag_s & xess_busy_s when reg_addr_i = "0110" else
	               xess_error_s(7 downto 0)  when reg_addr_i = "0111" else
	               xess_error_s(15 downto 8) when reg_addr_i = "1000" else
	               (others => '0');

	reg_dout <= reg_rdata_s;

	wait_n_o <= wait_n_s;

	-- ------------------------------------------------------------------
	-- Debug outputs
	-- ------------------------------------------------------------------
	dbg_busy_o           <= xess_busy_s;
	dbg_error_o          <= xess_error_s;
	dbg_timeout_o        <= timeout_flag_q;
	dbg_last_tx_o        <= last_tx_q;
	dbg_last_rx_o        <= last_rx_q;
	dbg_ever_accessed_o  <= ever_accessed_q;
	dbg_init_done_o      <= init_done_q;

end architecture;

# Altera DE0 Projects — MSX_FPGA_Hat PCB v2.1b

Branch `v2.1b_working_designs` collects the designs that are **validated on real
hardware** for the Terasic DE0 (Cyclone III EP3C16F484C6) on PCB v2.1b, so they
sit side by side instead of one per branch.

Baseline machine is the **Panasonic FS-A1F**. The Zemmix is not a usable
reference — it boots unreliably even with no DE0 fitted at all, so its failures
cannot be attributed to a design.

## Working designs

| Project | What it is | Status |
|---|---|---|
| **`SDMapper_V2.1b`** | ★ **Current.** Nextor from Flash + SD card + 512KB SRAM memory mapper + sub-slot expansion, *plus* the 24-game multirom and 9 mapper test ROMs, all switch-selected from one Flash image | **Nextor boots; RAM mapper works.** `testrun.com` from inside Nextor detects 512KB and passes. SD read *and* write verified |
| `Multi_MegaromCartridge_v2.1b` | 24-game cartridge: plain 8/16/32KB, ASCII16 and Konami4 MegaROMs | Validated — all 24 slots play on Zemix BR, Panasonic FS-A1F, Canon V-25. 748 LE |
| `Multi_Cartridge_v2.1b` | Plain-ROM predecessor, 16 games; `SW(5)` selects multirom vs the Nextor path | Validated. Superseded by the MegaROM version, which carries both |
| `SDMapper_V2.1b_previous` | The SDMapper as it stood before the 2026-08 rework | Reference only — kept for comparison, not for use |

`SDMapper_V2.1b` supersedes the other two: it contains the same 24-game multirom
on `SW(9)=1`. The standalone cartridge branches are kept because they are simpler
and independently validated, which makes them useful fallbacks.

## Deliberately NOT included

- **`plain_rom_simulator`** — never stable, and it is a documented dead end. It
  served the ROM combinationally from FPGA fabric, which synthesised to a
  ~12,700 LE mux tree (83% of the device, **zero** memory bits) on a path
  TimeQuest never analysed, and it corrupted intermittently. Reading the same
  ROM from Flash costs ~19 LE and is rock solid, which is why
  `Multi_Cartridge_v2.1b` replaced it. It stays on branch `plain_rom_simulator`
  as part of the ruled-out list.
- **`V2.1b_Template`** — a validated minimal top level (address bus and D bus
  round-trip confirmed on hardware, Test0–Test4). Useful as a starting point for
  new work; on branch `V2.1b_Template`. Not merged here only because this branch
  is for finished designs.

## The bug that took the longest

For weeks the RAM mapper appeared to work in every test yet Nextor could never
load `NEXTOR.SYS`. The cause was one line's worth of meaning in
`SDMapper_Top.vhd`:

`s_addr_valid` meant *"the last address capture finished"* when it needed to mean
*"this address belongs to the cycle happening now"*. It was cleared only by
`addr_capture_trigger`, so any missed trigger left the **previous** cycle's
address still marked valid, and the design decoded it against a new access.
Nextor writes FFFFh on every inter-slot call, so it hit this constantly.

```vhdl
if bus_req_sync = '1' then    -- bus idle ends the cycle that address
    s_addr_valid <= '0';      -- belonged to; validity dies with it
end if;
```

**Why every mapper test passed anyway:** they write a value and read it straight
back. When the capture misses, the design does not drive `D` at all, so the Z80
reads the *floating bus* — which still holds the value just written. The tests
were structurally blind to the failure. They proved the datapath (segment
registers, SRAM) and said nothing about the bus protocol around it.

`SDMapper_V2.1b/Simulation/tb_ffff.vhd` is the GHDL bench that cleared
`exp_slot` and prevented a rewrite of logic that was already correct.

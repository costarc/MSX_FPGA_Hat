# Altera DE0 Projects — MSX_FPGA_Hat

Projects are filed by the **PCB revision they target**, because the two boards
present the address bus completely differently and a design for one will not
work on the other:

```
PCBv1.5/    older board - the 16 address lines are wired directly
PCBv2.1b/   current board - 16 address bits multiplexed over 8 shared pins
```

The reliable test is the top-level entity, not the folder name: a v2.1b design
declares `A_MUX` with `U2OE_n`/`U3OE_n` and reconstructs the address in a
capture state machine. A v1.5 design declares `A : in std_logic_vector(15 downto 0)`.

Baseline machine for hardware testing is the **Panasonic FS-A1F**. The Zemmix
boots unreliably even with no DE0 fitted at all, so its failures cannot be
attributed to a design.

## PCBv2.1b — validated on real hardware

| Project | What it is | Status |
|---|---|---|
| **`SDMapper`** | ★ **Current.** Nextor from Flash + SD card + 512KB SRAM memory mapper + sub-slot expansion, *plus* the 24-game multirom and 9 mapper test ROMs, all switch-selected from one Flash image | **Nextor boots; RAM mapper works.** `testrun.com` from inside Nextor detects 512KB and passes. SD read *and* write verified. A write-path bug remains — see `BACKLOG.md` |
| `Multi_MegaromCartridge` | 24-game cartridge: plain 8/16/32KB, ASCII16 and Konami4 MegaROMs | Validated — all 24 slots play on Zemix BR, Panasonic FS-A1F, Canon V-25. 748 LE |
| `Multi_Cartridge` | Plain-ROM predecessor, 16 games; `SW(5)` selects multirom vs the Nextor path | Validated. Superseded by the MegaROM version, which carries both |
| `MegaROM_ASCII16` | Multi-mapper cartridge simulator | Confirmed on hardware — Xevious, Nemesis, Penguin Adventure, Usas, Metal Gear all boot |
| `MemoryMapper` | Standalone 512KB MSX memory mapper | Compiles and programs clean, **not validated** — see `BACKLOG.md` |

`SDMapper` supersedes the two cartridge projects: it carries the same 24-game
multirom on `SW(9)=1`. They are kept because they are simpler and independently
validated, which makes them useful fallbacks.

## PCBv1.5 — older board

`MegaRAM`, `MegaROM_Konami8`, `Multi_Cartridge`, `SDMapper`. Kept for reference;
none of these run on PCB v2.1b without a rewrite of the address path.

The DE1 projects are filed the same way, under `../Altera DE1 Projects/PCBv1.5/`.

## Not kept here

- **`plain_rom_simulator`** — never stable, and a documented dead end. It served
  the ROM combinationally from FPGA fabric, which synthesised to a ~12,700 LE
  mux tree (83% of the device, **zero** memory bits) on a path TimeQuest never
  analysed, and it corrupted intermittently. Reading the same ROM from Flash
  costs ~19 LE and is rock solid, which is why `Multi_Cartridge` replaced it.
  Still on branch `plain_rom_simulator` as part of the ruled-out list.
- **`V2.1b_Template`** — a validated minimal top level (address bus and D bus
  round-trip confirmed on hardware, Test0–Test4). A good starting point for new
  work; still on branch `V2.1b_Template`.

## The bug that took the longest

For weeks the RAM mapper appeared to work in every test yet Nextor could never
load `NEXTOR.SYS`. The cause was one line's worth of meaning in `SDMapper_Top.vhd`:

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
registers, SRAM) and said nothing about the bus protocol around it. Trust Nextor
booting over any test-ROM result.

`PCBv2.1b/SDMapper/Simulation/tb_ffff.vhd` is the GHDL bench that cleared
`exp_slot` and prevented a rewrite of logic that was already correct.

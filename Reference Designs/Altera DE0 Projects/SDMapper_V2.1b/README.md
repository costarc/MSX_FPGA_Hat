# Multi MegaROM Cartridge — MSX_FPGA_Hat PCB v2.1b

A switch-selectable multi-ROM MSX cartridge for the **Terasic DE0** (Cyclone III
EP3C16F484C6) on the **MSX_FPGA_Hat PCB v2.1b**. Holds 24 games in the DE0's
onboard parallel Flash and presents any one of them to the MSX as a real
cartridge — plain ROMs and MegaROMs alike — selected entirely with the DE0's
slide switches. No reflashing to change games.

## Status — validated on real hardware

Confirmed working on three machines:

| Machine | Result |
|---|---|
| Zemix BR | OK |
| Panasonic FS-A1F | OK |
| Canon V-25 | OK, except MSX2 titles needing >64KB VRAM (machine limitation, not a cartridge fault) |

All 24 game slots play. Plain 8/16/32KB ROMs, ASCII16 MegaROMs and Konami4
MegaROMs are all exercised.

Resource usage: **748 LE (5%)**, 345 registers, 1 PLL. Worst-case setup slack
+13.5 ns on the 20 ns clock.

## Switches

| Switch | Function |
|---|---|
| `SW(9)` | **`1` = cartridge active** · `0` = silent (`/SLTSL` ignored, the MSX bypasses our slot entirely, as if no cart were fitted) |
| `SW(4:0)` | Game index, `0`–`23` (see table) |

> `SW(9)` is **inverted** relative to the SDMapper design this code descends
> from, where `0` enabled the cart. Setting it wrong gives a clean boot to BASIC
> with no cartridge detected — that is expected behaviour, not a fault.

Unused: `SW(8:5)`. The legacy SDMapper path (Nextor + RAM mapper + SD +
sub-slot expansion) is present in the source but **permanently disabled** on
this branch — see [Planned](#planned).

## Games

| Idx | Game | Size | Mapper | Flash |
|----:|------|-----:|--------|-------|
| 0 | Castle Excellent | 32K | plain | `0x080000` |
| 1 | Elevator Action | 32K | plain | `0x088000` |
| 2 | Galaga | 32K | plain | `0x090000` |
| 3 | The Goonies | 32K | plain | `0x098000` |
| 4 | Gulkave | 32K | plain | `0x0A0000` |
| 5 | Gyrodine | 32K | plain | `0x0A8000` |
| 6 | Lode Runner | 32K | plain | `0x0B0000` |
| 7 | Zanac | 32K | plain | `0x0B8000` |
| 8 | King's Master | 32K | plain | `0x0C0000` |
| 9 | Road Fighter | 16K | plain | `0x0C8000` |
| 10 | Hyper Rally | 16K | plain | `0x0D0000` |
| 11 | Avalanche | 16K | plain | `0x0D8000` |
| 12 | Pac-Man | 16K | plain | `0x0E0000` |
| 13 | Rally-X | 16K | plain | `0x0E8000` |
| 14 | Kung-Fu | 16K | plain | `0x0F0000` |
| 15 | Frogger | 8K | plain | `0x0F8000` |
| 16 | Xevious | 256K | ASCII16 | `0x100000` |
| 17 | Fan Zone 2 | 256K | ASCII16 | `0x140000` |
| 18 | Ishtar | 256K | ASCII16 | `0x180000` |
| 19 | Androgynus | 256K | ASCII16 | `0x1C0000` |
| 20 | Nemesis / Gradius | 128K | Konami4 | `0x200000` |
| 21 | Penguin Adventure | 128K | Konami4 | `0x220000` |
| 22 | Usas | 128K | Konami4 | `0x240000` |
| 23 | Metal Gear | 128K | Konami4 | `0x260000` |

Indices 24–31 are unused and fall back to slot 0.

## Flash layout

```
0x000000  128KB   System ROM (SDMAPPER.ROM) — reserved for the planned Nextor boot
0x020000  384KB   free
0x080000  512KB   PLAIN games    16 slots × 32KB     → index 0–15
0x100000 1024KB   ASCII16 games   4 slots × 256KB    → index 16–19
0x200000  512KB   Konami4 games   4 slots × 128KB    → index 20–23
                  ────────────────────────────────
                  2.5 MB total (4 MB device)
```

Every region base is a power of two and every slot a fixed power-of-two size, so
the FPGA computes the Flash address by **bit concatenation plus one add** — no
per-game lookup table of bases. Smaller ROMs are zero-padded into their slot, so
the stride stays uniform regardless of a game's real size.

**The FPGA game table and this layout must agree.** If you change one, change the
other: the table lives in the `MULTIROM` section of `SDMapper_Top.vhd`, the
layout in `Tools/build_multirom.py`.

## Building

### 1. Flash image

```bash
cd Tools
python build_multirom.py -o DE1ROMs.bin
```

Searches `MSX_FPGA_HAT_ROMS/` and `gameroms/` by default; override or add paths
with `--rom-dir`. Missing ROMs are reported and their slot left as `0xFF`
(erased Flash) so a partial set still builds. The script prints the full slot
map it produced — check it against the table above.

Write the resulting image to the DE0's **parallel Flash at offset 0** using the
Altera/Terasic DE0 Control Panel.

### 2. Bitstream

```bash
quartus_sh --flow compile SDMapper_Top
quartus_pgm -c "USB-Blaster [USB-0]" -m JTAG -o "p;output_files/SDMapper_Top.sof"
```

## How it works

The MSX address bus reaches the FPGA time-multiplexed over 8 shared pins (low
byte via U2, high byte via U3), so it is reconstructed into `s_A` by a capture
state machine; `s_addr_valid` marks when both halves come from the same bus
cycle, and **every decode gates on it**. Reading `s_A` while it is low risks a
chimera address — one byte from this cycle, one from the last.

Reads are answered combinationally: `s_mr_rd` qualifies slot select, address
validity, `/MREQ`, `/RD` and the selected mapper's own page decode, then drives
`D` straight from `FL_DQ`. Bank-switch writes re-latch `D` **continuously** while
the write is qualified rather than sampling once at the end — the Z80 releases
the data bus shortly after `/WR` rises, so a trailing-edge sample captures
floating noise. That distinction caused a real bug here (MegaROMs booted, then
showed garbage once bank-switched content loaded).

Konami bank registers reset to segments **0,1,2,3**, not zero — real hardware
powers up with the first 32KB mapped linearly. Resetting all to 0 makes segment 0
appear four times; games that bank every region explicitly survive it, games that
rely on the power-on layout hang. That was the Usas-hangs-but-Metal-Gear-works
bug.

Konami4 decodes only `D0–D3` of a bank write, Konami SCC only `D0–D5`. Real
mappers ignore the upper bits, so games leave them set — using the unmasked byte
computes a wildly out-of-range Flash address.

## Limitations

- **Konami SCC** banking is implemented but **untested** — no SCC title is in the
  current game table. SCC *audio* is not implemented at all; only banking.
- **ASCII8** is implemented but unused by the current table, so also untested.
- Canon V-25 (64KB VRAM) cannot display MSX2 titles that require 128KB.
- Two 32KB ROMs cannot both live in one plain slot — the slot stride is 32KB.

## Planned

`SW(9)=0` currently only silences the cartridge. The intent is:

```
SW(9)=0  →  boot Nextor, the first ROM in Flash (0x000000)
SW(9)=1  →  boot the games (working today)
```

The legacy SDMapper logic (Nextor ROM, RAM mapper, SD card, sub-slot expansion)
is retained in `SDMapper_Top.vhd` but disabled via `s_legacy_en = '0'`, so it can
be re-enabled for this. The `Multi_Cartridge_v2.1b` branch still carries both
paths, selectable with `SW(5)`.

## Lineage

Descends from `SDMapper_V2.1b` at commit `7fcb3c3` — the last commit before a
100 MHz address-capture redesign that introduced a still-unresolved regression.
Mapper decode is ported in structure from `MegaROM_ASCII16` in this repo, a
multi-mapper simulator already confirmed on hardware.

Entity and files are still named `SDMapper_Top` — the design is genuinely
SDMapper with a multirom mode built on top, and renaming validated hardware
carries no benefit worth the risk.

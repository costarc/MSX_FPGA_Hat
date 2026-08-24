# SDMapper V2.1b — MSX_FPGA_Hat PCB v2.1b

Three designs in one bitstream for the **Terasic DE0** (Cyclone III
EP3C16F484C6) on **MSX_FPGA_Hat PCB v2.1b**, selected entirely with the DE0's
slide switches:

1. **SDMapper** — Nextor booting from Flash, SD card, SRAM Memory Mapper
2. **MapperTest** — 9 diagnostic cartridges for bringing the mapper up
3. **Multirom** — 24 switch-selectable games (plain, ASCII16, Konami4)

**One Flash image covers all three.** Flash once, then everything is switch
selectable — no reflashing to move between Nextor, a tester, and games.

---

## Switch reference

### Mode select

| `SW(9)` | `SW(8)` | Mode |
|:---:|:---:|---|
| `0` | `0` | **SDMapper** — Nextor from `SDMAPPER.ROM`, SD card, RAM mapper |
| `0` | `1` | **MapperTest** — diagnostic ROM chosen by `SW(3:0)` |
| `1` | – | **Multirom** — game chosen by `SW(4:0)` |

`SW(9)` is the master: `0` selects the SDMapper design (ROM + SD + RAM mapper +
sub-slot expansion), `1` selects the plain-ROM/MegaROM game cartridge. The two
are mutually exclusive — neither can touch the bus while the other owns it.

### SDMapper mode — `SW(9)=0`

| Switch | `0` | `1` |
|---|---|---|
| `SW(8)` | Boot Nextor (`SDMAPPER.ROM`) | Boot a MapperTest ROM |
| `SW(7)` | SD register window **on** | SD register window **off** |
| `SW(4)` | Normal | **SRAM BIST** (see below) |
| `SW(3:0)` | — | MapperTest ROM index, when `SW(8)=1` |
| `SW(0)` | SD writes allowed | SD **write-protected** (Nextor refuses writes) |
| `SW(2)` | *(unused — was write-protect)* | |

**Card presence is no longer a switch.** `SD_STATUS` bit 2 is driven from the SD
core's own `init_done_q`, so the card is detected for real: insert one and it is
found, remove it and Nextor reports "SD Card not detected" and boots on.
`LEDG(2)` shows the same signal. `SW(0)` used to be the card-present gate and is
now free for write protect; booting with it ON works normally.

The RAM mapper and its FCh–FFh ports are always live in this mode — they follow
`SW(9)` and cannot be switched off independently.

> ⚠️ Because FCh–FFh are always claimed here, a machine with its **own** Memory
> Mapper (e.g. the Zemmix's internal 4096KB) will have two mappers answering the
> same ports. Use multirom mode on such machines, or a machine without one.

### Multirom mode — `SW(9)=1`

`SW(4:0)` selects the game. RAM mapper, SD, sub-slot expansion and the FCh–FFh
ports are all inert — the cartridge presents ROM only.

| Idx | Game | Size | Mapper | Idx | Game | Size | Mapper |
|----:|------|-----:|--------|----:|------|-----:|--------|
| 0 | Castle Excellent | 32K | plain | 12 | Pac-Man | 16K | plain |
| 1 | Elevator Action | 32K | plain | 13 | Rally-X | 16K | plain |
| 2 | Galaga | 32K | plain | 14 | Kung-Fu | 16K | plain |
| 3 | The Goonies | 32K | plain | 15 | Frogger | 8K | plain |
| 4 | Gulkave | 32K | plain | 16 | Xevious | 256K | ASCII16 |
| 5 | Gyrodine | 32K | plain | 17 | Fan Zone 2 | 256K | ASCII16 |
| 6 | Lode Runner | 32K | plain | 18 | Ishtar | 256K | ASCII16 |
| 7 | Zanac | 32K | plain | 19 | Androgynus | 256K | ASCII16 |
| 8 | King's Master | 32K | plain | 20 | Nemesis / Gradius | 128K | Konami4 |
| 9 | Road Fighter | 16K | plain | 21 | Penguin Adventure | 128K | Konami4 |
| 10 | Hyper Rally | 16K | plain | 22 | Usas | 128K | Konami4 |
| 11 | Avalanche | 16K | plain | 23 | Metal Gear | 128K | Konami4 |

Indices 24–31 fall back to slot 0.

### MapperTest ROMs — `SW(9)=0, SW(8)=1`

Set `SW(7)=1` as well, so the SD register window is off and nothing else of ours
is on the bus.

| `SW(3)` | ROM | What it does |
|:---:|---|---|
| `0` | **`testmapper`** | Measures the mapper's **real** size rather than assuming it — fingerprints segments and counts how many hold a distinct value before aliasing — then writes `00`/`FF`/`AA`/`55` over each one. Touches only port FEh / page 2, so it cannot disturb its own code or stack, and it sizes third-party mappers correctly too |
| `1` | **`ffffstress`** | Hammers the FFFFh sub-slot register and classifies every failure as **dropped** or **corrupt**. Keep this one: it is the only test here that ever caught a real bug, and it is the regression test for the address-capture path |

Only `SW(3)` changes between them — `SW(0)` keeps its normal job (SD write
protect), so selecting a test never disturbs the SD card flags. Card presence is
detected in hardware and is not switch-controlled at all.

> The other seven diagnostics (`maptest`, `testramrom`, `testramrom2`,
> `porttest`, `page0test`, `soaktest`, `soaktest_ei`) are **no longer flashed**.
> They were built to chase the stale-address bug fixed on 2026-08-23, and they
> were actively misleading: all of them passed continuously for weeks while
> Nextor could not boot. They write a value and read it straight back, and when
> the FPGA fails to recognise an access it does not drive `D` at all — so the
> Z80 reads the floating bus, which still holds the value just written. They are
> blind to that whole class of fault by construction.
>
> They remain in `MapperTest/` and in git; re-add one by putting it back in
> `TEST_ROMS` in `Tools/build_multirom.py`. No FPGA change is needed — the
> 16-slot map at `0x040000` is unchanged.

### SRAM BIST — `SW(4)=1`

The FPGA drives the SRAM itself, writing an address-derived pattern across
**256KB** and reading it back. **No MSX required** — this works with the machine
powered off, which is deliberate: the BIST resets from `KEY(0)` alone rather than
`s_reset`, because `s_reset` includes the MSX's `RESET_n` and that line sits low
when the MSX is off, which would otherwise hold the test in permanent reset.

Set `SW(4)=1`, keep `SW(9)=1` so the cart stays off the MSX bus, then power on.

| Indicator | Meaning |
|---|---|
| `LEDG(9)` | BIST complete |
| `LEDG(8)` | **PASS** — zero errors |
| `HEX3..0` | Mismatch count (hex) |

`SW(5)` selects the byte lane during the BIST, so running it in both positions
also settles which lane is physically wired.

The pattern is address-derived (low byte XOR high byte), so a stuck **address**
line fails the test too — a constant pattern would pass with the address bus
completely dead.

This proves the SRAM and addon board independently of the MSX, which matters:
a long-running mapper corruption in this project's history was eventually traced
to a faulty SRAM addon board, not to logic. Run this before suspecting VHDL.

### Unused

`SW(6)` — free. (It briefly held a Canon V-8 workaround that exposed RAM with no
sub-slot check; removed as non-compliant. `SW(8)`'s old meaning, disabling the
RAM mapper, is also gone.) `SW(5)` is free in normal operation and selects the
BIST byte lane when `SW(4)=1`.

---

## Flash map

```
0x000000  128KB   SDMAPPER.ROM (Nextor)          -> SW(9)=0, SW(8)=0
0x020000  128KB   free
0x040000  256KB   MapperTest  16 slots x 16KB    -> SW(9)=0, SW(8)=1, SW(3:0)
0x080000  512KB   plain games 16 slots x 32KB    -> SW(9)=1, SW(4:0)=0-15
0x100000 1024KB   ASCII16      4 slots x 256KB   -> SW(9)=1, SW(4:0)=16-19
0x200000  512KB   Konami4      4 slots x 128KB   -> SW(9)=1, SW(4:0)=20-23
                  ─────────────────────────────
                  2.5 MB used of a 4 MB device
```

Every region base is a power of two and every slot a fixed power-of-two size, so
the FPGA computes Flash addresses by bit concatenation — no adders, no per-game
lookup table. Smaller ROMs are zero-padded into their slot.

**The FPGA tables and this layout must agree.** Game table and `s_flashbase` live
in `SDMapper_Top.vhd`; the layout lives in `Tools/build_multirom.py`.

---

## Building

**Flash image:**

```bash
cd Tools
python build_multirom.py -o DE1ROMs.bin --rom-dir ../MapperTest --rom-dir <your-rom-dir>
```

It prints the full slot map it produced — check it against the tables above.
Missing ROMs are reported and their slot left as `0xFF`, so a partial set still
builds. Write the result to the DE0 parallel Flash **at offset 0** with the DE0
Control Panel.

**Bitstream:**

```bash
quartus_sh --flow compile SDMapper_Top
quartus_pgm -c "USB-Blaster [USB-0]" -m JTAG -o "p;output_files/SDMapper_Top.sof"
```

---

## Status

| Part | State |
|---|---|
| Multirom games | ✅ Validated — 24 games on Zemix BR, Panasonic FS-A1F, Canon V-25 |
| Nextor boot from Flash | ✅ Boots |
| SD card | ✅ Verified read **and** write on FS-A1F — a file on a card in the DE0 was renamed from Nextor, which no other interface's driver could have done |
| SRAM hardware | ✅ BIST passes over 256KB, zero errors |
| **RAM mapper** | ❌ **Not working** — Nextor does not load `NEXTOR.SYS` |
| Konami SCC / ASCII8 | ⚠️ Implemented, never exercised (no title in the table uses them). SCC *audio* not implemented |

**Machine baseline: Panasonic FS-A1F.** The Zemmix is not usable as a reference —
with only an MFRSCC+SD fitted and no DE0 involved at all, it boots roughly once in
several attempts, so its failures cannot be attributed to this design.

### The open problem

The SRAM passes its BIST and the SD card works, yet Nextor cannot load
`NEXTOR.SYS`. Nextor needs mapped RAM, so the fault lies somewhere on the path
the BIST deliberately bypasses:

```
MSX bus → A_MUX capture → exp_slot subslot → segment registers → SRAM
```

The leading suspect is **sub-slot visibility**: our RAM sits behind sub-slot 1 of
an expanded slot, so Nextor must navigate expanded-slot selection to reach it —
unlike an ordinary mapper cartridge in a plain slot. The MapperTest ROMs exist to
isolate exactly this, which is why they run in SDMapper mode with the mapper and
sub-slot expansion live rather than in multirom mode.

Note also that one earlier record has this mapper validated at 31/32 segments
byte-perfect, so the datapath may well be sound and the fault structural.

# SDMapper build tools

| File | Purpose |
|---|---|
| `build_multirom.py` | Assembles the 2.5 MB **Flash image** the DE0 is programmed with |
| `build_sdmapper_rom.sh` | Rebuilds `SDMAPPER.ROM`. **Verified byte-identical**; run under Debian WSL |
| `Nextor-2.1.2.base.dat` | Nextor kernel base — input to `SDMAPPER.ROM` |
| `driver.bin` | The disk driver bank — input to `SDMAPPER.ROM` |
| `mapper.bin` | The 4-byte ASCII16 bank-switch routine — input to `SDMAPPER.ROM` |
| `SDMAPPER.ROM` | The built output, committed so the Flash image can be rebuilt |

---

## 1. Building the Flash image

```bash
cd Tools
python build_multirom.py -o DE1ROMs.bin --rom-dir ../MapperTest --rom-dir <your-rom-dir>
```

It prints the slot map it produced — check that against the tables in the
project `README.md`. Missing ROMs are reported and their slot left as `0xFF`, so
a partial set still builds. Write the result to the DE0's **parallel Flash at
offset 0** with the DE0 Control Panel.

```
0x000000  128KB   SDMAPPER.ROM (Nextor)          SW(9)=0, SW(8)=0
0x020000  128KB   free
0x040000  256KB   MapperTest  16 slots x 16KB    SW(9)=0, SW(8)=1, SW(3:0)
0x080000  512KB   plain games 16 slots x 32KB    SW(9)=1, SW(4:0)=0-15
0x100000 1024KB   ASCII16      4 slots x 256KB   SW(9)=1, SW(4:0)=16-19
0x200000  512KB   Konami4      4 slots x 128KB   SW(9)=1, SW(4:0)=20-23
```

`SDMAPPER.ROM` is a **128 KB ASCII16** image and must be exactly that: the FPGA
maps it with `s_flashbase = 0x000000` and the ASCII16 bank registers at
6000–67FF / 7000–77FF.

---

## 2. Building `SDMAPPER.ROM`

### The three input files

| File | Size | What it is |
|---|---|---|
| `Nextor-2.1.2.base.dat` | 114688 (7 banks) | The Nextor kernel — DOS1/DOS2, FAT, everything hardware-independent. **Identical for every Nextor cartridge.** Byte `0xFE` holds the bank count (7), which is how `mknexrom` knows where the driver goes. Produced by `make base` in the Nextor tree |
| `driver.bin` | 16336 (`0x3FD0`) | The disk driver — **the only hardware-specific code**. Becomes bank 7 at `0x1C000`. Starts `41 42` (`AB`), signature `NEXTOR_DRIVER` at `+0x100`, then a jump table, then code. Talks to our registers: `ld a,(7B06h)` polls `SD_STATUS`, `ld (7B00h),a` pushes `SD_DATA`. Ends at `0x3FD0`, where the reserved mapper slot begins |
| `mapper.bin` | 4 | `32 00 60 C9` = `ld (6000h),a` / `ret` — the bank-switch routine. `mknexrom` stamps it into a reserved 48-byte slot at address `0x7FD0` of **every** bank, so whichever bank is live can switch away, plus one at file offset `0x07DC`. `0x6000` is the ASCII16 bank-1 register; an ASCII8 cartridge would use a different address |

```
base (7 banks)                    driver.bin            mapper.bin
bank 0 ─┐                                                   |
  ...   +- kernel, unchanged ---------------------+      stamped at
bank 6 -+                                         |      0x7FD0 in
                                                  v      every bank
bank 7  <-------- appended as the driver bank -- 0x1C000

= 131072 bytes / 8 banks / "AB"
```

**base = the OS, driver = the storage hardware, mapper = the ROM-banking
hardware.** Only the last two know anything about this board.

### Rebuilding it

```bash
wsl -d Debian
cd "/mnt/c/.../PCBv2.1b/SDMapper/Tools"
./build_sdmapper_rom.sh
```

The script runs `mknexrom`, normalises the padding, checks the size and `AB`
signature, and compares against the existing `SDMAPPER.ROM`. **Verified
2026-08-23: the rebuild is byte-identical.**

Two traps it handles, both of which cost time to find:

- `mknexrom` treats any argument beginning with `/` as a DOS-style switch, so
  **absolute Linux paths break it**. The script keeps every path relative.
- `mknexrom` fills the leftover mapper-area bytes with `0x00`; the original ROM
  has `0xFF` there. Without normalising, the rebuild differs in exactly
  9 x 44 = 396 pure padding bytes. Debian WSL has no `python3`, so this is done
  with `dd`.

### What is still missing: the driver SOURCE

The build is reproducible, but `driver.bin` is a **binary extracted from the
working ROM** — its source has never been in this repository. So the ROM can be
*rebuilt* but not *modified*.

That matters for the open Nextor write bug: if the fault is in the driver rather
than the VHDL, it cannot be fixed without either recovering the source or
disassembling the binary (the driver code sits around `0x1C180`-`0x1C4C0` in the
ROM image).

Note the driver is **bespoke to our register map**, confirmed by scanning the
ROM: 12 x `ld a,(7B06h)` and `ld (7B00h),a`, and *zero* references to `7FF0` or
`7FF1`. So `fbelavenuto/msxsdmapperv2`'s `DRIVER.ASM` is **not** a drop-in — it
expects raw SPI at `7B00`-`7EFF` with control at `7FF0` and a timer at `7FF1`,
which this FPGA does not decode. Adopting it would mean changing both halves.

### Toolchain

`N80`, `LK80`, `LB80` and `mknexrom` live in `Nextor/buildtools/linux/` and are
**Linux ELF x86-64 binaries** requiring .NET 6. They cannot run under Windows or
Git Bash.

Use the **Debian WSL** instance, which already has .NET 6 installed. Do not use
the IIQ WSL instance, and do not install new dependencies without asking.

```bash
wsl -d Debian
cd /mnt/c/Users/roniv/Dev/github/Nextor/source/kernel
export N80=../../buildtools/linux/N80
export LK80=../../buildtools/linux/LK80
export LB80=../../buildtools/linux/LB80
export MKNEXROM=../../buildtools/linux/mknexrom
```

### The two pieces every Nextor ROM needs

A Nextor ROM is the kernel base plus **two** driver binaries:

```bash
mknexrom nextor_base.dat OUTPUT.ROM /d:<driver>.bin /m:<chgbnk>.bin
```

- **`/d:`** the disk driver — talks to the storage hardware. For this design
  that means the SD register window at 7B00–7B08, visible only when
  `rom_bank1_q = 7`.
- **`/m:`** the bank-switching code (`CHGBNK.MAC`) — how the kernel switches its
  own ROM banks. For an ASCII16 cartridge this is the ASCII16 variant.

Per `Nextor/source/kernel/drivers/README.TXT`, each driver subfolder must
contain `DRIVER.MAC` and `CHGBNK.MAC`.

### Building the base

```bash
make base          # produces nextor_base.dat
```

`Nextor-2.1.2.base.dat` in this folder is a copy of that output, taken from
`Nextor/bin/kernels/`. It is kept here so the ROM can be reassembled without
rebuilding the whole kernel.

### Adding an SDMapper driver

1. `mkdir Nextor/source/kernel/drivers/SDMapper`
2. Add `DRIVER.MAC` for the 7B00–7B08 SD register interface, and `CHGBNK.MAC`
   for ASCII16 bank switching — `drivers/StandaloneASCII16/chgbnk.mac` is the
   right starting point, since this cartridge is ASCII16.
3. Add a rule to `source/kernel/Makefile` mirroring the existing ones, e.g.
   `mknexrom nextor_base.dat $@ /d:drivers/SDMapper/_driver.bin /m:drivers/SDMapper/chgbnk.bin`
4. `make` it, then copy the result here as `SDMAPPER.ROM` and rebuild the Flash
   image.

The `MegaFlashRomSD` driver is the closest existing reference — it is also an
SD-card driver on a Flash cartridge.

---

## Verifying a rebuilt ROM

`SDMAPPER.ROM` must be **exactly 131072 bytes** and start with `AB`. Quick check
before flashing:

```bash
python -c "d=open('SDMAPPER.ROM','rb').read(); print(len(d), d[:2])"
```

Expected: `131072 b'AB'`.

Then flash, set `SW(9)=0, SW(8)=0`, and confirm Nextor boots on the
**Panasonic FS-A1F** — the baseline machine. The Zemmix boots unreliably even
with no DE0 fitted, so it cannot be used to judge a change.

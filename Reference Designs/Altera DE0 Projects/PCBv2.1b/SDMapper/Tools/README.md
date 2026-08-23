# SDMapper build tools

| File | Purpose |
|---|---|
| `build_multirom.py` | Assembles the 2.5 MB **Flash image** the DE0 is programmed with |
| `build_sdmapper_rom.sh` | Builds **`SDMAPPER.ROM` from source**. Run under Debian WSL |
| `Nextor-2.1.2.base.dat` | The Nextor kernel — one of the three inputs to `SDMAPPER.ROM` |
| `SDMAPPER.ROM` | The built Nextor ROM, committed so the Flash image can be rebuilt |

The driver **sources** live next door in [`../Nextor_Driver/`](../Nextor_Driver).

---

## 1. Building the Flash image

```bash
python build_multirom.py -o DE1ROMs.bin --rom-dir . --rom-dir ../MapperTest --rom-dir <your-game-roms>
```

It prints the slot map it produced — check that against the project
[`README.md`](../README.md). Missing ROMs are reported and their slot left as
`0xFF`, so a partial set still builds. Write the result to the DE0's **parallel
Flash at offset 0** with the DE0 Control Panel.

```
0x000000  128KB   SDMAPPER.ROM (Nextor)          SW(9)=0, SW(8)=0
0x020000  128KB   free
0x040000  256KB   MapperTest  16 slots x 16KB    SW(9)=0, SW(8)=1, SW(3:0)
0x080000  512KB   plain games 16 slots x 32KB    SW(9)=1, SW(4:0)=0-15
0x100000 1024KB   ASCII16      4 slots x 256KB   SW(9)=1, SW(4:0)=16-19
0x200000  512KB   Konami4      4 slots x 128KB   SW(9)=1, SW(4:0)=20-23
```

Only two MapperTest slots are populated — `testmapper` at 0 and `ffffstress` at
8, which differ only in `SW(3)`. See the project README for why the rest were
dropped. `place()` accepts `None` for a deliberately empty slot.

---

## 2. Building `SDMAPPER.ROM` from source

```bash
wsl -d Debian
cd "/mnt/c/.../PCBv2.1b/SDMapper/Tools"
./build_sdmapper_rom.sh
```

```
../Nextor_Driver/driver.mac  --N80-->  driver.bin  (code only)
../Nextor_Driver/256.bytes   ----------prepended   (header + signature slot)
../Nextor_Driver/chgbnk.mac  --N80-->  chgbnk.bin  (48 bytes)
Nextor-2.1.2.base.dat -----------------the kernel  (7 banks)
                              |
                          mknexrom
                              |
                              v
                    SDMAPPER.ROM   131072 bytes / 8 banks / "AB"
```

### The three inputs

| File | Size | What it is |
|---|---|---|
| `Nextor-2.1.2.base.dat` | 114688 (7 banks) | The Nextor kernel — DOS1/DOS2, FAT, everything hardware-independent. **Identical for every Nextor cartridge.** Byte `0xFE` holds the bank count (7), which is how `mknexrom` knows where the driver goes. From `make base` in the Nextor tree |
| `../Nextor_Driver/driver.mac` | 13508 | The disk driver — **the only hardware-specific code**. Becomes bank 7 at `0x1C000`. `SD_DATA equ 7B00h`, `SD_STATUS equ 7B06h`. Device-based, modelled on Nextor's SunriseIDE driver; all SD protocol (CMD0/CMD8/ACMD41/CMD17/CMD24) runs in the FPGA's XESS core, so this only does register I/O |
| `../Nextor_Driver/chgbnk.mac` | 916 | `ld (6000h),a` / `ret` at `org 7FD0h`, then `defs …,0FFh`. Assembles to exactly 48 bytes: 4 of code, 44 of `0xFF`. `mknexrom` stamps it into every bank's mapper slot. `6000h` is the ASCII16 bank-1 register |

**base = the OS, driver = the storage hardware, chgbnk = the ROM-banking
hardware.** Only the last two know anything about this board.

`256.bytes` is the header that must sit at offsets `0x00`-`0xFF` of the driver
file, because `driver.mac` is `org 4100h` — it *starts* at the `NEXTOR_DRIVER`
signature, which `mknexrom` requires at position 256.

### Three traps, all handled in the script

- **`mknexrom` needs the signature at position 256.** Feed it the bare N80
  output and it refuses: *"The driver file is invalid. Driver signature not
  found at position 256."* `256.bytes` must be prepended.
- **`mknexrom` parses any argument starting with `/` as a DOS-style switch**, so
  absolute Linux paths make it print usage and silently produce nothing. Every
  path the script passes is relative.
- **The script must have LF line endings.** CRLF breaks the shebang under WSL
  (`cannot execute: required file not found`). Pinned by `*.sh text eol=lf` in
  the repo `.gitattributes`.

### Toolchain

`N80` (Nestor80, the assembler Nextor itself uses) and `mknexrom` live in
`Nextor/buildtools/linux/` and are **Linux ELF x86-64 binaries** — they cannot
run under Windows or Git Bash. Use the **Debian WSL** instance. Nothing needs
installing; `python3` is *not* required.

Override the locations if your checkout differs:

```bash
NEXTOR_DIR=/path/to/Nextor ./build_sdmapper_rom.sh
```

### Why the driver lives here and not in the Nextor tree

It did live there, in a `drivers/SDMapperXess/` folder on a branch of the Nextor
fork — and it was **deleted** by a commit whose message said it had been "moved
into the SDMapper_V2.1b project". It never arrived, and it took a search of the
Nextor repo's history to get it back.

It is this board's own code. Only the Nextor **kernel** and **tools** stay
external, referenced by path.

---

## Verifying a rebuilt ROM

The script already checks the size and `AB` signature and reports how many bytes
changed. Manually:

```bash
python -c "d=open('SDMAPPER.ROM','rb').read(); print(len(d), d[:2])"
```

Expected: `131072 b'AB'`.

Then flash, set `SW(9)=0, SW(8)=0`, and confirm Nextor boots on the
**Panasonic FS-A1F** — the baseline machine. The Zemmix boots unreliably even
with no DE0 fitted, so it cannot be used to judge a change.

> **Not yet hardware-tested.** The committed `SDMAPPER.ROM` was built from a
> later, debug-heavy version of the driver that was never committed. A build
> from the current source differs from it by roughly 1542 bytes — it is the
> *cleaner* driver, with the SD bring-up diagnostics gone — but it has not been
> booted yet. Keep the committed ROM until it has.

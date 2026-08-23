# SDMapper build tools

Two separate things live here:

| File | Purpose |
|---|---|
| `build_multirom.py` | Assembles the 2.5 MB **Flash image** the DE0 is programmed with |
| `Nextor-2.1.2.base.dat` | The Nextor kernel base — an **input** to building `SDMAPPER.ROM` |

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

### Important: the current ROM was not built here

The Nextor source tree at `C:\Users\roniv\Dev\github\Nextor` contains drivers
for `SunriseIDE`, `StandaloneASCII8`, `StandaloneASCII16`, `MegaFlashRomSD`,
`Flashjacks` and `OCM` — **there is no SDMapper driver**. The `SDMAPPER.ROM`
currently in the Flash image was obtained pre-built, not produced from source in
either repository.

So the steps below describe how a Nextor ROM *is* built. Regenerating **this**
one additionally needs the SD Mapper disk driver, which is not present. Until
that driver exists, treat the existing `SDMAPPER.ROM` as an irreplaceable
binary — keep a backup.

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

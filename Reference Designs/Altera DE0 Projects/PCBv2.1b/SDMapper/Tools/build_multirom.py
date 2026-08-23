#!/usr/bin/env python3
"""
build_multirom.py - assemble the DE0 Flash image for the SDMapper multirom design.

Produces a single .bin to write to the DE0's onboard parallel Flash with the
Quartus/Altera Control Panel. Every region sits on a power-of-2 boundary so the
FPGA can decode addresses by bit-concatenation alone (no adders) - see
SDMapper_Top.vhd's MULTIROM section.

    FLASH MAP
    ---------
    0x000000  128KB   System ROM (SDMAPPER.ROM) - fixed, boots Nextor
    0x020000  128KB   reserved / free
    0x040000  256KB   MapperTest diagnostic ROMs - 16 slots x 16KB
                      (SW(9)=0, SW(8)=1, SW(3:0) selects)
    0x080000  512KB   PLAIN games   - 16 slots x 32KB   -> game index 0-15
    0x100000 1024KB   ASCII16 games -  4 slots x 256KB  -> game index 16-19
    0x200000  512KB   Konami4 games -  4 slots x 128KB  -> game index 20-23

The FPGA's game table (SDMapper_Top.vhd, MULTIROM section) must match these
bases exactly - SW(4:0) selects the index shown above.

Smaller ROMs are zero-padded up to their slot size, so a 16KB or 8KB game still
occupies one 32KB plain slot. That wastes a little Flash (4MB device, ~2.5MB
used) in exchange for trivial address decode.

Usage:
    python build_multirom.py [-o DE1ROMs.bin] [--rom-dir DIR ...]

Missing ROMs are reported and their slot left as 0xFF (erased Flash); the build
still succeeds so you can flash a partial set.
"""

import argparse
import os
import sys

KB = 1024

# --- region bases (must stay power-of-2 aligned; see note above) -------------
SYSTEM_BASE  = 0x000000
TEST_BASE    = 0x040000
PLAIN_BASE   = 0x080000
ASCII16_BASE = 0x100000
KONAMI8_BASE = 0x200000

TEST_SLOT    = 16 * KB      # MapperTest diagnostic ROMs
PLAIN_SLOT   = 32 * KB      # every plain game gets a 32KB slot
ASCII16_SLOT = 256 * KB
KONAMI8_SLOT = 128 * KB

IMAGE_SIZE   = KONAMI8_BASE + 4 * KONAMI8_SLOT   # 0x280000 = 2.5MB

# --- system ROM --------------------------------------------------------------
SYSTEM_ROM = "SDMAPPER.ROM"

# --- MapperTest diagnostic ROMs: SW(2:0) selects, with SW(9)=0 and SW(8)=1 --
# These run with the RAM mapper and sub-slot expansion LIVE, which is the whole
# point - they exercise the path the FPGA-side SRAM BIST cannot reach:
# MSX bus -> A_MUX capture -> exp_slot subslot -> segment registers -> SRAM.
TEST_ROMS = [
    ("maptest.rom",      16 * KB),   # 0 - segment integrity + aliasing
    ("testramrom.rom",   16 * KB),   # 1
    ("testramrom2.rom",  16 * KB),   # 2
    ("porttest.rom",     16 * KB),   # 3 - FCh-FFh segment registers
    ("page0test.rom",    16 * KB),   # 4
    ("soaktest.rom",     16 * KB),   # 5
    ("soaktest_ei.rom",  16 * KB),   # 6
    ("ffffstress.rom",   16 * KB),   # 7 - FFFF subslot-select stress
    ("testmapper.rom",   16 * KB),   # 8 - empirical mapper SIZE detection +
                                     #     00/FF/AA/55 patterns over every
                                     #     detected segment. Port FEh / page 2
                                     #     only, so it is safe on any machine
                                     #     and also sizes third-party mappers.
]

# --- plain (non-mapped) games: slot index -> (filename, expected size) --------
# Slot index is what the FPGA's game-select switches choose.
# Sizes are the REAL sizes; the loader pads each up to PLAIN_SLOT.
PLAIN_GAMES = [
    ("CASTLE.ROM",   32 * KB),   # 0
    ("ELEVATOR.ROM", 32 * KB),   # 1
    ("GALAGA.ROM",   32 * KB),   # 2
    ("GOONIES.ROM",  32 * KB),   # 3
    ("GULKAVE.ROM",  32 * KB),   # 4
    ("GYRODINE.ROM", 32 * KB),   # 5
    ("LODERUN.ROM",  32 * KB),   # 6
    ("ZANAC.ROM",    32 * KB),   # 7
    ("KMASTER.ROM",  32 * KB),   # 8
    ("ROAD.ROM",     16 * KB),   # 9
    ("HRALLY.ROM",   16 * KB),   # 10
    ("AVALANCH.ROM", 16 * KB),   # 11
    ("PACMAN.ROM",   16 * KB),   # 12
    ("Rally-X.rom",  16 * KB),   # 13
    ("kung-fu.rom",  16 * KB),   # 14
    ("FROGGER.ROM",   8 * KB),   # 15
]

# --- mapped games: game index 16-19 (ASCII16) and 20-23 (Konami4) ------------
ASCII16_GAMES = [
    ("XEVIOUS.ROM",  256 * KB),
    ("FANZONE2.ROM", 256 * KB),
    ("ISHTAR.ROM",   256 * KB),
    ("ANDROGYN.ROM", 256 * KB),
]

KONAMI8_GAMES = [
    ("NEMESIS.ROM", 128 * KB),
    ("PENGUIN.ROM", 128 * KB),
    ("USAS.ROM",    128 * KB),
    ("MGEAR.ROM",   128 * KB),
]

DEFAULT_ROM_DIRS = [
    r"C:\Users\roniv\Dev\MSX\MSX_FPGA_HAT_ROMS",
    r"C:\Users\roniv\Dev\MSX\gameroms",
]


def find_rom(name, rom_dirs):
    """Locate a ROM case-insensitively across the search directories."""
    for d in rom_dirs:
        if not os.path.isdir(d):
            continue
        direct = os.path.join(d, name)
        if os.path.isfile(direct):
            return direct
        lowered = name.lower()
        for entry in os.listdir(d):
            if entry.lower() == lowered:
                return os.path.join(d, entry)
    return None


def place(image, base, slot_size, entries, rom_dirs, label, missing, oversize):
    """Write each entry into its slot, zero-padded. Returns a report list."""
    rows = []
    for idx, (name, expected) in enumerate(entries):
        addr = base + idx * slot_size
        path = find_rom(name, rom_dirs)
        if path is None:
            missing.append(f"{label}[{idx}] {name}")
            rows.append((idx, addr, name, expected, None))
            continue

        with open(path, "rb") as fh:
            data = fh.read()

        if len(data) > slot_size:
            oversize.append(f"{label}[{idx}] {name}: {len(data)} > slot {slot_size}")
            data = data[:slot_size]

        image[addr:addr + len(data)] = data
        rows.append((idx, addr, name, expected, len(data)))
    return rows


def main():
    ap = argparse.ArgumentParser(description="Build the DE0 multirom Flash image.")
    ap.add_argument("-o", "--output", default="DE1ROMs.bin", help="output image")
    ap.add_argument("--rom-dir", action="append", dest="rom_dirs",
                    help="ROM search directory (repeatable)")
    args = ap.parse_args()

    rom_dirs = args.rom_dirs or DEFAULT_ROM_DIRS

    # 0xFF matches erased Flash, so unwritten slots look genuinely empty.
    image = bytearray(b"\xFF" * IMAGE_SIZE)

    missing, oversize = [], []

    # System ROM
    sys_path = find_rom(SYSTEM_ROM, rom_dirs)
    if sys_path:
        with open(sys_path, "rb") as fh:
            sys_data = fh.read()
        image[SYSTEM_BASE:SYSTEM_BASE + len(sys_data)] = sys_data
        sys_len = len(sys_data)
    else:
        missing.append(f"system {SYSTEM_ROM}")
        sys_len = None

    tests = place(image, TEST_BASE, TEST_SLOT, TEST_ROMS,
                  rom_dirs, "test", missing, oversize)
    plain = place(image, PLAIN_BASE, PLAIN_SLOT, PLAIN_GAMES,
                  rom_dirs, "plain", missing, oversize)
    place(image, ASCII16_BASE, ASCII16_SLOT, ASCII16_GAMES,
          rom_dirs, "ascii16", missing, oversize)
    place(image, KONAMI8_BASE, KONAMI8_SLOT, KONAMI8_GAMES,
          rom_dirs, "konami8", missing, oversize)

    with open(args.output, "wb") as fh:
        fh.write(image)

    # --- report --------------------------------------------------------------
    print(f"Flash image: {args.output}  ({len(image)} bytes, "
          f"{len(image)//KB}KB)\n")
    print(f"  0x{SYSTEM_BASE:06X}  system  {SYSTEM_ROM}"
          f"{'' if sys_len else '   *** MISSING ***'}")
    print()
    print("  MAPPERTEST ROMS (SW(9)=0, SW(8)=1, SW(3:0) selects)")
    print("  slot  flash      size   rom")
    for idx, addr, name, expected, actual in tests:
        mark = "" if actual is not None else "   *** MISSING ***"
        print(f"  {idx:>4}  0x{addr:06X}  {expected//KB:>3}KB   {name}{mark}")
    print()
    print("  PLAIN GAMES (switch-selectable slots)")
    print("  slot  flash      size   rom")
    for idx, addr, name, expected, actual in plain:
        size = f"{expected//KB}KB".rjust(5)
        mark = "" if actual is not None else "   *** MISSING ***"
        print(f"  {idx:>4}  0x{addr:06X}  {size}   {name}{mark}")

    if oversize:
        print("\nOVERSIZE (truncated to slot):")
        for m in oversize:
            print("  " + m)

    if missing:
        print(f"\nMISSING ({len(missing)}) - slots left as 0xFF:")
        for m in missing:
            print("  " + m)
        print("\nSearched: " + ", ".join(rom_dirs))

    print("\nWrite this image to the DE0 parallel Flash at offset 0.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/bin/bash
# ---------------------------------------------------------------------------
# build_sdmapper_rom.sh - rebuild SDMAPPER.ROM for the SDMapper v2.1b design
#
# MUST RUN UNDER LINUX. The Nextor build tools (N80, LK80, LB80, mknexrom) are
# Linux ELF x86-64 binaries and cannot run under Windows or Git Bash. Use the
# Debian WSL instance:
#
#     wsl -d Debian
#     cd "/mnt/c/.../PCBv2.1b/SDMapper/Tools"
#     ./build_sdmapper_rom.sh
#
# A Nextor ROM is the kernel base plus a driver bank:
#
#     mknexrom <base> <output> /d:<driver.bin> /m:<mapper.bin>
#
# The base is 7 banks (114688 bytes). mknexrom appends the driver as bank 7 at
# 0x1C000 and writes the 4-byte mapper routine into each bank's mapper area,
# giving a 128KB / 8-bank image.
#
# THE DRIVER IS A BINARY, not source. driver.bin was extracted from the working
# SDMAPPER.ROM; its source has never been in this repository (see README.md).
# mknexrom consumes a binary anyway, so the build is fully reproducible - the
# driver simply cannot be MODIFIED until its source is recovered or rewritten.
#
# Two gotchas cost time; both are handled below:
#   * mknexrom parses any argument starting with "/" as a DOS-style switch, so
#     absolute Linux paths break it. All paths here are relative.
#   * Debian WSL has no python3, so the pad fix-up uses dd.
# ---------------------------------------------------------------------------
set -u

# ---- paths (override via environment if your checkout differs) ------------
NEXTOR_DIR="${NEXTOR_DIR:-/mnt/c/Users/roniv/Dev/github/Nextor}"
MKNEXROM="${MKNEXROM:-$NEXTOR_DIR/buildtools/linux/mknexrom}"

BASE="${BASE:-Nextor-2.1.2.base.dat}"
DRIVER="${DRIVER:-driver.bin}"
MAPPER="${MAPPER:-mapper.bin}"
OUTPUT="${OUTPUT:-SDMAPPER.ROM}"
REFERENCE="${REFERENCE:-SDMAPPER.ROM}"   # compared against when present
# ---------------------------------------------------------------------------

cd "$(dirname "$0")" || exit 1

ROM_SIZE=131072
BANK_SIZE=16384
MAPPER_CODE_LEN=4
MAPPER_AREA_LEN=48

echo
echo "Building $OUTPUT"
echo

for f in "$MKNEXROM" "$BASE" "$DRIVER" "$MAPPER"; do
    if [ ! -f "$f" ]; then
        echo "  ERROR: missing: $f"
        if [ "$f" = "$MKNEXROM" ]; then
            echo "         Set NEXTOR_DIR or MKNEXROM, or check the Nextor checkout."
        fi
        exit 1
    fi
done
chmod +x "$MKNEXROM" 2>/dev/null

# Preserve the reference before it is overwritten
REF_COPY=""
if [ -f "$REFERENCE" ]; then
    REF_COPY=".ref_$$.ROM"
    cp "$REFERENCE" "$REF_COPY"
fi

# Relative temp name: mknexrom would treat a leading "/" as a switch.
TMP_OUT=".build_$$.ROM"
rm -f "$TMP_OUT"

if ! "$MKNEXROM" "$BASE" "$TMP_OUT" "/d:$DRIVER" "/m:$MAPPER" >/dev/null; then
    echo "  ERROR: mknexrom failed"
    rm -f "$TMP_OUT" "$REF_COPY"
    exit 1
fi
if [ ! -f "$TMP_OUT" ]; then
    echo "  ERROR: mknexrom produced no output"
    rm -f "$REF_COPY"
    exit 1
fi

# ---------------------------------------------------------------------------
# Pad normalisation.
#
# mknexrom reserves a 48-byte mapper area in each bank (address 0x7FD0 = bank
# offset 0x3FD0), plus one at file offset 0x07DC. It writes the 4-byte mapper
# routine and leaves the remaining 44 bytes as 0x00; the original SDMAPPER.ROM
# has 0xFF there, the erased-Flash convention.
#
# No functional byte is affected - without this the rebuild differs from the
# original in exactly 9 x 44 = 396 pure padding bytes. Normalising makes the
# build byte-exact, which is the point of a reproducible build.
# ---------------------------------------------------------------------------
PAD_LEN=$(( MAPPER_AREA_LEN - MAPPER_CODE_LEN ))
FF_BLOB=".ff_$$.bin"
: > "$FF_BLOB"
i=0
while [ "$i" -lt "$PAD_LEN" ]; do printf '\377' >> "$FF_BLOB"; i=$(( i + 1 )); done

pad_at() {
    dd if="$FF_BLOB" of="$TMP_OUT" bs=1 seek="$1" conv=notrunc status=none 2>/dev/null
}

pad_at $(( 0x07DC + MAPPER_CODE_LEN ))
bank=0
while [ "$bank" -lt $(( ROM_SIZE / BANK_SIZE )) ]; do
    pad_at $(( bank * BANK_SIZE + 0x3FD0 + MAPPER_CODE_LEN ))
    bank=$(( bank + 1 ))
done
rm -f "$FF_BLOB"
echo "  padding   : mapper-area 0x00 normalised to 0xFF"

SIZE=$(stat -c%s "$TMP_OUT")
SIG=$(head -c2 "$TMP_OUT")
echo "  size      : $SIZE bytes"
echo "  signature : $SIG"

if [ "$SIZE" -ne "$ROM_SIZE" ]; then
    echo "  ERROR: expected $ROM_SIZE bytes (128KB / 8 banks)"
    rm -f "$TMP_OUT" "$REF_COPY"; exit 1
fi
if [ "$SIG" != "AB" ]; then
    echo "  ERROR: expected an 'AB' MSX cartridge signature"
    rm -f "$TMP_OUT" "$REF_COPY"; exit 1
fi

RC=0
if [ -n "$REF_COPY" ]; then
    if cmp -s "$TMP_OUT" "$REF_COPY"; then
        echo "  compare   : BYTE-IDENTICAL to $REFERENCE"
    else
        N=$(cmp -l "$TMP_OUT" "$REF_COPY" 2>/dev/null | wc -l)
        echo "  compare   : DIFFERS from $REFERENCE in $N byte(s) - inspect before flashing"
        RC=1
    fi
    rm -f "$REF_COPY"
fi

mv "$TMP_OUT" "$OUTPUT"
echo
echo "  written   : $OUTPUT"
echo
echo "Next: rebuild the Flash image, then write it to Flash at offset 0."
echo "  python build_multirom.py -o DE1ROMs.bin --rom-dir . --rom-dir ../MapperTest --rom-dir <games>"
echo
exit $RC

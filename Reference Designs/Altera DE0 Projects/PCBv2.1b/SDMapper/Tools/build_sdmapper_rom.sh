#!/bin/bash
# ---------------------------------------------------------------------------
# build_sdmapper_rom.sh - build SDMAPPER.ROM from source
#
#   Nextor_Driver/driver.mac  --N80-->  driver code
#   Nextor_Driver/256.bytes   ----------prepended (header + signature slot)
#   Nextor_Driver/chgbnk.mac  --N80-->  48-byte ASCII16 bank switcher
#   Tools/Nextor-2.1.2.base.dat --------the Nextor kernel, 7 banks
#                                |
#                            mknexrom
#                                |
#                                v
#                     SDMAPPER.ROM  (128KB / 8 banks)
#
# MUST RUN UNDER LINUX - N80 and mknexrom are Linux ELF x86-64 binaries:
#
#     wsl -d Debian
#     cd "/mnt/c/.../PCBv2.1b/SDMapper/Tools"
#     ./build_sdmapper_rom.sh
#
# Only the Nextor KERNEL and the TOOLS come from the Nextor checkout. The
# driver is this board's own code and lives in this repository - it was once
# kept in a Nextor fork branch and was very nearly lost when that branch was
# tidied up, so it stays here now.
# ---------------------------------------------------------------------------
set -u

# ---- paths (override via environment) -------------------------------------
NEXTOR_DIR="${NEXTOR_DIR:-/mnt/c/Users/roniv/Dev/github/Nextor}"
N80="${N80:-$NEXTOR_DIR/buildtools/linux/N80}"
MKNEXROM="${MKNEXROM:-$NEXTOR_DIR/buildtools/linux/mknexrom}"

DRV_DIR="${DRV_DIR:-../Nextor_Driver}"
BASE="${BASE:-Nextor-2.1.2.base.dat}"
OUTPUT="${OUTPUT:-SDMAPPER.ROM}"
# ---------------------------------------------------------------------------

cd "$(dirname "$0")" || exit 1
ROM_SIZE=131072

echo
echo "Building $OUTPUT from source"
echo

for f in "$N80" "$MKNEXROM" "$BASE" \
         "$DRV_DIR/driver.mac" "$DRV_DIR/chgbnk.mac" "$DRV_DIR/256.bytes"; do
    if [ ! -f "$f" ]; then
        echo "  ERROR: missing: $f"
        exit 1
    fi
done
chmod +x "$N80" "$MKNEXROM" 2>/dev/null

# --- 1. assemble ------------------------------------------------------------
# "$" tells N80 to write output beside the source. --build-type abs gives a
# raw binary; this is exactly how Nextor's own kernel Makefile builds drivers.
for src in chgbnk driver; do
    echo "  assembling $src.mac"
    ( cd "$DRV_DIR" && "$N80" "$src.mac" "$"         --build-type abs --output-file-extension bin >/dev/null ) || {
        echo "  ERROR: $src.mac failed to assemble"
        ( cd "$DRV_DIR" && "$N80" "$src.mac" "$" --build-type abs --output-file-extension bin )
        exit 1; }
done

for f in "$DRV_DIR/chgbnk.bin" "$DRV_DIR/driver.bin"; do
    [ -f "$f" ] || { echo "  ERROR: $f was not produced"; exit 1; }
done
echo "    chgbnk.bin : $(stat -c%s "$DRV_DIR/chgbnk.bin") bytes  (4 code + 44 x 0xFF padding)"
echo "    driver.bin : $(stat -c%s "$DRV_DIR/driver.bin") bytes  (code only)"

# --- 2. prepend the 256-byte header ----------------------------------------
# driver.mac is "org 4100h" - it starts AT the NEXTOR_DRIVER signature, which
# mknexrom requires to be at position 256 of the driver file. 256.bytes is the
# header that occupies 0x00-0xFF. Without it mknexrom reports:
#   "The driver file is invalid. Driver signature not found at position 256."
DRV_FULL="_driver_full.bin"
cat "$DRV_DIR/256.bytes" "$DRV_DIR/driver.bin" > "$DRV_FULL"
echo "    combined   : $(stat -c%s "$DRV_FULL") bytes  (256-byte header + code)"

# --- 3. link the ROM --------------------------------------------------------
# NOTE: mknexrom parses any argument starting with "/" as a DOS-style switch,
# so absolute Linux paths silently break it. Keep every path relative.
TMP_OUT="_build.ROM"
rm -f "$TMP_OUT"
if ! "$MKNEXROM" "$BASE" "$TMP_OUT" "/d:$DRV_FULL" "/m:$DRV_DIR/chgbnk.bin" >/dev/null 2>&1; then
    cp "$DRV_DIR/chgbnk.bin" ./_map.bin
    "$MKNEXROM" "$BASE" "$TMP_OUT" "/d:$DRV_FULL" "/m:_map.bin" || {
        echo "  ERROR: mknexrom failed"; rm -f "$DRV_FULL" ./_map.bin; exit 1; }
    rm -f ./_map.bin
fi
rm -f "$DRV_FULL"

# --- 4. verify --------------------------------------------------------------
SIZE=$(stat -c%s "$TMP_OUT")
SIG=$(head -c2 "$TMP_OUT")
echo
echo "  size       : $SIZE bytes"
echo "  signature  : $SIG"

if [ "$SIZE" -ne "$ROM_SIZE" ] || [ "$SIG" != "AB" ]; then
    echo "  ERROR: expected $ROM_SIZE bytes starting with 'AB'"
    rm -f "$TMP_OUT"; exit 1
fi

if [ -f "$OUTPUT" ]; then
    if cmp -s "$TMP_OUT" "$OUTPUT"; then
        echo "  compare    : identical to the existing $OUTPUT"
    else
        N=$(cmp -l "$TMP_OUT" "$OUTPUT" 2>/dev/null | wc -l)
        echo "  compare    : differs from the existing $OUTPUT in $N byte(s)"
        echo "               (expected if the driver source changed - test on hardware)"
    fi
fi

mv "$TMP_OUT" "$OUTPUT"
echo
echo "  written    : $OUTPUT"
echo
echo "Next:"
echo "  python build_multirom.py -o DE1ROMs.bin --rom-dir . --rom-dir ../MapperTest --rom-dir <games>"
echo "  flash at offset 0, then SW(9)=0 SW(8)=0 and check Nextor boots on the FS-A1F."
echo

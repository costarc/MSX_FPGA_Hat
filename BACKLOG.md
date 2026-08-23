# Backlog

Open work, newest first. Baseline machine for all hardware testing is the
**Panasonic FS-A1F** — the Zemmix boots unreliably even with no DE0 fitted, so
it cannot be used as a reference.

---

## DONE 2026-08-23: from-source driver now works

`SDMAPPER.ROM` builds from source and is confirmed on hardware — boots Nextor,
FDISK creates partitions, device name shows. Committed as `b20cd53`.

The fix was porting three `DEV_RW` differences, found by disassembling the
working binary and comparing routine sizes through the jump table:

1. **One single-block command per sector**, address recomputed as `base+E`,
   instead of one command plus `SD_CMD_CONTINUE`.
2. **A wait after every `SD_CMD`** (`SD_WAIT`, polls `SD_STATUS` bit 5). The old
   code wrote `SD_CMD` and read `SD_DATA` immediately.
3. **`ld b,c` on success** so `B` reports sectors transferred; falling out of
   `djnz` left `B=0`.

Still deferred, each wanting its own build and hardware test:

- `LUN_INFO` write-protect flag from `SD_STATUS` bit 3 — correct, but adds an
  `SW(2)` dependency that looks like a `DEV_RW` failure if the switch is on
- `LUN_INFO` "removable" bit — separate item below
- exposing `init_done_q` in `SD_STATUS` so card detection stops depending on
  `SW(0)`, a manual switch

---

## Make SDMAPPER.ROM buildable from source

**Status:** open.

`SDMAPPER.ROM` currently exists only as a binary, recovered from a Flash image.
It cannot be rebuilt from what is in these repositories — but it is not
unrecreatable in principle, and the gap is exactly one file.

```
mknexrom nextor_base.dat SDMAPPER.ROM /d:<MISSING>.bin /m:<have this>.bin
```

- `/m:` **solved** — `drivers/StandaloneASCII16/chgbnk.mac`, the ASCII16
  bank-switching code, which is what this cartridge is.
- `/d:` **missing** — the disk driver for this cartridge's SD register window at
  7B00–7B08, visible only when `rom_bank1_q = 7`. `mknexrom` only embeds a
  `.bin` you supply; it cannot generate one.

### Checked 2026-08-23: the obvious candidate does NOT match our hardware

`github.com/fbelavenuto/msxsdmapperv2/blob/master/driver/DRIVER.ASM` is the
right family — ASCII16, registers enabled only at page 7, same as ours — but a
**different register map**:

| | fbelavenuto SD Mapper v2 | our `sdcard_bridge.vhd` |
|---|---|---|
| Data | `7B00`–`7EFF`, raw SPI | `7B00` `SD_DATA` |
| Control / status | `7FF0` | offset 6 → `7B06` `SD_STATUS` |
| Timer | `7FF1` | — |
| Errors | — | `7B07` / `7B08` `SD_ERRLO` / `SD_ERRHI` |
| Model | raw SPI byte shifting | byte-level bridge over the XESS `SdCardCtrl` core |

`SDMapper_Top.vhd` decodes only `7B00`–`7B0F` (`s_A(15 downto 8) = x"7B"` and
`s_A(7 downto 4) = x"0"`), so **`7FF0`/`7FF1` are not decoded at all** and that
driver would read ROM bytes when polling `SPISTATUS`.

Consequence: since the SD card demonstrably works, the driver inside the current
`SDMAPPER.ROM` **already speaks our custom register map** — it is a bespoke
driver written for this design, not the stock one. `sdcard_bridge.vhd`'s own
header calls the raw-SPI protocol "now abandoned".

`github.com/Konamiman/Nextor` (already cloned at `Dev/github/Nextor`) supplies
the kernel, base and `mknexrom`, but contains no SD Mapper driver either.

### Settled 2026-08-23 by scanning the ROM binary

Hypothesis tested: *could the undecoded `7FF0`/`7FF1` be the cause of the Nextor
write bug?* Scanned the 128KB `SDMAPPER.ROM` for both register maps:

```
7FF0 (SPICTRL/SPISTATUS) :  0 hits in the whole ROM
7FF1 (TIMERREG)          :  0 hits

7B06 (our SD_STATUS)     : 15 hits, including 12 x  ld a,(7B06h)
7B00 (our SD_DATA)       : 10 hits, including       ld (7B00h),a
```

**Answer: no.** The driver never references `7FF0`/`7FF1`, so the missing decode
cannot cause anything — nothing asks for it. Our FPGA decode is complete for the
driver we actually have.

This also confirms the driver is **bespoke to our register map**, not the stock
fbelavenuto one, so route 1 below means replacing BOTH halves, not just adopting
a driver.

The driver code sits around **`0x1C180`–`0x1C4C0`** in the ROM image, so it can
be disassembled from there if the source is never recovered — which is a real
option for chasing the write bug.

### Two routes

1. **Adopt fbelavenuto's driver and change the FPGA to match it** — implement
   raw SPI at `7B00`–`7EFF`, control/status at `7FF0`, timer at `7FF1`. More
   VHDL work, but it lands on a maintained open-source stack where both halves
   are public and proven together.
2. **Keep our bridge and write `DRIVER.MAC` for our map** —
   `SD_DATA`/`SD_STATUS`/`SD_ERRLO`/`SD_ERRHI`. `MegaFlashRomSD` is the closest
   model in the Nextor tree.

**This bears on the Nextor write bug below.** If that bug is in the driver
rather than the VHDL, route 2 cannot fix it without the source, while route 1
would replace the driver wholesale and likely take the bug with it.

Worth doing: until then a single corrupted file loses the ability to boot
Nextor on this design, and the driver cannot be modified or fixed.

Build details are in
`Reference Designs/Altera DE0 Projects/PCBv2.1b/SDMapper/Tools/README.md`.

---

## Review: should LUN_INFO report the medium as REMOVABLE?

**Status:** open, deliberately deferred.

`LUN_INFO` byte +7 bit 0 means "the medium is removable". We currently leave it
**0**, even though an SD card arguably *is* removable and the driver already
declares `DRV_HOTPLUG equ 1`.

It was left out on purpose rather than overlooked: setting it changes Nextor's
medium-change handling, and stacking that onto a design that had only just
started booting would have muddied the test of the three `LUN_INFO`/`DEV_INFO`
fixes landed at the same time. It wants its own build and its own hardware test.

Flag layout, from the Driver Development Guide:

```
+7 (1): bit 0: 1 if the medium is removable
        bit 1: 1 if the medium is read only     <- now driven by SW(0)
        bit 2: 1 if the logical unit is a floppy disk drive
        bit 3: 1 if the logical unit should not be used for automapping
```

Worth checking before changing it: whether Nextor then re-validates the medium
on every access, and what that does to performance and to the card-swap
behaviour. `SunriseIDE` and `Flashjacks` both set this byte to 0, but they are
fixed media, so neither is a useful precedent for an SD card.

Related: `Nextor_Driver/driver.mac`, `LUN_INFO`.

---

## Report the REAL SD card identity and capacity

**Status:** open. Needs an FPGA change, not just a driver change.

Nextor and FDISK can show a card's manufacturer, product name and true size;
other interfaces (e.g. fbelavenuto's sdmapperv2) do this. We cannot, and the
blocker is hardware:

- `sdcard_xess.vhd` has **no CID or CSD support at all** - it never issues CMD9
  (SEND_CSD) or CMD10 (SEND_CID), and runs the SD protocol internally.
- `sdcard_bridge.vhd` exposes only `SD_DATA`, `SD_ADDR0-3`, `SD_CMD`,
  `SD_STATUS`, `SD_ERRLO/HI` - no capacity or identity register.

So `LUN_INFO` hardcodes 16GB (`0x02000000` sectors), which is why FDISK always
reports a 16GB card whatever is inserted. sdmapperv2 can do it because its
driver bit-bangs raw SPI and can issue any command; ours delegates to a hardware
core that only does block read/write.

To fix:
1. Extend the XESS core with CMD9/CMD10, or add a small state machine that
   issues them at init.
2. Expose the 16-byte responses through new bridge registers.
3. In `driver.mac`, decode CSD for capacity (`LUN_INFO` total sectors) and CID
   for the product name (`DEV_INFO` index 2).

Worth doing beyond cosmetics: a wrong capacity means FDISK will happily create a
partition table larger than a small card, which would fail at the far end of the
medium rather than at partition time.

---

## Fix the write bug in Nextor

**Status:** open — reported 2026-08-23, details not yet captured.

Nextor now boots on `SDMapper_V2.1b` and `testrun.com` run from inside it
detects 512KB and passes, but a bug remains on the **write** path.

Needs pinning down before any code changes:

- What operation fails — file write, file create, directory update, format?
- Does it corrupt, fail cleanly with an error, or hang?
- Does it reproduce on a freshly partitioned card?
- Does the SD card content afterwards look wrong when read on a PC?

Worth knowing that SD **write** was previously verified end to end: a file on a
card physically in the DE0 was renamed from Nextor, which no other interface's
driver could have done. So the low-level SD write path works; the fault is
likely higher up.

Related: `SDMapper_V2.1b/`, `sdcard_bridge.vhd`, `sdcard_xess.vhd`.

---

## Fix the MemoryMapper project

**Status:** open.

`Reference Designs/Altera DE0 Projects/MemoryMapper/` — the standalone 512KB
MSX memory mapper for PCB v2.1b. It compiles and programs clean, but is not
validated as working.

Almost certainly worth applying the fix that made the mapper work inside
`SDMapper_V2.1b`, since it is the same class of design on the same board:

`s_addr_valid` must be **cycle-scoped**. It previously meant "the last address
capture finished" rather than "this address belongs to the cycle happening now",
so any missed capture trigger left the previous cycle's address marked valid and
it got decoded against the next access:

```vhdl
if bus_req_sync = '1' then    -- bus idle ends the cycle that address
    s_addr_valid <= '0';      -- belonged to; validity dies with it
end if;
```

Check whether `MemoryMapper/MSX_FPGA_Top.vhd` has the same defect.

Note also: on the Canon V-8/V-9 only page 2 / port FEh is actually
cartridge-routed (pages 1 and 3 are fixed), so a mapper test that exercises all
four pages will appear to fail on those machines for reasons that are not the
design's fault.

---

## Notes for whoever picks these up

Mapper test ROMs are **structurally blind** to a whole class of bus fault: they
write a value and read it straight back, and when the FPGA fails to recognise an
access it does not drive `D` at all — so the Z80 reads the floating bus, which
still holds the value just written. The test passes having proved nothing. That
is why every mapper test passed for weeks while Nextor could not boot. Trust
Nextor booting over any test ROM result.

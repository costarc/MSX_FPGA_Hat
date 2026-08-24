# Backlog

Open work, newest first. Baseline machine for all hardware testing is the
**Panasonic FS-A1F** — the Zemmix boots unreliably even with no DE0 fitted, so
it cannot be used as a reference.

---

## DONE 2026-08-24: real card detection, SW(0) freed for write protect

**Status:** working on hardware. Boots with a card, reports "not detected"
without one, and `SW(0)` now drives write protect (verified: Nextor refuses to
write, copies fail, and the machine still boots normally with it ON).

### What worked — one line, in the bridge, driver untouched

`SD_STATUS` bit 2 keeps meaning "card present" to the Nextor driver. Only its
*source* changed, inside `sdcard_bridge.vhd`'s read mux:

```vhdl
-- was:  ... & write_protect_i & card_present_i & error_flag_s & xess_busy_s
"00" & sd_ready_s & timeout_flag_q & write_protect_i & init_done_q & error_flag_s & xess_busy_s
   when reg_addr_i = "0110" else
```

`init_done_q` is set once SdCardCtrl completes CMD0/CMD8/ACMD41 — a genuine
card-detect, not an operator assertion. The `card_present_i` port then had no
remaining use and **was removed** from both the entity and the top-level
instantiation. `write_protect_i` moved to `SW(0)`; `SW(2)` is now free.

**No driver change. No ROM rebuild. No flash write.** Only the bitstream.

### Why this fits better than it looks

`init_done_q` is cleared by the software reset that `DRV_INIT` pulses on every
boot, so it re-detects per boot rather than latching once at power-on — and
`DRV_INIT`'s existing 1.8s wait-for-`BUSY`-to-clear is exactly the window in
which it re-asserts. The driver already waits for the right thing.

### Do it IN THE BRIDGE, not via the port map

The obvious-looking version — `card_present_i => <init_done>` in the top-level
port map — is worse: `init_done_q` is internal to the bridge and only leaves it
via `dbg_init_done_o` (→ `LEDG(2)`), so that route needs a round trip out of the
component and back in. Editing the mux where the signal already lives avoids it
entirely. Fixating on the port map is what delayed finding this.

### Attempt 1 (failed): expose init_done_q as a new status bit

Exposing `init_done_q` as a NEW bit (SD_STATUS bit 6) and repointing the driver
to read it. Reduced to the absolute minimum — one equate plus four
`bit SDSTAT_PRESENT` -> `bit SDSTAT_INITDONE`, driver size unchanged at 809
bytes, one read-only line of VHDL, Quartus reporting BETTER setup slack
(12.62ns vs 11.96ns) and identical hold slack (0.358ns).

**The MSX still rebooted.** Reading bit 6 instead of bit 2, in the same
instruction on the same register, should not be able to do that.

### Attempt 2 (failed): one shared CHK_CARD routine in the driver

Reasoning at the time: four routines — `DRV_INIT`, `DEV_RW`, `DEV_STATUS`,
`LUN_INFO` — each rolled their own "is the card usable" check and they had
drifted; with bit 2 hardwired `'1'` (Attempt 2 was done on top of that broken
core) `LUN_INFO` appeared to have no real check at all. So: factor the verified
`DRV_INIT` sequence into one `CHK_CARD` routine and call it from all four.

Note the premise was doubly wrong — with `SW(0)` restored as the gate,
`LUN_INFO`'s `SDSTAT_PRESENT` test is a genuine check, and the error registers
`CHK_CARD` would have added are not a valid detector anyway (see above).

Assembled clean, `driver.bin` 794 bytes. **On hardware: three auto-reboots, then
the Apps ROM, then a reboot, then a hang on a blue screen.** Reverted.

**Why it failed — the premise was wrong.** The four checks are not accidentally
inconsistent. Part of the variation is load-bearing:

| Routine | When Nextor calls it | Tolerates transient `BUSY`? |
|---|---|---|
| `DRV_INIT` | once, after a reset pulse + 1.8s wait | yes — nothing else running |
| `DEV_RW` | before a transfer it owns | yes — `BUSY` genuinely blocks it |
| `DEV_STATUS` | any time, **including mid-I/O** | **NO** — must not fail transiently |
| `LUN_INFO` | enumeration, any time | **NO** — same |

`CHK_CARD` tested `PRESENT` + `BUSY` + errors, so it silently **added a `BUSY`
test to `DEV_STATUS`**, which never had one. Nextor asking "is the device there?"
while the card was mid-transfer now got "no", and the device vanished underneath
it. That is exactly the unpredictable reboot/hang signature observed.

**Lesson:** one shared predicate cannot serve both halves of that table. Do not
re-attempt the refactor.

### Why the failures happened — the common thread

Both attempts tried to make the **driver** answer a question it has no stable
input for. Everything it can read is either a manual switch (`PRESENT`, before
this change) or transient (`BUSY`, `ERROR`, `READY`). A driver-side card-detect
therefore either fails transiently (Attempt 2) or, with the switch removed and
nothing put in its place, destabilises the machine.

It was always a hardware gap, and it was closed in hardware — by giving bit 2 a
real source, so all four routines test `SDSTAT_PRESENT` and the question becomes
trivial. No shared routine, no `BUSY` test, no error-register reads.

### CORRECTED: the clock-domain theory was wrong

This file previously named an unsynchronised clock crossing on `init_done_q` as
the leading suspect for Attempt 1's reboots, and recommended a two-flop
synchroniser. **That was wrong.** `init_done_q` is set in a process clocked by
`clock_i` — the same domain as the register mux. There is no crossing, and no
synchroniser was needed; the working fix uses the signal directly.

Attempt 1's reboots are therefore still unexplained. They are also now moot: the
difference was that Attempt 1 changed the *driver* as well (new bit 6, four
`bit SDSTAT_PRESENT` -> `bit SDSTAT_INITDONE`), so the ROM and bitstream had to
agree — and that is a known recurring failure mode on this board. The working
change touches one artefact only.

Still on the shelf, never ruled out: the documented aliasing hazard (`SD_STATUS`
lives at `7B00`-`7B0F` INSIDE ROM address space, so any stray access looks like a
register access), and hold slack of 0.358ns leaving no margin for a re-fit.

---

## NOT A BUG 2026-08-24: "write protect ON hangs the machine at boot"

Briefly recorded here as a real defect. It was not one.

The observation was genuine — with write protect asserted the MSX hung while
NEXTOR.SYS loaded — but it was **collateral from the broken
`card_present_i => '1'` core it was tested on**, not from write protect. Once bit
2 was driven from `init_done_q`, the same switch ON boots normally *and* correctly
refuses writes (copies fail in Nextor, as intended).

Two wrong conclusions were drawn from it, both worth not repeating:

- that `LUN_INFO` reporting the medium read-only (`ld (ix+7),00000010b`) was
  upsetting Nextor's boot. It is not — that flag is fine.
- that `SW(0)` carrying write protect was a "footgun" because operators habitually
  set it ON. It is not; ON is a perfectly normal, working state.

**Lesson:** a symptom observed on a knowingly-broken core is not evidence about
anything else. Re-test on a good core before opening a defect.

---

## DONE 2026-08-23: write protect works, both halves

`SW(2)` -> `write_protect_i` -> `SD_STATUS` bit 3, and both consumers are
confirmed on hardware:

- **`DEV_RW`** rejects every write with `.WPROT` — immediate, no reboot needed,
  because it re-reads `SD_STATUS` on each write
- **`LUN_INFO`** byte +7 bit 1 reports the medium read-only, so FDISK declines
  the device up front rather than failing at "write changes to disk"

**Diagnostic note:** *"there are no suitable logical units available in the
device"* now has **two** causes — total sectors reported as 0, and a read-only
medium. Check `SW(2)` before chasing the size field.

Caveat: `LUN_INFO` is only read when Nextor asks, and with `DRV_HOTPLUG equ 0`
and `DEV_STATUS` always returning "available, unchanged", nothing prompts a
re-query. Flipping `SW(2)` mid-session changes `DEV_RW` behaviour immediately but
not Nextor's cached view. Set the switch before power-on.

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

- `LUN_INFO` "removable" bit — separate item below
- exposing `init_done_q` in `SD_STATUS` so card detection stops depending on
  `SW(0)`, a manual switch

---

## DONE 2026-08-23: SDMAPPER.ROM is buildable from source — reference notes

**Status:** resolved (see the DONE entry above). The source was recovered from
the Nextor fork's history, not reconstructed. Kept below because the register-map
comparison and the ROM scan are still the reference for anyone touching the
driver or considering route 1.

### The problem as it stood

`SDMAPPER.ROM` existed only as a binary, recovered from a Flash image.
It could not be rebuilt from what was in these repositories — but it was not
unrecreatable in principle, and the gap was exactly one file.

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
**0**, even though an SD card arguably *is* removable. Note the driver declares
`DRV_HOTPLUG equ 0` (this file previously claimed `1` — it is `0`), so there is
no hot-plug support to build on either.

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

## DONE 2026-08-23: the Nextor write bug is fixed

Writes confirmed working on hardware — FDISK creates partitions and file writes
from within Nextor succeed. This had been open since before the driver work.

It was fixed by the `DEV_RW` rewrite (`4c9ba48`), not by anything aimed at it
directly. The most likely cause is the missing **wait after every `SD_CMD`**:
without it the driver began pushing bytes into `SD_DATA` before the core was
ready to accept them, which hurts writes more than reads — a read that starts
early stalls on `WAIT_n` and recovers, whereas a write that starts early can
lose the leading bytes of the block.

Honest caveat: the exact mechanism was never isolated. The rewrite changed three
things at once (per-sector single-block commands, the post-command wait, and the
`B` return value) and writes worked afterwards. If write problems ever resurface,
`SD_WAIT` is the first place to look.

Low-level SD write was always sound — a file on a card in the DE0 was renamed
from Nextor months ago — so the fault was in the driver, as suspected.

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

# Backlog

Open work, newest first. Baseline machine for all hardware testing is the
**Panasonic FS-A1F** — the Zemmix boots unreliably even with no DE0 fitted, so
it cannot be used as a reference.

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

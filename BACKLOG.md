# Backlog

Open work, newest first. Baseline machine for all hardware testing is the
**Panasonic FS-A1F** — the Zemmix boots unreliably even with no DE0 fitted, so
it cannot be used as a reference.

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

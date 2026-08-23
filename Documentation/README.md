# Documentation

Third-party reference documentation, kept here rather than under
`Reference Designs/` (which holds Quartus projects) or `Hardware Interface/`
(which holds this board's own schematics and the datasheets for parts fitted
to it).

| File | What it is |
|---|---|
| `Zilog Z80 - um0080.pdf` | Zilog Z80 CPU user manual. The authority for bus cycle timing — M1 and refresh, memory read/write, and where `MREQ`/`IORQ`/`RD`/`WR` assert relative to each other |
| `msx_technical_data_book_text.pdf` | MSX Technical Data Book. Slot and sub-slot selection, the FFFFh sub-slot register, memory mapper ports FCh–FFh, and `BUSDIR` |

Both were needed repeatedly while debugging the PCB v2.1b address capture, where
assumptions about Z80 cycle timing turned out to be the thing getting measured
wrong. Worth reading rather than recalling: the M1 opcode-fetch and refresh
cycles assert `MREQ_n` **twice**, about half a T-state apart, and `MREQ_n` and
`RD_n` assert essentially **together** on a read — two details that invalidated
three separate diagnostic counters before they were checked against the manual.

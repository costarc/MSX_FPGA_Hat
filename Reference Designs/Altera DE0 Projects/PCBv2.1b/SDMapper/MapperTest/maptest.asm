; ============================================================================
; maptest.asm - standalone MSX Memory Mapper test cartridge for SDMapper_V2.1b
;
; WHY THIS EXISTS
; ---------------------------------------------------------------------------
; Every mapper test so far has been either FPGA-side (the on-chip SRAM BIST,
; which bypasses the MSX entirely and PASSES over all 512KB) or full-Nextor
; (which fails for reasons several layers downstream). Nothing has ever
; verified data integrity through the actual path in question:
;
;     MSX bus -> A_MUX address capture -> exp_slot subslot -> mapper segment
;     registers -> SRAM
;
; This ROM closes that gap. It boots from the cartridge Flash (subslot 0),
; uses the BIOS ENASLT to page our RAM SUBSLOT into page 2, then writes and
; verifies patterns across all 32 segments. It reports on screen.
;
; The expanded slot is deliberately KEPT - testing RAM on a subslot is the
; whole point, since that is the one structural difference from the known-good
; MemoryMapper design (plain slot) and from Belavenuto's msxsdmapperv2 (which
; has all 16 address lines and therefore no address-capture window).
;
; SWITCH SETUP
;   SW(9)=0  SDMapper mode
;   SW(8)=0  mapper RAM + FCh-FFh ports enabled
;   SW(7)=1  SD register window DISABLED (nothing else of ours on the bus)
;   SW(6)=0  standard subslot-compliant RAM
;   SW(4)=0  BIST off
;
; WHAT IT TESTS
;   1. Data integrity: a pattern derived from segment AND address, so stuck
;      data bits and stuck address bits both fail.
;   2. Segment independence: every segment is written first, then ALL are
;      re-read. If two segments alias to the same SRAM, the second write
;      corrupts the first and the read-back catches it. A per-segment
;      write-then-immediately-read test would MISS aliasing entirely.
;
; Build:  pasmo --bin maptest.asm maptest.bin
;         (then pad to 16384 bytes and flash at Flash offset 0)
; ============================================================================

CHPUT   equ 000A2h          ; BIOS: print char in A
ENASLT  equ 00024h          ; BIOS: A=slot id, H=page base -> select slot
RAMAD2  equ 0F343h          ; BIOS var: slot id of RAM in page 2
MAPPORT2 equ 0FEh           ; mapper segment register for page 2

TESTBASE equ 08000h         ; page 2 - where we page our RAM subslot in
; 256 bytes per segment: DJNZ with B=0 iterates 256 times (B is 8-bit,
; so 'ld b,256' is not encodable - this is the standard idiom).
TESTLEN  equ 0              ; -> 256 iterations
NSEG     equ 32             ; segments to test (32 x 16KB = 512KB)

        org 04000h

; ---------------------------------------------------------------- ROM header
        db  "AB"            ; cartridge signature
        dw  INIT            ; init entry
        dw  0               ; statement
        dw  0               ; device
        dw  0               ; text
        dw  0,0,0           ; reserved

; ---------------------------------------------------------------------------
INIT:
        ld      de,MSG_BANNER
        call    PRINT

        ; ------------------------------------------------------------------
        ; Work out our own slot. At INIT time the BIOS has this cartridge
        ; paged into page 1, so the page-1 field of the primary slot register
        ; (port A8h, bits 3:2) IS our primary slot.
        ;
        ; Then build a slot id for our RAM SUBSLOT:
        ;   bit7 = 1  expanded slot
        ;   bits3:2   = secondary slot = 01 (subslot 1 = mapper RAM)
        ;   bits1:0   = primary slot
        ; ------------------------------------------------------------------
        in      a,(0A8h)
        rrca
        rrca
        and     00000011b       ; a = our primary slot
        or      10000100b       ; + expanded flag + subslot 1
        ld      (OURSLOT),a

        ld      de,MSG_SLOT
        call    PRINT
        ld      a,(OURSLOT)
        call    PRINTHEX
        call    CRLF

        ; ------------------------------------------------------------------
        ; DECISIVE CHECK (2026-08-17): print port A8h - the PRIMARY slot
        ; selection for all four pages. This settles whether page 3
        ; (C000-FFFF, where this test's variables and the STACK live) is our
        ; cartridge or the machine's own RAM.
        ;
        ; The subslot register (FFFF / HEX display) is NOT sufficient on its
        ; own: its page-3 field only matters if page 3's PRIMARY slot is ours.
        ; If A8h bits 7:6 do not equal our primary slot, our RAM is not in
        ; page 3 at all, no matter what the subslot register says.
        ;
        ; Read A8h bits 7:6 and compare against our own primary slot.
        ; ------------------------------------------------------------------
        ld      de,MSG_A8
        call    PRINT
        in      a,(0A8h)
        call    PRINTHEX
        call    CRLF

        ; ------------------------------------------------------------------
        ; CRITICAL (2026-08-17): find out which segment page 3 is showing and
        ; SKIP it.
        ;
        ; The first run reported 763 mismatches in exactly segments 0,1,2 with
        ; 3-31 perfect. exp_reg read 0x50 - page 3 on subslot 1, i.e. page 3
        ; IS our mapper RAM, mapped to its default segment 0. Page 3 is
        ; C000-FFFF, which holds this test's own variables AND the stack. So
        ; writing "segment 0" through page 2 was overwriting the test's own
        ; loop counter and results - SEGNO lives at C002, and segment 0's
        ; pattern at offset 2 is 0 XOR 2 = 2, which corrupts the loop and
        ; cascades into the next segments. The test was destroying itself, not
        ; measuring the hardware.
        ;
        ; Page 3's segment register (port FFh) is readable on this design, so
        ; read it and exclude that one segment. Everything else is testable.
        ; ------------------------------------------------------------------
        in      a,(0FFh)
        and     00011111b
        ld      (SKIPSEG),a

        ld      de,MSG_SKIP
        call    PRINT
        ld      a,(SKIPSEG)
        call    PRINTHEX
        call    CRLF

        ; Remember what normally lives in page 2 so we can put it back.
        ld      a,(RAMAD2)
        ld      (SAVESLOT),a

        ; Page our RAM subslot into page 2.
        ld      a,(OURSLOT)
        ld      h,080h
        call    ENASLT

        ; ==================================================================
        ; PHASE 1 - write every segment
        ;
        ; Interrupts OFF for both phases (2026-08-17). The 60Hz interrupt
        ; handler runs with OUR RAM paged into page 2, and anything it touches
        ; there would be counted as a mapper error. The first run reported 762
        ; mismatches; some of those could have been the ISR rather than the
        ; hardware, and that ambiguity has to go before the number means
        ; anything.
        ; ==================================================================
        di

        ld      de,MSG_WRITING
        call    PRINT

        xor     a
        ld      (SEGNO),a
PH1_SEG:
        ld      a,(SEGNO)
        ld      hl,SKIPSEG
        cp      (hl)
        jp      z,PH1_NEXT          ; page 3 lives here - do not touch it
        out     (MAPPORT2),a        ; select this segment in page 2

        ld      hl,TESTBASE
        ld      b,TESTLEN           ; 0 => 256 iterations
        ld      c,0                 ; c = index within the segment
PH1_BYTE:
        ld      a,(SEGNO)
        xor     c                   ; pattern = segment XOR index
        ld      (hl),a
        inc     hl
        inc     c
        djnz    PH1_BYTE

PH1_NEXT:
        ld      a,(SEGNO)
        inc     a
        ld      (SEGNO),a
        cp      NSEG
        jp      c,PH1_SEG

        ; ==================================================================
        ; PHASE 2 - re-read every segment and count mismatches
        ;
        ; All segments were written BEFORE any is read back, so if two
        ; segments alias onto the same SRAM the later write has clobbered the
        ; earlier one and this pass detects it.
        ; ==================================================================
        ld      de,MSG_READING
        call    PRINT

        ld      hl,0
        ld      (ERRCNT),hl
        ; clear the 32-bit per-segment failure map
        xor     a
        ld      (SEGMAP+0),a
        ld      (SEGMAP+1),a
        ld      (SEGMAP+2),a
        ld      (SEGMAP+3),a
        ld      (SEGNO),a
PH2_SEG:
        xor     a
        ld      (SEGERR),a
        ld      a,(SEGNO)
        ld      hl,SKIPSEG
        cp      (hl)
        jp      z,PH2_NEXT          ; skipped in phase 1 too
        ld      a,(SEGNO)
        out     (MAPPORT2),a

        ld      hl,TESTBASE
        ld      b,TESTLEN           ; 0 => 256 iterations
        ld      c,0
PH2_BYTE:
        ld      a,(SEGNO)
        xor     c                   ; expected value
        ld      d,a
        ld      a,(hl)
        cp      d
        jr      z,PH2_OK
        push    bc
        push    hl
        ld      hl,(ERRCNT)
        inc     hl
        ld      (ERRCNT),hl
        ld      a,1
        ld      (SEGERR),a
        pop     hl
        pop     bc
PH2_OK:
        inc     hl
        inc     c
        djnz    PH2_BYTE

        ; If this segment had any mismatch, set its bit in SEGMAP. Knowing
        ; WHICH segments fail separates two very different faults: specific
        ; segments failing points at addressing or bank selection, while
        ; scattered failures across all segments points at data corruption.
        ld      a,(SEGERR)
        or      a
        jr      z,PH2_NOFLAG
        call    SETSEGBIT
PH2_NOFLAG:

PH2_NEXT:
        ld      a,(SEGNO)
        inc     a
        ld      (SEGNO),a
        cp      NSEG
        jp      c,PH2_SEG

        ; ==================================================================
        ; Restore page 2 BEFORE printing, so the BIOS workspace and the rest
        ; of the boot are undisturbed and the machine can carry on to BASIC.
        ; ==================================================================
        ei

        ld      a,(SAVESLOT)
        ld      h,080h
        call    ENASLT

        ld      de,MSG_ERRS
        call    PRINT
        ld      a,(ERRCNT+1)
        call    PRINTHEX
        ld      a,(ERRCNT)
        call    PRINTHEX
        call    CRLF

        ld      de,MSG_MAP
        call    PRINT
        ld      a,(SEGMAP+3)
        call    PRINTHEX
        ld      a,(SEGMAP+2)
        call    PRINTHEX
        ld      a,(SEGMAP+1)
        call    PRINTHEX
        ld      a,(SEGMAP+0)
        call    PRINTHEX
        call    CRLF

        ld      hl,(ERRCNT)
        ld      a,h
        or      l
        jr      nz,FAILED
        ld      de,MSG_PASS
        call    PRINT
        ret
FAILED:
        ld      de,MSG_FAIL
        call    PRINT
        ret

; ---------------------------------------------------------------- helpers
; Set bit (SEGNO) in the 32-bit SEGMAP bitmap.
SETSEGBIT:
        ld      a,(SEGNO)
        ld      c,a
        srl     a
        srl     a
        srl     a               ; a = byte index (SEGNO / 8)
        ld      e,a
        ld      d,0
        ld      hl,SEGMAP
        add     hl,de           ; hl -> target byte
        ld      a,c
        and     00000111b       ; bit position within the byte
        ld      b,a
        ld      a,1
SETSB_SHIFT:
        inc     b
        dec     b
        jr      z,SETSB_DONE
        add     a,a
        dec     b
        jr      SETSB_SHIFT
SETSB_DONE:
        or      (hl)
        ld      (hl),a
        ret

PRINT:
        ld      a,(de)
        or      a
        ret     z
        call    CHPUT
        inc     de
        jr      PRINT

CRLF:
        ld      a,13
        call    CHPUT
        ld      a,10
        call    CHPUT
        ret

PRINTHEX:
        push    af
        rrca
        rrca
        rrca
        rrca
        call    PRNIB
        pop     af
        call    PRNIB
        ret
PRNIB:
        and     00001111b
        add     a,'0'
        cp      '9'+1
        jr      c,PRNIB1
        add     a,7
PRNIB1:
        call    CHPUT
        ret

; ---------------------------------------------------------------- strings
MSG_BANNER:  db "SDMapper V2.1b mapper test",13,10
             db "RAM on subslot 1, 32 segments",13,10,0
MSG_SLOT:    db "Our RAM slot id: ",0
MSG_WRITING: db "Writing all segments...",13,10,0
MSG_READING: db "Verifying all segments...",13,10,0
MSG_ERRS:    db "Mismatches: ",0
MSG_MAP:     db "Failing segs (31..0): ",0
MSG_SKIP:    db "Skipping seg (page3): ",0
MSG_A8:      db "Port A8h (prim slots): ",0
MSG_PASS:    db "MAPPER PASS - subslot RAM is good",13,10,0
MSG_FAIL:    db "MAPPER FAIL - subslot RAM corrupts",13,10,0

; ---------------------------------------------------------------------------
; Scratch. This ROM cannot use its own address space for variables, so these
; live in the top of the BIOS scratch area in page 3 (safe during INIT).
; ---------------------------------------------------------------------------
OURSLOT  equ 0C000h
SAVESLOT equ 0C001h
SEGNO    equ 0C002h
ERRCNT   equ 0C003h        ; 2 bytes
SEGERR   equ 0C005h        ; per-segment mismatch flag
SEGMAP   equ 0C006h        ; 4 bytes: bit N set if segment N failed
SKIPSEG  equ 0C00Ah        ; segment page 3 is showing - excluded from the test

        end

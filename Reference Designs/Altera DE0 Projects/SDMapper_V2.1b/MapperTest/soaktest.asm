; ============================================================================
; soaktest.asm - Memory Mapper SOAK test cartridge for SDMapper_V2.1b
;
; WHY THIS EXISTS
; ---------------------------------------------------------------------------
; maptest.asm answers "does the mapper work?" and the answer is yes: 31 of 32
; segments byte-perfect. But it only moves 31 x 256 = 7,936 bytes, and that is
; the wrong question.
;
; Port A8h reads 54h on this machine: page 3 (C000-FFFF) is primary slot 1,
; our cartridge, and the subslot register puts subslot 1 (mapper RAM) there.
; The BIOS has adopted our mapper as the machine's MAIN RAM. The Z80 stack and
; the entire BIOS workspace live in our SRAM, so every push, call, ret and
; interrupt touches it. That is correct behaviour for a Memory Mapper cart -
; it is what makes Nextor/DOS2 possible - but it means the mapper does not
; need to be good, it needs to be PERFECT.
;
; It also explains the symptom pattern exactly: SW(8)=1 (mapper off) and
; SW(9)=1 (cart off) both stop the random crashing, because the machine falls
; back to its internal RAM.
;
; The stack moves maptest's entire 7,936 bytes in a few milliseconds. So a
; one-in-a-million access failure passes maptest and kills Nextor within
; seconds of boot. Pass/fail is useless here - we need an error RATE.
;
; WHAT THIS DOES DIFFERENTLY
;   - Full 16KB of every segment, not 256 bytes: ~496KB written and ~496KB
;     verified per pass, roughly 1MB of bus traffic, about 16s at 3.58MHz.
;   - Runs forever, accumulating a 32-BIT total error count across all passes.
;   - Reports pass number and cumulative errors on a new line per pass, then
;     dumps segment / address / expected / actual for the first MAXFAIL
;     mismatches of that pass so the failures can be LOCATED, not just counted.
;
; Leave it running for a few minutes and the error total is a real measurement:
;   E stays 00000000 over tens of MB -> the mapper is genuinely exonerated and
;                                       the Nextor fault is elsewhere (ROM / SD
;                                       / U1 transceiver interaction).
;   E ticks up slowly               -> this is the bug, and we now have a fast
;                                       instrument to measure fixes against.
;
; STRUCTURE: all segments are written BEFORE any is read back, so segment
; aliasing cannot hide behind a per-segment write-then-read.
;
; The pattern is derived from the segment number AND both address bytes
; (seg XOR L XOR H), so a stuck data bit, a stuck address bit and a wrong
; segment all produce mismatches.
;
; SWITCH SETUP (same as maptest)
;   SW(9)=0  SDMapper mode
;   SW(8)=0  mapper RAM + FCh-FFh ports enabled
;   SW(7)=1  SD register window DISABLED
;   SW(6)=0  standard subslot-compliant RAM
;   SW(4)=0  BIST off
;
; Build:  zmac --od . -o soaktest.cim soaktest.asm   (then pad to 16384)
; ============================================================================

CHPUT   equ 000A2h          ; BIOS: print char in A
ENASLT  equ 00024h          ; BIOS: A=slot id, H=page base -> select slot
MAPPORT2 equ 0FEh           ; mapper segment register for page 2
MAPPORT3 equ 0FFh           ; mapper segment register for page 3

TESTBASE equ 08000h         ; page 2 - where the mapper RAM is paged in
TESTLEN  equ 04000h         ; full 16KB per segment
NSEG     equ 32             ; 32 x 16KB = 512KB
MAXFAIL  equ 8              ; failure samples logged per pass

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

        ; Our own slot: at INIT the BIOS has this cartridge in page 1, so the
        ; page-1 field of port A8h (bits 3:2) is our primary slot. Build the
        ; slot id for the RAM subslot: expanded + subslot 1 + primary.
        in      a,(0A8h)
        rrca
        rrca
        and     00000011b
        or      10000100b
        ld      (OURSLOT),a

        ld      de,MSG_SLOT
        call    PRINT
        ld      a,(OURSLOT)
        call    PRINTHEX
        call    CRLF

        ld      de,MSG_A8
        call    PRINT
        in      a,(0A8h)
        call    PRINTHEX
        call    CRLF

        ; ------------------------------------------------------------------
        ; Exclude the segment page 3 is showing. That segment is the same
        ; physical memory as this test's variables AND the stack - writing it
        ; through page 2 would corrupt the test itself. This is what produced
        ; maptest's phantom 763 mismatches before it was understood.
        ; ------------------------------------------------------------------
        in      a,(MAPPORT3)
        and     00011111b
        ld      (SKIPSEG),a

        ld      de,MSG_SKIP
        call    PRINT
        ld      a,(SKIPSEG)
        call    PRINTHEX
        call    CRLF

        ld      de,MSG_START
        call    PRINT

        ; Page the mapper RAM subslot into page 2.
        ld      a,(OURSLOT)
        ld      h,080h
        call    ENASLT

        ; Zero the counters.
        xor     a
        ld      (ERRTOT+0),a
        ld      (ERRTOT+1),a
        ld      (ERRTOT+2),a
        ld      (ERRTOT+3),a
        ld      (PASSCNT+0),a
        ld      (PASSCNT+1),a

        ; ------------------------------------------------------------------
        ; Interrupts OFF for the whole soak. The 60Hz handler runs with our
        ; RAM paged into page 2, so anything it touched there would be counted
        ; as a mapper error. The VDP refreshes itself, so the display survives.
        ; ------------------------------------------------------------------
        di

; ============================================================================
; SOAK LOOP - runs until power off
; ============================================================================
SOAK:
        ; ---------------------------------------------- PHASE 1: write all
        ld      e,0                 ; e = segment number, held in a register
                                    ; so the inner loop never reads page 3
SOAKWSEG:
        ld      a,(SKIPSEG)
        cp      e
        jr      z,SOAKWNEXT
        ld      a,e
        out     (MAPPORT2),a

        ld      hl,TESTBASE
        ld      bc,TESTLEN
SOAKWBYTE:
        ld      a,e
        xor     l
        xor     h                   ; pattern = segment XOR addr low XOR high
        ld      (hl),a
        inc     hl
        dec     bc
        ld      a,b
        or      c
        jr      nz,SOAKWBYTE

SOAKWNEXT:
        inc     e
        ld      a,e
        cp      NSEG
        jr      c,SOAKWSEG

        ; ---------------------------------------------- PHASE 2: verify all
        xor     a
        ld      (FAILN),a           ; fresh sample log for this pass
        ld      e,0
SOAKRSEG:
        ld      a,(SKIPSEG)
        cp      e
        jr      z,SOAKRNEXT
        ld      a,e
        out     (MAPPORT2),a

        ld      hl,TESTBASE
        ld      bc,TESTLEN
SOAKRBYTE:
        ld      a,e
        xor     l
        xor     h
        ld      d,a                 ; d = expected
        ld      a,(hl)
        cp      d
        jr      z,SOAKROK
        call    RECERR
SOAKROK:
        inc     hl
        dec     bc
        ld      a,b
        or      c
        jr      nz,SOAKRBYTE

SOAKRNEXT:
        inc     e
        ld      a,e
        cp      NSEG
        jr      c,SOAKRSEG

        ; ---------------------------------------------- report this pass
        ld      hl,(PASSCNT)
        inc     hl
        ld      (PASSCNT),hl

        ld      a,13                ; CR only - overwrite the same line
        call    CHPUT
        ld      de,MSG_P
        call    PRINT
        ld      a,(PASSCNT+1)
        call    PRINTHEX
        ld      a,(PASSCNT+0)
        call    PRINTHEX
        ld      de,MSG_E
        call    PRINT
        ld      a,(ERRTOT+3)
        call    PRINTHEX
        ld      a,(ERRTOT+2)
        call    PRINTHEX
        ld      a,(ERRTOT+1)
        call    PRINTHEX
        ld      a,(ERRTOT+0)
        call    PRINTHEX
        call    CRLF

        ; ------------------------------------------------------------------
        ; Dump where the failures actually were. The error count per pass is
        ; almost constant (9,7,7,7 on the first run), which is the signature
        ; of DETERMINISTIC failures at fixed locations rather than random
        ; metastability - so the addresses should repeat pass to pass, and
        ; that is what identifies the fault.
        ; ------------------------------------------------------------------
        xor     a
        ld      (FI),a
PRF_LOOP:
        ld      a,(FI)
        ld      b,a
        ld      a,(FAILN)
        cp      b
        jp      z,PRF_END

        ld      a,b                 ; hl = FAILBUF + index*5
        add     a,a
        add     a,a
        add     a,b
        ld      l,a
        ld      h,0
        ld      de,FAILBUF
        add     hl,de
        ld      (RECPTR),hl

        ld      de,MSG_S
        call    PRINT
        ld      hl,(RECPTR)
        ld      a,(hl)              ; segment
        call    PRINTHEX

        ld      de,MSG_AT
        call    PRINT
        ld      hl,(RECPTR)
        inc     hl
        ld      a,(hl)              ; address high
        call    PRINTHEX
        inc     hl
        ld      a,(hl)              ; address low
        call    PRINTHEX

        ld      de,MSG_EXP
        call    PRINT
        ld      hl,(RECPTR)
        ld      de,3
        add     hl,de
        ld      a,(hl)              ; expected
        call    PRINTHEX

        ld      de,MSG_GOT
        call    PRINT
        ld      hl,(RECPTR)
        ld      de,4
        add     hl,de
        ld      a,(hl)              ; actual
        call    PRINTHEX
        call    CRLF

        ld      a,(FI)
        inc     a
        ld      (FI),a
        jp      PRF_LOOP
PRF_END:

        jp      SOAK

; ---------------------------------------------------------------- helpers
; Record one mismatch: bump the 32-bit total, and for the first MAXFAIL of
; each pass also log segment / address / expected / actual so the failures can
; be located instead of merely counted.
;
; Must preserve BC, DE and HL - the caller is mid-scan and holds the pointer,
; the byte count, the expected value and the segment number in them.
; On entry: A = actual, D = expected, E = segment, HL = address.
RECERR:
        ld      (TMPACT),a
        push    hl
        push    de
        push    bc
        push    af
        ld      (TMPADR),hl
        ld      a,e
        ld      (TMPSEG),a
        ld      a,d
        ld      (TMPEXP),a

        ld      hl,ERRTOT
        inc     (hl)
        jr      nz,RE_1
        inc     hl
        inc     (hl)
        jr      nz,RE_1
        inc     hl
        inc     (hl)
        jr      nz,RE_1
        inc     hl
        inc     (hl)
RE_1:
        ld      a,(FAILN)
        cp      MAXFAIL
        jr      nc,RE_DONE
        ld      b,a
        inc     a
        ld      (FAILN),a
        ld      a,b                 ; hl = FAILBUF + index*5
        add     a,a
        add     a,a
        add     a,b
        ld      l,a
        ld      h,0
        ld      de,FAILBUF
        add     hl,de

        ld      a,(TMPSEG)
        ld      (hl),a
        inc     hl
        ld      a,(TMPADR+1)
        ld      (hl),a
        inc     hl
        ld      a,(TMPADR+0)
        ld      (hl),a
        inc     hl
        ld      a,(TMPEXP)
        ld      (hl),a
        inc     hl
        ld      a,(TMPACT)
        ld      (hl),a
RE_DONE:
        pop     af
        pop     bc
        pop     de
        pop     hl
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
MSG_BANNER:  db "SDMapper V2.1b mapper SOAK",13,10
             db "Full 16KB x 31 segs per pass",13,10,0
MSG_SLOT:    db "Our RAM slot id: ",0
MSG_A8:      db "Port A8h (prim slots): ",0
MSG_SKIP:    db "Skipping seg (page3): ",0
MSG_START:   db "Soaking - leave it running.",13,10
             db "E must stay 00000000.",13,10,0
MSG_P:       db "pass ",0
MSG_E:       db "  errors ",0
MSG_S:       db " s=",0
MSG_AT:      db " @",0
MSG_EXP:     db " exp=",0
MSG_GOT:     db " got=",0

; ---------------------------------------------------------------------------
; Scratch in page 3. Page 3 is our own mapper RAM at the segment named by
; SKIPSEG, which is why that segment is excluded from the test.
; ---------------------------------------------------------------------------
OURSLOT  equ 0C000h
SKIPSEG  equ 0C001h
ERRTOT   equ 0C002h        ; 4 bytes, little-endian
PASSCNT  equ 0C006h        ; 2 bytes
FAILN    equ 0C008h        ; failures logged this pass
FI       equ 0C009h        ; print loop index
RECPTR   equ 0C00Ah        ; 2 bytes
TMPSEG   equ 0C00Ch
TMPEXP   equ 0C00Dh
TMPACT   equ 0C00Eh
TMPADR   equ 0C00Fh        ; 2 bytes
FAILBUF  equ 0C020h        ; MAXFAIL x 5 bytes: seg, addrH, addrL, exp, got

        end

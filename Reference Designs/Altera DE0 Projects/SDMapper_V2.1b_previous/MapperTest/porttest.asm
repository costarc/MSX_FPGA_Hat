; ============================================================================
; porttest.asm - Memory Mapper PORT test cartridge for SDMapper_V2.1b
;
; WHY THIS EXISTS
; ---------------------------------------------------------------------------
; soaktest proves the mapper's MEMORY path is clean: ~27MB with zero errors.
; But it barely touches the mapper's I/O PORT path - it writes only port FEh
; and reads port FFh exactly once, at startup.
;
; Nextor does the opposite. Its DOS2 mapper support routines read and write
; all four ports (FCh-FFh) constantly while allocating segments, and that is
; precisely where boot now hangs: NEXTOR.SYS loads (so the SD path and the
; memory path both work), then the machine dies during Nextor's own
; initialisation. With a MegaFlashROM supplying the mapper instead, this same
; driver and SD path boot all the way to the file manager. So the fault is
; specific to OUR mapper, used the way Nextor uses it - which is via the
; ports, the one path never measured.
;
; The port READ path is also the slowest decode in the design:
;   s_addr_valid rises ~200ns into the cycle (A_MUX capture), and
;   s_io_mapper_rd_qualified then needs MIN_PULSE_CYCLES = 8 more (160ns),
; so D and BUSDIR_n only assert ~360ns in, against a Z80 I/O read that
; samples at ~558ns. About 200ns of margin - enough on paper, never measured.
; If that margin is not really there, reads return stale or floating data,
; DOS2 misreads which segments are in use, allocates the segment holding the
; stack, writes it, and the machine hangs exactly where it does.
;
; WHAT THIS DOES
;   Phase 1 (READ ONLY, completely safe): read all four ports once to learn
;   their current values, then re-read them thousands of times and count any
;   reading that differs. A correct port read is perfectly repeatable, so ANY
;   mismatch is a marginal read path.
;
;   Phase 2 (write+verify, page 2 only): write every value 0-31 to port FEh
;   and read it back, expecting "111" & value per the MSX standard (and per
;   memoria2_en.pdf Table 1 for a 512KB/32-segment mapper).
;
; SAFETY: port FFh is NEVER written. It selects page 3's segment, and page 3
; holds this program's stack and the BIOS workspace - writing a different
; segment there would swap the stack out mid-instruction. Ports FCh and FDh
; are safe to write (pages 0 and 1 are the BIOS and our ROM subslot, so our
; mapper is not visible there), but this test only writes FEh, which is the
; page our own RAM is legitimately paged into.
;
; SWITCH SETUP: same isolation config as soaktest -
;   SW(9)=0  SW(8)=0  SW(7)=1  SW(6)=0  SW(4)=0
;
; Build:  zmac --od . -o porttest.cim porttest.asm   (then pad to 16384)
; ============================================================================

CHPUT   equ 000A2h
MAPPORT0 equ 0FCh
MAPPORT1 equ 0FDh
MAPPORT2 equ 0FEh
MAPPORT3 equ 0FFh

NPASS   equ 32              ; outer passes; inner loop is 256 -> 8192 reads/port

        org 04000h

        db  "AB"
        dw  INIT
        dw  0
        dw  0
        dw  0
        dw  0,0,0

; ---------------------------------------------------------------------------
INIT:
        ld      de,MSG_BANNER
        call    PRINT

        di                      ; the 60Hz handler must not touch the ports

        ; ---------------------------------------------------------------
        ; Learn the current value of each port. These are whatever the BIOS
        ; left set up; we only care that they stay CONSTANT when re-read.
        ; ---------------------------------------------------------------
        in      a,(MAPPORT0)
        ld      (EXP0),a
        in      a,(MAPPORT1)
        ld      (EXP1),a
        in      a,(MAPPORT2)
        ld      (EXP2),a
        in      a,(MAPPORT3)
        ld      (EXP3),a

        ld      de,MSG_BASE
        call    PRINT
        ld      a,(EXP0)
        call    PRINTHEX
        ld      a,' '
        call    CHPUT
        ld      a,(EXP1)
        call    PRINTHEX
        ld      a,' '
        call    CHPUT
        ld      a,(EXP2)
        call    PRINTHEX
        ld      a,' '
        call    CHPUT
        ld      a,(EXP3)
        call    PRINTHEX
        call    CRLF

        ; zero the four mismatch counters
        xor     a
        ld      (ERR0),a
        ld      (ERR1),a
        ld      (ERR2),a
        ld      (ERR3),a
        ld      (ERRW),a
        ; BUG FIX (2026-08-18): these three were never zeroed, so FIRSTW held
        ; whatever garbage page-3 RAM happened to contain and the "first bad
        ; seg" line printed stale memory even when write/verify errs was 00.
        ; It also made the test look reset-dependent, because a cold power-on
        ; leaves different garbage in page 3 than a reset does.
        ld      (FIRSTW),a
        ld      (FIRSTSEG),a
        ld      (FIRSTGOT),a

        ; ---------------------------------------------------------------
        ; PHASE 1 - hammer all four ports read-only
        ; ---------------------------------------------------------------
        ld      de,MSG_P1
        call    PRINT

        ld      c,NPASS
PT_OUTER:
        ld      b,0             ; 0 -> 256 iterations
PT_LOOP:
        in      a,(MAPPORT0)
        ld      hl,EXP0
        cp      (hl)
        jr      z,PT_OK0
        ld      hl,ERR0
        inc     (hl)
PT_OK0:
        in      a,(MAPPORT1)
        ld      hl,EXP1
        cp      (hl)
        jr      z,PT_OK1
        ld      hl,ERR1
        inc     (hl)
PT_OK1:
        in      a,(MAPPORT2)
        ld      hl,EXP2
        cp      (hl)
        jr      z,PT_OK2
        ld      hl,ERR2
        inc     (hl)
PT_OK2:
        in      a,(MAPPORT3)
        ld      hl,EXP3
        cp      (hl)
        jr      z,PT_OK3
        ld      hl,ERR3
        inc     (hl)
PT_OK3:
        djnz    PT_LOOP
        dec     c
        jr      nz,PT_OUTER

        ld      de,MSG_R1
        call    PRINT
        ld      a,(ERR0)
        call    PRINTHEX
        ld      a,' '
        call    CHPUT
        ld      a,(ERR1)
        call    PRINTHEX
        ld      a,' '
        call    CHPUT
        ld      a,(ERR2)
        call    PRINTHEX
        ld      a,' '
        call    CHPUT
        ld      a,(ERR3)
        call    PRINTHEX
        call    CRLF

        ; ---------------------------------------------------------------
        ; PHASE 2 - write/verify port FEh (page 2) across all 32 segments.
        ; Expected readback is "111" & value: unimplemented high bits read
        ; as 1s, which is how DOS sizes the mapper (memoria2 Table 1).
        ; ---------------------------------------------------------------
        ld      de,MSG_P2
        call    PRINT

        ld      c,NPASS
PW_OUTER:
        ld      b,32            ; segments 0..31
        ld      e,0
PW_LOOP:
        ld      a,e
        out     (MAPPORT2),a
        in      a,(MAPPORT2)
        ld      d,a
        ld      a,e
        or      11100000b       ; expected = "111" & segment
        cp      d
        jr      z,PW_OK
        ld      hl,ERRW
        inc     (hl)
        ; log the first bad one so we can see the shape of the failure
        ld      a,(FIRSTW)
        or      a
        jr      nz,PW_OK
        ld      a,1
        ld      (FIRSTW),a
        ld      a,e
        ld      (FIRSTSEG),a
        ld      a,d
        ld      (FIRSTGOT),a
PW_OK:
        inc     e
        djnz    PW_LOOP
        dec     c
        jr      nz,PW_OUTER

        ; restore page 2 to the segment it had on entry
        ld      a,(EXP2)
        and     00011111b
        out     (MAPPORT2),a

        ld      de,MSG_R2
        call    PRINT
        ld      a,(ERRW)
        call    PRINTHEX
        call    CRLF

        ld      a,(FIRSTW)
        or      a
        jr      z,PT_DONE
        ld      de,MSG_FIRST
        call    PRINT
        ld      a,(FIRSTSEG)
        call    PRINTHEX
        ld      de,MSG_GOT
        call    PRINT
        ld      a,(FIRSTGOT)
        call    PRINTHEX
        call    CRLF

PT_DONE:
        ld      de,MSG_END
        call    PRINT
PT_HALT:
        jr      PT_HALT

; ---------------------------------------------------------------- helpers
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
MSG_BANNER: db "SDMapper V2.1b mapper PORT test",13,10
            db "Ports FCh-FFh read/write path",13,10,0
MSG_BASE:   db "Base FC FD FE FF: ",0
MSG_P1:     db "Phase1: 8192 reads x 4 ports",13,10,0
MSG_R1:     db " errs FC FD FE FF: ",0
MSG_P2:     db "Phase2: FEh write+verify",13,10,0
MSG_R2:     db " write/verify errs: ",0
MSG_FIRST:  db " first bad seg=",0
MSG_GOT:    db " got=",0
MSG_END:    db "Done.",13,10,0

; ---------------------------------------------------------------------------
EXP0     equ 0C000h
EXP1     equ 0C001h
EXP2     equ 0C002h
EXP3     equ 0C003h
ERR0     equ 0C004h
ERR1     equ 0C005h
ERR2     equ 0C006h
ERR3     equ 0C007h
ERRW     equ 0C008h
FIRSTW   equ 0C009h
FIRSTSEG equ 0C00Ah
FIRSTGOT equ 0C00Bh

        end

; ============================================================================
; ffffstress.asm - subslot register (0FFFFh) stress test for SDMapper_V2.1b
;
; THE QUESTION THIS ANSWERS
; ---------------------------------------------------------------------------
; On real hardware Nextor hangs with exp_reg frozen at 0x55 while the value it
; needed was 0x51. It is tempting to call that "one bit corrupted" - but BOTH
; values are legitimate:
;
;   0x55 = 0101 0101 -> all four pages on subslot 1 (RAM). Normal TPA routing
;                       while Nextor runs user code.
;   0x51 = 0101 0001 -> page 1 on subslot 0 (ROM). Written to bank the Nextor
;                       kernel in before calling it.
;
; So a frozen 0x55 has two completely different explanations:
;
;   (a) DROPPED WRITE - Nextor wrote 0x51, our register never took it, and the
;       PREVIOUS legitimate value 0x55 simply remained. Suspect:
;         if exp_wr_raw = '0' and exp_wr_raw_d = '1' and exp_wr_len >= "0100"
;       silently discards any window shorter than 4 clocks, and the window
;       cannot open until s_addr_valid (the reconstructed address) asserts.
;       Belavenuto's working CPLD has neither the length filter nor the
;       address-capture dependency.
;
;   (b) CORRUPTED WRITE - the 0x51 arrived but a bit was mis-sampled.
;
; The two demand opposite fixes, and per-bit voting only helps (b). This test
; distinguishes them directly: it writes a known value, reads it back, and on a
; mismatch classifies the result by comparing against the PREVIOUS value
; written.
;
;   got == previous value  -> the write was DROPPED
;   got == something else  -> the write was CORRUPTED
;
; SAFETY - why only two fields are varied
; ---------------------------------------------------------------------------
; Writing 0FFFFh re-routes memory under the running program, so only the two
; fields that are inert here are touched:
;
;   bits 1:0 (page 0) - port A8h keeps the BIOS in page 0, so our subslot
;                       field for page 0 has no effect at all.
;   bits 5:4 (page 2) - page 2 is not used by this test.
;
; PRESERVED, and it is fatal to disturb either:
;   bits 3:2 (page 1) - our ROM, where this code is EXECUTING.
;   bits 7:6 (page 3) - our RAM, where the STACK and these variables live.
;
; That gives 16 patterns, cycled continuously. Reading 0FFFFh returns the
; COMPLEMENT of the register, hence the CPL after each read.
;
; SWITCH SETUP: SW(9)=0 SW(8)=0 SW(7)=1 SW(6)=0 SW(4)=0
;
; Build:  zmac --od . -o ffffstress.cim ffffstress.asm  (then pad to 16384)
; ============================================================================

CHPUT   equ 000A2h

VARMASK equ 00110011b       ; page 0 (1:0) and page 2 (5:4) - safe to change
KEEPMASK equ 11001100b      ; page 1 (3:2) and page 3 (7:6) - MUST be preserved

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

        di                      ; the ISR makes inter-slot calls, which write FFFF

        ; Current subslot register (read returns the complement).
        ld      a,(0FFFFh)
        cpl
        ld      (BASE),a
        ld      (PREVV),a       ; the "previous value written", to start with

        ld      de,MSG_BASE
        call    PRINT
        ld      a,(BASE)
        call    PRINTHEX
        call    CRLF

        xor     a
        ld      (VIDX),a
        ld      (ERRT+0),a
        ld      (ERRT+1),a
        ld      (NDROP+0),a
        ld      (NDROP+1),a
        ld      (NCORR+0),a
        ld      (NCORR+1),a
        ld      (GOTFIRST),a

        ld      de,MSG_RUN
        call    PRINT

        ld      hl,0            ; 65536 iterations
        ld      (ITER),hl

; ============================================================================
STRESS:
        ; ---- build the next pattern: VIDX low 2 bits -> page 0 field,
        ;      VIDX high 2 bits -> page 2 field
        ld      a,(VIDX)
        ld      c,a
        and     00000011b
        ld      b,a
        ld      a,c
        and     00001100b
        add     a,a
        add     a,a             ; bits 3:2 -> bits 5:4
        or      b               ; a = varying bits, within VARMASK
        ld      c,a
        ld      a,(BASE)
        and     KEEPMASK        ; keep page 1 and page 3 exactly as they are
        or      c
        ld      (EXPV),a

        ; ---- write it, then read it straight back
        ld      (0FFFFh),a
        ld      a,(0FFFFh)
        cpl
        ld      (GOTV),a

        ld      hl,EXPV
        cp      (hl)
        jr      z,ST_OK

        ; ---- mismatch: classify it
        ld      hl,ERRT
        inc     (hl)
        jr      nz,ST_C1
        inc     hl
        inc     (hl)
ST_C1:
        ld      a,(GOTV)
        ld      hl,PREVV
        cp      (hl)
        jr      nz,ST_CORRUPT

        ; got == previous value written -> the write never landed
        ld      hl,NDROP
        inc     (hl)
        jr      nz,ST_LOG
        inc     hl
        inc     (hl)
        jr      ST_LOG

ST_CORRUPT:
        ld      hl,NCORR
        inc     (hl)
        jr      nz,ST_LOG
        inc     hl
        inc     (hl)

ST_LOG:
        ld      a,(GOTFIRST)
        or      a
        jr      nz,ST_OK
        ld      a,1
        ld      (GOTFIRST),a
        ld      a,(EXPV)
        ld      (FEXP),a
        ld      a,(GOTV)
        ld      (FGOT),a
        ld      a,(PREVV)
        ld      (FPREV),a

ST_OK:
        ; whatever happened, the value we ATTEMPTED becomes "previous"
        ld      a,(EXPV)
        ld      (PREVV),a

        ld      a,(VIDX)
        inc     a
        and     00001111b
        ld      (VIDX),a

        ld      hl,(ITER)
        dec     hl
        ld      (ITER),hl
        ld      a,h
        or      l
        jp      nz,STRESS

; ============================================================================
        ; restore the register to exactly what we found
        ld      a,(BASE)
        ld      (0FFFFh),a
        ei

        ld      de,MSG_TOT
        call    PRINT
        ld      a,(ERRT+1)
        call    PRINTHEX
        ld      a,(ERRT+0)
        call    PRINTHEX
        call    CRLF

        ld      de,MSG_DROP
        call    PRINT
        ld      a,(NDROP+1)
        call    PRINTHEX
        ld      a,(NDROP+0)
        call    PRINTHEX
        call    CRLF

        ld      de,MSG_CORR
        call    PRINT
        ld      a,(NCORR+1)
        call    PRINTHEX
        ld      a,(NCORR+0)
        call    PRINTHEX
        call    CRLF

        ld      a,(GOTFIRST)
        or      a
        jr      z,ST_END
        ld      de,MSG_F1
        call    PRINT
        ld      a,(FEXP)
        call    PRINTHEX
        ld      de,MSG_F2
        call    PRINT
        ld      a,(FGOT)
        call    PRINTHEX
        ld      de,MSG_F3
        call    PRINT
        ld      a,(FPREV)
        call    PRINTHEX
        call    CRLF

ST_END:
        ld      de,MSG_DONE
        call    PRINT
ST_HALT:
        jr      ST_HALT

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
MSG_BANNER: db "SDMapper V2.1b FFFF stress",13,10
            db "Subslot reg: dropped vs corrupt",13,10,0
MSG_BASE:   db "Base FFFF value: ",0
MSG_RUN:    db "65536 write+readback...",13,10,0
MSG_TOT:    db "Total mismatches: ",0
MSG_DROP:   db "  DROPPED (got=prev): ",0
MSG_CORR:   db "  CORRUPT (got=other): ",0
MSG_F1:     db "first exp=",0
MSG_F2:     db " got=",0
MSG_F3:     db " prev=",0
MSG_DONE:   db "Done.",13,10,0

; ---------------------------------------------------------------------------
BASE     equ 0C000h
PREVV    equ 0C001h
EXPV     equ 0C002h
GOTV     equ 0C003h
VIDX     equ 0C004h
ITER     equ 0C005h        ; 2 bytes
ERRT     equ 0C007h        ; 2 bytes
NDROP    equ 0C009h        ; 2 bytes
NCORR    equ 0C00Bh        ; 2 bytes
GOTFIRST equ 0C00Dh
FEXP     equ 0C00Eh
FGOT     equ 0C00Fh
FPREV    equ 0C010h

        end

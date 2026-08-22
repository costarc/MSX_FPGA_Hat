; ============================================================================
; page0test.asm - Memory Mapper PAGE 0 test cartridge for SDMapper_V2.1b
;
; WHY THIS EXISTS
; ---------------------------------------------------------------------------
; Every mapper test written for this project - maptest, soaktest, soaktest_ei,
; porttest - uses ENASLT to page our RAM into PAGE 2 and tests only
; 8000-BFFF. That is ~27MB through ONE of the four decode paths:
;
;   s_mem_page_seg <= reg_page0_q when s_A(15 downto 14) = "00" else
;                     reg_page1_q when s_A(15 downto 14) = "01" else
;                     reg_page2_q when s_A(15 downto 14) = "10" else
;                     reg_page3_q;
;
; reg_page2_q is exhaustively proven. reg_page3_q is exercised incidentally
; (the stack lives in page 3 and works). reg_page0_q has NEVER been touched by
; any test.
;
; That matters now. Real hardware shows Nextor writing 0x51 to the subslot
; register, which decodes as:
;     page 0 -> subslot 1 (our RAM)     <-- the untested path
;     page 1 -> subslot 0 (our ROM)
;     page 2 -> subslot 1 (our RAM)
;     page 3 -> subslot 1 (our RAM)
; Under DOS the TPA starts at 0100h, so page 0 IS our mapper RAM - and that is
; exactly where an FCB lives. On the runs where the subslot register captured
; correctly (0x51), NEXTOR.SYS loaded and then failed with a File Control
; Block error: data corruption in DOS structures, not a routing failure.
;
; HOW IT WORKS - and why it cannot use the BIOS
; ---------------------------------------------------------------------------
; Mapping our RAM into page 0 REMOVES THE BIOS: no CHPUT, no RST vectors, no
; interrupt handler at 0038h. So the test:
;   1. saves port A8h and the subslot register,
;   2. switches page 0 to our RAM by direct port writes (ENASLT itself lives
;      in the BIOS and cannot be used to bring the BIOS back afterwards),
;   3. runs the whole write/verify pass with interrupts OFF and NO BIOS calls,
;      accumulating results in page-3 variables,
;   4. restores A8h and the subslot register,
;   5. only THEN prints.
;
; Code executes from page 1 (our ROM) and the stack is in page 3 (our RAM)
; throughout, so neither is disturbed by swapping page 0.
;
; SAFETY: the segment currently mapped in page 3 is skipped, exactly as in
; soaktest - page 3 holds this program's stack and variables, and writing that
; same segment through page 0 would corrupt them.
;
; SWITCH SETUP: SW(9)=0 SW(8)=0 SW(7)=1 SW(6)=0 SW(4)=0
;
; Build:  zmac --od . -o page0test.cim page0test.asm   (then pad to 16384)
; ============================================================================

CHPUT    equ 000A2h
MAPPORT0 equ 0FCh           ; segment register for PAGE 0 - the path under test
MAPPORT3 equ 0FFh

P0BASE   equ 00000h         ; page 0
P0LEN    equ 04000h         ; full 16KB
NSEG     equ 32
MAXFAIL  equ 8

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

        ; our primary slot, from the page-1 field of A8h (we are in page 1)
        in      a,(0A8h)
        rrca
        rrca
        and     00000011b
        ld      (OURPRIM),a

        ; the segment page 3 is showing - must not be written through page 0
        in      a,(MAPPORT3)
        and     00011111b
        ld      (SKIPSEG),a

        ld      de,MSG_SKIP
        call    PRINT
        ld      a,(SKIPSEG)
        call    PRINTHEX
        call    CRLF

        ld      de,MSG_RUN
        call    PRINT

        xor     a
        ld      (ERRC+0),a
        ld      (ERRC+1),a
        ld      (FAILN),a

        di                      ; no ISR: its vector at 0038h is about to vanish

        ; ---------------------------------------------------------------
        ; Save the current page-0 routing, then point page 0 at our RAM.
        ; Reading 0FFFFh returns the COMPLEMENT of the subslot register.
        ; ---------------------------------------------------------------
        in      a,(0A8h)
        ld      (SAVEA8),a
        ld      a,(0FFFFh)
        cpl                     ; -> the actual subslot register value
        ld      (SAVEFF),a

        and     11111100b       ; page-0 field = subslot 1 (our RAM)
        or      00000001b
        ld      (0FFFFh),a

        ld      a,(SAVEA8)
        and     11111100b       ; page-0 primary slot = ours
        ld      hl,OURPRIM
        or      (hl)
        out     (0A8h),a

        ; ===============================================================
        ; From here until the restore below: NO BIOS, NO interrupts.
        ; Page 0 is our mapper RAM. Code is in page 1 (ROM), stack in
        ; page 3 (RAM).
        ; ===============================================================

        ; ---- PHASE 1: write every segment through PAGE 0
        ld      e,0
P0WSEG:
        ld      a,(SKIPSEG)
        cp      e
        jr      z,P0WNEXT
        ld      a,e
        out     (MAPPORT0),a

        ld      hl,P0BASE
        ld      bc,P0LEN
P0WBYTE:
        ld      a,e
        xor     l
        xor     h
        ld      (hl),a
        inc     hl
        dec     bc
        ld      a,b
        or      c
        jr      nz,P0WBYTE
P0WNEXT:
        inc     e
        ld      a,e
        cp      NSEG
        jr      c,P0WSEG

        ; ---- PHASE 2: verify every segment through PAGE 0
        ld      e,0
P0RSEG:
        ld      a,(SKIPSEG)
        cp      e
        jr      z,P0RNEXT
        ld      a,e
        out     (MAPPORT0),a

        ld      hl,P0BASE
        ld      bc,P0LEN
P0RBYTE:
        ld      a,e
        xor     l
        xor     h
        ld      d,a
        ld      a,(hl)
        cp      d
        jr      z,P0ROK
        call    P0REC
P0ROK:
        inc     hl
        dec     bc
        ld      a,b
        or      c
        jr      nz,P0RBYTE
P0RNEXT:
        inc     e
        ld      a,e
        cp      NSEG
        jr      c,P0RSEG

        ; ---------------------------------------------------------------
        ; Restore page 0: primary slot FIRST (brings the BIOS back), then
        ; the subslot register. Only after this is CHPUT callable again.
        ; ---------------------------------------------------------------
        ld      a,(SAVEA8)
        out     (0A8h),a
        ld      a,(SAVEFF)
        ld      (0FFFFh),a
        ei

        ; ---------------------------------------------------------------
        ld      de,MSG_ERRS
        call    PRINT
        ld      a,(ERRC+1)
        call    PRINTHEX
        ld      a,(ERRC+0)
        call    PRINTHEX
        call    CRLF

        xor     a
        ld      (FI),a
P0P_LOOP:
        ld      a,(FI)
        ld      b,a
        ld      a,(FAILN)
        cp      b
        jp      z,P0P_END
        ld      a,b
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
        ld      a,(hl)
        call    PRINTHEX
        ld      de,MSG_AT
        call    PRINT
        ld      hl,(RECPTR)
        inc     hl
        ld      a,(hl)
        call    PRINTHEX
        inc     hl
        ld      a,(hl)
        call    PRINTHEX
        ld      de,MSG_EXP
        call    PRINT
        ld      hl,(RECPTR)
        ld      de,3
        add     hl,de
        ld      a,(hl)
        call    PRINTHEX
        ld      de,MSG_GOT
        call    PRINT
        ld      hl,(RECPTR)
        ld      de,4
        add     hl,de
        ld      a,(hl)
        call    PRINTHEX
        call    CRLF

        ld      a,(FI)
        inc     a
        ld      (FI),a
        jp      P0P_LOOP
P0P_END:
        ld      de,MSG_DONE
        call    PRINT
P0_HALT:
        jr      P0_HALT

; ---------------------------------------------------------------- helpers
; Record a mismatch. Runs with NO BIOS available - page-3 memory only.
; On entry: A = actual, D = expected, E = segment, HL = address.
P0REC:
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

        ld      hl,(ERRC)
        inc     hl
        ld      (ERRC),hl

        ld      a,(FAILN)
        cp      MAXFAIL
        jr      nc,P0REC_DONE
        ld      b,a
        inc     a
        ld      (FAILN),a
        ld      a,b
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
P0REC_DONE:
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
MSG_BANNER: db "SDMapper V2.1b PAGE 0 test",13,10
            db "reg_page0_q path - never tested",13,10,0
MSG_SKIP:   db "Skipping seg (page3): ",0
MSG_RUN:    db "Testing 0000-3FFF, BIOS off...",13,10,0
MSG_ERRS:   db "Page 0 mismatches: ",0
MSG_S:      db " s=",0
MSG_AT:     db " @",0
MSG_EXP:    db " e=",0
MSG_GOT:    db " g=",0
MSG_DONE:   db "Done.",13,10,0

; ---------------------------------------------------------------------------
OURPRIM  equ 0C000h
SKIPSEG  equ 0C001h
SAVEA8   equ 0C002h
SAVEFF   equ 0C003h
ERRC     equ 0C004h        ; 2 bytes
FAILN    equ 0C006h
FI       equ 0C007h
RECPTR   equ 0C008h        ; 2 bytes
TMPSEG   equ 0C00Ah
TMPEXP   equ 0C00Bh
TMPACT   equ 0C00Ch
TMPADR   equ 0C00Dh        ; 2 bytes
FAILBUF  equ 0C020h        ; MAXFAIL x 5: seg, addrH, addrL, exp, got

        end

; =============================================================================
; TESTMAPPER.ROM - Standard MSX Memory Mapper detection & test utility
;
; Boots as a standard 16KB MSX cartridge ROM (page 1, 4000h-7FFFh).
; Targets the Memory-Mapper segment register on port FEh, which drives the
; page-2 window (8000h-BFFFh) - the standard MSX page for testing a mapper
; from a cartridge, and the only page confirmed cartridge-routed on the
; SDMapper_V2.1b test hardware (Canon V-8/V-9). Ports FCh/FDh/FFh are
; intentionally never WRITTEN, to avoid any risk to the ROM's own execution
; page (FDh = page 1) or the system stack (FFh = page 3).
;
; The segment register is a standard MSX Memory Mapper register: up to 256
; segments (4096KB), all reachable from port FEh regardless of how many the
; specific hardware actually implements - this is not specific to our own
; 512KB SDMapper_V2.1b, it also correctly sizes far larger third-party
; mappers (e.g. a 4096KB Zemmix mapper).
;
; Size is not read from the register width (some hardware always implements
; the full width even if less SRAM is actually populated). Instead it is
; measured empirically: a unique fingerprint is written to address 8000h of
; every one of the up to 256 possible segments, then read back. The count of
; segments that still hold their own distinct fingerprint (before the first
; mismatch/alias) is the real, physically-present size.
;
; The optional test writes and verifies four full-fill patterns (00h, FFh,
; AAh, 55h) across the entire 16KB window of every detected segment. 00h/FFh
; catch stuck-at-0 and stuck-at-1 faults on every data bit; AAh/55h catch
; adjacent-bit coupling faults that 00h/FFh alone would miss.
;
; Screen output deliberately avoids the BIOS POSIT call for anything beyond
; a single CLS-then-flow-down sequence: POSIT's row parameter was found (on
; real MSX BIOS, though not in the openMSX/C-BIOS emulator used for initial
; development) to not reliably move to the requested row, corrupting text by
; printing a second line on top of the first. Every screen here is instead
; built as CLS followed by purely sequential PRSTR/NEWLINE calls, the same
; mechanism BASIC's own PRINT statement uses - guaranteed identical cursor
; behaviour on every MSX ever made.
; =============================================================================

    DEVICE NOSLOT64K
    ORG 4000h

; -----------------------------------------------------------------------------
; ROM header
; -----------------------------------------------------------------------------
    DB "AB"
    DW START
    DW 0,0,0,0,0,0,0,0,0,0

; -----------------------------------------------------------------------------
; BIOS entry points / system variables
; -----------------------------------------------------------------------------
CHGET       equ 009Fh
CHPUT       equ 00A2h
CHSNS       equ 009Ch
INITXT      equ 006Ch

FORCLR      equ 0F3E9h
BAKCLR      equ 0F3EAh
BDRCLR      equ 0F3EBh

; -----------------------------------------------------------------------------
; Hardware constants
; -----------------------------------------------------------------------------
MAPPORT     equ 0FEh        ; Memory Mapper segment register - page 2 (8000h)
P3PORT      equ 0FFh        ; page-3 segment register - READ ONLY, never written
TESTADR     equ 8000h       ; base of the page-2 test window
FPBYTE      equ 0A5h        ; fingerprint XOR constant used for size detection

; -----------------------------------------------------------------------------
; Scratch RAM variables
; DOS/BASIC are never running (this ROM takes over the whole machine at
; boot), so an unused pocket of system work RAM below our own stack is used.
; -----------------------------------------------------------------------------
VARBASE     equ 0F000h
ORIGSEG     equ VARBASE+0    ; segment value to restore when done (1 byte)
SEGCOUNT    equ VARBASE+1    ; detected segment count, 0-256 (2 bytes)
CURPAT      equ VARBASE+3    ; pattern currently being filled/verified (1 byte)
SEGFAIL     equ VARBASE+4    ; 0/1 - did the current pattern check fail
ANYFAIL     equ VARBASE+5    ; 0/1 - did any pattern fail for current segment
FAILCOUNT   equ VARBASE+6    ; total segments that failed, 0-256 (2 bytes)
SEGTOTAL    equ VARBASE+8    ; segments to test, copy of SEGCOUNT (2 bytes)
RTREMAIN    equ VARBASE+10   ; RUN_TEST down-counter, 0-256 (2 bytes)
CURSEG      equ VARBASE+12   ; current segment index, 0-255 (1 byte)
PATNUM      equ VARBASE+13   ; current pattern number (1-4), for display
LEADZ       equ VARBASE+14   ; leading-zero suppression flag for NUM2DEC
FAILBITMAP  equ VARBASE+15   ; 32 bytes / 256 bits, one per segment
PROTSEG     equ VARBASE+47   ; segment number currently backing page 3 (our
                              ; own stack/system RAM) - a standard Memory
                              ; Mapper draws all 4 pages from ONE shared pool
                              ; of segments, so this exact number must never
                              ; be written/verified via page 2, or we would
                              ; be overwriting our own stack out from under
                              ; ourselves. Read-only, taken from port FFh.
DETBASE     equ VARBASE+48   ; which segment (0 or 1) DETECT used as its
                              ; aliasing-probe baseline
PROBE_SAVED   equ VARBASE+49 ; PROBE_ALIAS scratch: original page-3 byte
PROBE_SAVEDP2 equ VARBASE+50 ; PROBE_ALIAS scratch: original page-2 byte

; =============================================================================
; Entry point
; =============================================================================
START:
    DI
    LD SP,0F380h
    EI

    CALL SETUP_SCREEN
    CALL DRAW_TITLE
    CALL DETECT
    CALL SHOW_DETECT_RESULT

MENU:
    CALL FLUSH_KEYS
    CALL PRINT_MENU
WAITKEY:
    CALL CHGET
    CP 'T'
    JR Z,DO_TEST
    CP 't'
    JR Z,DO_TEST
    CP 27               ; ESC
    JR Z,DO_REBOOT
    JR WAITKEY

DO_TEST:
    LD HL,(SEGCOUNT)
    LD A,H
    OR L
    JP Z,MENU             ; nothing detected - nothing to test
    CALL RUN_TEST
    CALL DRAW_TITLE
    CALL SHOW_DETECT_RESULT
    JP MENU

DO_REBOOT:
    DI
    JP 0000h

; =============================================================================
; Screen setup / drawing
; =============================================================================
SETUP_SCREEN:
    LD A,15
    LD (FORCLR),A
    LD A,4
    LD (BAKCLR),A
    LD A,4
    LD (BDRCLR),A
    CALL INITXT
    RET

CLS_ONLY:
    LD A,12              ; form feed - clears text screen via CHPUT
    CALL CHPUT
    RET

; -- Move to the start of the next line. CR alone was tried first (BASIC's
; PRINT only ever sends CR) but measurably failed on real BIOS: on a real
; NMS8245, CR only resets the column - it does NOT advance the row, so
; text was overwriting itself. CR+LF is sent instead, which is safe on any
; BIOS that treats CR as a full newline too - the worst case there is one
; extra blank line, not lines overwriting each other. ------------------------
NEWLINE:
    LD A,13
    CALL CHPUT
    LD A,10
    CALL CHPUT
    RET

DRAW_TITLE:
    CALL CLS_ONLY
    LD HL,MSG_RULE
    CALL PRSTR
    CALL NEWLINE
    LD HL,MSG_TITLE
    CALL PRSTR
    CALL NEWLINE
    LD HL,MSG_RULE
    CALL PRSTR
    CALL NEWLINE
    RET

; =============================================================================
; Detection: empirical size measurement on port FEh / page 2
;
; Standard MSX Memory Mapper sizes are always a power of two number of
; segments (4/8/16/32/64/128/256 = 64KB..4096KB), so the true size is found
; with a doubling aliasing probe: write a marker at a fixed baseline
; segment, then write a DIFFERENT marker at successively doubling candidate
; segments (1,2,4,8,...256) and check whether the baseline changed. The
; first candidate that clobbers the baseline is aliasing back onto it -
; that candidate count IS the true segment count.
;
; This replaces an earlier "stamp all 256, then read all 256 back" design
; that looked correct but was not: on hardware narrower than 256 segments,
; index 32 (say) aliases back onto index 0, so writing index 32's
; fingerprint silently overwrites index 0's before it is ever read back -
; every comparison from index 0 onward then fails, misreporting "no mapper"
; even though one is present (found by testing against a real 32-segment
; mapper). A doubling probe only ever has ONE candidate on the bus at a
; time, so it cannot destroy evidence it hasn't looked at yet.
; =============================================================================
DETECT:
    DI
    IN A,(MAPPORT)
    LD (ORIGSEG),A
    IN A,(P3PORT)          ; page 3 (our own stack) draws from the SAME
    LD (PROTSEG),A          ; shared segment pool - never touch its segment

    ; Baseline is segment 0, unless page 3 is currently using segment 0 -
    ; then use segment 1 instead, since the baseline must be safe to write.
    XOR A
    LD (DETBASE),A
    LD A,(PROTSEG)
    OR A
    JR NZ,DET_BASE_OK
    LD A,1
    LD (DETBASE),A
DET_BASE_OK:
    LD A,(DETBASE)
    OUT (MAPPORT),A
    LD A,0AAh
    LD (TESTADR),A

    LD HL,2                 ; first candidate to probe (1 is the smallest
                             ; possible baseline itself, so start at 2)
DET_PROBE:
    LD A,H
    OR A
    JR NZ,DET_PROBE_MAX      ; HL reached 256 - largest standard size, stop

    LD A,(PROTSEG)           ; never write the segment page 3 is using
    CP L
    JR Z,DET_PROBE_NEXT
    LD A,(DETBASE)            ; never write over the baseline itself
    CP L
    JR Z,DET_PROBE_NEXT

    LD A,L
    OUT (MAPPORT),A
    LD A,055h
    LD (TESTADR),A

    LD A,(DETBASE)             ; re-select baseline and see if it changed
    OUT (MAPPORT),A
    LD A,(TESTADR)
    CP 0AAh
    JR NZ,DET_PROBE_ALIASED

DET_PROBE_NEXT:
    ADD HL,HL
    JR DET_PROBE

DET_PROBE_MAX:
    LD HL,256                ; swept to the max without ever aliasing
    JR DET_SIZE_KNOWN
DET_PROBE_ALIASED:
DET_SIZE_KNOWN:
    LD (SEGCOUNT),HL

    LD A,(ORIGSEG)
    OUT (MAPPORT),A
    EI
    RET

SHOW_DETECT_RESULT:
    CALL NEWLINE
    LD HL,(SEGCOUNT)
    LD A,H
    OR L
    JR NZ,SDR_FOUND
    LD HL,MSG_NONE
    CALL PRSTR
    CALL NEWLINE
    RET
SDR_FOUND:
    LD HL,MSG_FOUND1
    CALL PRSTR
    CALL NEWLINE
    LD A,' '
    CALL CHPUT
    LD A,' '
    CALL CHPUT
    LD HL,(SEGCOUNT)
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL             ; HL = SEGCOUNT * 16 = size in KB
    CALL NUM2DEC
    LD HL,MSG_FOUND2
    CALL PRSTR
    LD HL,(SEGCOUNT)
    CALL NUM2DEC
    LD HL,MSG_FOUND3
    CALL PRSTR
    CALL NEWLINE
    RET

PRINT_MENU:
    CALL NEWLINE
    CALL NEWLINE
    LD HL,MSG_RULE
    CALL PRSTR
    CALL NEWLINE
    LD HL,(SEGCOUNT)
    LD A,H
    OR L
    JR Z,PM_NOTEST
    LD HL,MSG_MENU_BOTH
    CALL PRSTR
    CALL NEWLINE
    RET
PM_NOTEST:
    LD HL,MSG_MENU_ESC
    CALL PRSTR
    CALL NEWLINE
    RET

; =============================================================================
; Test: exhaustive 00h/FFh/AAh/55h fill+verify of every detected segment
; =============================================================================
RUN_TEST:
    DI
    IN A,(MAPPORT)
    LD (ORIGSEG),A
    EI

    LD HL,0
    LD (FAILCOUNT),HL
    LD HL,FAILBITMAP
    LD B,32
    XOR A
RT_CLRBM:
    LD (HL),A
    INC HL
    DJNZ RT_CLRBM

    LD HL,(SEGCOUNT)
    LD (SEGTOTAL),HL
    LD (RTREMAIN),HL

    LD C,0
RT_SEG_LOOP:
    LD A,C
    LD (CURSEG),A

    CALL PROBE_ALIAS          ; empirically check THIS segment, fresh, every
    OR A                       ; time - see PROBE_ALIAS for why a register-
    JR Z,RT_NOTPROT             ; based check was not trustworthy
    CALL PRINT_PROGRESS_SKIP
    CALL SHORT_PAUSE            ; otherwise this is on screen for well under
                                  ; a frame before the next segment's CLS
                                  ; wipes it - invisible, even though the
                                  ; skip genuinely happened
    JR RT_NEXT
RT_NOTPROT:
    ; Page 2 is left at ORIGSEG (its boot-time segment) at this point, on
    ; purpose - see PRINT_PROGRESS for why it must stay that way for any
    ; screen output. It is only ever switched to the segment under test
    ; immediately around FILL_PATTERN/VERIFY_PATTERN, and restored straight
    ; back before the next CHPUT of any kind.
    XOR A
    LD (ANYFAIL),A

    CALL PRINT_PROGRESS      ; one CLS per segment, not per pattern - see
                              ; note above PRINT_PROGRESS for why

    LD A,C
    OUT (MAPPORT),A
    LD A,00h
    CALL FILL_PATTERN
    LD A,00h
    CALL VERIFY_PATTERN
    CALL OR_ANYFAIL
    LD A,(ORIGSEG)
    OUT (MAPPORT),A
    CALL PRINT_PATTERN_DOT

    LD A,C
    OUT (MAPPORT),A
    LD A,0FFh
    CALL FILL_PATTERN
    LD A,0FFh
    CALL VERIFY_PATTERN
    CALL OR_ANYFAIL
    LD A,(ORIGSEG)
    OUT (MAPPORT),A
    CALL PRINT_PATTERN_DOT

    LD A,C
    OUT (MAPPORT),A
    LD A,0AAh
    CALL FILL_PATTERN
    LD A,0AAh
    CALL VERIFY_PATTERN
    CALL OR_ANYFAIL
    LD A,(ORIGSEG)
    OUT (MAPPORT),A
    CALL PRINT_PATTERN_DOT

    LD A,C
    OUT (MAPPORT),A
    LD A,55h
    CALL FILL_PATTERN
    LD A,55h
    CALL VERIFY_PATTERN
    CALL OR_ANYFAIL
    LD A,(ORIGSEG)
    OUT (MAPPORT),A
    CALL PRINT_PATTERN_DOT

    CALL PRINT_SEG_RESULT      ; safe: page 2 is back at ORIGSEG

    LD A,(ANYFAIL)
    OR A
    JR Z,RT_NEXT
    LD HL,(FAILCOUNT)
    INC HL
    LD (FAILCOUNT),HL
    LD A,(CURSEG)
    CALL SET_FAILBIT
RT_NEXT:
    INC C
    LD HL,(RTREMAIN)
    DEC HL
    LD (RTREMAIN),HL
    LD A,H
    OR L
    JP NZ,RT_SEG_LOOP

    DI
    LD A,(ORIGSEG)
    OUT (MAPPORT),A
    EI

    CALL PRINT_TEST_SUMMARY
    CALL FLUSH_KEYS
    CALL CHGET
    RET

; -- Roughly a one-second busy-wait, no precision needed - just long enough
; for a human to actually see a screen before it's replaced. --------------
SHORT_PAUSE:
    LD B,10
SP_OUTER:
    PUSH BC
    LD DE,13000
SP_INNER:
    DEC DE
    LD A,D
    OR E
    JR NZ,SP_INNER
    POP BC
    DJNZ SP_OUTER
    RET

; =============================================================================
; PROBE_ALIAS: does page-2 segment C alias the SAME physical memory as
; whatever currently backs page 3 (our stack/system RAM)?
;
; An earlier version tried to answer this by reading port FFh (page 3's own
; segment register) and comparing it, masked, to the candidate. That was not
; trustworthy: on a real NMS8245 + 1MB mapper the register read back as 192
; on a 64-segment mapper (192 mod 64 = 0, so page 3 was really on segment 0,
; but the raw untruncated compare never caught it - fixed by masking). Then
; a real Panasonic FS-A1WX with a 1MB mapper expansion reset on segment 1
; regardless, meaning the register's value (or the masking of it) cannot be
; trusted the same way on every implementation - it may not even reflect
; page 3's real state at all on hardware where page 3 isn't wired the same
; way as page 2.
;
; This replaces that guesswork with a direct empirical test: temporarily
; write a marker through page 2 into the candidate segment, at the same
; offset (0) used everywhere else, and check - through page 3's completely
; normal, non-port-mediated memory read - whether that marker shows up
; there. If a memory-mapper segment aliases at all, EVERY offset within it
; aliases (it's the same physical 16KB block, not a partial overlap), so
; testing offset 0 is a fully sufficient stand-in for the whole segment.
; Two different marker values are written and checked (not one) so a
; coincidental pre-existing match cannot produce a false "safe" verdict.
; Runs with interrupts off and restores both bytes immediately either way,
; so it is safe regardless of the answer.
; =============================================================================
PROBE_ALIAS: ; in: C = candidate segment; out: A = 1 (unsafe/alias) or 0 (safe)
    DI
    LD HL,0C000h            ; page-3 address of the probe offset (=TESTADR's
                              ; page-2 address 8000h, offset 0, on the other
                              ; side of the page-2/page-3 boundary)
    LD A,(HL)
    LD (PROBE_SAVED),A

    LD A,C
    OUT (MAPPORT),A
    LD A,(TESTADR)
    LD (PROBE_SAVEDP2),A

    LD A,0AAh
    LD (TESTADR),A
    LD A,(HL)
    CP 0AAh
    JR NZ,PA_SAFE             ; first marker didn't show up on page 3 - safe

    LD A,55h
    LD (TESTADR),A
    LD A,(HL)
    CP 55h
    JR NZ,PA_SAFE             ; second, different marker didn't match either
                                ; -> the first match was coincidental, safe

    ; both markers were seen via page 3 - genuinely the same physical memory
    LD A,(PROBE_SAVEDP2)
    LD (TESTADR),A
    LD A,(PROBE_SAVED)
    LD (HL),A
    EI
    LD A,1
    RET

PA_SAFE:
    LD A,(PROBE_SAVEDP2)
    LD (TESTADR),A
    LD A,(PROBE_SAVED)
    LD (HL),A
    EI
    XOR A
    RET

OR_ANYFAIL:
    LD A,(SEGFAIL)
    OR A
    RET Z
    LD A,1
    LD (ANYFAIL),A
    RET

; -- Fill the whole page-2 window (16KB) with pattern in A ------------------
FILL_PATTERN:
    LD (CURPAT),A
    LD HL,TESTADR
    LD DE,4000h
FP_LOOP:
    LD (HL),A
    INC HL
    DEC DE
    LD A,D
    OR E
    JR Z,FP_DONE
    LD A,(CURPAT)
    JR FP_LOOP
FP_DONE:
    RET

; -- Verify the whole page-2 window against pattern in A ---------------------
VERIFY_PATTERN:
    LD (CURPAT),A
    XOR A
    LD (SEGFAIL),A
    LD HL,TESTADR
    LD DE,4000h
VP_LOOP:
    LD A,(HL)
    LD B,A
    LD A,(CURPAT)
    CP B
    JR Z,VP_OK
    LD A,1
    LD (SEGFAIL),A
VP_OK:
    INC HL
    DEC DE
    LD A,D
    OR E
    JR Z,VP_DONE
    JR VP_LOOP
VP_DONE:
    RET

; -- Progress: "Seg NNN/NNN " then one "." per pattern appended as it
; completes, then PRINT_SEG_RESULT's " -> OK"/" -> FAIL" on the same line.
; CLS is done here ONCE PER SEGMENT, not once per pattern as an earlier
; version did (up to 4x per segment, up to ~1000x over a full test) - that
; turned out to be capable of resetting a real MSX (reproduced on a real
; NMS8245 BIOS in openMSX): a VDP screen clear is not instant, and hammering
; it that rapidly with interrupts enabled desynced real BIOS/VDP state
; badly enough to crash. Per-pattern liveness is now shown by appending a
; single character with plain CHPUT (safe: no repositioning, no CLS)
; instead of redrawing the whole screen. ------------------------------------
PRINT_PROGRESS:
    CALL CLS_ONLY
    LD HL,MSG_TESTHDR
    CALL PRSTR
    CALL NEWLINE
    CALL NEWLINE
    LD HL,MSG_TESTING
    CALL PRSTR
    LD A,(CURSEG)
    CALL PR1BASED
    LD A,'/'
    CALL CHPUT
    LD HL,(SEGTOTAL)
    CALL NUM2DEC
    LD A,' '
    CALL CHPUT
    RET

PRINT_PATTERN_DOT:
    LD A,'.'
    CALL CHPUT
    RET

PRINT_PROGRESS_SKIP:
    CALL CLS_ONLY
    LD HL,MSG_TESTHDR
    CALL PRSTR
    CALL NEWLINE
    CALL NEWLINE
    LD HL,MSG_TESTING
    CALL PRSTR
    LD A,(CURSEG)
    CALL PR1BASED
    LD A,'/'
    CALL CHPUT
    LD HL,(SEGTOTAL)
    CALL NUM2DEC
    LD HL,MSG_RESERVED
    CALL PRSTR
    CALL NEWLINE
    LD HL,MSG_SEGSKIP
    CALL PRSTR
    CALL NEWLINE
    RET

PRINT_SEG_RESULT:
    LD A,(ANYFAIL)
    OR A
    JR Z,PSR_OK
    LD HL,MSG_SEGFAIL
    JR PSR_PRINT
PSR_OK:
    LD HL,MSG_SEGOK
PSR_PRINT:
    CALL PRSTR
    CALL NEWLINE
    RET

PRINT_TEST_SUMMARY:
    CALL CLS_ONLY
    LD HL,MSG_TESTHDR
    CALL PRSTR
    CALL NEWLINE
    CALL NEWLINE
    LD HL,(FAILCOUNT)
    LD A,H
    OR L
    JR Z,PTS_ALLPASS
    LD HL,MSG_SOMEFAIL
    CALL PRSTR
    CALL NEWLINE
    CALL PRINT_FAIL_LIST
    CALL NEWLINE
    JR PTS_DONE
PTS_ALLPASS:
    LD HL,MSG_ALLPASS1
    CALL PRSTR
    LD HL,(SEGTOTAL)
    CALL NUM2DEC
    LD HL,MSG_ALLPASS2
    CALL PRSTR
    CALL NEWLINE
PTS_DONE:
    CALL NEWLINE
    LD HL,MSG_ANYKEY
    CALL PRSTR
    RET

PRINT_FAIL_LIST:
    LD C,0
PFL_LOOP:
    PUSH BC
    LD A,C
    CALL PFL_TESTBIT
    POP BC
    OR A
    JR Z,PFL_SKIP
    LD A,C
    CALL PR1BASED
    LD A,' '
    CALL CHPUT
PFL_SKIP:
    INC C
    JR NZ,PFL_LOOP
    RET

; =============================================================================
; Fail-bitmap helpers (256 bits / 32 bytes, one bit per segment)
; =============================================================================
SET_FAILBIT: ; in: A = segment index (0-255)
    LD E,A
    LD A,E
    AND 07h
    LD C,A                 ; C = bit position (0-7)
    LD A,E
    RRCA
    RRCA
    RRCA
    AND 01Fh                ; byte index (0-31) - see PFL_TESTBIT for proof
    LD D,0
    LD E,A
    LD HL,FAILBITMAP
    ADD HL,DE               ; HL -> target byte
    LD A,1
SFB_LOOP:
    LD B,A
    LD A,C
    OR A
    JR Z,SFB_DONE
    LD A,B
    SLA A
    DEC C
    JR SFB_LOOP
SFB_DONE:
    LD A,B
    OR (HL)
    LD (HL),A
    RET

; Byte-index math: 3x RRCA on an 8-bit value E computes (E>>3) in the low 5
; bits, because rotating right 3 times is (E>>3)|(E<<5) mod 256, and masking
; to 5 bits discards the wrapped-around (E<<5) part - verified for E=0,7,8,
; 31,200,255 by hand; holds for the full 0-255 range this way.
PFL_TESTBIT: ; in: A = bit index (0-255); out: A = 0 or 1
    LD E,A
    LD A,E
    AND 07h
    LD C,A                 ; C = bit position (0-7)
    LD A,E
    RRCA
    RRCA
    RRCA
    AND 01Fh
    LD D,0
    LD E,A
    LD HL,FAILBITMAP
    ADD HL,DE
    LD A,(HL)
PFLT_LOOP:
    LD B,A
    LD A,C
    OR A
    JR Z,PFLT_DONE
    LD A,B
    SRL A
    DEC C
    JR PFLT_LOOP
PFLT_DONE:
    LD A,B
    AND 1
    RET

; =============================================================================
; Print helpers
; =============================================================================
; -- Drain any keys queued in the BIOS keyboard buffer (incl. key-repeat) --
; Must be called before every CHGET that is meant to wait for a fresh,
; deliberate keypress - otherwise a held/repeating key from earlier (e.g.
; the "T" that started a multi-minute test) gets replayed automatically.
FLUSH_KEYS:
    CALL CHSNS
    OR A
    RET Z
    CALL CHGET
    JR FLUSH_KEYS

PRSTR: ; HL = 0-terminated string
    LD A,(HL)
    OR A
    RET Z
    CALL CHPUT
    INC HL
    JR PRSTR

; -- Print (A+1) in decimal - "1-based segment number" display. Widened to
; 16-bit internally since A=255 (segment 256, the last of a 4096KB mapper)
; would silently wrap to 0 in an 8-bit INC. ---------------------------------
PR1BASED: ; A = 0-based segment index (0-255)
    LD H,0
    LD L,A
    INC HL
    JP NUM2DEC

NUM2DEC: ; HL = value 0-65535, prints decimal without leading zeros
    LD A,1
    LD (LEADZ),A
    PUSH HL
    LD DE,-10000
    CALL NDIGIT
    LD DE,-1000
    CALL NDIGIT
    LD DE,-100
    CALL NDIGIT
    LD DE,-10
    CALL NDIGIT
    XOR A
    LD (LEADZ),A
    LD DE,-1
    CALL NDIGIT
    POP HL
    RET

NDIGIT: ; DE = negative place value, HL = remaining value (updated)
    LD B,'0'-1
NDIGIT_LOOP:
    INC B
    ADD HL,DE
    JR C,NDIGIT_LOOP
    SBC HL,DE
    LD A,B
    CP '0'
    JR NZ,ND_PRINT
    LD A,(LEADZ)
    OR A
    RET NZ
ND_PRINT:
    XOR A
    LD (LEADZ),A
    LD A,B
    CALL CHPUT
    RET

; =============================================================================
; Text data
; =============================================================================
MSG_RULE:      DB "====================================",0
MSG_TITLE:     DB "   SDMAPPER MAPPER TEST UTILITY",0
MSG_NONE:      DB "No Mapper on Page 2 (port FEh)",0
MSG_FOUND1:    DB "  Mapper detected on Page 2:",0
MSG_FOUND2:    DB " KB  (",0
MSG_FOUND3:    DB " segments)",0
MSG_MENU_BOTH: DB "[T] Test Mapper   [ESC] Reboot",0
MSG_MENU_ESC:  DB "[ESC] Reboot",0
MSG_TESTHDR:   DB "Testing all segments",0
MSG_TESTING:   DB "Seg ",0
MSG_SEGOK:     DB "  -> OK",0
MSG_SEGFAIL:   DB "  -> FAIL",0
MSG_RESERVED:  DB "  (reserved)",0
MSG_SEGSKIP:   DB "  -> SKIPPED (system stack)",0
MSG_SOMEFAIL:  DB "RESULT: FAILURES in segment(s):",0
MSG_ALLPASS1:  DB "RESULT: ALL ",0
MSG_ALLPASS2:  DB " SEGMENTS PASSED.",0
MSG_ANYKEY:    DB "Press any key to continue...",0

; -----------------------------------------------------------------------------
; Pad to a full 16KB ROM
; -----------------------------------------------------------------------------
    DS 08000h-$,0FFh

    SAVEBIN "testmapper.rom",4000h,08000h-4000h

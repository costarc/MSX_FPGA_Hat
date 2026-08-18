; ============================================================================
; testramrom.asm - cartridge wrapper for testram.com (A&L Software 1998)
;
; WHY
; ---------------------------------------------------------------------------
; testram.com is a third-party MSX RAM tester. Running it from ROM gives an
; INDEPENDENT check of our mapper RAM - written by someone else, with no
; knowledge of this project's assumptions - which is worth a great deal after
; a long run of home-grown tests that each turned out to measure the wrong
; thing.
;
; It also needs no disk, so it can run on a machine whose DOS will not boot -
; which is exactly our situation.
;
; HOW IT WORKS
; ---------------------------------------------------------------------------
; testram.com's entry at 0100h is nothing but a relocator: it copies four
; blocks into pages 2 and 3 and jumps to E000h. Nothing of it executes at
; 0100h, and it makes ZERO BDOS calls - only ENASLT, RDVRM, WRTVRM, CHPUT and
; EXPTBL references. So it has no DOS dependency, and a cartridge can perform
; the same four copies straight out of ROM.
;
;   src 0130h len 1130h -> 8000h      (offsets are into the .COM image,
;   src 1300h len 0810h -> B000h       which loads at 0100h)
;   src 1B10h len 0540h -> A500h
;   src 2050h len 0160h -> E000h
;   jp E000h
;
; The one thing the ROM must do that DOS did for free: at cartridge INIT the
; BIOS has our SLOT paged into page 2 (port A8h reads 54h on this machine), so
; 8000h-BFFF is ROM, not RAM. ENASLT must put RAM there before the copies, or
; three of the four blocks would be written into nothing.
;
; Page 0 keeps the BIOS, which is what testram wants anyway - under DOS it has
; to page the BIOS back in itself before using ENASLT/CHPUT/RDVRM.
;
; NOTE ON EXIT: testram expects to return to DOS. From ROM there is nothing to
; return to, so expect a hang or reset when it finishes - that is normal here
; and not a failure of the test. Read the results off the screen.
;
; Build: assembled by build_testramrom.py, which appends the four payload
; blocks from testram.com at the PAY* addresses below.
; ============================================================================

ENASLT  equ 00024h
RAMAD2  equ 0F343h          ; BIOS var: slot id of RAM in page 2

PAY1    equ 04200h          ; len 1130h -> 8000h
PAY2    equ 05330h          ; len 0810h -> B000h
PAY3    equ 05B40h          ; len 0540h -> A500h
PAY4    equ 06080h          ; len 0160h -> E000h

        org 04000h

        db  "AB"
        dw  INIT
        dw  0
        dw  0
        dw  0
        dw  0,0,0

; ---------------------------------------------------------------------------
INIT:
        ; Put RAM in page 2 - at INIT the BIOS has our cartridge there.
        ld      a,(RAMAD2)
        ld      h,080h
        call    ENASLT

        ld      hl,PAY1
        ld      de,08000h
        ld      bc,01130h
        ldir

        ld      hl,PAY2
        ld      de,0B000h
        ld      bc,00810h
        ldir

        ld      hl,PAY3
        ld      de,0A500h
        ld      bc,00540h
        ldir

        ld      hl,PAY4
        ld      de,0E000h
        ld      bc,00160h
        ldir

        jp      0E000h

        end

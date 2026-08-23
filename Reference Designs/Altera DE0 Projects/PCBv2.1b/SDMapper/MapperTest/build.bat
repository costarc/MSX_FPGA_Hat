@echo off
setlocal enabledelayedexpansion
REM ===========================================================================
REM  build.bat - assemble the SDMapper MapperTest diagnostic ROMs
REM
REM  Each ROM is a plain 16KB MSX cartridge image loaded into the MapperTest
REM  region of the Flash (0x040000, 16 slots x 16KB). Select one at runtime
REM  with SW(9)=0, SW(8)=1, SW(3:0) = slot number.
REM
REM  Verified 2026-08-23: the zmac ROMs below rebuild BYTE-IDENTICAL to the
REM  committed .rom files.
REM ===========================================================================

REM ---------------------------------------------------------------------------
REM  TOOL PATHS - edit these to match your machine
REM ---------------------------------------------------------------------------
set "ZMAC=C:\Users\roniv\Dev\zmac\zmac.exe"

REM  sjasmplus is NOT the same tool as sjasm. testmapper.asm needs sjasmplus
REM  (DEVICE / SAVEBIN). The sjasm below is kept for reference only - it was
REM  tried and rejects both directives.
set "SJASMPLUS=sjasmplus.exe"
set "SJASM=C:\Users\roniv\Dev\sdcc-4.0.0\Tools\sjasm42c\sjasm.exe"

REM  pasmo is what maptest.asm's own header names, but zmac assembles it to a
REM  byte-identical ROM, so the build below uses zmac for everything it can.
REM  Kept here in case a source ever needs pasmo specifically.
set "PASMO=C:\Users\roniv\Dev\Z80\pasmo-0.5.4.beta2\pasmo.exe"

REM ---------------------------------------------------------------------------
REM  ROM geometry. The MapperTest slot stride is 16KB; images are padded with
REM  0xFF (erased-Flash value), which is what the committed ROMs use.
REM ---------------------------------------------------------------------------
set "ROMSIZE=16384"
set "PADBYTE=255"

REM  Sources built with zmac. Each assembles to a .cim, then is padded to
REM  ROMSIZE to produce the .rom.
set "ZMAC_SRCS=maptest porttest page0test soaktest soaktest_ei ffffstress"

REM  Built with sjasmplus instead: it uses DEVICE / SAVEBIN and pads itself
REM  (DS 08000h-$,0FFh), so it writes its own .rom and needs no pad step.
REM  NOTE: plain "sjasm" will NOT work - it does not know DEVICE or SAVEBIN.
set "SJASM_SRCS=testmapper"

REM ===========================================================================

echo.
echo Building MapperTest ROMs (%ROMSIZE% bytes each)
echo.

if not exist "%ZMAC%" (
    echo   ERROR: zmac not found at:
    echo            %ZMAC%
    echo          Edit the ZMAC variable at the top of this file.
    exit /b 1
)

set /a FAILED=0

REM ---------------------------------------------------------------------------
REM  zmac sources: assemble, then pad to ROMSIZE
REM ---------------------------------------------------------------------------
for %%S in (%ZMAC_SRCS%) do (
    if not exist "%%S.asm" (
        echo   SKIP  %%S  - %%S.asm not found
    ) else (
        "%ZMAC%" --od . -o "%%S.cim" "%%S.asm" >"%%S.lst" 2>&1
        if exist "%%S.cim" (
            powershell -NoProfile -Command ^
              "$b=[IO.File]::ReadAllBytes('%%S.cim');" ^
              "if ($b.Length -gt %ROMSIZE%) { Write-Host 'TOO BIG'; exit 1 };" ^
              "$o=New-Object byte[] %ROMSIZE%;" ^
              "for ($i=0; $i -lt %ROMSIZE%; $i++) { $o[$i]=%PADBYTE% };" ^
              "[Array]::Copy($b,$o,$b.Length);" ^
              "[IO.File]::WriteAllBytes('%%S.rom',$o)"
            if exist "%%S.rom" (
                echo   OK    %%S.rom
                REM  assembly succeeded - drop the listing. It is kept only
                REM  when something fails, so it is there when it is useful.
                del "%%S.lst" 2>nul
            ) else (
                echo   FAIL  %%S  - padding failed, see %%S.lst
                set /a FAILED+=1
            )
            del "%%S.cim" 2>nul
        ) else (
            echo   FAIL  %%S  - assembly failed, see %%S.lst
            set /a FAILED+=1
        )
    )
)

REM ---------------------------------------------------------------------------
REM  sjasmplus sources: they write their own .rom via SAVEBIN
REM ---------------------------------------------------------------------------
for %%S in (%SJASM_SRCS%) do (
    if not exist "%%S.asm" (
        echo   SKIP  %%S  - %%S.asm not found
    ) else (
        where "%SJASMPLUS%" >nul 2>&1
        if errorlevel 1 (
            echo   SKIP  %%S  - sjasmplus not on PATH, keeping existing %%S.rom
            echo         ^(plain sjasm will not do: no DEVICE / SAVEBIN support^)
        ) else (
            "%SJASMPLUS%" "%%S.asm"
            if exist "%%S.rom" (
                echo   OK    %%S.rom
            ) else (
                echo   FAIL  %%S
                set /a FAILED+=1
            )
        )
    )
)

REM ---------------------------------------------------------------------------
REM  Not rebuildable
REM ---------------------------------------------------------------------------
echo.
echo   NOTE  testramrom.rom / testramrom2.rom are NOT rebuilt here.
echo         testramrom.asm is assembled by build_testramrom.py, which appends
echo         four payload blocks - that script is not in this repository and
echo         is not in git history. testramrom2 has no .asm at all. Both .rom
echo         files are committed; do not delete them, they cannot be recreated.

echo.
if %FAILED%==0 (
    echo Done - no failures.
) else (
    echo Done - %FAILED% failure^(s^).
    exit /b 1
)
endlocal

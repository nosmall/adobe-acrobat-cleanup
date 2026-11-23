@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%Remove-AdobeAcrobatAndLicensing.ps1"

:: Always prefer 64-bit PowerShell even if cmd.exe was launched as 32-bit
set "PS_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" (
    set "PS_EXE=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
)

if not exist "%PS_SCRIPT%" (
    echo [ERROR] Nenalezen skript: "%PS_SCRIPT%"
    pause
    exit /b 1
)

:: Check Administrator privileges (auto-elevate via UAC)
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [INFO] Vybiram opravneni spravce ^(UAC^)...
    "%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b %errorlevel%
)

:menu
:: Fast live status check for menu header
set "IFEO_ON=0"
set "LOCK_ON=0"
set "SVC_FOUND=0"

reg.exe query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\AGSService.exe" /v Debugger /reg:64 >nul 2>&1
if %errorlevel% equ 0 set "IFEO_ON=1"

if defined CommonProgramFiles(x86) (
    dir /a:-d /b "%CommonProgramFiles(x86)%\Adobe\AdobeGCClient" >nul 2>&1
    if not errorlevel 1 set "LOCK_ON=1"
) else (
    dir /a:-d /b "%CommonProgramFiles%\Adobe\AdobeGCClient" >nul 2>&1
    if not errorlevel 1 set "LOCK_ON=1"
)

sc.exe query AGSService >nul 2>&1 && set "SVC_FOUND=1"
sc.exe query AGMService >nul 2>&1 && set "SVC_FOUND=1"
sc.exe query AdobeARMservice >nul 2>&1 && set "SVC_FOUND=1"

set "AGS_BLOCK_LABEL=VYPNUTA"
if "%IFEO_ON%-%LOCK_ON%"=="1-1" set "AGS_BLOCK_LABEL=ZAPNUTA ^(aktivni zamky + IFEO^)"
if "%IFEO_ON%-%LOCK_ON%"=="1-0" set "AGS_BLOCK_LABEL=CASTECNA ^(pouze IFEO^)"
if "%IFEO_ON%-%LOCK_ON%"=="0-1" set "AGS_BLOCK_LABEL=CASTECNA ^(pouze zamky souboru^)"

set "SVC_LABEL=CISTE ^(sluzby Adobe nenalezeny^)"
if "%SVC_FOUND%"=="1" set "SVC_LABEL=AKTIVNI ^(nalezeny sluzby Adobe ke smazani^)"

cls
echo ============================================================================
echo   ODINSTALACE A CISTENI: ADOBE ACROBAT + REFRESH MANAGER + GENUINE SERVICE
echo ============================================================================
echo   Stroj: %COMPUTERNAME%   ^|   Slozka: %SCRIPT_DIR%
echo   Blokace AGS: [%AGS_BLOCK_LABEL%]   ^|   Sluzby: [%SVC_LABEL%]
echo ----------------------------------------------------------------------------
echo.
echo   [S] DETAILNI KONTROLA STAVU ^(-ShowStatus^)
echo       Vypise podrobny stav vsech zamku souboru, IFEO klicu i sluzeb v PC.
echo.
echo   [1] NAHLED BEZE ZMEN ^(Dry-Run / -WhatIf^)
echo       Proskenuje cely PC a vypise vse, co by skript zastavil, odinstaloval
echo       a smazal. V systemu se v tomto rezimu NIC nemeni ani nemaze.
echo.
echo   [2] KOMPLETNI ODINSTALACE A VYCISTENI ^(bez blokace^)
echo       Zastavi sluzby Adobe, odinstaluje Acrobat + Refresh Manager + AppX,
echo       smaze naplanovane ulohy, Adobe Genuine Service, cache aktualizaci,
echo       rozsireni v Chrome/Edge, doplnky Office a zbyle klice v registrech.
echo.
echo   [3] KOMPLETNI ODINSTALACE + TRVALA BLOKACE ADOBE GENUINE SERVICE ^(Doporuceno^)
echo       Provede vse z bodu [2] a navic uzamkne slozky AdobeGCClient/AdobeGCData
echo       a zablokuje spousteni procesu AGS/AGM v registrech ^(IFEO^), aby se
echo       licencni kontrola uz nemohla znovu nainstalovat na pozadi.
echo.
echo   [4] ZRUSIT BLOKACI ADOBE GENUINE SERVICE ^(-UnblockAGSReinstall^)
echo       Odemkne a odstrani zamky vytvorene volbou [3] ^(vhodne, pokud byste
echo       v budoucnu chtel instalovat jiny Adobe SW vyzadujici AGS^).
echo.
echo   [H] NAPOVEDA - Jak nastroj funguje, bezpecnost a reseni problemu
echo   [0] KONEC
echo.
echo ----------------------------------------------------------------------------
set "CHOICE="
set /p "CHOICE=Zadejte volbu [S, 1-4, H, 0]: "

if /i "%CHOICE%"=="0" exit /b 0
if /i "%CHOICE%"=="s" goto run_status
if /i "%CHOICE%"=="1" goto run_whatif
if /i "%CHOICE%"=="2" goto run_clean
if /i "%CHOICE%"=="3" goto run_clean_block
if /i "%CHOICE%"=="4" goto run_unblock
if /i "%CHOICE%"=="h" goto show_help
if /i "%CHOICE%"=="?" goto show_help
if /i "%CHOICE%"=="help" goto show_help

echo.
echo [WARN] Neplatna volba "%CHOICE%". Zadejte S, cislo 1-4, H pro napovedu nebo 0.
pause
goto menu

:show_help
cls
echo ============================================================================
echo   NAPOVEDA - JAK FUNGUJE CISTENI A BLOKACE ADOBE ACROBAT / AGS
echo ============================================================================
echo.
echo 1. PROC NEJDE ADOBE GENUINE SERVICE ODINSTALOVAT BEZNYM ZPUSOBEM?
echo    Odinstalator AdobeCleanUpUtility.exe odmita sluzbu odebrat, dokud bezi
echo    procesy AGSService/AGMService nebo na disku lezi licencni cache ^(SLStore,
echo    SLCache, Adobe PCD^) a sluzba AdobeARMservice ^(Refresh Manager^).
echo.
echo 2. CO PRESNE SKRIPT POSTUPNE DELA ^(7 KROKU^):
echo    Krok 1: Ukonci bezici procesy Acrobat, ARM updater a AGS/AGM.
echo    Krok 2: Zastavi a odstrani sluzby AGSService, AGMService, AdobeARMservice.
echo    Krok 3: Spusti tichou odinstalaci vsech MSI balicku Adobe Acrobat/Reader
echo            a Refresh Manager ^(automaticky najde GUID na danem PC^) + AppX.
echo    Krok 4: Odstrani naplanovane ulohy Adobe v Task Scheduleru.
echo    Krok 5: Odstrani virtualni tiskarnu a ovladac Adobe PDF ^(pokud existuje^).
echo    Krok 6: Vycisti vynucene rozsireni v Chrome/Edge, PDFMaker v Office
echo            a zbyle klice v registrech ^(HKLM, WOW6432Node, HKCU, Classes^).
echo    Krok 7: Smaze zbyle soubory a giga-bajtove cache aktualizaci v ProgramData,
echo            Program Files, Common Files ^(32bit i 64bit^) a profilech uzivatelu.
echo            Zamcene knihovny ^(napr. v explorer.exe^) naplanuje ke smazani
echo            pri pristim restartu Windows.
echo.
echo 3. BEZPECNOST NA DRUHEM PC ^(OCHRANA JINYCH APLIKACI ADOBE^):
echo    Skript pred spustenim zkontroluje, zda na PC neni nainstalovan jiny SW
echo    od Adobe ^(napr. Photoshop, Lightroom, Creative Cloud^). Pokud ano, vypise
echo    varovani a automaticky ZACHOVA sdilene licencni slozky ^(SLStore, NGL,
echo    OOBE^), aby neporusil jejich prihlaseni. Cisti vzdy jen Acrobat/ARM/AGS.
echo    Slozky jinych vyrobcu ^(napr. Acronis^) nikdy nemaze.
echo.
echo 4. JAK FUNGUJE BLOKACE PRISTI INSTALACE ^(VOLBA [3]^):
echo    - V Common Files ^(32bit i 64bit^) vytvori misto slozek AdobeGCClient a
echo      AdobeGCData zamcene soubory s odeprenym zapisem a smazanim ^(icacls^).
echo      Instalator tak na tomto miste nemuze slozku znovu vytvorit.
echo    - V registru ^(Image File Execution Options^) presmeruje binarky AGS/AGM
echo      na necinny systemovy stub ^(systray.exe^), takze se nemohou spustit.
echo    - Kdykoliv vratne volbou [4].
echo.
echo 5. LOGY A PREHLEDY:
echo    Kazdy ostry beh uklada detailni log a CSV prehled vsech smazanych polozek
echo    do podslozky: "%SCRIPT_DIR%logs\"
echo.
echo ============================================================================
pause
goto menu

:run_status
cls
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -ShowStatus
echo.
pause
goto menu

:run_whatif
cls
echo [INFO] Spoustim bezpecny nahled ^(-WhatIf^). Zadne soubory ani klice nebudou smazany...
echo.
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -BlockAGSReinstall -WhatIf
goto done

:run_clean
cls
echo [INFO] Spoustim kompletni odinstalaci a cisteni ^(bez blokace AGS^)...
echo.
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Force -AutoExportCsv
goto done

:run_clean_block
cls
echo [INFO] Spoustim kompletni odinstalaci, cisteni a blokaci Adobe Genuine Service...
echo.
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -BlockAGSReinstall -Force -AutoExportCsv
goto done

:run_unblock
cls
echo [INFO] Odebiram blokaci Adobe Genuine Service...
echo.
"%PS_EXE%" -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -UnblockAGSReinstall -Force -AutoExportCsv
goto done

:done
set "EXIT_CODE=%errorlevel%"
echo.
echo ============================================================================
if "%EXIT_CODE%"=="0" (
    echo [OK] Dokonceno uspesne ^(ExitCode = 0^).
) else (
    echo [WARN] Skript skoncil s kodem %EXIT_CODE%. Zkontrolujte vypis nebo log v logs\.
)
echo ============================================================================
echo.
pause
goto menu

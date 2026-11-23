# adobe-acrobat-cleanup

> Stručné projektové instrukce pro AI agenty a IDE (Antigravity, Kilo Code, DeepSeek Harness, Gemini CLI).

## Přehled a technologie
- **Účel:** Přenositelná kompletní odinstalace a dočištění Adobe Acrobat (DC / 2020 / Reader), Adobe Refresh Manager (ARM) a Adobe Genuine Service (AGS / AGM) na Windows 10/11, včetně kontroly stavu a vratné blokace opětovné instalace AGS.
- **Stack:** Windows PowerShell 5.1+ / PowerShell 7+, Windows Batch (`cmd.exe`), standardní systémové nástroje Windows (`msiexec`, `sc.exe`, `icacls`, `takeown`, `attrib`, `reg.exe`). Žádné externí závislosti ani moduly.
- **Typ workspace:** Single Project

## Klíčové příkazy
- **Interaktivní spuštění (UAC menu):** `.\run.cmd`
- **Kontrola stavu (read-only):** `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Remove-AdobeAcrobatAndLicensing.ps1 -ShowStatus`
- **Bezpečný náhled (Dry-Run):** `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Remove-AdobeAcrobatAndLicensing.ps1 -BlockAGSReinstall -WhatIf`
- **Ostré vyčištění + blokace AGS:** `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Remove-AdobeAcrobatAndLicensing.ps1 -BlockAGSReinstall -Force -AutoExportCsv`
- **Kontrola syntaxe (AST parser):** `[System.Management.Automation.Language.Parser]::ParseFile('.\Remove-AdobeAcrobatAndLicensing.ps1', [ref]$null, [ref]$err); $err`
- **Public-Ready audit:** `python "$env:USERPROFILE\.gemini\config\skills\public-ready-audit\scripts\audit_repo.py" .`

## Struktura a konfigurace
- `run.cmd` – UAC spouštěč s 64bit PowerShell preferencí, živým stavem blokace v hlavičce, menu voleb `[S, 1-4, H, 0]` a vestavěnou nápovědou.
- `Remove-AdobeAcrobatAndLicensing.ps1` – hlavní skript s podporou `[CmdletBinding(SupportsShouldProcess = $true)]`, strukturovaným logováním, rotací logů a CSV exportem.
- `config.example.psd1` – volitelná šablona výchozích přepínačů (lokální hodnoty ukládat pouze do ne-verzovaného `config.psd1`).
- `README.md` (EN) & `README.cs.md` (CZ) – dvojjazyčná dokumentace s Disclaimerem; `LICENSE` – MIT License.
- `logs/` – ne-verzovaná složka s logy (`cleanup_*.log`) a CSV reporty (`report_*.csv`, `unblock_*.csv`).

## Projektová pravidla a omezení
- **Windows PowerShell 5.1 kompatibilita + `Set-StrictMode -Version Latest`:** Nepoužívat syntaxi výhradně z PS 7+ (`? :`, `??`). Každý dotaz, na kterém se volá `.Count`, obalit do `@(...)`.
- **Čisté ASCII v kódu i výstupech:** `Remove-AdobeAcrobatAndLicensing.ps1`, `run.cmd` a `config.example.psd1` musí mít `0` non-ASCII bajtů (žádná diakritika), aby fungovaly v CP852 / CP1250 / UTF-8 na jakýchkoliv Windows.
- **Jazykově nezávislé ACL a cesty:** Používat výhradně SIDy (`*S-1-5-32-544`, `*S-1-5-18`, `*S-1-1-0`) a dynamické systémové proměnné/profily – nikdy nehardcodovat lokální uživatelské jméno ani jednotlivá MSI GUID.
- **Ochrana jiných produktů:** Nikdy nemazat složky třetích stran (např. `Acronis`) a při detekci jiných produktů Adobe (Photoshop, Lightroom apod.) zachovat sdílené licenční složky (`SLStore`, `NGL`, `OOBE`), pokud není zadáno `-ForceSharedLicensingCleanup`.
- **Public-Ready hygiena:** Neposílat citlivé údaje, reálné cesty uživatelů, logy ani `config.psd1` do verzovaných souborů; při změně přepínačů aktualizovat `config.example.psd1`, `README.md` a tento soubor.

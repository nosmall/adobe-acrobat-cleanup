# Adobe Acrobat, Refresh Manager & Genuine Service Cleanup

**Language:** English | [Čeština (README.cs.md)](README.cs.md)

A portable Windows 10/11 cleanup toolkit for complete uninstallation and leftover removal of **Adobe Acrobat (DC / 2020 / Reader)**, **Adobe Refresh Manager (ARM)**, and **Adobe Genuine Service (AGS / AGM)**, including live status inspection and an optional reversible reinstallation lock for AGS.

> [!IMPORTANT]
> **Disclaimer:** This is an unofficial, independent system maintenance utility and is **not affiliated with, endorsed by, or associated with Adobe Inc.** All trademarks belong to their respective owners.
>
> This tool is intended **solely for clean uninstallation and removal of leftover background services, updater caches, and orphaned components** on machines where the user no longer wishes to have Adobe Acrobat or its background services installed. It is **not** intended for bypassing software licensing or enabling unlicensed software.
>
> **Use at your own risk:** This script modifies Windows services, registry keys, and system folders with Administrator privileges. Always run **Preview / Dry-Run (`-WhatIf`)** first and back up important data before making system changes. Provided **"AS IS"** without warranty of any kind under the [MIT License](LICENSE).

---

## Project Contents
| File / Folder | Description |
|---|---|
| `run.cmd` | Interactive Windows launcher with automatic UAC elevation, 64-bit PowerShell preference, live status header, menu descriptions, and built-in help (`[H]`). *(Console UI is currently in Czech ASCII.)* |
| `Remove-AdobeAcrobatAndLicensing.ps1` | Main portable PowerShell script (compatible with Windows PowerShell 5.1+ and PowerShell 7+, zero external dependencies). |
| `config.example.psd1` | Optional configuration template for default flags (copy to untracked `config.psd1` to customize). |
| `LICENSE` | MIT License (warranty disclaimer and liability limitation). |
| `README.cs.md` | Complete documentation in Czech. |
| `AGENTS.md` | Repository maintenance guidelines and verification commands. |
| `logs/` | Auto-created, rotated log directory (`cleanup_*.log`, keeps latest 10 runs) and CSV reports (`report_*.csv`, `unblock_*.csv`). |

## Quick Start (Windows 10 / 11)
1. Download or clone the `adobe-acrobat-cleanup` folder to the target Windows machine.
2. Close Google Chrome, Microsoft Edge, and Microsoft Office applications so browser extensions and add-ins are not locked.
3. Run `run.cmd` (approves UAC elevation automatically) **or** invoke the PowerShell script directly from an elevated PowerShell console.
4. In `run.cmd`, the header immediately displays the live status of AGS blocking and Adobe services. Available options:
   - `[S]` **Detailed Status (`-ShowStatus`)** – read-only inspection of all 4 filesystem path locks, 7 IFEO registry blocks, and any remaining Adobe Acrobat/ARM/AGS processes, services, tasks, or packages.
   - `[1]` **Dry-Run Preview (`-WhatIf`)** – lists everything detected without deleting or modifying anything.
   - `[2]` **Full Uninstall & Cleanup** – removes Acrobat, Refresh Manager, Adobe Genuine Service, caches, and leftovers.
   - `[3]` **Full Uninstall, Cleanup & Reversible AGS Lock** *(recommended)* – runs `[2]` and applies the two-layer AGS prevention lock.
   - `[4]` **Remove AGS Lock (`-UnblockAGSReinstall`)** – cleanly reverses all locks created by `[3]`.
   - `[H]` **Built-in Help** – step-by-step explanation inside the console.

## What the Script Removes (7 Steps)
1. **Processes:** Stops running Acrobat, ARM updater, and AGS/AGM processes (`AGSService`, `AGMService`, `AdobeGCClient`, `armsvc`, `Acrobat`, `AcroCEF`, `AcroTray`, etc.).
2. **Windows Services:** Stops and deletes `AGSService`, `AGMService`, `AdobeARMservice`, and `AdobeUpdateService`.
3. **MSI & AppX Packages:** Dynamically discovers MSI `{GUID}` entries for `Adobe Acrobat*`, `Adobe Reader*`, and `Adobe Refresh Manager*`, runs silent uninstallation (`msiexec /x ... /qn /norestart`), and removes related AppX and Provisioned AppX packages (`AdobeAcrobatDCCoreApp`, etc.).
4. **Scheduled Tasks:** Unregisters `Adobe Acrobat*`, `AdobeGC*`, and `Adobe-Genuine*` tasks.
5. **Printers & Drivers:** Removes `Adobe PDF*` virtual printer and printer driver if present.
6. **Browser Extensions, Office Add-ins & Registry:** Removes forced Acrobat Web2PDF extension entries in Chrome/Edge (`efaidnbmnnnibpcajpcglclefindmkaj`, `elhekieabhbkpmcefcoobjddigjcaadp`), orphaned `PDFMaker.OfficeAddin` Office registry keys, Startup `Run`/`RunOnce` keys, orphaned `Uninstall` entries, `SOFTWARE\Adobe` subkeys (`HKLM`, `WOW6432Node`, `HKCU`), Acrobat ProgIDs, and `.pdf\OpenWithProgids` entries.
7. **Filesystem & Update Caches:** Removes leftover folders across 64-bit and 32-bit `Program Files`, `Common Files`, `ProgramData` (including multi-gigabyte `.msp` update caches), `*Acrobat*.lnk` shortcuts, all Windows user profiles, and Adobe temp logs. Locked shell-extension DLLs (e.g. held by `explorer.exe`) are automatically scheduled for deletion on next reboot via `PendingFileRenameOperations`.

## How Optional AGS Prevention Works (`-BlockAGSReinstall`)
Both layers are cleanly reversible at any time via `-UnblockAGSReinstall` (menu option `[4]`):
1. **Filesystem Path Lock (`Common Files` x86 & x64):** Creates hidden/system 0-byte placeholder files at `AdobeGCClient` and `AdobeGCData` with inheritance removed and `Deny (W,D)` for `Everyone` (`*S-1-1-0`), preventing installers from recreating those directories.
2. **IFEO Execution Redirect:** Registers `AGSService.exe`, `AGMService.exe`, `AdobeGCClient.exe`, `agcinvokerutility.exe`, `AdobeCleanUpUtility.exe`, `gccustomhook.exe`, and `AdobeGenuineValidator.exe` under `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options` with `Debugger = %SystemRoot%\System32\systray.exe`.

## Safety & Multi-Machine Portability
- **Protects Other Adobe Products:** Before deleting shared licensing stores (`SLStore`, `SLCache`, `Adobe PCD`, `NGL`, `OOBE`), the script checks whether other Adobe applications (such as Photoshop, Lightroom, or Creative Cloud) are installed. If detected, shared stores are preserved automatically unless `-ForceSharedLicensingCleanup` is explicitly passed.
- **Safe for Chrome & Built-in PDF Viewing:** Never touches Chrome bookmarks, passwords, cookies, history, sessions, or Chrome's built-in `ChromePDF` viewer. (If Chrome Sync is enabled for extensions, remove any synced extension once via `chrome://extensions`.)
- **Locale & Architecture Independent:** Uses universal Windows SIDs (`*S-1-5-32-544`, `*S-1-5-18`, `*S-1-1-0`), dynamic 64-bit/32-bit environment paths, Windows `ProfileList` enumeration, and pure ASCII console/log output.

## PowerShell Parameters
| Parameter | Description |
|---|---|
| `-ShowStatus` | Displays detailed live status of AGS locks (4 paths + 7 IFEO keys) and remaining Adobe items (read-only). |
| `-WhatIf` | Dry-run preview of all planned actions without modifying the system. |
| `-BlockAGSReinstall` | Applies the two-layer AGS prevention lock after cleanup. |
| `-UnblockAGSReinstall` | Unlocks and removes path locks and IFEO registry entries created by `-BlockAGSReinstall`. |
| `-Force` | Suppresses interactive confirmation prompts (`$ConfirmPreference = 'None'`). |
| `-AutoExportCsv` | Automatically writes a timestamped CSV report (`logs\report_YYYYMMDD_HHmmss.csv`). |
| `-ExportCsv <path>` | Exports processed items to a custom CSV path. |
| `-KeepBrowserExtensions` | Skips removal of Chrome/Edge Acrobat extension entries and folders. |
| `-KeepOfficeAddins` | Skips removal of `PDFMaker.OfficeAddin` Office registry keys. |
| `-ForceSharedLicensingCleanup` | Forces cleanup of shared Adobe licensing folders even when other Adobe apps are detected. |
| `-ConfigPath <path>` | Loads default switch overrides from an external `.psd1` file (default `.\config.psd1`). |
| `-LogDir <path>` | Custom directory for log files (default `.\logs`). |

## Direct PowerShell Usage (Run as Administrator)
```powershell
# Check current AGS lock status and system cleanliness (read-only)
.\Remove-AdobeAcrobatAndLicensing.ps1 -ShowStatus

# Safe dry-run preview (no changes made)
.\Remove-AdobeAcrobatAndLicensing.ps1 -BlockAGSReinstall -WhatIf

# Full cleanup + reversible AGS lock + CSV report
.\Remove-AdobeAcrobatAndLicensing.ps1 -BlockAGSReinstall -Force -AutoExportCsv

# Remove AGS lock
.\Remove-AdobeAcrobatAndLicensing.ps1 -UnblockAGSReinstall -Force -AutoExportCsv
```

## Exit Codes & Logging
- `0` – Completed without errors.
- `1` – Missing Administrator privileges, invalid parameter combination, or partial failure (see `logs\cleanup_*.log`).

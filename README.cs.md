# Adobe Acrobat, Refresh Manager & Genuine Service Cleanup

**Jazyk:** [English (README.md)](README.md) | Čeština

Přenositelný nástroj pro kompletní odinstalaci a dočištění **Adobe Acrobat (DC / 2020 / Reader)**, **Adobe Refresh Manager (ARM)** a **Adobe Genuine Service (AGS / AGM)** na Windows 10/11, včetně kontroly aktuálního stavu a volitelné vratné blokace opětovné instalace Adobe Genuine Service.

> [!IMPORTANT]
> **Upozornění (Disclaimer):** Toto je neoficiální, nezávislý správní skript, který **není nijak spojen, podporován ani zaštítěn společností Adobe Inc.** Veškeré ochranné známky náleží jejich příslušným vlastníkům.
>
> Nástroj je určen **výhradně pro čistou odinstalaci a odstranění zbytkových služeb, aktualizačních cache a osiřelých součástí** na počítačích, kde uživatel již Adobe Acrobat ani jeho doprovodné služby nechce používat. **Není určen** k obcházení softwarového licencování ani k provozování nelicencovaného softwaru.
>
> **Použití na vlastní odpovědnost:** Skript pod oprávněním správce upravuje služby Windows, registr a systémové složky. Před ostrým spuštěním vždy nejprve použijte **náhled beze změn (`-WhatIf`)** a mějte zálohovaná důležitá data. Software je poskytován **„TAK, JAK JE“ („AS IS“)** bez jakékoli záruky podle licence [MIT License](LICENSE).

---

## Obsah projektu
| Soubor / Složka | Popis |
|---|---|
| `run.cmd` | Interaktivní spouštěč s automatickým vyžádáním práv správce (UAC), vynucením 64bitového PowerShellu, živým ukazatelem stavu v hlavičce, popisky voleb a vestavěnou nápovědou (`[H]`). |
| `Remove-AdobeAcrobatAndLicensing.ps1` | Hlavní PowerShell skript (kompatibilní s Windows PowerShell 5.1+ i PowerShell 7+, bez externích závislostí). |
| `config.example.psd1` | Volitelná šablona výchozích voleb (pro vlastní trvalé předvolby zkopírujte na ne-verzovaný `config.psd1`). |
| `LICENSE` | Licence MIT (zřeknutí se záruky a omezení odpovědnosti). |
| `README.md` | Anglická verze dokumentace. |
| `AGENTS.md` | Projektová pravidla a klíčové příkazy pro údržbu repozitáře. |
| `logs/` | Automaticky vytvářená a rotovaná složka logů (`cleanup_*.log`, uchovává se posledních 10 běhů) a CSV přehledů (`report_*.csv`, `unblock_*.csv`). |

## Rychlé spuštění (na libovolném PC / notebooku s Windows)
1. Zkopírujte nebo naklonujte celou složku `adobe-acrobat-cleanup` na cílový počítač.
2. Zavřete Google Chrome, Microsoft Edge a aplikace Microsoft Office (aby nedržely zámky na doplňcích).
3. Spusťte `run.cmd` a potvrďte UAC výzvu správce.
4. V hlavičce menu okamžitě uvidíte aktuální stav blokace AGS i služeb Adobe a můžete zvolit:
   - `[S]` **Detailní kontrola stavu (`-ShowStatus`)** – vypíše stav všech 4 zámků cest, 7 IFEO klíčů v registru i počty případných procesů, služeb, úloh a balíčků v PC (nic nemění).
   - `[1]` **Náhled beze změn (`-WhatIf`)** – bezpečně vypíše vše, co na daném PC našel, aniž by cokoliv smazal.
   - `[2]` **Kompletní odinstalace a vyčištění** – odstraní Acrobat, Refresh Manager, Adobe Genuine Service a všechny zbytky.
   - `[3]` **Kompletní odinstalace + trvalá blokace AGS** *(doporučeno)* – provede vyčištění a uzamkne cesty i binárky AGS proti opětovnému nainstalování.
   - `[4]` **Zrušit blokaci AGS** – odemkne cesty a odebere IFEO blokaci v registrech.
   - `[H]` **Nápověda** – podrobné vysvětlení všech kroků přímo v okně konzole.

## Co přesně skript provádí (7 kroků)
1. **Procesy:** Ukončí běžící procesy Acrobat, ARM updater a AGS/AGM (`AGSService`, `AGMService`, `AdobeGCClient`, `armsvc`, `Acrobat`, `AcroCEF`, `AcroTray` aj.).
2. **Služby Windows:** Zastaví a smaže služby `AGSService`, `AGMService`, `AdobeARMservice` a `AdobeUpdateService`.
3. **MSI a AppX balíčky:** Dynamicky vyhledá všechna MSI `{GUID}` pro `Adobe Acrobat*`, `Adobe Reader*` a `Adobe Refresh Manager*`, provede tichou odinstalaci (`msiexec /x ... /qn /norestart`) a odebere UWP/AppX i Provisioned balíčky (`AdobeAcrobatDCCoreApp` aj.).
4. **Plánovač úloh:** Odstraní úlohy `Adobe Acrobat*`, `AdobeGC*` a `Adobe-Genuine*`.
5. **Tiskárny:** Odebere virtuální tiskárnu a ovladač `Adobe PDF*`, pokud existují.
6. **Prohlížeče, Office a registry:** Odebere vynucené rozšíření Acrobat Web2PDF v Chrome/Edge (`efaidnbmnnnibpcajpcglclefindmkaj`, `elhekieabhbkpmcefcoobjddigjcaadp`), osiřelé Office doplňky `PDFMaker.OfficeAddin`, klíče po spuštění (`Run`/`RunOnce`), zbytky v `Uninstall`, větve `SOFTWARE\Adobe` (`HKLM`, `WOW6432Node`, `HKCU`), ProgID třídy a `OpenWithProgids` u `.pdf`.
7. **Soubory a cache:** Vyčistí zbývající složky Acrobat/ARM/AGS v 64bit i 32bit `Program Files`, `Common Files`, `ProgramData` (včetně GB cache aktualizací `.msp`), zástupce `*Acrobat*.lnk`, profily všech uživatelů i logy v `Temp`. Zamčené soubory (např. knihovny držené procesem `explorer.exe`) automaticky naplánuje ke smazání při příštím restartu Windows (`PendingFileRenameOperations`).

## Jak funguje blokace opětovné instalace AGS (`-BlockAGSReinstall`)
Blokace je dvouvrstvá a kdykoliv plně vratná přepínačem `-UnblockAGSReinstall` (volba `[4]`):
1. **Zámek cest (`Common Files` x86 i x64):** Na místech `AdobeGCClient` a `AdobeGCData` vytvoří skryté/systémové 0bajtové soubory stejného názvu s odebranou dědičností a `Deny (W,D)` pro `Everyone` (`*S-1-1-0`). Instalátor tak na těchto cestách nemůže složky znovu vytvořit.
2. **IFEO blokace spuštění v registru:** Pod `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\` přesměruje spustitelné soubory `AGSService.exe`, `AGMService.exe`, `AdobeGCClient.exe`, `agcinvokerutility.exe`, `AdobeCleanUpUtility.exe`, `gccustomhook.exe` a `AdobeGenuineValidator.exe` (`Debugger = %SystemRoot%\System32\systray.exe`), takže se nemohou spustit ani z jiného umístění.

## Bezpečnost a přenositelnost na další počítače
- **Ochrana jiných aplikací Adobe:** Před čištěním kontroluje přítomnost jiných produktů Adobe (Photoshop, Lightroom, Creative Cloud apod.). Pokud je najde, automaticky zachová sdílené licenční složky (`SLStore`, `SLCache`, `Adobe PCD`, `NGL`, `OOBE`) a vyčistí jen Acrobat, ARM a AGS.
- **Bezpečnost pro Chrome a PDF:** Nesahá na záložky, hesla, cookies, historii ani vestavěný prohlížeč `ChromePDF` v Google Chrome. Pokud má uživatel zapnutou synchronizaci rozšíření přes Google účet, stačí případně obnovené rozšíření jedním klikem odebrat v `chrome://extensions`.
- **Jazyková a profilová nezávislost:** Využívá univerzální SIDy (`*S-1-5-32-544`, `*S-1-5-18`, `*S-1-1-0`), dynamické systémové cesty (x64/x86) a registr `ProfileList`. Výstupy do konzole i logy jsou v čistém ASCII (odolnost proti kódování CP852/CP1250/UTF-8).

## Parametry PowerShell skriptu
| Parametr | Význam |
|---|---|
| `-ShowStatus` | Vypíše detailní stav blokace AGS (4 zámky + 7 IFEO) a zbytků v PC (read-only). |
| `-WhatIf` | Bezpečný náhled všech akcí bez provedení jakýchkoli změn. |
| `-BlockAGSReinstall` | Po vyčištění aktivuje dvouvrstvou blokaci opětovné instalace AGS. |
| `-UnblockAGSReinstall` | Odemkne a odstraní zámky i IFEO klíče vytvořené blokací. |
| `-Force` | Potlačí interaktivní potvrzovací dotazy (`$ConfirmPreference = 'None'`). |
| `-AutoExportCsv` | Automaticky vygeneruje `logs\report_YYYYMMDD_HHmmss.csv` (resp. `unblock_*.csv`). |
| `-ExportCsv <cesta>` | Uloží CSV report zpracovaných položek na vlastní cestu. |
| `-KeepBrowserExtensions` | Přeskočí čištění rozšíření v Chrome/Edge. |
| `-KeepOfficeAddins` | Přeskočí odstranění registrů `PDFMaker.OfficeAddin` v Office. |
| `-ForceSharedLicensingCleanup` | Vynutí smazání sdílených licenčních složek i při detekci jiných aplikací Adobe. |
| `-ConfigPath <cesta>` | Načte výchozí přepínače z externího `.psd1` souboru (výchozí `.\config.psd1`). |
| `-LogDir <cesta>` | Vlastní adresář pro logy (výchozí `.\logs`). |

## Přímé spuštění z PowerShellu (jako Správce)
```powershell
# Kontrola aktuálního stavu blokace a čistoty systému
.\Remove-AdobeAcrobatAndLicensing.ps1 -ShowStatus

# Bezpečný náhled (nic nemaže)
.\Remove-AdobeAcrobatAndLicensing.ps1 -BlockAGSReinstall -WhatIf

# Kompletní vyčištění + blokace budoucí instalace AGS + CSV report
.\Remove-AdobeAcrobatAndLicensing.ps1 -BlockAGSReinstall -Force -AutoExportCsv

# Odblokování AGS
.\Remove-AdobeAcrobatAndLicensing.ps1 -UnblockAGSReinstall -Force -AutoExportCsv
```

## Návratové kódy a logování
- `0` – skript proběhl bez chyb.
- `1` – chybějící oprávnění správce, neplatná kombinace parametrů nebo dílčí chyba při mazání (detaily v `logs\cleanup_*.log`).

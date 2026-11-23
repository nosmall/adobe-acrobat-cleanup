<#
.SYNOPSIS
    Prenositelny odinstalacni a cistici nastroj pro Adobe Acrobat (DC/2020/Reader),
    Adobe Refresh Manager (ARM) a Adobe Genuine Service (AGS/AGM) s volitelnou blokaci.

.DESCRIPTION
    Kompatibilni s Windows 10/11 (Windows PowerShell 5.1+ i PowerShell 7+).
    - Dynamicky rozpozna 64bit/32bit Program Files, Common Files, ProgramData a profily uzivatelu.
    - Detekuje jine produkty Adobe (napr. Photoshop, Lightroom) a automaticky chrani sdilene licence.
    - Zastavi procesy a sluzby, odinstaluje MSI/AppX balicky, odstrani naplanovane ulohy,
      zastupce, tiskarny, rozsireni prohlizecu, Office doplnky, registry a cache aktualizaci.
    - Zamcene soubory naplanuje ke smazani pri pristim restartu Windows.
    - Podporuje -WhatIf / -Confirm, volitelny config.psd1, CSV export a vratnou blokaci AGS.

.PARAMETER BlockAGSReinstall
    Po vycisteni vytvori zamcene soubory AdobeGCClient / AdobeGCData (x86 i x64)
    a nastavi IFEO blokaci spousteni pro procesy AGS/AGM v registrech.

.PARAMETER UnblockAGSReinstall
    Odebere zamky souboru a IFEO blokaci vytvorenou parametrem -BlockAGSReinstall.

.PARAMETER ShowStatus
    Pouze zkontroluje a prehledne vypise aktualni stav blokace AGS (zamky souboru + IFEO)
    i pripadne zbytky Adobe Acrobat / ARM / AGS v systemu (nic nemeni).

.PARAMETER ForceSharedLicensingCleanup
    Vynuti smazani sdilenych licencnich slozek (SLStore, SLCache, NGL, OOBE) i kdyz
    jsou na PC detekovany jine aplikace Adobe.

.PARAMETER KeepBrowserExtensions
    Preskoci odstraneni rozsireni Adobe Acrobat v Chrome a Edge.

.PARAMETER KeepOfficeAddins
    Preskoci odstraneni klicu doplnku PDFMaker pro Microsoft Office.

.PARAMETER ConfigPath
    Volitelna cesta ke konfiguracnimu souboru (config.psd1).

.PARAMETER LogDir
    Slozka pro ukladani logu (uchovava se poslednich 10 souboru).

.PARAMETER ExportCsv
    Volitelna cesta pro export CSV reportu vsech zpracovanych polozek.

.PARAMETER Force
    Potlaci interaktivni vyzvy k potvrzeni (nastavi ConfirmPreference = None).
    Vhodne pro davkove spousteni z run.cmd (-File rezim).

.PARAMETER AutoExportCsv
    Automaticky ulozi CSV prehled zpracovanych polozek do slozky LogDir.

.EXAMPLE
    .\Remove-AdobeAcrobatAndLicensing.ps1 -WhatIf

.EXAMPLE
    .\Remove-AdobeAcrobatAndLicensing.ps1 -BlockAGSReinstall -Force -AutoExportCsv
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [switch]$BlockAGSReinstall,
    [switch]$UnblockAGSReinstall,
    [switch]$ShowStatus,
    [switch]$ForceSharedLicensingCleanup,
    [switch]$KeepBrowserExtensions,
    [switch]$KeepOfficeAddins,
    [switch]$Force,
    [switch]$AutoExportCsv,
    [string]$ConfigPath,
    [string]$LogDir,
    [string]$ExportCsv
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'
if ($Force) {
    $ConfirmPreference = 'None'
}

# --- Resolve base paths portably (handles both 64-bit and 32-bit PowerShell hosts) ---
$script:BaseDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $defaultCfg = Join-Path $script:BaseDir 'config.psd1'
    if (Test-Path -LiteralPath $defaultCfg) {
        $ConfigPath = $defaultCfg
    }
}

if (-not [string]::IsNullOrWhiteSpace($ConfigPath) -and (Test-Path -LiteralPath $ConfigPath)) {
    try {
        $cfg = Import-PowerShellDataFile -LiteralPath $ConfigPath -ErrorAction Stop
        if (-not $PSBoundParameters.ContainsKey('BlockAGSReinstall') -and $cfg.ContainsKey('BlockAGSReinstall')) {
            $BlockAGSReinstall = [bool]$cfg['BlockAGSReinstall']
        }
        if (-not $PSBoundParameters.ContainsKey('KeepBrowserExtensions') -and $cfg.ContainsKey('KeepBrowserExtensions')) {
            $KeepBrowserExtensions = [bool]$cfg['KeepBrowserExtensions']
        }
        if (-not $PSBoundParameters.ContainsKey('KeepOfficeAddins') -and $cfg.ContainsKey('KeepOfficeAddins')) {
            $KeepOfficeAddins = [bool]$cfg['KeepOfficeAddins']
        }
        if (-not $PSBoundParameters.ContainsKey('ForceSharedLicensingCleanup') -and $cfg.ContainsKey('ForceSharedLicensingCleanup')) {
            $ForceSharedLicensingCleanup = [bool]$cfg['ForceSharedLicensingCleanup']
        }
        if (-not $PSBoundParameters.ContainsKey('LogDir') -and $cfg.ContainsKey('LogDir') -and -not [string]::IsNullOrWhiteSpace($cfg['LogDir'])) {
            $LogDir = [string]$cfg['LogDir']
        }
    } catch {
        Write-Warning ("Nepodarilo se nacist konfiguracni soubor {0}: {1}" -f $ConfigPath, $_.Exception.Message)
    }
}

if ([string]::IsNullOrWhiteSpace($LogDir)) {
    $LogDir = Join-Path $script:BaseDir 'logs'
}

$script:ProgramFiles64 = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
$script:ProgramFilesX86 = if (${env:ProgramFiles(x86)}) { ${env:ProgramFiles(x86)} } else { $null }
$script:CommonFiles64 = if ($env:CommonProgramW6432) { $env:CommonProgramW6432 } else { $env:CommonProgramFiles }
$script:CommonFilesX86 = if (${env:CommonProgramFiles(x86)}) { ${env:CommonProgramFiles(x86)} } else { $null }
$script:ProgData = if ($env:ProgramData) { $env:ProgramData } else { Join-Path $env:SystemDrive 'ProgramData' }
$script:SysRoot = if ($env:SystemRoot) { $env:SystemRoot } else { Join-Path $env:SystemDrive 'Windows' }

$script:HasError = $false
$script:NeedsReboot = $false
$script:ReportItems = New-Object System.Collections.Generic.List[object]

if (-not (Test-Path -LiteralPath $LogDir)) {
    if (-not $WhatIfPreference) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
}
$tsNow = Get-Date -Format 'yyyyMMdd_HHmmss'
$script:LogFile = Join-Path $LogDir ("cleanup_{0}.log" -f $tsNow)
if ($AutoExportCsv -and [string]::IsNullOrWhiteSpace($ExportCsv)) {
    $prefix = if ($UnblockAGSReinstall) { 'unblock' } else { 'report' }
    $ExportCsv = Join-Path $LogDir ("{0}_{1}.csv" -f $prefix, $tsNow)
}

function Invoke-LogRotation {
    param([string]$Directory, [int]$KeepCount = 10)
    if (-not (Test-Path -LiteralPath $Directory)) { return }
    $logs = @(Get-ChildItem -LiteralPath $Directory -Filter 'cleanup_*.log' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending)
    if ($logs.Count -gt $KeepCount -and -not $WhatIfPreference) {
        $logs | Select-Object -Skip $KeepCount | Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[{0}] [{1}] {2}" -f $ts, $Level, $Message
    if (-not $WhatIfPreference -and (Test-Path -LiteralPath $LogDir)) {
        Add-Content -LiteralPath $script:LogFile -Value $line -Encoding Ascii -ErrorAction SilentlyContinue
    }
    switch ($Level) {
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        default { Write-Host $line }
    }
}

function Add-ReportItem {
    param(
        [string]$Category,
        [string]$Target,
        [string]$Action,
        [string]$Status
    )
    $script:ReportItems.Add([PSCustomObject]@{
        Timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        Category  = $Category
        Target    = $Target
        Action    = $Action
        Status    = $Status
    }) | Out-Null
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-UserProfilePaths {
    $paths = New-Object System.Collections.Generic.List[string]
    $excludedNames = @('Public', 'Default', 'Default User', 'All Users', 'defaultuser0')

    # 1. From Windows ProfileList registry (handles moved or domain profiles)
    $profileReg = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    if (Test-Path -LiteralPath $profileReg) {
        Get-ChildItem -LiteralPath $profileReg -ErrorAction SilentlyContinue |
            Where-Object { $_.PSChildName -like 'S-1-5-21-*' } |
            ForEach-Object {
                $p = (Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue).ProfileImagePath
                if ($p -and (Test-Path -LiteralPath $p -PathType Container)) {
                    $leaf = Split-Path -Leaf $p
                    if ($excludedNames -notcontains $leaf -and -not $paths.Contains($p)) {
                        $paths.Add($p) | Out-Null
                    }
                }
            }
    }

    # 2. Fallback scan of SystemDrive\Users
    $usersRoot = Join-Path $env:SystemDrive 'Users'
    if (Test-Path -LiteralPath $usersRoot -PathType Container) {
        Get-ChildItem -LiteralPath $usersRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $excludedNames -notcontains $_.Name } |
            ForEach-Object {
                if (-not $paths.Contains($_.FullName)) {
                    $paths.Add($_.FullName) | Out-Null
                }
            }
    }
    return @($paths)
}

function Get-OtherAdobeProducts {
    $found = New-Object System.Collections.Generic.List[string]
    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    Get-ItemProperty -Path $uninstallRoots -ErrorAction SilentlyContinue | ForEach-Object {
        $dn = if ($_.PSObject.Properties['DisplayName']) { [string]$_.DisplayName } else { '' }
        $pub = if ($_.PSObject.Properties['Publisher']) { [string]$_.Publisher } else { '' }
        if (($dn -match 'Adobe' -or $pub -match 'Adobe') -and -not [string]::IsNullOrWhiteSpace($dn)) {
            if ($dn -notmatch 'Acrobat|Reader|Refresh Manager|Genuine') {
                if (-not $found.Contains($dn)) {
                    $found.Add($dn) | Out-Null
                }
            }
        }
    }

    foreach ($pf in @($script:ProgramFiles64, $script:ProgramFilesX86)) {
        if (-not $pf) { continue }
        $adobeDir = Join-Path $pf 'Adobe'
        if (Test-Path -LiteralPath $adobeDir -PathType Container) {
            Get-ChildItem -LiteralPath $adobeDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                if ($_.Name -notmatch '^(Acrobat|Reader)') {
                    $files = @(Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Select-Object -First 1)
                    if ($files.Count -gt 0) {
                        $label = "Folder: {0}" -f $_.FullName
                        if (-not $found.Contains($label)) {
                            $found.Add($label) | Out-Null
                        }
                    }
                }
            }
        }
    }
    return @($found)
}

function Register-DeleteOnReboot {
    param([Parameter(Mandatory = $true)][string]$Path)
    $smKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    try {
        $existing = @()
        $prop = Get-ItemProperty -LiteralPath $smKey -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue
        if ($prop -and $prop.PSObject.Properties['PendingFileRenameOperations']) {
            $existing = @($prop.PendingFileRenameOperations)
        }
        $ntPath = "\??\{0}" -f $Path
        $updated = @($existing) + @($ntPath, '')
        Set-ItemProperty -LiteralPath $smKey -Name 'PendingFileRenameOperations' -Value ([string[]]$updated) -Type MultiString -ErrorAction Stop
        $script:NeedsReboot = $true
        Write-Log -Message ("Zamcena polozka naplanovana ke smazani po restartu Windows: {0}" -f $Path) -Level 'WARN'
        Add-ReportItem -Category 'PendingRebootDelete' -Target $Path -Action 'ScheduleRebootDelete' -Status 'Scheduled'
    } catch {
        $script:HasError = $true
        Write-Log -Message ("Nepodarilo se naplanovat smazani po restartu pro {0}: {1}" -f $Path, $_.Exception.Message) -Level 'ERROR'
    }
}

function Remove-PathSafe {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Category = 'Filesystem'
    )
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return
    }
    if ($PSCmdlet.ShouldProcess($Path, 'Smazat slozku nebo soubor')) {
        try {
            $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
            if ($item -and $item.PSIsContainer) {
                Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                    try { $_.Attributes = 'Normal' } catch {}
                }
            } elseif ($item) {
                try { $item.Attributes = 'Normal' } catch {}
            }
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            Write-Log -Message ("Smazano: {0}" -f $Path)
            Add-ReportItem -Category $Category -Target $Path -Action 'Remove' -Status 'Removed'
        } catch {
            Write-Log -Message ("Bezne smazani selhalo pro {0}, zkousim reset opravneni (ACL): {1}" -f $Path, $_.Exception.Message) -Level 'WARN'
            try {
                if (Test-Path -LiteralPath $Path -PathType Container) {
                    & takeown.exe /F "$Path" /R /D Y | Out-Null
                    & icacls.exe "$Path" /remove:d "*S-1-1-0" /T /C /Q | Out-Null
                    & icacls.exe "$Path" /grant "*S-1-5-32-544:(OI)(CI)F" /T /C /Q | Out-Null
                } else {
                    & takeown.exe /F "$Path" | Out-Null
                    & icacls.exe "$Path" /remove:d "*S-1-1-0" /C /Q | Out-Null
                    & icacls.exe "$Path" /grant "*S-1-5-32-544:F" /C /Q | Out-Null
                }
                Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
                Write-Log -Message ("Smazano po resetu opravneni: {0}" -f $Path)
                Add-ReportItem -Category $Category -Target $Path -Action 'RemoveWithAcl' -Status 'Removed'
            } catch {
                # Handle locked DLLs (e.g., Explorer context menu extensions) by scheduling delete on reboot
                if (Test-Path -LiteralPath $Path -PathType Container) {
                    $remainingFiles = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue)
                    foreach ($rf in $remainingFiles) {
                        try {
                            Remove-Item -LiteralPath $rf.FullName -Force -ErrorAction Stop
                        } catch {
                            Register-DeleteOnReboot -Path $rf.FullName
                        }
                    }
                    Register-DeleteOnReboot -Path $Path
                } else {
                    Register-DeleteOnReboot -Path $Path
                }
            }
        }
    } else {
        Add-ReportItem -Category $Category -Target $Path -Action 'Remove' -Status 'WhatIf'
    }
}

function Remove-EmptyDirSafe {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Container)) {
        return
    }
    $children = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
    if ($children.Count -eq 0) {
        Remove-PathSafe -Path $Path -Category 'EmptyParentDir'
    }
}

function Remove-RegistryKeySafe {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [string]$Category = 'RegistryKey'
    )
    if (-not (Test-Path -LiteralPath $LiteralPath)) {
        return
    }
    if ($PSCmdlet.ShouldProcess($LiteralPath, 'Smazat klic registru')) {
        try {
            Remove-Item -LiteralPath $LiteralPath -Recurse -Force -ErrorAction Stop
            Write-Log -Message ("Smazan klic registru: {0}" -f $LiteralPath)
            Add-ReportItem -Category $Category -Target $LiteralPath -Action 'RemoveKey' -Status 'Removed'
        } catch {
            $script:HasError = $true
            Write-Log -Message ("Nepodarilo se smazat klic registru {0}: {1}" -f $LiteralPath, $_.Exception.Message) -Level 'ERROR'
            Add-ReportItem -Category $Category -Target $LiteralPath -Action 'RemoveKey' -Status 'Failed'
        }
    } else {
        Add-ReportItem -Category $Category -Target $LiteralPath -Action 'RemoveKey' -Status 'WhatIf'
    }
}

function Remove-RegistryValueSafe {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Category = 'RegistryValue'
    )
    if (-not (Test-Path -LiteralPath $LiteralPath)) {
        return
    }
    $prop = Get-ItemProperty -LiteralPath $LiteralPath -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $prop) {
        return
    }
    $targetDesc = "{0} :: {1}" -f $LiteralPath, $Name
    if ($PSCmdlet.ShouldProcess($targetDesc, 'Smazat hodnotu v registru')) {
        try {
            Remove-ItemProperty -LiteralPath $LiteralPath -Name $Name -Force -ErrorAction Stop
            Write-Log -Message ("Smazana hodnota v registru: {0}" -f $targetDesc)
            Add-ReportItem -Category $Category -Target $targetDesc -Action 'RemoveValue' -Status 'Removed'
        } catch {
            $script:HasError = $true
            Write-Log -Message ("Nepodarilo se smazat hodnotu v registru {0}: {1}" -f $targetDesc, $_.Exception.Message) -Level 'ERROR'
            Add-ReportItem -Category $Category -Target $targetDesc -Action 'RemoveValue' -Status 'Failed'
        }
    } else {
        Add-ReportItem -Category $Category -Target $targetDesc -Action 'RemoveValue' -Status 'WhatIf'
    }
}

function Stop-TargetProcesses {
    $processNames = @(
        'AGSService', 'AGMService', 'AdobeGCClient', 'agcinvokerutility',
        'AdobeCleanUpUtility', 'gccustomhook', 'AdobeGenuineValidator',
        'armsvc', 'AdobeARM', 'AdobeARMHelper', 'AdobeARM_UCB',
        'Acrobat', 'AcroRd32', 'AcroCEF', 'AcroTray', 'AcroBroker',
        'AdobeCollabSync', 'AdobeIPCBroker', 'RdrCEF', 'RdrServicesUpdater',
        'Distiller', 'acrodist', 'AcrobatNotificationClient'
    )
    $running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $processNames -contains $_.ProcessName })
    foreach ($proc in $running) {
        $desc = "{0} (PID {1})" -f $proc.ProcessName, $proc.Id
        if ($PSCmdlet.ShouldProcess($desc, 'Ukoncit proces')) {
            try {
                Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                Write-Log -Message ("Ukoncen proces: {0}" -f $desc)
                Add-ReportItem -Category 'Process' -Target $desc -Action 'Stop' -Status 'Stopped'
            } catch {
                Write-Log -Message ("Nepodarilo se ukoncit proces {0}: {1}" -f $desc, $_.Exception.Message) -Level 'WARN'
                Add-ReportItem -Category 'Process' -Target $desc -Action 'Stop' -Status 'Failed'
            }
        } else {
            Add-ReportItem -Category 'Process' -Target $desc -Action 'Stop' -Status 'WhatIf'
        }
    }
}

function Remove-TargetServices {
    $serviceNames = @('AGSService', 'AGMService', 'AdobeARMservice', 'AdobeUpdateService')
    foreach ($svcName in $serviceNames) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if (-not $svc) {
            continue
        }
        if ($PSCmdlet.ShouldProcess($svcName, 'Zastavit a odstranit sluzbu Windows')) {
            try {
                if ($svc.Status -ne 'Stopped') {
                    Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 2
                }
                & sc.exe delete "$svcName" | Out-Null
                Write-Log -Message ("Odstranena sluzba: {0}" -f $svcName)
                Add-ReportItem -Category 'Service' -Target $svcName -Action 'DeleteService' -Status 'Removed'
            } catch {
                $script:HasError = $true
                Write-Log -Message ("Nepodarilo se odstranit sluzbu {0}: {1}" -f $svcName, $_.Exception.Message) -Level 'ERROR'
                Add-ReportItem -Category 'Service' -Target $svcName -Action 'DeleteService' -Status 'Failed'
            }
        } else {
            Add-ReportItem -Category 'Service' -Target $svcName -Action 'DeleteService' -Status 'WhatIf'
        }
    }
}

function Remove-TargetTasks {
    $exactTasks = @(
        'Adobe Acrobat Update Task',
        'Adobe-Genuine-Software-Integrity-Scheduler-1.0',
        'AdobeGCInvoker-1.0',
        'AdobeGCInvokerLogon'
    )
    $tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
        ($exactTasks -contains $_.TaskName) -or
        ($_.TaskName -like 'Adobe Acrobat*') -or
        ($_.TaskName -like 'AdobeGC*') -or
        ($_.TaskName -like 'Adobe-Genuine*')
    })
    foreach ($task in $tasks) {
        $fullTask = "{0}{1}" -f $task.TaskPath, $task.TaskName
        if ($PSCmdlet.ShouldProcess($fullTask, 'Odstranit naplanovanou ulohu')) {
            try {
                Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction Stop
                Write-Log -Message ("Odstranena naplanovana uloha: {0}" -f $fullTask)
                Add-ReportItem -Category 'ScheduledTask' -Target $fullTask -Action 'Unregister' -Status 'Removed'
            } catch {
                $script:HasError = $true
                Write-Log -Message ("Nepodarilo se odstranit ulohu {0}: {1}" -f $fullTask, $_.Exception.Message) -Level 'ERROR'
                Add-ReportItem -Category 'ScheduledTask' -Target $fullTask -Action 'Unregister' -Status 'Failed'
            }
        } else {
            Add-ReportItem -Category 'ScheduledTask' -Target $fullTask -Action 'Unregister' -Status 'WhatIf'
        }
    }
}

function Uninstall-MsiAndAppx {
    # 1. Dynamically discover any MSI-based Adobe Acrobat / Reader / Refresh Manager GUIDs on this machine
    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $seenGuids = New-Object System.Collections.Generic.List[string]
    $guidRegex = '\{[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}\}'

    $candidates = @(Get-ItemProperty -Path $uninstallRoots -ErrorAction SilentlyContinue | Where-Object {
        ($_.PSObject.Properties['DisplayName']) -and (
            $_.DisplayName -like 'Adobe Acrobat*' -or
            $_.DisplayName -like 'Adobe Reader*' -or
            $_.DisplayName -like 'Adobe Refresh Manager*'
        )
    })

    foreach ($item in $candidates) {
        $guid = $null
        if ($item.PSChildName -match "^$guidRegex$") {
            $guid = $item.PSChildName
        } elseif ($item.PSObject.Properties['UninstallString'] -and $item.UninstallString -match "($guidRegex)") {
            $guid = $Matches[1]
        }

        if ($guid -and -not $seenGuids.Contains($guid.ToUpperInvariant())) {
            $seenGuids.Add($guid.ToUpperInvariant()) | Out-Null
            $desc = "{0} ({1})" -f $item.DisplayName, $guid
            if ($PSCmdlet.ShouldProcess($desc, 'Odinstalovat MSI balicek')) {
                try {
                    $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList "/x $guid /qn /norestart" -Wait -PassThru -NoNewWindow
                    Write-Log -Message ("Spusten msiexec /x {0} pro '{1}' (ExitCode={2})" -f $guid, $item.DisplayName, $proc.ExitCode)
                    Add-ReportItem -Category 'MSI' -Target $desc -Action 'MsiUninstall' -Status ("ExitCode:{0}" -f $proc.ExitCode)
                } catch {
                    $script:HasError = $true
                    Write-Log -Message ("Odinstalace MSI selhala pro {0}: {1}" -f $desc, $_.Exception.Message) -Level 'ERROR'
                    Add-ReportItem -Category 'MSI' -Target $desc -Action 'MsiUninstall' -Status 'Failed'
                }
            } else {
                Add-ReportItem -Category 'MSI' -Target $desc -Action 'MsiUninstall' -Status 'WhatIf'
            }
        }
    }

    # Re-stop any helper processes spawned during MSI uninstall
    Stop-TargetProcesses

    # 2. AppX packages (Explorer context menu / CoreApp / Notification client)
    $appxList = @()
    if (Test-IsAdministrator) {
        $appxList = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -like 'AdobeAcrobat*' -or $_.Name -like 'adobe.acrobat*' -or $_.Name -like 'AcrobatNotificationClient*'
        })
    } else {
        $appxList = @(Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -like 'AdobeAcrobat*' -or $_.Name -like 'adobe.acrobat*' -or $_.Name -like 'AcrobatNotificationClient*'
        })
    }
    foreach ($pkg in $appxList) {
        if ($PSCmdlet.ShouldProcess($pkg.PackageFullName, 'Odstranit AppX balicek')) {
            try {
                if (Test-IsAdministrator) {
                    Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                } else {
                    Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
                }
                Write-Log -Message ("Odstranen AppX balicek: {0}" -f $pkg.PackageFullName)
                Add-ReportItem -Category 'AppX' -Target $pkg.PackageFullName -Action 'RemoveAppx' -Status 'Removed'
            } catch {
                $script:HasError = $true
                Write-Log -Message ("Nepodarilo se odstranit AppX balicek {0}: {1}" -f $pkg.PackageFullName, $_.Exception.Message) -Level 'ERROR'
                Add-ReportItem -Category 'AppX' -Target $pkg.PackageFullName -Action 'RemoveAppx' -Status 'Failed'
            }
        } else {
            Add-ReportItem -Category 'AppX' -Target $pkg.PackageFullName -Action 'RemoveAppx' -Status 'WhatIf'
        }
    }

    if (Test-IsAdministrator) {
        $provList = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object {
            $_.DisplayName -like 'AdobeAcrobat*' -or $_.DisplayName -like 'adobe.acrobat*' -or $_.DisplayName -like 'AcrobatNotificationClient*'
        })
        foreach ($prov in $provList) {
            if ($PSCmdlet.ShouldProcess($prov.PackageName, 'Odstranit provisioned AppX balicek')) {
                try {
                    Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop | Out-Null
                    Write-Log -Message ("Odstranen provisioned AppX balicek: {0}" -f $prov.PackageName)
                    Add-ReportItem -Category 'AppXProvisioned' -Target $prov.PackageName -Action 'RemoveProvisioned' -Status 'Removed'
                } catch {
                    Write-Log -Message ("Nepodarilo se odstranit provisioned AppX {0}: {1}" -f $prov.PackageName, $_.Exception.Message) -Level 'WARN'
                }
            } else {
                Add-ReportItem -Category 'AppXProvisioned' -Target $prov.PackageName -Action 'RemoveProvisioned' -Status 'WhatIf'
            }
        }
    }
}

function Clean-Printers {
    $printers = @(Get-Printer -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -like 'Adobe PDF*' -or $_.DriverName -like 'Adobe PDF*'
    })
    foreach ($pr in $printers) {
        if ($PSCmdlet.ShouldProcess($pr.Name, 'Odstranit tiskarnu Adobe PDF')) {
            Remove-Printer -Name $pr.Name -ErrorAction SilentlyContinue
            Write-Log -Message ("Odstranena tiskarna: {0}" -f $pr.Name)
            Add-ReportItem -Category 'Printer' -Target $pr.Name -Action 'RemovePrinter' -Status 'Removed'
        } else {
            Add-ReportItem -Category 'Printer' -Target $pr.Name -Action 'RemovePrinter' -Status 'WhatIf'
        }
    }

    $drivers = @(Get-PrinterDriver -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -like 'Adobe PDF*'
    })
    foreach ($drv in $drivers) {
        if ($PSCmdlet.ShouldProcess($drv.Name, 'Odstranit ovladac tiskarny Adobe PDF')) {
            Remove-PrinterDriver -Name $drv.Name -ErrorAction SilentlyContinue
            Write-Log -Message ("Odstranen ovladac tiskarny: {0}" -f $drv.Name)
            Add-ReportItem -Category 'PrinterDriver' -Target $drv.Name -Action 'RemoveDriver' -Status 'Removed'
        } else {
            Add-ReportItem -Category 'PrinterDriver' -Target $drv.Name -Action 'RemoveDriver' -Status 'WhatIf'
        }
    }
}

function Clean-FilesystemAndProfiles {
    param([bool]$CleanSharedLicensing)

    # 1. Program Files (64-bit & 32-bit) Acrobat/Reader folders
    foreach ($pf in @($script:ProgramFiles64, $script:ProgramFilesX86)) {
        if (-not $pf) { continue }
        $adobePf = Join-Path $pf 'Adobe'
        if (Test-Path -LiteralPath $adobePf -PathType Container) {
            Get-ChildItem -LiteralPath $adobePf -Directory -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^(Acrobat|Reader)' } |
                ForEach-Object {
                    Remove-PathSafe -Path $_.FullName -Category 'SystemFilesystem'
                }
        }
    }

    # 2. Common Files (64-bit & 32-bit) AGS, ARM, Acrobat, and optionally shared licensing
    foreach ($cf in @($script:CommonFiles64, $script:CommonFilesX86)) {
        if (-not $cf) { continue }
        $adobeCf = Join-Path $cf 'Adobe'
        $alwaysRemoveCf = @('AdobeGCClient', 'AdobeGCData', 'ARM', 'Acrobat', 'Reader')
        foreach ($sub in $alwaysRemoveCf) {
            Remove-PathSafe -Path (Join-Path $adobeCf $sub) -Category 'SystemFilesystem'
        }
        if ($CleanSharedLicensing) {
            foreach ($sharedSub in @('Adobe PCD', 'SLCache', 'PCF', 'Color')) {
                Remove-PathSafe -Path (Join-Path $adobeCf $sharedSub) -Category 'SharedLicensingFS'
            }
        }
    }

    # 3. ProgramData Adobe caches & licensing
    $adobePd = Join-Path $script:ProgData 'Adobe'
    foreach ($pdSub in @('ARM', 'Acrobat', 'Setup')) {
        Remove-PathSafe -Path (Join-Path $adobePd $pdSub) -Category 'SystemFilesystem'
    }
    if ($CleanSharedLicensing) {
        Remove-PathSafe -Path (Join-Path $adobePd 'SLStore') -Category 'SharedLicensingFS'
    }

    # 4. Shortcuts in Public Desktop and Common Start Menu
    $shortcutRoots = @(
        (Join-Path $env:SystemDrive 'Users\Public\Desktop'),
        (Join-Path $script:ProgData 'Microsoft\Windows\Start Menu\Programs')
    )

    # 5. Per-user profiles
    $profilePaths = @(Get-UserProfilePaths)
    foreach ($uRoot in $profilePaths) {
        $shortcutRoots += (Join-Path $uRoot 'Desktop')
        $shortcutRoots += (Join-Path $uRoot 'OneDrive\Desktop')
        $shortcutRoots += (Join-Path $uRoot 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs')

        $userTargets = @(
            (Join-Path $uRoot 'AppData\Local\Adobe\Acrobat'),
            (Join-Path $uRoot 'AppData\Local\Adobe\AcroCef'),
            (Join-Path $uRoot 'AppData\Local\Adobe\ARM'),
            (Join-Path $uRoot 'AppData\Roaming\Adobe\Acrobat'),
            (Join-Path $uRoot 'AppData\Roaming\Adobe\Adobe PDF'),
            (Join-Path $uRoot 'AppData\Roaming\com.adobe.dunamis'),
            (Join-Path $uRoot 'AppData\LocalLow\Adobe\Acrobat'),
            (Join-Path $uRoot 'AppData\LocalLow\Adobe\AcroCef'),
            (Join-Path $uRoot 'AppData\Local\Packages\adobe.acrobatreaderdc.protectedmode')
        )
        if ($CleanSharedLicensing) {
            $userTargets += @(
                (Join-Path $uRoot 'AppData\Local\Adobe\AAMUpdater'),
                (Join-Path $uRoot 'AppData\Local\Adobe\Color'),
                (Join-Path $uRoot 'AppData\Local\Adobe\licflags'),
                (Join-Path $uRoot 'AppData\Local\Adobe\NGL'),
                (Join-Path $uRoot 'AppData\Local\Adobe\OOBE'),
                (Join-Path $uRoot 'AppData\Local\Adobe\.adobelicnotification'),
                (Join-Path $uRoot 'AppData\Roaming\Adobe\Adobe PCD'),
                (Join-Path $uRoot 'AppData\Roaming\Adobe\Color'),
                (Join-Path $uRoot 'AppData\Roaming\Adobe\CRLogs'),
                (Join-Path $uRoot 'AppData\Roaming\Adobe\Flash Player'),
                (Join-Path $uRoot 'AppData\Roaming\Adobe\Headlights'),
                (Join-Path $uRoot 'AppData\Roaming\Adobe\Linguistics'),
                (Join-Path $uRoot 'AppData\Roaming\Adobe\LogTransport2'),
                (Join-Path $uRoot 'AppData\Roaming\Adobe\LogTransport2CC'),
                (Join-Path $uRoot 'AppData\Roaming\Adobe\NGL'),
                (Join-Path $uRoot 'AppData\Roaming\Adobe\OOBE'),
                (Join-Path $uRoot 'AppData\Roaming\Adobe\RTTransfer'),
                (Join-Path $uRoot 'AppData\Roaming\Adobe\SLData'),
                (Join-Path $uRoot 'AppData\Roaming\Adobe\Sonar'),
                (Join-Path $uRoot 'AppData\LocalLow\Adobe\CRLogs'),
                (Join-Path $uRoot 'AppData\LocalLow\Adobe\GrowthSDK'),
                (Join-Path $uRoot 'AppData\LocalLow\Adobe\Linguistics')
            )
        }

        $pkgDir = Join-Path $uRoot 'AppData\Local\Packages'
        if (Test-Path -LiteralPath $pkgDir) {
            Get-ChildItem -LiteralPath $pkgDir -Directory -Filter 'AdobeAcrobat*' -Force -ErrorAction SilentlyContinue | ForEach-Object {
                $userTargets += $_.FullName
            }
        }

        foreach ($ut in $userTargets) {
            Remove-PathSafe -Path $ut -Category 'UserFilesystem'
        }

        # Temp logs & caches
        $tempDir = Join-Path $uRoot 'AppData\Local\Temp'
        if (Test-Path -LiteralPath $tempDir) {
            $tempExact = @(
                'Acrobat Distiller DC', 'acrobat_sbx', 'AdobeGCCache',
                'AdobeARM.log', 'AdobeARM_NotLocked.log', 'AdobeARM_UCB.log',
                'adobegc.log', 'AdobeIPCBroker.log', 'AdobeIPCBrokerCustomHook.log'
            )
            foreach ($ti in $tempExact) {
                Remove-PathSafe -Path (Join-Path $tempDir $ti) -Category 'UserTemp'
            }
        }

        Remove-EmptyDirSafe -Path (Join-Path $uRoot 'AppData\Local\Adobe')
        Remove-EmptyDirSafe -Path (Join-Path $uRoot 'AppData\Roaming\Adobe')
        Remove-EmptyDirSafe -Path (Join-Path $uRoot 'AppData\LocalLow\Adobe')
    }

    # Clean Adobe Acrobat shortcuts (.lnk)
    foreach ($sr in ($shortcutRoots | Select-Object -Unique)) {
        if ($sr -and (Test-Path -LiteralPath $sr -PathType Container)) {
            Get-ChildItem -LiteralPath $sr -Filter '*Acrobat*.lnk' -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-PathSafe -Path $_.FullName -Category 'Shortcut'
            }
        }
    }

    # Remove empty system Adobe parent directories
    Remove-EmptyDirSafe -Path (Join-Path $script:ProgramFiles64 'Adobe')
    if ($script:ProgramFilesX86) { Remove-EmptyDirSafe -Path (Join-Path $script:ProgramFilesX86 'Adobe') }
    Remove-EmptyDirSafe -Path $adobePd
    if (-not $BlockAGSReinstall) {
        Remove-EmptyDirSafe -Path (Join-Path $script:CommonFiles64 'Adobe')
        if ($script:CommonFilesX86) { Remove-EmptyDirSafe -Path (Join-Path $script:CommonFilesX86 'Adobe') }
    }
}

function Clean-BrowserAndOffice {
    if (-not $KeepBrowserExtensions) {
        $extIds = @('efaidnbmnnnibpcajpcglclefindmkaj', 'elhekieabhbkpmcefcoobjddigjcaadp')
        $browserRegRoots = @(
            'HKCU:\SOFTWARE\Google\Chrome\Extensions',
            'HKLM:\SOFTWARE\Google\Chrome\Extensions',
            'HKLM:\SOFTWARE\WOW6432Node\Google\Chrome\Extensions',
            'HKCU:\SOFTWARE\Microsoft\Edge\Extensions',
            'HKLM:\SOFTWARE\Microsoft\Edge\Extensions',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Edge\Extensions'
        )
        foreach ($root in $browserRegRoots) {
            foreach ($id in $extIds) {
                Remove-RegistryKeySafe -LiteralPath (Join-Path $root $id) -Category 'BrowserExtensionReg'
            }
        }

        foreach ($uRoot in @(Get-UserProfilePaths)) {
            $browserDataRoots = @(
                (Join-Path $uRoot 'AppData\Local\Google\Chrome\User Data'),
                (Join-Path $uRoot 'AppData\Local\Microsoft\Edge\User Data')
            )
            foreach ($bd in $browserDataRoots) {
                if (Test-Path -LiteralPath $bd) {
                    Get-ChildItem -LiteralPath $bd -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
                        foreach ($id in $extIds) {
                            Remove-PathSafe -Path (Join-Path $_.FullName ("Extensions\{0}" -f $id)) -Category 'BrowserExtensionDir'
                        }
                    }
                }
            }
        }
    }

    if (-not $KeepOfficeAddins) {
        $officeApps = @('Word', 'Excel', 'PowerPoint', 'Outlook')
        foreach ($app in $officeApps) {
            Remove-RegistryKeySafe -LiteralPath ("HKCU:\SOFTWARE\Microsoft\Office\{0}\Addins\PDFMaker.OfficeAddin" -f $app) -Category 'OfficeAddin'
            Remove-RegistryKeySafe -LiteralPath ("HKLM:\SOFTWARE\Microsoft\Office\{0}\Addins\PDFMaker.OfficeAddin" -f $app) -Category 'OfficeAddin'
            Remove-RegistryKeySafe -LiteralPath ("HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\{0}\Addins\PDFMaker.OfficeAddin" -f $app) -Category 'OfficeAddin'
        }
    }
}

function Clean-Registry {
    param([bool]$CleanSharedLicensing)

    # 1. Startup Run keys
    $runRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
    )
    foreach ($rr in $runRoots) {
        if (Test-Path -LiteralPath $rr) {
            $item = Get-Item -LiteralPath $rr -ErrorAction SilentlyContinue
            $props = @(if ($item -and $item.Property) { $item.Property })
            foreach ($p in $props) {
                $val = [string](Get-ItemProperty -LiteralPath $rr -Name $p -ErrorAction SilentlyContinue).$p
                if ($p -match 'AdobeGC|AdobeARM|AcroTray|Adobe Acrobat|Acrobat Assistant' -or $val -match 'AdobeGCClient|AGCInvokerUtility|AdobeARM|AcroTray|Acrobat') {
                    Remove-RegistryValueSafe -LiteralPath $rr -Name $p -Category 'StartupRun'
                }
            }
        }
    }

    # 2. Dynamically remove leftover Uninstall entries for AGS, ARM, and Acrobat (no hardcoded single-PC GUIDs)
    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($ur in $uninstallRoots) {
        if (-not (Test-Path -LiteralPath $ur)) { continue }
        Get-ChildItem -LiteralPath $ur -ErrorAction SilentlyContinue | ForEach-Object {
            $props = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
            $dn = if ($props -and $props.PSObject.Properties['DisplayName']) { [string]$props.DisplayName } else { '' }
            if ($_.PSChildName -eq 'AdobeGenuineService' -or
                $dn -like 'Adobe Genuine Service*' -or
                $dn -like 'Adobe Refresh Manager*' -or
                $dn -like 'Adobe Acrobat*' -or
                $dn -like 'Adobe Reader*') {
                Remove-RegistryKeySafe -LiteralPath $_.PSPath -Category 'UninstallReg'
            }
        }
    }

    # 3. HKLM / WOW6432Node / HKCU Adobe subkeys
    $adobeRegKeys = @(
        'HKLM:\SOFTWARE\Adobe\Adobe Acrobat',
        'HKLM:\SOFTWARE\Adobe\Acrobat Reader',
        'HKLM:\SOFTWARE\Adobe\Adobe Genuine Service',
        'HKLM:\SOFTWARE\Adobe\PDF Admin Settings',
        'HKLM:\SOFTWARE\WOW6432Node\Adobe\Adobe Acrobat',
        'HKLM:\SOFTWARE\WOW6432Node\Adobe\Acrobat Reader',
        'HKLM:\SOFTWARE\WOW6432Node\Adobe\Adobe ARM',
        'HKLM:\SOFTWARE\WOW6432Node\Adobe\PDF Admin Settings',
        'HKCU:\SOFTWARE\Adobe\Adobe Acrobat',
        'HKCU:\SOFTWARE\Adobe\Acrobat Reader',
        'HKCU:\SOFTWARE\Adobe\Acrobat Distiller',
        'HKCU:\SOFTWARE\Adobe\Adobe ARM',
        'HKCU:\SOFTWARE\Adobe\Adobe Send for Microsoft Outlook',
        'HKCU:\SOFTWARE\Adobe\Adobe Synchronizer',
        'HKCU:\SOFTWARE\Adobe\PDF Settings'
    )
    if ($CleanSharedLicensing) {
        $adobeRegKeys += @(
            'HKLM:\SOFTWARE\Adobe\Identity',
            'HKLM:\SOFTWARE\Adobe\Installer',
            'HKLM:\SOFTWARE\Adobe\InstallerAnalytics',
            'HKLM:\SOFTWARE\Adobe\Licensing',
            'HKLM:\SOFTWARE\WOW6432Node\Adobe\Installer',
            'HKLM:\SOFTWARE\WOW6432Node\Adobe\Setup',
            'HKCU:\SOFTWARE\Adobe\Adobe Express Photos',
            'HKCU:\SOFTWARE\Adobe\CommonFiles',
            'HKCU:\SOFTWARE\Adobe\Dunamis'
        )
        # Also remove dynamic 12-hex-character tracking subkeys under HKCU:\SOFTWARE\Adobe (e.g. A1B2C3D4E5F6)
        if (Test-Path -LiteralPath 'HKCU:\SOFTWARE\Adobe') {
            Get-ChildItem -LiteralPath 'HKCU:\SOFTWARE\Adobe' -ErrorAction SilentlyContinue |
                Where-Object { $_.PSChildName -match '^[0-9A-Fa-f]{12}$' } |
                ForEach-Object {
                    $adobeRegKeys += $_.PSPath
                }
        }
    }
    foreach ($rk in $adobeRegKeys) {
        Remove-RegistryKeySafe -LiteralPath $rk -Category 'AdobeRegistry'
    }

    # Clean empty root Adobe registry keys
    foreach ($parentKey in @('HKLM:\SOFTWARE\Adobe', 'HKLM:\SOFTWARE\WOW6432Node\Adobe', 'HKCU:\SOFTWARE\Adobe')) {
        if (Test-Path -LiteralPath $parentKey) {
            $sub = @(Get-ChildItem -LiteralPath $parentKey -ErrorAction SilentlyContinue)
            $keyItem = Get-Item -LiteralPath $parentKey -ErrorAction SilentlyContinue
            $props = @(if ($keyItem -and $keyItem.Property) { $keyItem.Property })
            if ($sub.Count -eq 0 -and $props.Count -eq 0) {
                Remove-RegistryKeySafe -LiteralPath $parentKey -Category 'AdobeRegistryRoot'
            }
        }
    }

    # 4. HKLM Classes ProgIDs (dynamic scan for acrobat20*, AcroExch*, Acrobat.Document*, adobe.genuine*)
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Classes') {
        Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\Classes' -ErrorAction SilentlyContinue |
            Where-Object {
                $_.PSChildName -match '^(acrobat20\d\d|adobe\.genuine\.invoker|Acrobat\.Document.*|AcroExch\..*|PDFMaker\..*)$'
            } |
            ForEach-Object {
                Remove-RegistryKeySafe -LiteralPath $_.PSPath -Category 'ClassesRegistry'
            }
    }

    $openWithKey = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\OpenWithProgids'
    if (Test-Path -LiteralPath $openWithKey) {
        $owItem = Get-Item -LiteralPath $openWithKey -ErrorAction SilentlyContinue
        $owProps = @(if ($owItem -and $owItem.Property) { $owItem.Property })
        foreach ($progId in $owProps) {
            if ($progId -match '^(Acrobat\.|AcroExch\.)') {
                Remove-RegistryValueSafe -LiteralPath $openWithKey -Name $progId -Category 'PdfOpenWith'
            }
        }
    }

    $userChoiceKey = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf\UserChoice'
    if (Test-Path -LiteralPath $userChoiceKey) {
        $uc = (Get-ItemProperty -LiteralPath $userChoiceKey -ErrorAction SilentlyContinue).ProgId
        if ($uc -match '^(Acrobat|AcroExch)') {
            Write-Log -Message ("Vychozi prohlizec .pdf byl nastaven na '{0}'. Pri pristi otevreni PDF si Windows vyzadavaji volbu aplikace." -f $uc) -Level 'INFO'
        }
    }
}

function Get-AGSLockTargets {
    $targets = New-Object System.Collections.Generic.List[string]
    foreach ($cf in @($script:CommonFilesX86, $script:CommonFiles64)) {
        if (-not $cf) { continue }
        $adobeCf = Join-Path $cf 'Adobe'
        foreach ($name in @('AdobeGCClient', 'AdobeGCData')) {
            $t = Join-Path $adobeCf $name
            if (-not $targets.Contains($t)) {
                $targets.Add($t) | Out-Null
            }
        }
    }
    return @($targets)
}

function Set-AGSBlock {
    $lockTargets = @(Get-AGSLockTargets)
    foreach ($target in $lockTargets) {
        $parentAdobe = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $parentAdobe)) {
            if ($PSCmdlet.ShouldProcess($parentAdobe, 'Vytvorit slozku Common Files\Adobe pro zamek AGS')) {
                New-Item -Path $parentAdobe -ItemType Directory -Force | Out-Null
            }
        }

        if ($PSCmdlet.ShouldProcess($target, 'Vytvorit zamceny soubor proti opetovne instalaci AGS')) {
            try {
                if (Test-Path -LiteralPath $target) {
                    Remove-PathSafe -Path $target -Category 'AGSBlockPrep'
                }
                New-Item -Path $target -ItemType File -Force | Out-Null
                & attrib.exe +R +S +H "$target" | Out-Null
                # Deny Write (W) and Delete (D) for Everyone (*S-1-1-0) using language-neutral SIDs
                & icacls.exe "$target" /inheritance:r /grant "*S-1-5-32-544:R" "*S-1-5-18:R" /deny "*S-1-1-0:(W,D)" /Q | Out-Null
                Write-Log -Message ("Cesta uzamcena proti instalaci AGS: {0}" -f $target)
                Add-ReportItem -Category 'AGSBlock' -Target $target -Action 'LockDummyFile' -Status 'Blocked'
            } catch {
                $script:HasError = $true
                Write-Log -Message ("Nepodarilo se uzamknout cestu {0}: {1}" -f $target, $_.Exception.Message) -Level 'ERROR'
                Add-ReportItem -Category 'AGSBlock' -Target $target -Action 'LockDummyFile' -Status 'Failed'
            }
        } else {
            Add-ReportItem -Category 'AGSBlock' -Target $target -Action 'LockDummyFile' -Status 'WhatIf'
        }
    }

    # IFEO Debugger block to prevent execution if any AGS/AGM binary is dropped elsewhere
    $ifeoBase = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
    $blockedExes = @(
        'AGSService.exe',
        'AGMService.exe',
        'AdobeGCClient.exe',
        'agcinvokerutility.exe',
        'AdobeCleanUpUtility.exe',
        'gccustomhook.exe',
        'AdobeGenuineValidator.exe'
    )
    $stubExe = Join-Path $script:SysRoot 'System32\systray.exe'
    if (-not (Test-Path -LiteralPath $stubExe)) {
        $stubExe = Join-Path $script:SysRoot 'System32\rundll32.exe'
    }

    foreach ($exe in $blockedExes) {
        $keyPath = Join-Path $ifeoBase $exe
        if ($PSCmdlet.ShouldProcess($keyPath, 'Nastavit IFEO blokaci spousteni')) {
            try {
                if (-not (Test-Path -LiteralPath $keyPath)) {
                    New-Item -Path $keyPath -Force | Out-Null
                }
                New-ItemProperty -LiteralPath $keyPath -Name 'Debugger' -Value $stubExe -PropertyType String -Force | Out-Null
                Write-Log -Message ("Nastavena IFEO blokace spousteni pro: {0}" -f $exe)
                Add-ReportItem -Category 'AGSBlockIFEO' -Target $keyPath -Action 'SetDebuggerStub' -Status 'Blocked'
            } catch {
                $script:HasError = $true
                Write-Log -Message ("Nepodarilo se nastavit IFEO blokaci pro {0}: {1}" -f $exe, $_.Exception.Message) -Level 'ERROR'
                Add-ReportItem -Category 'AGSBlockIFEO' -Target $keyPath -Action 'SetDebuggerStub' -Status 'Failed'
            }
        } else {
            Add-ReportItem -Category 'AGSBlockIFEO' -Target $keyPath -Action 'SetDebuggerStub' -Status 'WhatIf'
        }
    }
}

function Remove-AGSBlock {
    foreach ($target in @(Get-AGSLockTargets)) {
        if (Test-Path -LiteralPath $target) {
            if ($PSCmdlet.ShouldProcess($target, 'Odemknout a smazat zamek AGS')) {
                try {
                    & takeown.exe /F "$target" | Out-Null
                    & icacls.exe "$target" /remove:d "*S-1-1-0" /Q | Out-Null
                    & icacls.exe "$target" /grant "*S-1-5-32-544:F" /Q | Out-Null
                    & icacls.exe "$target" /inheritance:e /Q | Out-Null
                    & attrib.exe -R -S -H "$target" | Out-Null
                    Remove-Item -LiteralPath $target -Force -ErrorAction Stop
                    Write-Log -Message ("Odstranen zamek AGS: {0}" -f $target)
                    Add-ReportItem -Category 'AGSUnblock' -Target $target -Action 'RemoveLock' -Status 'Unblocked'
                } catch {
                    $script:HasError = $true
                    Write-Log -Message ("Nepodarilo se odstranit zamek AGS {0}: {1}" -f $target, $_.Exception.Message) -Level 'ERROR'
                    Add-ReportItem -Category 'AGSUnblock' -Target $target -Action 'RemoveLock' -Status 'Failed'
                }
            } else {
                Add-ReportItem -Category 'AGSUnblock' -Target $target -Action 'RemoveLock' -Status 'WhatIf'
            }
        }
    }

    $ifeoBase = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
    $blockedExes = @(
        'AGSService.exe',
        'AGMService.exe',
        'AdobeGCClient.exe',
        'agcinvokerutility.exe',
        'AdobeCleanUpUtility.exe',
        'gccustomhook.exe',
        'AdobeGenuineValidator.exe'
    )
    foreach ($exe in $blockedExes) {
        $keyPath = Join-Path $ifeoBase $exe
        if (Test-Path -LiteralPath $keyPath) {
            Remove-RegistryValueSafe -LiteralPath $keyPath -Name 'Debugger' -Category 'AGSUnblockIFEO'
            $sub = @(Get-ChildItem -LiteralPath $keyPath -ErrorAction SilentlyContinue)
            $keyItem = Get-Item -LiteralPath $keyPath -ErrorAction SilentlyContinue
            $props = @(if ($keyItem -and $keyItem.Property) { $keyItem.Property })
            if ($sub.Count -eq 0 -and $props.Count -eq 0) {
                Remove-RegistryKeySafe -LiteralPath $keyPath -Category 'AGSUnblockIFEO'
            }
        }
    }
}

function Show-CurrentStatus {
    Write-Host "============================================================================"
    Write-Host ("  AKTUALNI STAV BLOKACE AGS A CISTOTY SYSTEMU ({0})" -f $env:COMPUTERNAME)
    Write-Host "============================================================================"
    Write-Host ""

    # 1. Check file locks
    $lockTargets = @(Get-AGSLockTargets)
    $lockedCount = 0
    Write-Host "--- 1. ZAMKY CEST PROTI INSTALACI AGS (Common Files x86 / x64) ---"
    foreach ($target in $lockTargets) {
        if (Test-Path -LiteralPath $target) {
            $item = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
            if ($item -and -not $item.PSIsContainer) {
                $hasDeny = $false
                $aclLockedForNonAdmin = $false
                try {
                    $acl = Get-Acl -LiteralPath $target -ErrorAction Stop
                    if ($acl) {
                        $denyRules = @($acl.Access | Where-Object { $_.AccessControlType -eq 'Deny' })
                        if ($denyRules.Count -gt 0) { $hasDeny = $true }
                    }
                } catch [System.UnauthorizedAccessException] {
                    # Non-elevated user denied ReadControl on locked R+S+H 0-byte file -> lock is active
                    if ($item.Length -eq 0) { $aclLockedForNonAdmin = $true }
                } catch {}

                if ($hasDeny -or $aclLockedForNonAdmin) {
                    $lockedCount++
                    Write-Host ("  [ZAMCENO]  {0}" -f $target) -ForegroundColor Green
                } else {
                    Write-Host ("  [SOUBOR BEZ DENY ACL] {0}" -f $target) -ForegroundColor Yellow
                }
            } else {
                Write-Host ("  [SLOZKA EXISTUJE - NEZAMCENO] {0}" -f $target) -ForegroundColor Red
            }
        } else {
            Write-Host ("  [VYPNUTO]  {0}" -f $target) -ForegroundColor DarkGray
        }
    }

    # 2. Check IFEO registry blocks
    $ifeoBase = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
    $blockedExes = @(
        'AGSService.exe',
        'AGMService.exe',
        'AdobeGCClient.exe',
        'agcinvokerutility.exe',
        'AdobeCleanUpUtility.exe',
        'gccustomhook.exe',
        'AdobeGenuineValidator.exe'
    )
    $ifeoCount = 0
    Write-Host ""
    Write-Host "--- 2. BLOKACE SPOUSTENI V REGISTRECH (IFEO Debugger) ---"
    foreach ($exe in $blockedExes) {
        $keyPath = Join-Path $ifeoBase $exe
        $dbg = $null
        if (Test-Path -LiteralPath $keyPath) {
            $prop = Get-ItemProperty -LiteralPath $keyPath -Name 'Debugger' -ErrorAction SilentlyContinue
            if ($prop -and $prop.PSObject.Properties['Debugger']) {
                $dbg = [string]$prop.Debugger
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($dbg)) {
            $ifeoCount++
            Write-Host ("  [AKTIVNI]  {0} -> {1}" -f $exe, $dbg) -ForegroundColor Green
        } else {
            Write-Host ("  [VYPNUTO]  {0}" -f $exe) -ForegroundColor DarkGray
        }
    }

    Write-Host ""
    Write-Host "--- 3. PRITOMNOST ADOBE ACROBAT / ARM / AGS V SYSTEMU ---"
    $procNames = @('AGSService', 'AGMService', 'AdobeGCClient', 'agcinvokerutility', 'armsvc', 'AdobeARM', 'Acrobat', 'AcroRd32', 'AcroCEF')
    $procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $procNames -contains $_.ProcessName })
    $svcs = @(Get-Service -Name 'AGSService', 'AGMService', 'AdobeARMservice', 'AdobeUpdateService' -ErrorAction SilentlyContinue)
    $tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
        $_.TaskName -like 'Adobe Acrobat*' -or $_.TaskName -like 'AdobeGC*' -or $_.TaskName -like 'Adobe-Genuine*'
    })
    $uninstRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $pkgs = @(Get-ItemProperty -Path $uninstRoots -ErrorAction SilentlyContinue | Where-Object {
        ($_.PSObject.Properties['DisplayName']) -and (
            $_.DisplayName -like 'Adobe Genuine Service*' -or
            $_.DisplayName -like 'Adobe Refresh Manager*' -or
            $_.DisplayName -like 'Adobe Acrobat*' -or
            $_.DisplayName -like 'Adobe Reader*'
        )
    })

    Write-Host ("  Bezici procesy Acrobat/ARM/AGS : {0}" -f $procs.Count)
    Write-Host ("  Sluzby Windows (AGS/AGM/ARM)   : {0}" -f $svcs.Count)
    Write-Host ("  Naplanovane ulohy Adobe        : {0}" -f $tasks.Count)
    Write-Host ("  Nainstalovane balicky v PC     : {0}" -f $pkgs.Count)

    Write-Host ""
    Write-Host "============================================================================"
    if ($lockedCount -eq $lockTargets.Count -and $ifeoCount -eq $blockedExes.Count) {
        Write-Host ("  CELKOVY STAV BLOKACE AGS: ZAPNUTA (zamky {0}/{1}, IFEO {2}/{3})" -f $lockedCount, $lockTargets.Count, $ifeoCount, $blockedExes.Count) -ForegroundColor Green
    } elseif ($lockedCount -gt 0 -or $ifeoCount -gt 0) {
        Write-Host ("  CELKOVY STAV BLOKACE AGS: CASTECNE ZAPNUTA (zamky {0}/{1}, IFEO {2}/{3})" -f $lockedCount, $lockTargets.Count, $ifeoCount, $blockedExes.Count) -ForegroundColor Yellow
    } else {
        Write-Host ("  CELKOVY STAV BLOKACE AGS: VYPNUTA (zamky 0/{0}, IFEO 0/{1})" -f $lockTargets.Count, $blockedExes.Count) -ForegroundColor Cyan
    }
    Write-Host "============================================================================"
}

# --- Main Execution ---
if ($ShowStatus) {
    Show-CurrentStatus
    exit 0
}

Invoke-LogRotation -Directory $LogDir -KeepCount 10
Write-Log -Message ("=== Spusteno cisteni Adobe Acrobat a licencnich sluzeb na {0} (PS={1}, WhatIf={2}, BlockAGS={3}, UnblockAGS={4}) ===" -f $env:COMPUTERNAME, $PSVersionTable.PSVersion, [bool]$WhatIfPreference, [bool]$BlockAGSReinstall, [bool]$UnblockAGSReinstall)

if ($BlockAGSReinstall -and $UnblockAGSReinstall) {
    Write-Log -Message "Nelze soucasne zadat -BlockAGSReinstall a -UnblockAGSReinstall." -Level 'ERROR'
    exit 1
}

if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    Write-Log -Message "Skript bezi v 32bitovem PowerShellu na 64bitovych Windows. Pro plny pristup do HKLM pouzijte 64bitovy PowerShell." -Level 'WARN'
}

$isAdmin = Test-IsAdministrator
if (-not $isAdmin) {
    if ($WhatIfPreference) {
        Write-Log -Message "Nahled -WhatIf bezi bez opravneni spravce (kontrola AppX pro vsechny uzivatele preskocena)." -Level 'WARN'
    } else {
        Write-Log -Message "Pro upravu sluzeb, Program Files a HKLM jsou nutna opravneni spravce. Spustte pres run.cmd nebo jako Spravce." -Level 'ERROR'
        exit 1
    }
}

if ($UnblockAGSReinstall) {
    Remove-AGSBlock
} else {
    $otherAdobe = @(Get-OtherAdobeProducts)
    $cleanShared = $true
    if ($otherAdobe.Count -gt 0 -and -not $ForceSharedLicensingCleanup) {
        $cleanShared = $false
        Write-Log -Message ("Detekovany dalsi produkty Adobe ({0}). Sdilene licencni slozky (SLStore, NGL, OOBE) zustanou zachovany." -f ($otherAdobe -join '; ')) -Level 'WARN'
    } elseif ($otherAdobe.Count -eq 0) {
        Write-Log -Message "Zadne jine aplikace Adobe nenalezeny. Povolen kompletni uklid licencnich slozek."
    }

    Write-Log -Message "Krok 1/7: Ukoncovani bezicich procesu Adobe Acrobat / ARM / AGS..."
    Stop-TargetProcesses

    Write-Log -Message "Krok 2/7: Zastaveni a odstraneni sluzeb Adobe..."
    Remove-TargetServices

    Write-Log -Message "Krok 3/7: Odinstalace MSI a AppX balicku..."
    Uninstall-MsiAndAppx

    Write-Log -Message "Krok 4/7: Odstraneni naplanovanych uloh Adobe..."
    Remove-TargetTasks

    Write-Log -Message "Krok 5/7: Odstraneni tiskarny a ovladace Adobe PDF..."
    Clean-Printers

    Write-Log -Message "Krok 6/7: Cisteni rozsireni prohlizecu, doplnku Office a klicu v registrech..."
    Clean-BrowserAndOffice
    Clean-Registry -CleanSharedLicensing $cleanShared

    Write-Log -Message "Krok 7/7: Cisteni souboru na disku, zastupcu a profilu uzivatelu..."
    Clean-FilesystemAndProfiles -CleanSharedLicensing $cleanShared

    if ($BlockAGSReinstall) {
        Write-Log -Message "Aplikuji blokaci opetovne instalace Adobe Genuine Service (x86 i x64)..."
        Set-AGSBlock
    }
}

if ($ExportCsv) {
    try {
        $csvDir = Split-Path -Parent $ExportCsv
        if ($csvDir -and -not (Test-Path -LiteralPath $csvDir) -and -not $WhatIfPreference) {
            New-Item -Path $csvDir -ItemType Directory -Force | Out-Null
        }
        $script:ReportItems | Export-Csv -LiteralPath $ExportCsv -NoTypeInformation -Encoding Ascii
        Write-Log -Message ("CSV report ulozen do: {0}" -f $ExportCsv)
    } catch {
        $script:HasError = $true
        Write-Log -Message ("Nepodarilo se ulozit CSV report: {0}" -f $_.Exception.Message) -Level 'ERROR'
    }
}

if ($script:NeedsReboot) {
    Write-Log -Message "POZNAMKA: Nektere zamcene soubory budou smazany pri pristim restartu Windows." -Level 'WARN'
}

Write-Log -Message ("=== Dokonceno. Celkem zpracovano polozek: {0} | Log: {1} ===" -f $script:ReportItems.Count, $script:LogFile)

if ($script:HasError) {
    exit 1
}
exit 0

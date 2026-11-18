<#
.SYNOPSIS
    Installs and configures the Backup-HyperVVM automation suite on the target
    Hyper-V server (all production paths on C:\).

.DESCRIPTION
    The Install-Backup-HyperVVM.ps1 script automates deployment after copying the
    package directory onto the target Windows Server Hyper-V host (for example,
    to C:\Temp\Backup-HyperVVM or C:\Backup-HyperVVM).
    It performs the following installation steps:
    1. Verifies Administrator privileges (SID S-1-5-32-544) and auto-elevates
       via UAC if required.
    2. Performs Pre-Flight Dependency & Environment Checks BEFORE modifying the
       system:
       - .NET Zip64 compression assembly (System.IO.Compression.FileSystem)
       - Hyper-V PowerShell module availability
       - Hyper-V Virtual Machine Management service (vmms) running state
       - Target VMs existence, state, and disk size audit (SQL2022, Unify,
         Elektrimont ESET Protect)
       - Drive availability and free disk space check on target volumes
    3. Unblocks all package .ps1 files and creates the directory structure:
       - Script installation folder (default: C:\Scripts\Backup-HyperVVM)
       - Backup destination folder (default: C:\DANE\Backup)
       - Audit log folder (default: C:\Logi)
    4. Deploys package files into C:\Scripts\Backup-HyperVVM and unblocks them.
    5. Calls Register-Backup-HyperVVM.ps1 to register 3 dedicated monthly
       Sunday Hot-backup tasks (SQL2022 -> 1st Sunday 14:00, Unify -> 2nd
       Sunday 14:00, Elektrimont ESET Protect -> 3rd Sunday 14:00) and enables
       Task Scheduler execution history.

.PARAMETER InstallDir
    Target installation directory where scripts will be deployed.
    Default: 'C:\Scripts\Backup-HyperVVM'.

.PARAMETER BackupPath
    Destination directory for VM backup archives/folders.
    Default: 'C:\DANE\Backup'.

.PARAMETER LogDir
    Directory for execution audit logs.
    Default: 'C:\Logi'.

.PARAMETER RetentionCount
    Number of valid backup copies per VM retained by the scheduled tasks.
    Default: 1.

.PARAMETER NoZip
    Switch parameter. Configures the scheduled tasks to use -NoZip (uncompressed
    folder, no password) instead of -NoEncrypt (unencrypted .zip, no password).

.PARAMETER ExpectedVMs
    List of expected Hyper-V VM names to verify during pre-flight checks.
    Default: @('SQL2022', 'Unify', 'Elektrimont ESET Protect').

.PARAMETER SkipTaskRegistration
    Switch parameter. Skips registering the scheduled tasks in Task Scheduler.

.PARAMETER ElevatedLaunch
    Internal switch used when relaunching with UAC elevation.

.PARAMETER Help
    Displays detailed help, parameter descriptions, usage examples, and author
    metadata. Alias: -h.

.EXAMPLE
    .\Install-Backup-HyperVVM.ps1
    Runs the full interactive installer, verifies Hyper-V & VMs, deploys to
    C:\Scripts\Backup-HyperVVM, creates C:\DANE\Backup and C:\Logi, and
    registers the 3 monthly Sunday scheduled tasks.

.EXAMPLE
    .\Install-Backup-HyperVVM.ps1 -BackupPath "D:\HyperV-Backup" -SkipTaskRegistration
    Deploys scripts and directories using D:\HyperV-Backup without creating
    scheduled tasks.

.EXAMPLE
    .\Install-Backup-HyperVVM.ps1 -Help
    Displays CLI help.

.NOTES
    Author       : Roman Pindela
    Email        : roman.pindela@gmail.com
    GitHub       : https://github.com/romanpindela
    Version      : 1.0.0
    Release Date : 2026-11-18
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param (
    [Parameter(Mandatory = $false, HelpMessage = 'Target installation directory for production scripts.')]
    [ValidateNotNullOrEmpty()]
    [string]$InstallDir = 'C:\Scripts\Backup-HyperVVM',

    [Parameter(Mandatory = $false, HelpMessage = 'Destination directory for VM backups.')]
    [ValidateNotNullOrEmpty()]
    [string]$BackupPath = 'C:\DANE\Backup',

    [Parameter(Mandatory = $false, HelpMessage = 'Directory for audit log files.')]
    [ValidateNotNullOrEmpty()]
    [string]$LogDir = 'C:\Logi',

    [Parameter(Mandatory = $false, HelpMessage = 'Number of valid backup copies per VM to retain.')]
    [ValidateRange(0, 3650)]
    [int]$RetentionCount = 1,

    [Parameter(Mandatory = $false, HelpMessage = 'Configure scheduled tasks with -NoZip instead of -NoEncrypt.')]
    [switch]$NoZip,

    [Parameter(Mandatory = $false, HelpMessage = 'Expected VM names verified during pre-flight checks.')]
    [string[]]$ExpectedVMs = @('SQL2022', 'Unify', 'Elektrimont ESET Protect'),

    [Parameter(Mandatory = $false, HelpMessage = 'Skip Windows Task Scheduler registration.')]
    [switch]$SkipTaskRegistration,

    [Parameter(Mandatory = $false, DontShow = $true)]
    [switch]$ElevatedLaunch,

    [Alias('h')]
    [Parameter(Mandatory = $false, HelpMessage = 'Displays help and script information.')]
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ==============================================================================
# 1. Handle -Help / -h parameter (Native Get-Help engine)
# ==============================================================================
if ($Help.IsPresent) {
    Get-Help -Name $MyInvocation.MyCommand.Path -Detailed
    exit 0
}

# ==============================================================================
# 2. Helper functions
# ==============================================================================
function Test-IsAdministrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
    $adminSid = [System.Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
    return $principal.IsInRole($adminSid)
}

function Write-StepMessage {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'SUCCESS', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    $ts = (Get-Date).ToString('HH:mm:ss')
    switch ($Level) {
        'INFO'    { Write-Host "[$ts] [INFO]    $Message" -ForegroundColor Cyan }
        'SUCCESS' { Write-Host "[$ts] [SUCCESS] $Message" -ForegroundColor Green }
        'WARN'    { Write-Host "[$ts] [WARN]    $Message" -ForegroundColor Yellow }
        'ERROR'   { Write-Host "[$ts] [ERROR]   $Message" -ForegroundColor Red }
    }
}

function Test-HyperVServerDependencies {
    param (
        [string[]]$TargetVMs,
        [string[]]$PathsToCheckSpace
    )

    Write-Host '------------------------------------------------------------------------' -ForegroundColor DarkCyan
    Write-Host '  PRE-FLIGHT DEPENDENCY & HYPER-V ENVIRONMENT CHECK' -ForegroundColor Cyan
    Write-Host '------------------------------------------------------------------------' -ForegroundColor DarkCyan

    $criticalMissing = $false

    # 1. Check native .NET Zip64 compression support
    try {
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        Write-StepMessage '[OK]      Native .NET Zip64 assemblies loaded successfully.' 'SUCCESS'
    }
    catch {
        Write-StepMessage "[MISSING] Failed to load .NET System.IO.Compression assemblies: $($_.Exception.Message)" 'ERROR'
        $criticalMissing = $true
    }

    # 2. Check Hyper-V PowerShell module
    $hvModule = Get-Module -ListAvailable -Name 'Hyper-V'
    if ($null -ne $hvModule) {
        Import-Module -Name 'Hyper-V' -ErrorAction Stop
        Write-StepMessage '[OK]      Hyper-V PowerShell module is available and imported.' 'SUCCESS'
    }
    else {
        Write-StepMessage '[MISSING] Hyper-V PowerShell module was not found (install Hyper-V role / RSAT-Hyper-V-Tools).' 'ERROR'
        $criticalMissing = $true
    }

    # 3. Check Hyper-V Virtual Machine Management service (vmms)
    $vmms = Get-Service -Name 'vmms' -ErrorAction SilentlyContinue
    if ($null -eq $vmms) {
        Write-StepMessage '[MISSING] Hyper-V Virtual Machine Management service (vmms) not found.' 'ERROR'
        $criticalMissing = $true
    }
    elseif ($vmms.Status -eq 'Running') {
        Write-StepMessage "[OK]      Hyper-V service 'vmms' is Running." 'SUCCESS'
    }
    else {
        Write-StepMessage "[WARN]    Hyper-V service 'vmms' is currently '$($vmms.Status)'." 'WARN'
    }

    # 4. Check expected target VMs and disk footprints
    $maxVmBytes = [int64]0
    if ($null -ne $hvModule -and $null -ne $vmms -and $vmms.Status -eq 'Running') {
        foreach ($vmName in $TargetVMs) {
            $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
            if ($null -eq $vm) {
                Write-StepMessage "[WARN]    Expected VM '$vmName' was NOT found on this host (verify exact VM name)." 'WARN'
            }
            else {
                $disks = @(Get-VMHardDiskDrive -VMName $vm.Name -ErrorAction SilentlyContinue)
                $vmBytes = [int64]0
                foreach ($d in $disks) {
                    if (-not [string]::IsNullOrWhiteSpace($d.Path) -and (Test-Path -Path $d.Path -PathType Leaf)) {
                        $vmBytes += [int64](Get-Item -Path $d.Path).Length
                    }
                }
                if ($vmBytes -gt $maxVmBytes) { $maxVmBytes = $vmBytes }
                $vmGB = [math]::Round(($vmBytes / 1GB), 2)
                $vss = Get-VMIntegrationService -VMName $vm.Name -Name 'VSS' -ErrorAction SilentlyContinue
                $vssState = if ($null -ne $vss) { "VSS=$($vss.Enabled)" } else { 'VSS=N/A' }
                Write-StepMessage "[OK]      VM '$($vm.Name)' found (State: $($vm.State), Disks: $($disks.Count) / ${vmGB} GB, $vssState)." 'SUCCESS'
            }
        }
    }

    # 5. Check Drive Availability & Free Disk Space
    $checkedDrives = @{}
    foreach ($p in $PathsToCheckSpace) {
        if ($p -like '\\*') {
            Write-StepMessage "[INFO]    UNC path '$p' configured; verify share free space and SYSTEM permissions manually." 'INFO'
            continue
        }
        $qualifier = Split-Path -Path $p -Qualifier
        if ([string]::IsNullOrWhiteSpace($qualifier)) { continue }
        if ($checkedDrives.ContainsKey($qualifier.ToUpper())) { continue }
        $checkedDrives[$qualifier.ToUpper()] = $true

        $driveLetter = $qualifier.TrimEnd(':')
        $psDrive = Get-PSDrive -Name $driveLetter -PSProvider FileSystem -ErrorAction SilentlyContinue
        if ($null -eq $psDrive) {
            Write-StepMessage "[MISSING] Target drive '$qualifier' (for '$p') does NOT exist or is not mounted." 'ERROR'
            $criticalMissing = $true
        }
        else {
            $freeGB = [math]::Round(($psDrive.Free / 1GB), 2)
            $recommendedMinBytes = [Math]::Max([int64](2GB), ($maxVmBytes + [int64](2GB)))
            $recGB = [math]::Round(($recommendedMinBytes / 1GB), 2)
            if ($psDrive.Free -lt $recommendedMinBytes) {
                Write-StepMessage "[WARN]    Drive '$qualifier' has $freeGB GB free (recommended >= $recGB GB for largest VM + 2 GB buffer)." 'WARN'
            }
            else {
                Write-StepMessage "[OK]      Drive '$qualifier' is mounted with $freeGB GB free space (>= $recGB GB recommended)." 'SUCCESS'
            }
        }
    }

    Write-Host '------------------------------------------------------------------------' -ForegroundColor DarkCyan

    if ($criticalMissing) {
        Write-Host ''
        Write-StepMessage 'One or more critical Hyper-V dependencies or target drives are missing!' 'ERROR'
        $continueChoice = Read-Host -Prompt 'Do you want to continue installation anyway? (Y/N)'
        if ($continueChoice -notmatch '^[YyTt]$') {
            throw 'Installation aborted by user due to missing critical dependencies.'
        }
    }
}

# ==============================================================================
# 3. UAC Elevation Check (SID S-1-5-32-544)
# ==============================================================================
if (-not (Test-IsAdministrator)) {
    Write-Host '[INFO] Administrator privileges are required (SID S-1-5-32-544). Requesting UAC elevation...' -ForegroundColor Yellow

    $relaunchArgs = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', "`"$($MyInvocation.MyCommand.Path)`"",
        '-InstallDir', "`"$InstallDir`"",
        '-BackupPath', "`"$BackupPath`"",
        '-LogDir', "`"$LogDir`"",
        '-RetentionCount', "$RetentionCount",
        '-ElevatedLaunch'
    )
    if ($NoZip.IsPresent) {
        $relaunchArgs += '-NoZip'
    }
    if ($SkipTaskRegistration.IsPresent) {
        $relaunchArgs += '-SkipTaskRegistration'
    }

    $pwshExe = (Get-Process -Id $PID).Path
    $elevatedProcess = Start-Process -FilePath $pwshExe -ArgumentList $relaunchArgs -Verb RunAs -PassThru -Wait
    exit $elevatedProcess.ExitCode
}

# ==============================================================================
# 4. Main Installation Workflow
# ==============================================================================
$exitCode = 0
$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent -Path $MyInvocation.MyCommand.Definition }
$resolvedSourceDir = (Resolve-Path -Path $scriptRoot).Path.TrimEnd('\')
$normalizedInstallDir = $InstallDir.TrimEnd('\')

try {
    Write-Host ''
    Write-Host '========================================================================' -ForegroundColor Cyan
    Write-Host '  Backup-HyperVVM - Hyper-V Server Installation & Task Setup Wizard' -ForegroundColor Cyan
    Write-Host '========================================================================' -ForegroundColor Cyan
    Write-StepMessage "Source package directory : $resolvedSourceDir" 'INFO'
    Write-StepMessage "Target install directory : $normalizedInstallDir" 'INFO'
    Write-StepMessage "Backup destination dir   : $BackupPath" 'INFO'
    Write-StepMessage "Audit logs directory     : $LogDir" 'INFO'
    Write-StepMessage "Retention per VM         : $RetentionCount valid copy (backup-first)" 'INFO'
    Write-StepMessage "Output format for tasks  : $(if ($NoZip) { 'Uncompressed Folder (-NoZip)' } else { 'Unencrypted ZIP (-NoEncrypt)' })" 'INFO'
    Write-Host ''

    # 4.1. Pre-flight Dependency & Hyper-V Check
    Write-StepMessage 'Step 1/5: Checking Hyper-V dependencies, VMs, and disk space...' 'INFO'
    Test-HyperVServerDependencies `
        -TargetVMs $ExpectedVMs `
        -PathsToCheckSpace @($normalizedInstallDir, $BackupPath, $LogDir)

    # 4.2. Validate and unblock package files in source directory
    Write-StepMessage 'Step 2/5: Validating and unblocking source package files...' 'INFO'
    $requiredFiles = @(
        'Backup-HyperVVM.ps1',
        'Register-Backup-HyperVVM.ps1'
    )
    foreach ($fileName in $requiredFiles) {
        $srcPath = Join-Path -Path $resolvedSourceDir -ChildPath $fileName
        if (-not (Test-Path -Path $srcPath -PathType Leaf)) {
            throw "Required package file not found in source directory: '$srcPath'"
        }
    }

    Get-ChildItem -Path $resolvedSourceDir -Filter '*.ps1' -File | ForEach-Object {
        Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue
    }
    Write-StepMessage 'Source scripts validated and unblocked.' 'SUCCESS'

    # 4.3. Create required directory structure
    Write-StepMessage 'Step 3/5: Creating required directory structure...' 'INFO'
    $directoriesToCreate = @($normalizedInstallDir, $BackupPath, $LogDir)
    foreach ($dirPath in $directoriesToCreate) {
        if (-not (Test-Path -Path $dirPath)) {
            if ($PSCmdlet.ShouldProcess($dirPath, 'Create directory')) {
                New-Item -ItemType Directory -Path $dirPath -Force | Out-Null
                Write-StepMessage "Created directory: $dirPath" 'SUCCESS'
            }
        }
        else {
            Write-StepMessage "Directory already exists: $dirPath" 'INFO'
        }
    }

    # 4.4. Deploy files into InstallDir
    Write-StepMessage "Step 4/5: Deploying script files to '$normalizedInstallDir'..." 'INFO'
    $filesToDeploy = @(
        'Backup-HyperVVM.ps1',
        'Decrypt-HyperVBackup.ps1',
        'Register-Backup-HyperVVM.ps1',
        'Install-Backup-HyperVVM.ps1',
        'README.md'
    )

    if ($resolvedSourceDir -ieq $normalizedInstallDir) {
        Write-StepMessage 'Source and install directories are identical. Skipping file copy.' 'INFO'
    }
    else {
        foreach ($fileName in $filesToDeploy) {
            $srcFile = Join-Path -Path $resolvedSourceDir -ChildPath $fileName
            $dstFile = Join-Path -Path $normalizedInstallDir -ChildPath $fileName
            if (Test-Path -Path $srcFile -PathType Leaf) {
                if ($PSCmdlet.ShouldProcess($dstFile, 'Copy package file')) {
                    Copy-Item -Path $srcFile -Destination $dstFile -Force
                    if ($fileName -like '*.ps1') {
                        Unblock-File -Path $dstFile -ErrorAction SilentlyContinue
                    }
                    Write-StepMessage "Deployed: $dstFile" 'SUCCESS'
                }
            }
        }
    }

    # 4.5. Register Scheduled Tasks & Enable Execution History
    $deployedBackupScript = Join-Path -Path $normalizedInstallDir -ChildPath 'Backup-HyperVVM.ps1'
    $deployedRegisterScript = Join-Path -Path $normalizedInstallDir -ChildPath 'Register-Backup-HyperVVM.ps1'

    if ($SkipTaskRegistration.IsPresent) {
        Write-StepMessage 'Step 5/5: Skipping Scheduled Task registration (-SkipTaskRegistration specified).' 'WARN'
    }
    else {
        Write-StepMessage 'Step 5/5: Registering monthly Sunday Scheduled Tasks and enabling Task History...' 'INFO'
        if ($PSCmdlet.ShouldProcess('Backup-HyperVVM Tasks', 'Register monthly Hyper-V VM backup scheduled tasks')) {
            & $deployedRegisterScript `
                -ScriptPath $deployedBackupScript `
                -BackupPath $BackupPath `
                -LogDir $LogDir `
                -RetentionCount $RetentionCount `
                -NoZip:$NoZip
            Write-StepMessage 'All monthly Hyper-V VM backup tasks configured and Task History enabled.' 'SUCCESS'
        }
    }

    # Final Summary
    $formatFlag = if ($NoZip) { '-NoZip' } else { '-NoEncrypt' }
    Write-Host ''
    Write-Host '========================================================================' -ForegroundColor Green
    Write-Host '  INSTALLATION COMPLETED SUCCESSFULLY' -ForegroundColor Green
    Write-Host '========================================================================' -ForegroundColor Green
    Write-Host "  Installed Script  : $deployedBackupScript" -ForegroundColor White
    Write-Host "  Register Script   : $deployedRegisterScript" -ForegroundColor White
    Write-Host "  Backup Destination: $BackupPath (Retention: $RetentionCount copy per VM)" -ForegroundColor White
    Write-Host "  Audit Logs        : $LogDir" -ForegroundColor White
    Write-Host "  Scheduled Tasks   : (NT AUTHORITY\SYSTEM, Highest Privileges)" -ForegroundColor White
    Write-Host '    - Backup-HyperVVM-SQL2022                  -> 1st Sunday at 14:00' -ForegroundColor Gray
    Write-Host '    - Backup-HyperVVM-Unify                    -> 2nd Sunday at 14:00' -ForegroundColor Gray
    Write-Host '    - Backup-HyperVVM-Elektrimont-ESET-Protect -> 3rd Sunday at 14:00' -ForegroundColor Gray
    Write-Host '  Task History      : Enabled (Microsoft-Windows-TaskScheduler/Operational)' -ForegroundColor White
    Write-Host ''
    Write-Host '  Next Step (Recommended Safe -WhatIf Test):' -ForegroundColor Cyan
    Write-Host "      & `"$deployedBackupScript`" -VMName `"SQL2022`" -BackupMode Hot $formatFlag -BackupPath `"$BackupPath`" -WhatIf" -ForegroundColor White
    Write-Host '========================================================================' -ForegroundColor Green
    Write-Host ''
}
catch {
    Write-StepMessage "Installation failed: $_" 'ERROR'
    $exitCode = 1
}
finally {
    if ($ElevatedLaunch.IsPresent) {
        Write-Host ''
        Read-Host -Prompt 'Press Enter to close this elevated installer window' | Out-Null
    }
    exit $exitCode
}

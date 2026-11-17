<#
================================================================================
  Script Name : Backup-HyperVVM.ps1
  Author      : Roman Pindela
  Contact     : roman.pindela@gmail.com
  Version     : 1.0.0
  Release Date: 2026-11-17
  License     : MIT
  Repository  : https://github.com/romanpindela/Windows-Server

  DESCRIPTION:
    Enterprise-grade PowerShell automation tool for creating complete,
    self-contained, AES-256 password-protected ZIP backups of Hyper-V virtual
    machines on Windows Server (2016/2019/2022/2025) and Windows 10/11 Pro.

    Key Capabilities:
    1. Zero-Parameter Interactive Help (-Help / -h):
       Displays complete syntax, parameter reference, security guidance, and
       usage examples when run without arguments or with -Help, without
       triggering an unnecessary UAC elevation prompt.
    2. Hot & Cold Backup Modes (-BackupMode Hot | Cold):
       - Hot: Exports the running VM live without downtime via Export-VM.
       - Cold: Gracefully shuts down the VM (with configurable timeout and
         optional -ForceShutdown), exports a clean offline state, and
         automatically restarts the VM afterward (unless -KeepStopped is set).
    3. Complete Self-Contained Recovery Package:
       Includes the full Hyper-V Export-VM structure (Virtual Machines/*.vmcx,
       Virtual Hard Disks/*.vhdx, Snapshots/*), hardware/vSwitch metadata
       (VM-Metadata.json), step-by-step RESTORE-INSTRUCTIONS.txt, and copy
       execution logs (Backup-Copy.log).
    4. Secure AES-256 Encrypted ZIP Archiving:
       Accepts a [SecureString] password (-ZipPassword) or prompts securely via
       Read-Host -AsSecureString. Uses 7-Zip (7z.exe) with AES-256 ZIP
       encryption, verifies archive integrity, and securely clears in-memory
       BSTR credentials in finally {}.
    5. Multi-Language UAC Auto-Elevation:
       Verifies Administrator privileges using the well-known Windows SID
       (S-1-5-32-544 / BuiltInAdministratorsSid) for 100% compatibility across
       Polish and English Windows editions.
    6. Detailed Audit Logging:
       Writes UTF-8 timestamped logs to:
       C:\Logs\<yyyyMMdd-HHmmss>-Backup-HyperVVM-<ComputerName>-<UserName>.logs
================================================================================
#>

<#
.SYNOPSIS
    Creates a complete, AES-256 password-protected ZIP backup of one or more
    Hyper-V virtual machines in Hot or Cold mode.

.DESCRIPTION
    Automates full Hyper-V virtual machine backup on a Hyper-V host:
    - Validates Administrator privileges via SID S-1-5-32-544.
    - Supports single or multiple VMs via -VMName or pipeline input.
    - Supports Hot backup (live Export-VM) and Cold backup (graceful shutdown,
      Export-VM, and automatic restart in try/finally).
    - Exports all VM configuration files, virtual hard disks, and checkpoints.
    - Generates VM-Metadata.json and RESTORE-INSTRUCTIONS.txt tailored to the
      backed-up VM inside the archive.
    - Includes Backup-Copy.log inside the archive and writes full audit logs
      to C:\Logs\.
    - Compresses the entire package into an AES-256 encrypted .zip archive in
      C:\DANE\Backup using 7-Zip and verifies archive integrity.

.PARAMETER VMName
    One or more Hyper-V virtual machine names to back up. Supports pipeline input.
    Aliases: -Name

.PARAMETER BackupMode
    Backup mode: 'Hot' (live export without stopping the VM) or 'Cold' (stops
    the VM before export and restarts it afterward unless -KeepStopped is set).
    Default: 'Hot'.
    Aliases: -Mode

.PARAMETER BackupPath
    Destination directory for the final encrypted ZIP backup archives.
    Default: 'C:\DANE\Backup'.

.PARAMETER ZipPassword
    Encryption password as a [SecureString]. If omitted during interactive runs,
    the script prompts securely via Read-Host -AsSecureString.
    Aliases: -Password

.PARAMETER CompressionLevel
    7-Zip compression level from 0 (Store/Copy) to 9 (Ultra). Default: 5.

.PARAMETER SevenZipPath
    Optional explicit path to 7z.exe. Auto-detected from PATH or standard
    Program Files locations if omitted.

.PARAMETER KeepStopped
    Switch parameter (Cold mode only). Leaves the VM powered off after backup
    even if it was running prior to the backup.

.PARAMETER ShutdownTimeoutSeconds
    Maximum time in seconds to wait for graceful VM shutdown in Cold mode.
    Default: 300.

.PARAMETER ForceShutdown
    Switch parameter (Cold mode only). Forces VM power-off (Stop-VM -TurnOff)
    if graceful shutdown does not complete within ShutdownTimeoutSeconds.

.PARAMETER KeepUncompressed
    Switch parameter. Retains the uncompressed staging directory after creating
    and verifying the ZIP archive.

.PARAMETER SkipArchiveVerification
    Switch parameter. Skips the post-compression '7z.exe t' integrity check.

.PARAMETER LogPath
    Custom file path for the execution log file.
    Default: C:\Logs\<yyyyMMdd-HHmmss>-Backup-HyperVVM-<ComputerName>-<UserName>.logs
    Aliases: -l, -Log

.PARAMETER NoLog
    Switch parameter. Disables writing execution logs to disk.

.PARAMETER SkipAdminCheck
    Switch parameter. Skips automatic UAC Administrator privilege verification.

.PARAMETER PassThru
    Switch parameter. Returns structured [PSCustomObject] backup results to the
    PowerShell pipeline.

.PARAMETER Help
    Switch parameter (-Help / -h). Displays this help guide and exits safely.

.EXAMPLE
    C:\Scripts\Backup-HyperVVM.ps1
    Displays the built-in help screen without elevating or modifying anything.

.EXAMPLE
    $pwd = Read-Host "Enter ZIP Password" -AsSecureString
    C:\Scripts\Backup-HyperVVM.ps1 -VMName "DC01" -BackupMode Cold -ZipPassword $pwd
    Performs a Cold backup of DC01, includes restore instructions and copy logs,
    and saves an AES-256 encrypted ZIP archive to C:\DANE\Backup.

.EXAMPLE
    C:\Scripts\Backup-HyperVVM.ps1 -VMName "APP01","SQL01" -BackupMode Hot -CompressionLevel 3
    Performs a Hot backup of APP01 and SQL01, prompting securely for the ZIP password.

.NOTES
    Author       : Roman Pindela
    Email        : roman.pindela@gmail.com
    GitHub       : https://github.com/romanpindela
    Version      : 1.0.0
    Last Modified: 2026-11-17
    Deployment   : Recommended location on Hyper-V host: C:\Scripts\Backup-HyperVVM.ps1
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param (
    [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
    [Alias('Name')]
    [ValidateNotNullOrEmpty()]
    [string[]]$VMName,

    [Parameter()]
    [Alias('Mode')]
    [ValidateSet('Hot', 'Cold')]
    [string]$BackupMode = 'Hot',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$BackupPath = 'C:\DANE\Backup',

    [Parameter()]
    [Alias('Password')]
    [SecureString]$ZipPassword,

    [Parameter()]
    [ValidateRange(0, 9)]
    [int]$CompressionLevel = 5,

    [Parameter()]
    [string]$SevenZipPath,

    [Parameter()]
    [switch]$KeepStopped,

    [Parameter()]
    [ValidateRange(10, 3600)]
    [int]$ShutdownTimeoutSeconds = 300,

    [Parameter()]
    [switch]$ForceShutdown,

    [Parameter()]
    [switch]$KeepUncompressed,

    [Parameter()]
    [switch]$SkipArchiveVerification,

    [Parameter()]
    [Alias('l', 'Log')]
    [ValidateNotNullOrEmpty()]
    [string]$LogPath,

    [Parameter()]
    [switch]$NoLog,

    [Parameter()]
    [switch]$SkipAdminCheck,

    [Parameter()]
    [switch]$PassThru,

    [Parameter()]
    [Alias('h')]
    [switch]$Help
)

begin {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $ScriptVersion = '1.0.0'
    $ScriptName = 'Backup-HyperVVM'
    $RunTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

    #region Helper Functions

    function Show-ScriptHelp {
        [CmdletBinding()]
        param ()

        Write-Host ''
        Write-Host '================================================================================' -ForegroundColor Cyan
        Write-Host "  $ScriptName.ps1  (v$ScriptVersion)" -ForegroundColor White
        Write-Host '  Complete Hyper-V VM Hot/Cold Backup with AES-256 Encrypted ZIP & Restore Guide' -ForegroundColor Gray
        Write-Host '================================================================================' -ForegroundColor Cyan
        Write-Host ''
        Write-Host 'SYNTAX:' -ForegroundColor Yellow
        Write-Host '  .\Backup-HyperVVM.ps1 -VMName <string[]> [-BackupMode Hot|Cold]' -ForegroundColor White
        Write-Host '                        [-BackupPath <string>] [-ZipPassword <SecureString>]' -ForegroundColor White
        Write-Host '                        [-CompressionLevel 0..9] [-KeepStopped] [-ForceShutdown]' -ForegroundColor White
        Write-Host '                        [-KeepUncompressed] [-LogPath <string>] [-NoLog] [-PassThru]' -ForegroundColor White
        Write-Host '  .\Backup-HyperVVM.ps1 [-Help | -h]' -ForegroundColor White
        Write-Host ''
        Write-Host 'PARAMETERS:' -ForegroundColor Yellow
        Write-Host '  -VMName <string[]>          Target Hyper-V VM name(s) (aliases: -Name; pipeline supported)'
        Write-Host '  -BackupMode <Hot|Cold>      Hot = live export; Cold = stop VM, export, restart (default: Hot)'
        Write-Host '  -BackupPath <string>        Target folder for encrypted ZIPs (default: C:\DANE\Backup)'
        Write-Host '  -ZipPassword <SecureString> Encryption password; prompts securely if omitted'
        Write-Host '  -CompressionLevel <0-9>     7-Zip compression level (default: 5)'
        Write-Host '  -SevenZipPath <string>      Explicit path to 7z.exe (auto-detected by default)'
        Write-Host '  -KeepStopped                (Cold mode) Do not restart VM after backup'
        Write-Host '  -ShutdownTimeoutSeconds     Graceful shutdown wait in seconds (default: 300)'
        Write-Host '  -ForceShutdown              Force TurnOff if graceful shutdown times out'
        Write-Host '  -KeepUncompressed           Keep staging folder after ZIP creation'
        Write-Host '  -SkipArchiveVerification    Skip 7-Zip archive integrity test'
        Write-Host '  -LogPath <string>           Custom log path (default: C:\Logs\<timestamp>-Backup-HyperVVM-*.logs)'
        Write-Host '  -NoLog                      Disable disk logging'
        Write-Host '  -PassThru                   Output structured [PSCustomObject] results to pipeline'
        Write-Host '  -Help / -h                  Display this help screen and exit'
        Write-Host ''
        Write-Host 'SECURE PASSWORD EXAMPLES:' -ForegroundColor Yellow
        Write-Host '  # Interactive secure prompt (recommended):' -ForegroundColor DarkGray
        Write-Host '  $pwd = Read-Host "Enter ZIP Password" -AsSecureString' -ForegroundColor Green
        Write-Host '  C:\Scripts\Backup-HyperVVM.ps1 -VMName "DC01" -BackupMode Cold -ZipPassword $pwd' -ForegroundColor Green
        Write-Host ''
        Write-Host '  # Scheduled Task (DPAPI per-user/machine encrypted secret):' -ForegroundColor DarkGray
        Write-Host '  # 1. Save once: Read-Host -AsSecureString | Export-Clixml C:\Scripts\zip.cred' -ForegroundColor DarkGray
        Write-Host '  # 2. Load:      $pwd = Import-Clixml C:\Scripts\zip.cred' -ForegroundColor Green
        Write-Host '  C:\Scripts\Backup-HyperVVM.ps1 -VMName "APP01","DB01" -BackupMode Hot -ZipPassword $pwd' -ForegroundColor Green
        Write-Host ''
        Write-Host 'AUTHOR:' -ForegroundColor Yellow
        Write-Host '  Roman Pindela | roman.pindela@gmail.com | https://github.com/romanpindela' -ForegroundColor Gray
        Write-Host ''
    }

    function Test-IsAdministrator {
        [CmdletBinding()]
        [OutputType([bool])]
        param ()

        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
        $adminSid = [System.Security.Principal.SecurityIdentifier]::new(
            [System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid,
            $null
        )
        return $principal.IsInRole($adminSid)
    }

    function Invoke-UacElevation {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [hashtable]$BoundParameters
        )

        if ($BoundParameters.ContainsKey('ZipPassword')) {
            throw 'Script is not running as Administrator. Because -ZipPassword is a [SecureString], it cannot be forwarded across a UAC relaunch. Please open an elevated PowerShell session and re-run the command.'
        }

        $argList = [System.Collections.Generic.List[string]]::new()
        $argList.Add('-NoProfile')
        $argList.Add('-ExecutionPolicy')
        $argList.Add('Bypass')
        $argList.Add('-File')
        $argList.Add("`"$PSCommandPath`"")

        foreach ($entry in $BoundParameters.GetEnumerator()) {
            $key = $entry.Key
            $val = $entry.Value
            if ($val -is [switch]) {
                if ($val.IsPresent) {
                    $argList.Add("-$key")
                }
            }
            elseif ($val -is [array]) {
                $joined = ($val | ForEach-Object { "`"$_`"" }) -join ','
                $argList.Add("-$key")
                $argList.Add($joined)
            }
            else {
                $argList.Add("-$key")
                $argList.Add("`"$val`"")
            }
        }

        $pwshExe = (Get-Process -Id $PID).Path
        Write-Host '[INFO] Administrator privileges required (SID S-1-5-32-544). Requesting UAC elevation...' -ForegroundColor Yellow
        $proc = Start-Process -FilePath $pwshExe -ArgumentList $argList -Verb RunAs -PassThru -Wait
        exit $proc.ExitCode
    }

    function Write-Log {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$Message,

            [Parameter()]
            [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')]
            [string]$Level = 'INFO',

            [Parameter()]
            [string]$FilePath,

            [Parameter()]
            [switch]$DisableDiskLog
        )

        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $formatted = "[$timestamp] [$Level] $Message"

        switch ($Level) {
            'INFO'    { Write-Host $formatted -ForegroundColor Cyan }
            'WARN'    { Write-Host $formatted -ForegroundColor Yellow }
            'ERROR'   { Write-Host $formatted -ForegroundColor Red }
            'SUCCESS' { Write-Host $formatted -ForegroundColor Green }
        }

        if (-not $DisableDiskLog -and -not [string]::IsNullOrWhiteSpace($FilePath)) {
            $parentDir = Split-Path -Path $FilePath -Parent
            if (-not (Test-Path -Path $parentDir)) {
                New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
            }
            Add-Content -Path $FilePath -Value $formatted -Encoding UTF8
        }
    }

    function Resolve-SevenZipExecutable {
        [CmdletBinding()]
        [OutputType([string])]
        param (
            [Parameter()]
            [string]$ExplicitPath
        )

        if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
            if (Test-Path -Path $ExplicitPath -PathType Leaf) {
                return (Resolve-Path -Path $ExplicitPath).Path
            }
            throw "7-Zip executable not found at specified path: $ExplicitPath"
        }

        $cmd = Get-Command -Name '7z.exe' -ErrorAction SilentlyContinue
        if ($null -ne $cmd) {
            return $cmd.Source
        }

        $candidates = @(
            "$env:ProgramFiles\7-Zip\7z.exe",
            "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
            "$env:ProgramData\chocolatey\bin\7z.exe"
        )

        foreach ($candidate in $candidates) {
            if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -Path $candidate -PathType Leaf)) {
                return $candidate
            }
        }

        throw '7-Zip (7z.exe) is required for AES-256 password-protected ZIP creation but was not found. Install 7-Zip or pass -SevenZipPath.'
    }

    function ConvertFrom-SecureStringToPlainText {
        [CmdletBinding()]
        [OutputType([string])]
        param (
            [Parameter(Mandatory = $true)]
            [SecureString]$SecureValue
        )

        $bstr = [System.IntPtr]::Zero
        try {
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
            return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        }
        finally {
            if ($bstr -ne [System.IntPtr]::Zero) {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
        }
    }

    function Export-HyperVVMMetadata {
        [CmdletBinding()]
        [OutputType([pscustomobject])]
        param (
            [Parameter(Mandatory = $true)]
            [Microsoft.HyperV.PowerShell.VirtualMachine]$VM,

            [Parameter(Mandatory = $true)]
            [string]$OutputJsonPath
        )

        $disks = @(Get-VMHardDiskDrive -VMName $VM.Name | ForEach-Object {
                [PSCustomObject]@{
                    ControllerType   = $_.ControllerType.ToString()
                    ControllerNumber = $_.ControllerNumber
                    ControllerLocation = $_.ControllerLocation
                    Path             = $_.Path
                }
            })

        $nics = @(Get-VMNetworkAdapter -VMName $VM.Name | ForEach-Object {
                [PSCustomObject]@{
                    Name            = $_.Name
                    SwitchName      = $_.SwitchName
                    MacAddress      = $_.MacAddress
                    DynamicMac      = $_.DynamicMacAddressEnabled
                    VlanSetting     = (Get-VMNetworkAdapterVlan -VMNetworkAdapter $_ -ErrorAction SilentlyContinue).OperationMode
                }
            })

        $snapshots = @(Get-VMSnapshot -VMName $VM.Name -ErrorAction SilentlyContinue | ForEach-Object {
                [PSCustomObject]@{
                    Name         = $_.Name
                    CreationTime = $_.CreationTime.ToString('o')
                    SnapshotType = $_.SnapshotType.ToString()
                }
            })

        $metadata = [PSCustomObject]@{
            VMName              = $VM.Name
            VMId                = $VM.Id.ToString()
            Generation          = $VM.Generation
            Version             = $VM.Version
            ProcessorCount      = $VM.ProcessorCount
            MemoryStartupBytes  = $VM.MemoryStartup
            DynamicMemoryEnabled = $VM.DynamicMemoryEnabled
            OriginalState       = $VM.State.ToString()
            HostComputerName    = $env:COMPUTERNAME
            ExportedAtUtc       = (Get-Date).ToUniversalTime().ToString('o')
            HardDisks           = $disks
            NetworkAdapters     = $nics
            Checkpoints         = $snapshots
        }

        $metadata | ConvertTo-Json -Depth 5 | Set-Content -Path $OutputJsonPath -Encoding UTF8
        return $metadata
    }

    function New-RestoreInstructionFile {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [pscustomobject]$Metadata,

            [Parameter(Mandatory = $true)]
            [string]$BackupModeUsed,

            [Parameter(Mandatory = $true)]
            [string]$ArchiveFileName,

            [Parameter(Mandatory = $true)]
            [string]$OutputPath
        )

        $vmName = $Metadata.VMName
        $vmId = $Metadata.VMId
        $nicSummary = if ($Metadata.NetworkAdapters.Count -gt 0) {
            ($Metadata.NetworkAdapters | ForEach-Object {
                "  - Adapter: $($_.Name) | vSwitch: $($_.SwitchName) | MAC: $($_.MacAddress)"
            }) -join "`r`n"
        }
        else {
            '  - None configured'
        }

        $diskSummary = if ($Metadata.HardDisks.Count -gt 0) {
            ($Metadata.HardDisks | ForEach-Object {
                "  - $($_.ControllerType) $($_.ControllerNumber):$($_.ControllerLocation) -> $($_.Path)"
            }) -join "`r`n"
        }
        else {
            '  - None configured'
        }

        $content = @"
================================================================================
  HYPER-V VIRTUAL MACHINE RESTORE INSTRUCTIONS
================================================================================
  VM Name          : $vmName
  Original VM ID   : $vmId
  Source Host      : $($Metadata.HostComputerName)
  Backup Mode      : $BackupModeUsed
  Original State   : $($Metadata.OriginalState)
  Generation       : $($Metadata.Generation)
  Exported (UTC)   : $($Metadata.ExportedAtUtc)
  Archive File     : $ArchiveFileName

  ORIGINAL NETWORK ADAPTERS:
$nicSummary

  ORIGINAL VIRTUAL DISKS:
$diskSummary
================================================================================

1. EXTRACT THE BACKUP ARCHIVE
--------------------------------------------------------------------------------
Extract the AES-256 encrypted ZIP archive using 7-Zip (built-in Windows Explorer
cannot decrypt AES-256 ZIP archives):
  7z.exe x "$ArchiveFileName" -o"C:\Restore\$vmName"

Inside "C:\Restore\$vmName\$vmName\" you will find:
  - Virtual Machines\      (.vmcx, .vmrs, .vmgs configuration files)
  - Virtual Hard Disks\    (.vhdx / .vhd / .avhdx disk files)
  - Snapshots\             (checkpoints, if any existed at backup time)

2. OPTION A: RESTORE IN-PLACE / MOVE TO NEW HOST (PowerShell - As Administrator)
--------------------------------------------------------------------------------
Use this when restoring a deleted VM or moving to another Hyper-V host while
preserving the original VM ID and copying files into Hyper-V's default storage:

  `$vmcx = Get-ChildItem "C:\Restore\$vmName\$vmName\Virtual Machines\*.vmcx" | Select-Object -First 1
  Import-VM -Path `$vmcx.FullName -Copy
  Start-VM -Name "$vmName"

3. OPTION B: CLONE SIDE-BY-SIDE ON THE SAME HOST (PowerShell - As Administrator)
--------------------------------------------------------------------------------
Use -GenerateNewId when the original VM still exists on the host to avoid
VM ID collisions:

  `$vmcx = Get-ChildItem "C:\Restore\$vmName\$vmName\Virtual Machines\*.vmcx" | Select-Object -First 1
  `$cloned = Import-VM -Path `$vmcx.FullName -Copy -GenerateNewId
  Rename-VM -VM `$cloned -NewName "${vmName}-Restored"
  Start-VM -VM `$cloned

4. OPTION C: RESTORE VIA HYPER-V MANAGER (GUI)
--------------------------------------------------------------------------------
  1. Open Hyper-V Manager (virtmgmt.msc) as Administrator.
  2. Click "Import Virtual Machine..." in the right Actions pane.
  3. Browse to: C:\Restore\$vmName\$vmName
  4. Select "$vmName" and choose an Import Type:
     - "Restore the virtual machine (use the existing unique ID)" -> Option A
     - "Copy the virtual machine (create a new unique ID)"        -> Option B
  5. If restoring to a different host, map the Virtual Switch (vSwitch) when
     prompted (see ORIGINAL NETWORK ADAPTERS above).
  6. Complete the wizard and start the virtual machine.

5. VERIFICATION CHECKLIST AFTER RESTORE
--------------------------------------------------------------------------------
  [ ] Confirm Virtual Switch connectivity (Get-VMNetworkAdapter -VMName "$vmName")
  [ ] Verify VM boots cleanly and Integration Services are active
  [ ] Remove temporary extracted files from C:\Restore\$vmName once verified
================================================================================
"@

        Set-Content -Path $OutputPath -Value $content -Encoding UTF8
    }

    function Compress-BackupWithPassword {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$SevenZipExe,

            [Parameter(Mandatory = $true)]
            [string]$SourceDirectory,

            [Parameter(Mandatory = $true)]
            [string]$DestinationZipPath,

            [Parameter(Mandatory = $true)]
            [SecureString]$Password,

            [Parameter(Mandatory = $true)]
            [int]$Level,

            [Parameter()]
            [switch]$SkipVerify
        )

        $plainPwd = $null
        try {
            $plainPwd = ConvertFrom-SecureStringToPlainText -SecureValue $Password
            if ([string]::IsNullOrEmpty($plainPwd)) {
                throw 'ZIP encryption password cannot be empty.'
            }

            if (Test-Path -Path $DestinationZipPath) {
                Remove-Item -Path $DestinationZipPath -Force
            }

            $sourceGlob = Join-Path -Path $SourceDirectory -ChildPath '*'
            $addArgs = @(
                'a',
                '-tzip',
                '-mem=AES256',
                "-mx=$Level",
                "-p$plainPwd",
                $DestinationZipPath,
                $sourceGlob
            )

            $addOutput = & $SevenZipExe @addArgs 2>&1
            if ($LASTEXITCODE -ne 0) {
                $errDetail = ($addOutput | Out-String).Trim()
                throw "7-Zip compression failed with exit code $LASTEXITCODE. Details: $errDetail"
            }

            if (-not $SkipVerify) {
                $testArgs = @(
                    't',
                    "-p$plainPwd",
                    $DestinationZipPath
                )
                $testOutput = & $SevenZipExe @testArgs 2>&1
                if ($LASTEXITCODE -ne 0) {
                    $errDetail = ($testOutput | Out-String).Trim()
                    throw "7-Zip integrity verification failed with exit code $LASTEXITCODE. Details: $errDetail"
                }
            }
        }
        finally {
            $plainPwd = $null
            [System.GC]::Collect()
        }
    }

    function Backup-SingleHyperVVM {
        [CmdletBinding(SupportsShouldProcess = $true)]
        [OutputType([pscustomobject])]
        param (
            [Parameter(Mandatory = $true)]
            [string]$Name,

            [Parameter(Mandatory = $true)]
            [string]$Mode,

            [Parameter(Mandatory = $true)]
            [string]$TargetBackupDir,

            [Parameter(Mandatory = $true)]
            [SecureString]$Password,

            [Parameter(Mandatory = $true)]
            [string]$SevenZipExe,

            [Parameter(Mandatory = $true)]
            [int]$Level,

            [Parameter()]
            [switch]$LeaveStopped,

            [Parameter(Mandatory = $true)]
            [int]$StopTimeoutSec,

            [Parameter()]
            [switch]$ForceStop,

            [Parameter()]
            [switch]$RetainStaging,

            [Parameter()]
            [switch]$SkipVerify,

            [Parameter()]
            [string]$GlobalLogPath,

            [Parameter()]
            [switch]$DisableDiskLog
        )

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $vm = Get-VM -Name $Name -ErrorAction Stop
        $originalState = $vm.State.ToString()
        $vmTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $safeVmName = $vm.Name -replace '[\\/:*?"<>|]', '_'
        $stagingDir = Join-Path -Path $TargetBackupDir -ChildPath "_staging_${safeVmName}_${vmTimestamp}"
        $zipFileName = "${safeVmName}_${vmTimestamp}.zip"
        $zipFullPath = Join-Path -Path $TargetBackupDir -ChildPath $zipFileName
        $vmCopyLogLines = [System.Collections.Generic.List[string]]::new()

        $addVmLog = {
            param([string]$Msg, [string]$Lvl = 'INFO')
            $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Lvl] $Msg"
            $vmCopyLogLines.Add($line)
            Write-Log -Message "[$($vm.Name)] $Msg" -Level $Lvl -FilePath $GlobalLogPath -DisableDiskLog:$DisableDiskLog
        }

        $wasStoppedByScript = $false
        $status = 'Success'
        $errorMessage = $null

        try {
            & $addVmLog "Starting $Mode backup (Original State: $originalState)" 'INFO'

            if (-not $PSCmdlet.ShouldProcess($vm.Name, "Perform $Mode Hyper-V backup to $zipFullPath")) {
                return [PSCustomObject]@{
                    VMName         = $vm.Name
                    BackupMode     = $Mode
                    OriginalState  = $originalState
                    FinalState     = $originalState
                    ArchivePath    = $zipFullPath
                    ArchiveSizeMB  = 0
                    DurationSec    = 0
                    Status         = 'WhatIf'
                    Error          = $null
                }
            }

            New-Item -Path $stagingDir -ItemType Directory -Force | Out-Null

            # Step 1: Cold backup shutdown if required
            if ($Mode -eq 'Cold' -and $originalState -eq 'Running') {
                & $addVmLog "Stopping VM gracefully (timeout: ${StopTimeoutSec}s)..." 'INFO'
                Stop-VM -Name $vm.Name -Force -ErrorAction Stop

                $waitElapsed = 0
                while ((Get-VM -Name $vm.Name).State -ne 'Off' -and $waitElapsed -lt $StopTimeoutSec) {
                    Start-Sleep -Seconds 2
                    $waitElapsed += 2
                }

                if ((Get-VM -Name $vm.Name).State -ne 'Off') {
                    if ($ForceStop) {
                        & $addVmLog 'Graceful shutdown timed out; forcing power off (TurnOff)...' 'WARN'
                        Stop-VM -Name $vm.Name -TurnOff -Force -ErrorAction Stop
                    }
                    else {
                        throw "VM '$($vm.Name)' did not shut down within $StopTimeoutSec seconds. Re-run with -ForceShutdown to force power off."
                    }
                }

                $wasStoppedByScript = $true
                & $addVmLog 'VM is now powered off.' 'SUCCESS'
            }

            # Step 2: Export full VM (config, VHDX, checkpoints)
            & $addVmLog "Exporting full VM package to staging folder '$stagingDir'..." 'INFO'
            Export-VM -Name $vm.Name -Path $stagingDir -ErrorAction Stop
            & $addVmLog 'Export-VM completed successfully.' 'SUCCESS'

            # Step 3: Restart VM immediately after export if Cold mode stopped it
            if ($wasStoppedByScript -and -not $LeaveStopped) {
                & $addVmLog 'Restarting VM after Cold export...' 'INFO'
                Start-VM -Name $vm.Name -ErrorAction Stop
                $wasStoppedByScript = $false
                & $addVmLog 'VM restarted successfully.' 'SUCCESS'
            }

            # Step 4: Metadata & Restore Instructions
            $metadataPath = Join-Path -Path $stagingDir -ChildPath 'VM-Metadata.json'
            $metadata = Export-HyperVVMMetadata -VM $vm -OutputJsonPath $metadataPath
            & $addVmLog 'Captured VM hardware and vSwitch metadata (VM-Metadata.json).' 'INFO'

            $restoreDocPath = Join-Path -Path $stagingDir -ChildPath 'RESTORE-INSTRUCTIONS.txt'
            New-RestoreInstructionFile -Metadata $metadata -BackupModeUsed $Mode -ArchiveFileName $zipFileName -OutputPath $restoreDocPath
            & $addVmLog 'Generated restore instructions (RESTORE-INSTRUCTIONS.txt).' 'INFO'

            # Step 5: Embed copy logs inside the backup package
            & $addVmLog 'Embedding copy logs into backup package (Backup-Copy.log).' 'INFO'
            $vmCopyLogPath = Join-Path -Path $stagingDir -ChildPath 'Backup-Copy.log'
            Set-Content -Path $vmCopyLogPath -Value $vmCopyLogLines -Encoding UTF8

            if (-not $DisableDiskLog -and -not [string]::IsNullOrWhiteSpace($GlobalLogPath) -and (Test-Path -Path $GlobalLogPath)) {
                $embeddedGlobalLog = Join-Path -Path $stagingDir -ChildPath (Split-Path -Path $GlobalLogPath -Leaf)
                Copy-Item -Path $GlobalLogPath -Destination $embeddedGlobalLog -Force
            }

            # Step 6: Compress and encrypt with AES-256 ZIP
            & $addVmLog "Creating AES-256 password-protected ZIP archive '$zipFullPath' (Compression: $Level)..." 'INFO'
            Compress-BackupWithPassword -SevenZipExe $SevenZipExe `
                -SourceDirectory $stagingDir `
                -DestinationZipPath $zipFullPath `
                -Password $Password `
                -Level $Level `
                -SkipVerify:$SkipVerify
            & $addVmLog 'ZIP archive created and verified successfully.' 'SUCCESS'

            # Step 7: Cleanup staging folder
            if (-not $RetainStaging -and (Test-Path -Path $stagingDir)) {
                Remove-Item -Path $stagingDir -Recurse -Force
                & $addVmLog 'Removed temporary staging directory.' 'INFO'
            }
        }
        catch {
            $status = 'Failed'
            $errorMessage = $_.Exception.Message
            & $addVmLog "Backup failed: $errorMessage" 'ERROR'
            throw
        }
        finally {
            # Safety net: ensure VM is restarted if Cold backup failed mid-export
            if ($wasStoppedByScript -and -not $LeaveStopped) {
                try {
                    if ((Get-VM -Name $vm.Name).State -ne 'Running') {
                        & $addVmLog 'Recovery finally block: restarting VM...' 'WARN'
                        Start-VM -Name $vm.Name -ErrorAction Stop
                    }
                }
                catch {
                    & $addVmLog "Failed to restart VM in finally block: $($_.Exception.Message)" 'ERROR'
                }
            }
            $sw.Stop()
        }

        $zipSizeMB = if (Test-Path -Path $zipFullPath) {
            [math]::Round(((Get-Item -Path $zipFullPath).Length / 1MB), 2)
        }
        else {
            0
        }

        $finalState = (Get-VM -Name $vm.Name).State.ToString()

        return [PSCustomObject]@{
            VMName        = $vm.Name
            BackupMode    = $Mode
            OriginalState = $originalState
            FinalState    = $finalState
            ArchivePath   = $zipFullPath
            ArchiveSizeMB = $zipSizeMB
            DurationSec   = [math]::Round($sw.Elapsed.TotalSeconds, 1)
            Status        = $status
            Error         = $errorMessage
        }
    }

    #endregion Helper Functions

    # Zero-parameter or -Help / -h safe exit before UAC elevation
    if ($Help -or ($PSBoundParameters.Count -eq 0 -and -not $MyInvocation.ExpectingInput)) {
        Show-ScriptHelp
        exit 0
    }

    if (-not $SkipAdminCheck -and -not (Test-IsAdministrator)) {
        Invoke-UacElevation -BoundParameters $PSBoundParameters
    }

    # Resolve default log path
    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        $LogPath = "C:\Logs\${RunTimestamp}-${ScriptName}-${env:COMPUTERNAME}-${env:USERNAME}.logs"
    }

    Write-Log -Message "=== Starting $ScriptName v$ScriptVersion ===" -Level 'INFO' -FilePath $LogPath -DisableDiskLog:$NoLog
    Write-Log -Message "BackupMode: $BackupMode | BackupPath: $BackupPath | CompressionLevel: $CompressionLevel" -Level 'INFO' -FilePath $LogPath -DisableDiskLog:$NoLog

    # Verify Hyper-V module availability
    if (-not (Get-Module -ListAvailable -Name 'Hyper-V')) {
        throw 'The Hyper-V PowerShell module is not installed on this machine. Install RSAT-Hyper-V-Tools or the Hyper-V role.'
    }
    Import-Module -Name 'Hyper-V' -ErrorAction Stop

    # Resolve 7-Zip executable
    $resolved7z = Resolve-SevenZipExecutable -ExplicitPath $SevenZipPath
    Write-Log -Message "Using 7-Zip executable: $resolved7z" -Level 'INFO' -FilePath $LogPath -DisableDiskLog:$NoLog

    # Ensure backup directory exists
    if (-not (Test-Path -Path $BackupPath)) {
        if ($PSCmdlet.ShouldProcess($BackupPath, 'Create backup destination directory')) {
            New-Item -Path $BackupPath -ItemType Directory -Force | Out-Null
            Write-Log -Message "Created backup destination directory: $BackupPath" -Level 'INFO' -FilePath $LogPath -DisableDiskLog:$NoLog
        }
    }

    # Obtain ZIP password securely if not supplied via parameter
    if ($null -eq $ZipPassword -and -not $WhatIfPreference) {
        $ZipPassword = Read-Host -Prompt 'Enter AES-256 ZIP encryption password' -AsSecureString
        $confirmPwd = Read-Host -Prompt 'Confirm AES-256 ZIP encryption password' -AsSecureString

        $p1 = $null
        $p2 = $null
        try {
            $p1 = ConvertFrom-SecureStringToPlainText -SecureValue $ZipPassword
            $p2 = ConvertFrom-SecureStringToPlainText -SecureValue $confirmPwd
            if ($p1 -cne $p2) {
                throw 'Password confirmation did not match. Aborting backup.'
            }
        }
        finally {
            $p1 = $null
            $p2 = $null
        }
    }
    elseif ($null -eq $ZipPassword -and $WhatIfPreference) {
        $ZipPassword = ConvertTo-SecureString -String 'WhatIfPlaceholder' -AsPlainText -Force
    }

    $vmQueue = [System.Collections.Generic.List[string]]::new()
    $results = [System.Collections.Generic.List[pscustomobject]]::new()
}

process {
    foreach ($name in $VMName) {
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $vmQueue.Add($name)
        }
    }
}

end {
    if ($vmQueue.Count -eq 0) {
        Write-Log -Message 'No VM names provided. Use -Help for usage instructions.' -Level 'WARN' -FilePath $LogPath -DisableDiskLog:$NoLog
        return
    }

    $total = $vmQueue.Count
    $index = 0
    $hasFailures = $false

    foreach ($targetVm in $vmQueue) {
        $index++
        $pct = [int](($index / $total) * 100)
        Write-Progress -Activity 'Backing up Hyper-V Virtual Machines' -Status "Processing $targetVm ($index of $total)" -PercentComplete $pct

        try {
            $result = Backup-SingleHyperVVM -Name $targetVm `
                -Mode $BackupMode `
                -TargetBackupDir $BackupPath `
                -Password $ZipPassword `
                -SevenZipExe $resolved7z `
                -Level $CompressionLevel `
                -LeaveStopped:$KeepStopped `
                -StopTimeoutSec $ShutdownTimeoutSeconds `
                -ForceStop:$ForceShutdown `
                -RetainStaging:$KeepUncompressed `
                -SkipVerify:$SkipArchiveVerification `
                -GlobalLogPath $LogPath `
                -DisableDiskLog:$NoLog
            $results.Add($result)
        }
        catch {
            $hasFailures = $true
            $results.Add([PSCustomObject]@{
                    VMName        = $targetVm
                    BackupMode    = $BackupMode
                    OriginalState = 'Unknown'
                    FinalState    = 'Unknown'
                    ArchivePath   = $null
                    ArchiveSizeMB = 0
                    DurationSec   = 0
                    Status        = 'Failed'
                    Error         = $_.Exception.Message
                })
        }
    }

    Write-Progress -Activity 'Backing up Hyper-V Virtual Machines' -Completed

    Write-Host ''
    Write-Host '=== Backup Summary ===' -ForegroundColor Cyan
    $results | Format-Table -AutoSize VMName, BackupMode, OriginalState, FinalState, ArchiveSizeMB, DurationSec, Status

    Write-Log -Message "=== Finished $ScriptName (Total: $total, Failures: $($hasFailures)) ===" -Level $(if ($hasFailures) { 'WARN' } else { 'SUCCESS' }) -FilePath $LogPath -DisableDiskLog:$NoLog

    if ($PassThru) {
        $results
    }

    if ($hasFailures) {
        exit 1
    }
}

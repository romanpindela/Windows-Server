<#
================================================================================
  Script Name : Backup-HyperVVM.ps1
  Author      : Roman Pindela
  Contact     : roman.pindela@gmail.com
  Version     : 1.3.1
  Release Date: 2026-11-18
  License     : MIT
  Repository  : https://github.com/romanpindela/Windows-Server

  DESCRIPTION:
    100% native Microsoft PowerShell/.NET automation tool for creating complete,
    self-contained backups of Hyper-V virtual machines on Windows Server
    (2016/2019/2022/2025) and Windows 10/11 Pro — with zero third-party
    dependencies. Supports AES-256-CBC + HMAC-SHA256 encrypted ZIP archives
    (.zip.aes), unencrypted ZIP archives (.zip, -NoEncrypt), or raw
    uncompressed VM export folders (-NoZip).

    Key Capabilities & 8 Defensive Safeguards:
    1. Single-Instance Execution Lock (Global Named Mutex) preventing
       overlapping runs from colliding on Hyper-V exports or retention.
    2. Language-Independent Admin SID (S-1-5-32-544), NTFS Write/Delete
       Permission Probe, and Hyper-V VMMS Service Readiness Verification.
    3. Pre-Flight VM Existence, State, Disk Path, & VSS Integration Check.
    4. Dynamic Pre-Flight Free Disk Space Verification (VM disk footprint +
       configurable -MinFreeSpaceMB buffer) preventing disk-full crashes.
    5. Post-Export Structural Verification (.vmcx/.xml & .vhdx completeness).
    6. Minimum Valid Backup Size Enforcement (-MinValidSizeMB, default 10 MB).
    7. Post-Creation Archive Integrity Verification (Zip64 central directory
       & core entry check for .zip; HMAC-SHA256 cryptographic tag for .zip.aes).
    8. Backup-First Count- & Size-Guarded Retention (-RetentionCount, default 1)
       + Automatic Cleanup of Partial/Unverified Artifacts on Failure.
    9. Detailed UTF-8 Audit Logging in C:\Logi\ (configurable via -LogDir/-LogPath).
================================================================================
#>

<#
.SYNOPSIS
    Creates a complete, safeguarded Hyper-V virtual machine backup in Hot or Cold
    mode as an AES-256 encrypted ZIP (.zip.aes), unencrypted ZIP (.zip), or folder.

.DESCRIPTION
    Automates full Hyper-V virtual machine backup on a Hyper-V host using only
    built-in Microsoft Windows/PowerShell/.NET components:
    - Acquires a Global Named Mutex lock to prevent overlapping backup runs.
    - Validates Administrator privileges (SID S-1-5-32-544), NTFS write/delete
      permissions, and Hyper-V Management Service (vmms) status.
    - Checks VM state, virtual disk paths, VSS integration, and free disk space
      dynamically before exporting.
    - Supports Hot backup (live Export-VM, default) and Cold backup (graceful
      shutdown, Export-VM, and automatic restart in try/finally).
    - Verifies exported VM structure, minimum archive size (-MinValidSizeMB),
      and ZIP / HMAC-SHA256 integrity before deleting any previous backup.
    - Enforces backup-first retention (-RetentionCount, default 1 valid copy
      per VM in C:\DANE\Backup) and writes full audit logs to C:\Logi\.

.PARAMETER VMName
    One or more Hyper-V virtual machine names to back up. Supports pipeline input.
    Aliases: -Name

.PARAMETER BackupMode
    Backup mode: 'Hot' (live export without stopping the VM) or 'Cold' (stops
    the VM before export and restarts it afterward unless -KeepStopped is set).
    Default: 'Hot'.
    Aliases: -Mode

.PARAMETER BackupPath
    Destination directory for the final backup archives (.zip.aes / .zip) or
    uncompressed backup folders (-NoZip).
    Default: 'C:\DANE\Backup'.

.PARAMETER ZipPassword
    Encryption password as a [SecureString]. If omitted during interactive runs
    (and neither -NoEncrypt nor -NoZip is set), the script prompts securely
    via Read-Host -AsSecureString. Cannot be combined with -NoEncrypt or -NoZip.
    Aliases: -Password

.PARAMETER NoEncrypt
    Switch parameter. Skips AES-256 encryption and password prompting, creating
    an unencrypted native .NET Zip64 archive (<VMName>_<timestamp>.zip).
    Aliases: -NoPassword, -Unencrypted

.PARAMETER NoZip
    Switch parameter. Skips ZIP compression and AES-256 encryption (no password
    required), saving the complete self-contained backup directly as an
    uncompressed directory (<BackupPath>\<VMName>_<timestamp>\).
    Aliases: -SkipZip, -NoCompress, -Uncompressed

.PARAMETER CompressionLevel
    .NET ZipFile compression level: 'Optimal', 'Fastest', or 'NoCompression'.
    Default: 'Optimal'.

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
    and verifying the ZIP or encrypted archive.

.PARAMETER SkipArchiveVerification
    Switch parameter. Skips the post-compression / post-encryption archive
    integrity verification pass.

.PARAMETER RetentionCount
    Number of valid backup copies (>= MinValidSizeMB) to keep per VM in
    BackupPath. Older valid copies for that VM are deleted ONLY AFTER the new
    backup passes all verification checks. Set to 0 to disable cleanup.
    Default: 1.

.PARAMETER MinValidSizeMB
    Minimum backup output size in MB required for a backup to be considered
    valid (when the VM has virtual disks attached). Protects against empty or
    truncated backups replacing healthy backups. Default: 10.

.PARAMETER MinFreeSpaceMB
    Minimum free disk space buffer in MB required on target backup volume
    above the VM's disk footprint before starting Export-VM. Default: 2048.

.PARAMETER SkipDiskSpaceCheck
    Switch parameter. Bypasses the pre-flight free disk space check.

.PARAMETER SkipMutex
    Switch parameter. Bypasses the single-instance Global Mutex lock.

.PARAMETER MutexTimeoutSeconds
    Seconds to wait for the Global Mutex lock if another instance is running.
    Default: 0 (fail immediately if locked).

.PARAMETER LogDir
    Directory for execution audit logs when -LogPath is not specified.
    Default: 'C:\Logi'.

.PARAMETER LogPath
    Custom file path for the execution log file.
    Default: <LogDir>\<yyyyMMdd-HHmmss>-Backup-HyperVVM-<ComputerName>-<UserName>.log
    Aliases: -l, -Log

.PARAMETER NoLog
    Switch parameter. Disables writing execution logs to disk.

.PARAMETER SkipAdminCheck
    Switch parameter. Skips automatic UAC Administrator privilege verification.

.PARAMETER PassThru
    Switch parameter. Returns structured [PSCustomObject] backup results to the
    PowerShell pipeline.

.PARAMETER ListVMs
    Switch parameter (-ListVMs / -List). Lists all Hyper-V virtual machines on
    the host with detailed configuration and state in a formatted table and exits.

.PARAMETER Help
    Switch parameter (-Help / -h). Displays this help guide and exits safely.

.EXAMPLE
    C:\Scripts\Backup-HyperVVM\Backup-HyperVVM.ps1
    Displays the built-in help screen without elevating or modifying anything.

.EXAMPLE
    C:\Scripts\Backup-HyperVVM\Backup-HyperVVM.ps1 -ListVMs
    Lists all Hyper-V virtual machines on the host with state, CPU, RAM, disks,
    checkpoints, vSwitches, and uptime in a table.

.EXAMPLE
    C:\Scripts\Backup-HyperVVM\Backup-HyperVVM.ps1 -VMName "SQL2022" -BackupMode Hot -NoEncrypt -BackupPath "C:\DANE\Backup"
    Performs a live Hot backup of SQL2022 without a password, saves an
    unencrypted .zip archive to C:\DANE\Backup, keeps only the latest valid copy
    (deleting the previous one after verification), and logs to C:\Logi.

.EXAMPLE
    C:\Scripts\Backup-HyperVVM\Backup-HyperVVM.ps1 -VMName "WEB01" -BackupMode Hot -NoZip
    Performs a live Hot backup of WEB01 without a password and without ZIP
    compression, saving the full VM export folder directly to C:\DANE\Backup.

.EXAMPLE
    $pwd = Read-Host "Enter Encryption Password" -AsSecureString
    C:\Scripts\Backup-HyperVVM\Backup-HyperVVM.ps1 -VMName "DC01" -BackupMode Cold -ZipPassword $pwd
    Performs a Cold backup of DC01, includes restore instructions and copy logs,
    and saves an AES-256 encrypted .zip.aes archive to C:\DANE\Backup.

.EXAMPLE
    C:\Scripts\Backup-HyperVVM\Decrypt-HyperVBackup.ps1 -ArchivePath "C:\DANE\Backup\DC01_20261117-220000.zip.aes" -DestinationPath "C:\Restore\DC01"
    Decrypts and extracts the encrypted VM backup archive for restoration.

.NOTES
    Author       : Roman Pindela
    Email        : roman.pindela@gmail.com
    GitHub       : https://github.com/romanpindela
    Version      : 1.3.1
    Last Modified: 2026-11-18
    Deployment   : Recommended location on Hyper-V host: C:\Scripts\Backup-HyperVVM\Backup-HyperVVM.ps1
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
    [Alias('NoPassword', 'Unencrypted')]
    [switch]$NoEncrypt,

    [Parameter()]
    [Alias('SkipZip', 'NoCompress', 'Uncompressed')]
    [switch]$NoZip,

    [Parameter()]
    [ValidateSet('Optimal', 'Fastest', 'NoCompression')]
    [string]$CompressionLevel = 'Optimal',

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
    [ValidateRange(0, 3650)]
    [int]$RetentionCount = 1,

    [Parameter()]
    [ValidateRange(0, 102400)]
    [int]$MinValidSizeMB = 10,

    [Parameter()]
    [ValidateRange(100, 1048576)]
    [int]$MinFreeSpaceMB = 2048,

    [Parameter()]
    [switch]$SkipDiskSpaceCheck,

    [Parameter()]
    [switch]$SkipMutex,

    [Parameter()]
    [ValidateRange(0, 3600)]
    [int]$MutexTimeoutSeconds = 0,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$LogDir = 'C:\Logi',

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
    [Alias('List')]
    [switch]$ListVMs,

    [Parameter()]
    [Alias('h')]
    [switch]$Help
)

begin {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $ScriptVersion = '1.3.1'
    $ScriptName = 'Backup-HyperVVM'
    $RunTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

    #region Helper Functions

    function Show-ScriptHelp {
        [CmdletBinding()]
        param ()

        Write-Host ''
        Write-Host '================================================================================' -ForegroundColor Cyan
        Write-Host "  $ScriptName.ps1  (v$ScriptVersion)" -ForegroundColor White
        Write-Host '  100% Native Hyper-V VM Hot/Cold Backup (Encrypted ZIP, Plain ZIP, or Folder)' -ForegroundColor Gray
        Write-Host '================================================================================' -ForegroundColor Cyan
        Write-Host ''
        Write-Host 'SYNTAX:' -ForegroundColor Yellow
        Write-Host '  .\Backup-HyperVVM.ps1 -VMName <string[]> [-BackupMode Hot|Cold]' -ForegroundColor White
        Write-Host '                        [-BackupPath <string>] [-ZipPassword <SecureString>]' -ForegroundColor White
        Write-Host '                        [-NoEncrypt] [-NoZip] [-RetentionCount <int>]' -ForegroundColor White
        Write-Host '                        [-CompressionLevel Optimal|Fastest|NoCompression]' -ForegroundColor White
        Write-Host '                        [-MinValidSizeMB <int>] [-MinFreeSpaceMB <int>]' -ForegroundColor White
        Write-Host '                        [-KeepStopped] [-ForceShutdown] [-KeepUncompressed]' -ForegroundColor White
        Write-Host '                        [-LogDir <string>] [-LogPath <string>] [-NoLog] [-PassThru]' -ForegroundColor White
        Write-Host '  .\Backup-HyperVVM.ps1 -ListVMs [-PassThru]' -ForegroundColor White
        Write-Host '  .\Backup-HyperVVM.ps1 [-Help | -h]' -ForegroundColor White
        Write-Host ''
        Write-Host 'PARAMETERS:' -ForegroundColor Yellow
        Write-Host '  -VMName <string[]>          Target Hyper-V VM name(s) (aliases: -Name; pipeline supported)'
        Write-Host '  -BackupMode <Hot|Cold>      Hot = live export; Cold = stop VM, export, restart (default: Hot)'
        Write-Host '  -BackupPath <string>        Target folder for backups (default: C:\DANE\Backup)'
        Write-Host '  -ZipPassword <SecureString> Encryption password; prompts securely if omitted'
        Write-Host '  -NoEncrypt                  Skip AES-256 encryption & password prompt (outputs plain .zip)'
        Write-Host '  -NoZip                      Skip ZIP & encryption (outputs uncompressed VM folder)'
        Write-Host '  -CompressionLevel <enum>    Optimal, Fastest, or NoCompression (default: Optimal)'
        Write-Host '  -RetentionCount <int>       Valid copies to keep per VM; 0 disables cleanup (default: 1)'
        Write-Host '  -MinValidSizeMB <int>       Min size in MB for a valid backup with disks (default: 10)'
        Write-Host '  -MinFreeSpaceMB <int>       Min free space buffer in MB above VM disk size (default: 2048)'
        Write-Host '  -SkipDiskSpaceCheck         Bypass pre-flight disk space validation'
        Write-Host '  -SkipMutex                  Bypass single-instance Global Mutex lock'
        Write-Host '  -MutexTimeoutSeconds <int>  Seconds to wait for Mutex lock if busy (default: 0)'
        Write-Host '  -KeepStopped                (Cold mode) Do not restart VM after backup'
        Write-Host '  -ShutdownTimeoutSeconds     Graceful shutdown wait in seconds (default: 300)'
        Write-Host '  -ForceShutdown              Force TurnOff if graceful shutdown times out'
        Write-Host '  -KeepUncompressed           Keep staging folder after archive creation'
        Write-Host '  -SkipArchiveVerification    Skip post-compression / HMAC-SHA256 verification'
        Write-Host '  -LogDir <string>            Audit log directory (default: C:\Logi)'
        Write-Host '  -LogPath <string>           Custom log path (default: C:\Logi\<timestamp>-Backup-HyperVVM-*.log)'
        Write-Host '  -NoLog                      Disable disk logging'
        Write-Host '  -PassThru                   Output structured [PSCustomObject] results to pipeline'
        Write-Host '  -ListVMs / -List            List all Hyper-V VMs with details in a table and exit'
        Write-Host '  -Help / -h                  Display this help screen and exit'
        Write-Host ''
        Write-Host 'HOT BACKUP WITHOUT PASSWORD EXAMPLES:' -ForegroundColor Yellow
        Write-Host '  # Hot backup compressed to unencrypted .zip (no password, keeps 1 copy, logs in C:\Logi):' -ForegroundColor DarkGray
        Write-Host '  C:\Scripts\Backup-HyperVVM\Backup-HyperVVM.ps1 -VMName "SQL2022" -BackupMode Hot -NoEncrypt -BackupPath "C:\DANE\Backup"' -ForegroundColor Green
        Write-Host ''
        Write-Host '  # Hot backup as uncompressed folder (no ZIP, no password):' -ForegroundColor DarkGray
        Write-Host '  C:\Scripts\Backup-HyperVVM\Backup-HyperVVM.ps1 -VMName "WEB01" -BackupMode Hot -NoZip' -ForegroundColor Green
        Write-Host ''
        Write-Host 'SECURE PASSWORD EXAMPLES:' -ForegroundColor Yellow
        Write-Host '  # Interactive secure prompt (recommended):' -ForegroundColor DarkGray
        Write-Host '  $pwd = Read-Host "Enter Encryption Password" -AsSecureString' -ForegroundColor Green
        Write-Host '  C:\Scripts\Backup-HyperVVM\Backup-HyperVVM.ps1 -VMName "DC01" -BackupMode Cold -ZipPassword $pwd' -ForegroundColor Green
        Write-Host ''
        Write-Host '  # Scheduled Task (DPAPI per-user/machine encrypted secret):' -ForegroundColor DarkGray
        Write-Host '  # 1. Save once: Read-Host -AsSecureString | Export-Clixml C:\Scripts\zip.cred' -ForegroundColor DarkGray
        Write-Host '  # 2. Load:      $pwd = Import-Clixml C:\Scripts\zip.cred' -ForegroundColor Green
        Write-Host '  C:\Scripts\Backup-HyperVVM\Backup-HyperVVM.ps1 -VMName "APP01","DB01" -BackupMode Hot -ZipPassword $pwd' -ForegroundColor Green
        Write-Host ''
        Write-Host 'DECRYPT & RESTORE EXAMPLE:' -ForegroundColor Yellow
        Write-Host '  C:\Scripts\Backup-HyperVVM\Decrypt-HyperVBackup.ps1 -ArchivePath "C:\DANE\Backup\DC01_20261117-220000.zip.aes" -DestinationPath "C:\Restore\DC01"' -ForegroundColor Green
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

    function ConvertFrom-SecureStringToBytes {
        [CmdletBinding()]
        [OutputType([byte[]])]
        param (
            [Parameter(Mandatory = $true)]
            [SecureString]$SecureValue
        )

        $bstr = [System.IntPtr]::Zero
        try {
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
            $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
            return ,([byte[]][System.Text.Encoding]::UTF8.GetBytes($plain))
        }
        finally {
            $plain = $null
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
            [psobject]$VM,

            [Parameter(Mandatory = $true)]
            [string]$OutputJsonPath
        )

        $disks = @(Get-VMHardDiskDrive -VMName $VM.Name | ForEach-Object {
                [PSCustomObject]@{
                    ControllerType     = $_.ControllerType.ToString()
                    ControllerNumber   = $_.ControllerNumber
                    ControllerLocation = $_.ControllerLocation
                    Path               = $_.Path
                }
            })

        $nics = @(Get-VMNetworkAdapter -VMName $VM.Name | ForEach-Object {
                $vlan = Get-VMNetworkAdapterVlan -VMNetworkAdapter $_ -ErrorAction SilentlyContinue
                [PSCustomObject]@{
                    Name        = $_.Name
                    SwitchName  = $_.SwitchName
                    MacAddress  = $_.MacAddress
                    DynamicMac  = $_.DynamicMacAddressEnabled
                    VlanSetting = if ($null -ne $vlan) { $vlan.OperationMode.ToString() } else { 'Untagged' }
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
            VMName               = $VM.Name
            VMId                 = $VM.Id.ToString()
            Generation           = $VM.Generation
            Version              = $VM.Version
            ProcessorCount       = $VM.ProcessorCount
            MemoryStartupBytes   = $VM.MemoryStartup
            DynamicMemoryEnabled = $VM.DynamicMemoryEnabled
            OriginalState        = $VM.State.ToString()
            HostComputerName     = $env:COMPUTERNAME
            ExportedAtUtc        = (Get-Date).ToUniversalTime().ToString('o')
            HardDisks            = $disks
            NetworkAdapters      = $nics
            Checkpoints          = $snapshots
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
            [ValidateSet('ZipAES', 'Zip', 'Folder')]
            [string]$BackupFormat,

            [Parameter(Mandatory = $true)]
            [string]$ArchiveFileName,

            [Parameter(Mandatory = $true)]
            [string]$ArchiveFullPath,

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

        $restoreRoot = if ($BackupFormat -eq 'Folder') { $ArchiveFullPath } else { "C:\Restore\$vmName" }

        switch ($BackupFormat) {
            'ZipAES' {
                $packageHeaderLine = "  Encrypted File   : $ArchiveFileName (Native .NET AES-256-CBC + HMAC-SHA256)"
                $step1Section = @"
1. DECRYPT & EXTRACT THE BACKUP ARCHIVE (100% Native PowerShell)
--------------------------------------------------------------------------------
Use Decrypt-HyperVBackup.ps1 (located in C:\DANE\Backup\ or C:\Scripts\):

  .\Decrypt-HyperVBackup.ps1 -ArchivePath "$ArchiveFullPath" -DestinationPath "$restoreRoot"
"@
                $cleanupChecklist = "  [ ] Remove temporary extracted files from $restoreRoot once verified"
            }
            'Zip' {
                $packageHeaderLine = "  Archive File     : $ArchiveFileName (Unencrypted Native .NET Zip64)"
                $step1Section = @"
1. EXTRACT THE UNENCRYPTED ZIP ARCHIVE (100% Native PowerShell)
--------------------------------------------------------------------------------
Extract the Zip64 archive using built-in .NET (supports >2 GB VHDX files):

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::ExtractToDirectory("$ArchiveFullPath", "$restoreRoot")
"@
                $cleanupChecklist = "  [ ] Remove temporary extracted files from $restoreRoot once verified"
            }
            'Folder' {
                $packageHeaderLine = "  Backup Folder    : $ArchiveFullPath (Uncompressed / Unencrypted)"
                $step1Section = @"
1. VERIFY THE UNCOMPRESSED BACKUP FOLDER
--------------------------------------------------------------------------------
This backup was created without ZIP compression or encryption (-NoZip).
No decryption or extraction step is required.
"@
                $cleanupChecklist = "  [ ] Keep or archive $restoreRoot safely according to your retention policy"
            }
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
$packageHeaderLine

  ORIGINAL NETWORK ADAPTERS:
$nicSummary

  ORIGINAL VIRTUAL DISKS:
$diskSummary
================================================================================

$step1Section

Inside "$restoreRoot\$vmName\" you will find:
  - Virtual Machines\      (.vmcx, .vmrs, .vmgs configuration files)
  - Virtual Hard Disks\    (.vhdx / .vhd / .avhdx disk files)
  - Snapshots\             (checkpoints, if any existed at backup time)

2. OPTION A: RESTORE IN-PLACE / MOVE TO NEW HOST (PowerShell - As Administrator)
--------------------------------------------------------------------------------
Use this when restoring a deleted VM or moving to another Hyper-V host while
preserving the original VM ID and copying files into Hyper-V's default storage:

  `$vmcx = Get-ChildItem "$restoreRoot\$vmName\Virtual Machines\*.vmcx" | Select-Object -First 1
  Import-VM -Path `$vmcx.FullName -Copy
  Start-VM -Name "$vmName"

3. OPTION B: CLONE SIDE-BY-SIDE ON THE SAME HOST (PowerShell - As Administrator)
--------------------------------------------------------------------------------
Use -GenerateNewId when the original VM still exists on the host to avoid
VM ID collisions:

  `$vmcx = Get-ChildItem "$restoreRoot\$vmName\Virtual Machines\*.vmcx" | Select-Object -First 1
  `$cloned = Import-VM -Path `$vmcx.FullName -Copy -GenerateNewId
  Rename-VM -VM `$cloned -NewName "${vmName}-Restored"
  Start-VM -VM `$cloned

4. OPTION C: RESTORE VIA HYPER-V MANAGER (GUI)
--------------------------------------------------------------------------------
  1. Open Hyper-V Manager (virtmgmt.msc) as Administrator.
  2. Click "Import Virtual Machine..." in the right Actions pane.
  3. Browse to: $restoreRoot\$vmName
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
$cleanupChecklist
================================================================================
"@

        Set-Content -Path $OutputPath -Value $content -Encoding UTF8
    }

    function Test-EncryptedArchiveHmac {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$ArchivePath,

            [Parameter(Mandatory = $true)]
            [byte[]]$PasswordBytes
        )

        $inStream = $null
        $kdf = $null
        $hmac = $null
        try {
            $inStream = [System.IO.File]::OpenRead($ArchivePath)
            if ($inStream.Length -lt 88) {
                throw 'Encrypted archive is smaller than minimum valid header size.'
            }

            $inStream.Position = 8
            $salt = New-Object byte[] 32
            [void]$inStream.Read($salt, 0, 32)

            $kdf = [System.Security.Cryptography.Rfc2898DeriveBytes]::new($PasswordBytes, $salt, 100000)
            [void]$kdf.GetBytes(32)
            $hmacKey = $kdf.GetBytes(32)

            $storedHmac = New-Object byte[] 32
            $inStream.Position = $inStream.Length - 32
            [void]$inStream.Read($storedHmac, 0, 32)

            $hmac = [System.Security.Cryptography.HMACSHA256]::new($hmacKey)
            $inStream.Position = 0
            $remaining = $inStream.Length - 32
            $buffer = New-Object byte[] (1024 * 1024)
            while ($remaining -gt 0) {
                $toRead = [int][Math]::Min([long]$buffer.Length, [long]$remaining)
                $read = $inStream.Read($buffer, 0, $toRead)
                if ($read -le 0) { break }
                [void]$hmac.TransformBlock($buffer, 0, $read, $buffer, 0)
                $remaining -= $read
            }
            [void]$hmac.TransformFinalBlock([byte[]]@(), 0, 0)
            $computed = $hmac.Hash

            for ($i = 0; $i -lt 32; $i++) {
                if ($computed[$i] -ne $storedHmac[$i]) {
                    throw 'Post-encryption HMAC-SHA256 integrity verification failed.'
                }
            }
        }
        finally {
            if ($null -ne $hmac) { $hmac.Dispose() }
            if ($null -ne $kdf) { $kdf.Dispose() }
            if ($null -ne $inStream) { $inStream.Dispose() }
        }
    }

    function Test-DirectoryWritePermission {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$DirectoryPath,

            [Parameter(Mandatory = $true)]
            [string]$Label
        )

        if (-not (Test-Path -Path $DirectoryPath -PathType Container)) {
            throw "Permission check failed: $Label directory '$DirectoryPath' does not exist."
        }

        $probeFile = Join-Path -Path $DirectoryPath -ChildPath (".permtest_" + [guid]::NewGuid().ToString('N') + '.tmp')
        try {
            [System.IO.File]::WriteAllText($probeFile, 'permcheck')
            if (-not (Test-Path -Path $probeFile -PathType Leaf)) {
                throw "Write probe file could not be verified in '$DirectoryPath'."
            }
            Remove-Item -Path $probeFile -Force -ErrorAction Stop
        }
        catch {
            if (Test-Path -Path $probeFile -PathType Leaf) {
                Remove-Item -Path $probeFile -Force -ErrorAction SilentlyContinue
            }
            throw "Insufficient NTFS/filesystem write or delete permissions on $Label directory '$DirectoryPath': $($_.Exception.Message)"
        }
    }

    function Test-VolumeFreeSpace {
        [CmdletBinding()]
        [OutputType([int64])]
        param (
            [Parameter(Mandatory = $true)]
            [string]$TargetPath,

            [Parameter(Mandatory = $true)]
            [int64]$RequiredBytes,

            [Parameter()]
            [string]$GlobalLogPath,

            [Parameter()]
            [switch]$DisableDiskLog
        )

        if ($TargetPath -like '\\*') {
            Write-Log -Message "Disk space check skipped for UNC path '$TargetPath' (ensure remote share quota/space is sufficient)." -Level 'WARN' -FilePath $GlobalLogPath -DisableDiskLog:$DisableDiskLog
            return [int64]0
        }

        $qualifier = Split-Path -Path $TargetPath -Qualifier
        if ([string]::IsNullOrWhiteSpace($qualifier)) {
            throw "Cannot resolve drive qualifier for path '$TargetPath'."
        }

        $driveLetter = $qualifier.TrimEnd(':')
        $psDrive = Get-PSDrive -Name $driveLetter -PSProvider FileSystem -ErrorAction SilentlyContinue
        if ($null -eq $psDrive) {
            throw "Drive '$qualifier' for path '$TargetPath' is not accessible or mounted."
        }

        $freeMB = [math]::Round(($psDrive.Free / 1MB), 2)
        $reqMB = [math]::Round(($RequiredBytes / 1MB), 2)
        if ($psDrive.Free -lt $RequiredBytes) {
            throw "Insufficient free space on drive '$qualifier' for '$TargetPath' ($freeMB MB free, minimum required: $reqMB MB)."
        }

        return [int64]$psDrive.Free
    }

    function Get-BackupItemSizeBytes {
        [CmdletBinding()]
        [OutputType([int64])]
        param (
            [Parameter(Mandatory = $true)]
            [string]$Path
        )

        if (Test-Path -Path $Path -PathType Leaf) {
            return [int64](Get-Item -Path $Path).Length
        }
        if (Test-Path -Path $Path -PathType Container) {
            $sum = (Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            if ($null -eq $sum) { return [int64]0 }
            return [int64]$sum
        }
        return [int64]0
    }

    function Test-ExportedVMPackage {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$StagingDirectory,

            [Parameter(Mandatory = $true)]
            [string]$VMName,

            [Parameter(Mandatory = $true)]
            [bool]$ExpectVirtualDisks
        )

        $vmSubDir = Join-Path -Path $StagingDirectory -ChildPath $VMName
        if (-not (Test-Path -Path $vmSubDir -PathType Container)) {
            throw "Post-export verification failed: expected VM export folder '$vmSubDir' does not exist."
        }

        $vmConfigDir = Join-Path -Path $vmSubDir -ChildPath 'Virtual Machines'
        $configFiles = @(Get-ChildItem -Path $vmConfigDir -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in @('.vmcx', '.xml') -and $_.Length -gt 0 })
        if ($configFiles.Count -eq 0) {
            throw "Post-export verification failed: no non-empty .vmcx/.xml configuration file found in '$vmConfigDir'."
        }

        if ($ExpectVirtualDisks) {
            $vhdDir = Join-Path -Path $vmSubDir -ChildPath 'Virtual Hard Disks'
            $vhdFiles = @(Get-ChildItem -Path $vhdDir -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Extension -in @('.vhdx', '.vhd', '.avhdx', '.avhd') -and $_.Length -gt 0 })
            if ($vhdFiles.Count -eq 0) {
                throw "Post-export verification failed: VM has attached disks, but no non-empty VHD/VHDX files were found in '$vhdDir'."
            }
        }
    }

    function Invoke-HyperVSafeRetentionCleanup {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$DirectoryPath,

            [Parameter(Mandatory = $true)]
            [string]$SafeVMName,

            [Parameter(Mandatory = $true)]
            [string]$CurrentBackupPath,

            [Parameter(Mandatory = $true)]
            [int]$KeepCount,

            [Parameter(Mandatory = $true)]
            [int64]$MinimumValidBytes,

            [Parameter(Mandatory = $true)]
            [scriptblock]$LogCallback
        )

        if ($KeepCount -le 0) {
            & $LogCallback 'Retention cleanup disabled (-RetentionCount 0). All previous backups preserved.' 'INFO'
            return
        }

        $escapedName = [regex]::Escape($SafeVMName)
        $pattern = "^${escapedName}_\d{8}-\d{6}(?:\.zip\.aes|\.zip)?$"
        $resolvedCurrent = [System.IO.Path]::GetFullPath($CurrentBackupPath)

        $matchingItems = @(Get-ChildItem -Path $DirectoryPath -ErrorAction SilentlyContinue | Where-Object {
                $_.Name -notlike '_staging_*' -and $_.Name -match $pattern
            })

        $validBackups = [System.Collections.Generic.List[pscustomobject]]::new()
        $undersizedBackups = [System.Collections.Generic.List[pscustomobject]]::new()

        foreach ($item in $matchingItems) {
            $itemBytes = Get-BackupItemSizeBytes -Path $item.FullName
            $entry = [PSCustomObject]@{
                FullName      = [System.IO.Path]::GetFullPath($item.FullName)
                Name          = $item.Name
                SizeBytes     = $itemBytes
                LastWriteTime = $item.LastWriteTime
                IsContainer   = $item.PSIsContainer
            }

            if ($itemBytes -ge $MinimumValidBytes) {
                $validBackups.Add($entry)
            }
            else {
                $undersizedBackups.Add($entry)
            }
        }

        $minMB = [math]::Round(($MinimumValidBytes / 1MB), 2)
        & $LogCallback "RETENTION AUDIT [$SafeVMName]: Found $($validBackups.Count) valid backup(s) (>= $minMB MB) and $($undersizedBackups.Count) undersized/corrupt item(s) (< $minMB MB) in '$DirectoryPath'." 'INFO'

        foreach ($bad in $undersizedBackups) {
            $badKB = [math]::Round(($bad.SizeBytes / 1KB), 2)
            & $LogCallback "RETENTION WARNING [$SafeVMName]: '$($bad.Name)' is smaller than $minMB MB ($badKB KB) and is NOT counted as a valid backup." 'WARN'
        }

        if ($validBackups.Count -le $KeepCount) {
            & $LogCallback "RETENTION GUARD [$SafeVMName]: Valid backup count ($($validBackups.Count)) <= retention limit ($KeepCount). No existing backups will be deleted." 'INFO'
            return
        }

        # Always keep the newly verified backup first, then newest previous valid copies up to KeepCount
        $orderedOthers = @($validBackups | Where-Object { $_.FullName -ine $resolvedCurrent } | Sort-Object -Property LastWriteTime -Descending)
        $othersToKeep = [Math]::Max(0, ($KeepCount - 1))
        $itemsToDelete = @($orderedOthers | Select-Object -Skip $othersToKeep)

        foreach ($old in $itemsToDelete) {
            if ($old.FullName -ieq $resolvedCurrent) { continue }
            $oldSizeMB = [math]::Round(($old.SizeBytes / 1MB), 2)
            if ($old.IsContainer) {
                Remove-Item -Path $old.FullName -Recurse -Force -ErrorAction Stop
            }
            else {
                Remove-Item -Path $old.FullName -Force -ErrorAction Stop
            }
            & $LogCallback "RETENTION CLEANUP [$SafeVMName]: Removed older backup '$($old.Name)' ($oldSizeMB MB, LastWriteTime: $($old.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')))." 'INFO'
        }
    }

    function Compress-BackupDirectory {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$SourceDirectory,

            [Parameter(Mandatory = $true)]
            [string]$DestinationZipPath,

            [Parameter(Mandatory = $true)]
            [string]$Level,

            [Parameter()]
            [switch]$VerifyZip
        )

        if (Test-Path -Path $DestinationZipPath) {
            Remove-Item -Path $DestinationZipPath -Force
        }

        $zipLevel = [System.IO.Compression.CompressionLevel]::$Level
        [System.IO.Compression.ZipFile]::CreateFromDirectory($SourceDirectory, $DestinationZipPath, $zipLevel, $false)

        if ($VerifyZip) {
            $zipArchive = $null
            try {
                $zipArchive = [System.IO.Compression.ZipFile]::OpenRead($DestinationZipPath)
                if ($zipArchive.Entries.Count -eq 0) {
                    throw 'Post-compression ZIP verification failed: archive contains zero entries.'
                }
                $entryNames = @($zipArchive.Entries | ForEach-Object { $_.FullName })
                $hasMeta = @($entryNames | Where-Object { $_ -like '*VM-Metadata.json' }).Count -gt 0
                $hasRestore = @($entryNames | Where-Object { $_ -like '*RESTORE-INSTRUCTIONS.txt' }).Count -gt 0
                $hasVmcx = @($entryNames | Where-Object { $_ -like '*.vmcx' -or $_ -like '*.xml' }).Count -gt 0
                if (-not ($hasMeta -and $hasRestore -and $hasVmcx)) {
                    throw 'Post-compression ZIP verification failed: archive is missing expected VM configuration or metadata entries.'
                }
            }
            finally {
                if ($null -ne $zipArchive) { $zipArchive.Dispose() }
            }
        }
    }

    function Compress-AndEncryptBackupNative {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory = $true)]
            [string]$SourceDirectory,

            [Parameter(Mandatory = $true)]
            [string]$DestinationEncryptedPath,

            [Parameter(Mandatory = $true)]
            [SecureString]$Password,

            [Parameter(Mandatory = $true)]
            [string]$Level,

            [Parameter()]
            [switch]$SkipVerify
        )

        $tempZipPath = "${DestinationEncryptedPath}.tmp.zip"
        $passwordBytes = $null
        $rng = $null
        $kdf = $null
        $aes = $null
        $inStream = $null
        $outStream = $null
        $cryptoStream = $null
        $hmac = $null

        try {
            $passwordBytes = ConvertFrom-SecureStringToBytes -SecureValue $Password
            if ($passwordBytes.Length -eq 0) {
                throw 'Encryption password cannot be empty.'
            }

            if (Test-Path -Path $DestinationEncryptedPath) {
                Remove-Item -Path $DestinationEncryptedPath -Force
            }

            Compress-BackupDirectory -SourceDirectory $SourceDirectory -DestinationZipPath $tempZipPath -Level $Level

            # Generate random 32-byte salt and 16-byte IV
            $salt = New-Object byte[] 32
            $iv = New-Object byte[] 16
            $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
            $rng.GetBytes($salt)
            $rng.GetBytes($iv)

            $kdf = [System.Security.Cryptography.Rfc2898DeriveBytes]::new($passwordBytes, $salt, 100000)
            $aesKey = $kdf.GetBytes(32)
            $hmacKey = $kdf.GetBytes(32)

            $magicHeader = [System.Text.Encoding]::ASCII.GetBytes('HYPVAES1')

            $aes = [System.Security.Cryptography.Aes]::Create()
            $aes.KeySize = 256
            $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
            $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
            $aes.Key = $aesKey
            $aes.IV = $iv

            $outStream = [System.IO.File]::Create($DestinationEncryptedPath)
            $outStream.Write($magicHeader, 0, $magicHeader.Length)
            $outStream.Write($salt, 0, $salt.Length)
            $outStream.Write($iv, 0, $iv.Length)

            $encryptor = $aes.CreateEncryptor()
            $cryptoStream = [System.Security.Cryptography.CryptoStream]::new($outStream, $encryptor, [System.Security.Cryptography.CryptoStreamMode]::Write)
            $inStream = [System.IO.File]::OpenRead($tempZipPath)

            $buffer = New-Object byte[] (1024 * 1024)
            while (($read = $inStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $cryptoStream.Write($buffer, 0, $read)
            }
            $cryptoStream.FlushFinalBlock()

            $inStream.Dispose()
            $inStream = $null
            $cryptoStream.Dispose()
            $cryptoStream = $null
            $outStream.Dispose()
            $outStream = $null

            # Compute HMAC-SHA256 over Magic + Salt + IV + Ciphertext and append 32-byte tag
            $hmac = [System.Security.Cryptography.HMACSHA256]::new($hmacKey)
            $inStream = [System.IO.File]::OpenRead($DestinationEncryptedPath)
            while (($read = $inStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                [void]$hmac.TransformBlock($buffer, 0, $read, $buffer, 0)
            }
            [void]$hmac.TransformFinalBlock([byte[]]@(), 0, 0)
            $tag = $hmac.Hash
            $inStream.Dispose()
            $inStream = $null

            $outStream = [System.IO.File]::Open($DestinationEncryptedPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write)
            $outStream.Write($tag, 0, $tag.Length)
            $outStream.Dispose()
            $outStream = $null

            if (-not $SkipVerify) {
                Test-EncryptedArchiveHmac -ArchivePath $DestinationEncryptedPath -PasswordBytes $passwordBytes
            }
        }
        finally {
            if ($null -ne $cryptoStream) { $cryptoStream.Dispose() }
            if ($null -ne $outStream) { $outStream.Dispose() }
            if ($null -ne $inStream) { $inStream.Dispose() }
            if ($null -ne $hmac) { $hmac.Dispose() }
            if ($null -ne $aes) { $aes.Dispose() }
            if ($null -ne $kdf) { $kdf.Dispose() }
            if ($null -ne $rng) { $rng.Dispose() }
            if ($null -ne $passwordBytes) { [Array]::Clear($passwordBytes, 0, $passwordBytes.Length) }
            if (Test-Path -Path $tempZipPath) {
                Remove-Item -Path $tempZipPath -Force -ErrorAction SilentlyContinue
            }
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
            [ValidateSet('ZipAES', 'Zip', 'Folder')]
            [string]$BackupFormat,

            [Parameter(Mandatory = $true)]
            [string]$TargetBackupDir,

            [Parameter()]
            [SecureString]$Password,

            [Parameter(Mandatory = $true)]
            [string]$Level,

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
            [int]$KeepCopies = 1,

            [Parameter()]
            [int64]$MinValidBytes = (10 * 1MB),

            [Parameter()]
            [int64]$MinFreeBytes = (2048 * 1MB),

            [Parameter()]
            [switch]$BypassDiskSpaceCheck,

            [Parameter()]
            [string]$GlobalLogPath,

            [Parameter()]
            [switch]$DisableDiskLog
        )

        if ($BackupFormat -eq 'ZipAES' -and $null -eq $Password -and -not $WhatIfPreference) {
            throw 'Encryption password is required when BackupFormat is ZipAES.'
        }

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $vm = Get-VM -Name $Name -ErrorAction Stop
        $originalState = $vm.State.ToString()
        $vmTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $safeVmName = $vm.Name -replace '[\\/:*?"<>|]', '_'

        switch ($BackupFormat) {
            'Folder' {
                $archiveFileName = "${safeVmName}_${vmTimestamp}"
                $archiveFullPath = Join-Path -Path $TargetBackupDir -ChildPath $archiveFileName
                $stagingDir = $archiveFullPath
            }
            'Zip' {
                $stagingDir = Join-Path -Path $TargetBackupDir -ChildPath "_staging_${safeVmName}_${vmTimestamp}"
                $archiveFileName = "${safeVmName}_${vmTimestamp}.zip"
                $archiveFullPath = Join-Path -Path $TargetBackupDir -ChildPath $archiveFileName
            }
            'ZipAES' {
                $stagingDir = Join-Path -Path $TargetBackupDir -ChildPath "_staging_${safeVmName}_${vmTimestamp}"
                $archiveFileName = "${safeVmName}_${vmTimestamp}.zip.aes"
                $archiveFullPath = Join-Path -Path $TargetBackupDir -ChildPath $archiveFileName
            }
        }

        $vmCopyLogLines = [System.Collections.Generic.List[string]]::new()

        $addVmLog = {
            param([string]$Msg, [string]$Lvl = 'INFO')
            $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Lvl] $Msg"
            $vmCopyLogLines.Add($line)
            Write-Log -Message "[$($vm.Name)] $Msg" -Level $Lvl -FilePath $GlobalLogPath -DisableDiskLog:$DisableDiskLog
        }

        $wasStoppedByScript = $false
        $backupVerified = $false
        $status = 'Success'
        $errorMessage = $null

        try {
            & $addVmLog "Starting $Mode backup (Format: $BackupFormat, Original State: $originalState)" 'INFO'

            if (-not $PSCmdlet.ShouldProcess($vm.Name, "Perform $Mode Hyper-V backup ($BackupFormat) to $archiveFullPath")) {
                return [PSCustomObject]@{
                    VMName        = $vm.Name
                    BackupMode    = $Mode
                    Format        = $BackupFormat
                    OriginalState = $originalState
                    FinalState    = $originalState
                    ArchivePath   = $archiveFullPath
                    ArchiveSizeMB = 0
                    DurationSec   = 0
                    Status        = 'WhatIf'
                    Error         = $null
                }
            }

            # Safeguard 3: Pre-flight VM state, attached disk paths, and VSS integration readiness check
            $blockedStates = @('Starting', 'Stopping', 'Saving', 'Pausing', 'Resuming')
            if ($originalState -in $blockedStates) {
                throw "VM '$($vm.Name)' is in transient state '$originalState' and cannot be safely exported right now."
            }

            $attachedDisks = @(Get-VMHardDiskDrive -VMName $vm.Name -ErrorAction Stop)
            $vmDiskBytes = [int64]0
            foreach ($disk in $attachedDisks) {
                if ([string]::IsNullOrWhiteSpace($disk.Path)) { continue }
                if (-not (Test-Path -Path $disk.Path -PathType Leaf)) {
                    throw "Virtual disk file not found for VM '$($vm.Name)': '$($disk.Path)'."
                }
                $vmDiskBytes += [int64](Get-Item -Path $disk.Path).Length
            }
            $hasVirtualDisks = ($attachedDisks.Count -gt 0 -and $vmDiskBytes -gt 0)
            $vmDiskGB = [math]::Round(($vmDiskBytes / 1GB), 2)
            & $addVmLog "Pre-flight VM check OK: Disks=$($attachedDisks.Count) (${vmDiskGB} GB), State=$originalState." 'INFO'

            if ($Mode -eq 'Hot' -and $originalState -eq 'Running') {
                $vssSvc = Get-VMIntegrationService -VMName $vm.Name -Name 'VSS' -ErrorAction SilentlyContinue
                if ($null -eq $vssSvc -or -not $vssSvc.Enabled) {
                    & $addVmLog 'Hyper-V VSS (Backup) Integration Service is disabled or unavailable on this VM; live export may be crash-consistent rather than app-consistent.' 'WARN'
                }
                else {
                    & $addVmLog "Hyper-V VSS Integration Service check OK (Enabled: $($vssSvc.Enabled), PrimaryStatus: $($vssSvc.PrimaryOperationalStatus))." 'INFO'
                }
            }

            # Safeguard 4: Dynamic pre-flight free disk space check
            if (-not $BypassDiskSpaceCheck) {
                $requiredFreeBytes = [Math]::Max($MinFreeBytes, ($vmDiskBytes + $MinFreeBytes))
                $freeBytes = Test-VolumeFreeSpace -TargetPath $TargetBackupDir -RequiredBytes $requiredFreeBytes -GlobalLogPath $GlobalLogPath -DisableDiskLog:$DisableDiskLog
                $freeGB = [math]::Round(($freeBytes / 1GB), 2)
                $reqGB = [math]::Round(($requiredFreeBytes / 1GB), 2)
                & $addVmLog "Disk space check OK on target volume ($freeGB GB free >= $reqGB GB required)." 'INFO'

                if ($BackupFormat -ne 'Folder' -and $freeBytes -gt 0) {
                    $conservativeBytes = [int64]($vmDiskBytes * 1.5) + $MinFreeBytes
                    if ($freeBytes -lt $conservativeBytes) {
                        $consGB = [math]::Round(($conservativeBytes / 1GB), 2)
                        & $addVmLog "Free space ($freeGB GB) is below recommended 1.5x staging+archive headroom ($consGB GB). Backup will proceed if compression ratio fits." 'WARN'
                    }
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
            $exportTargetLabel = if ($BackupFormat -eq 'Folder') { 'backup folder' } else { 'staging folder' }
            & $addVmLog "Exporting full VM package to $exportTargetLabel '$stagingDir'..." 'INFO'
            Export-VM -Name $vm.Name -Path $stagingDir -ErrorAction Stop
            & $addVmLog 'Export-VM completed successfully.' 'SUCCESS'

            # Safeguard 5: Post-export structural & VHDX completeness verification
            Test-ExportedVMPackage -StagingDirectory $stagingDir -VMName $vm.Name -ExpectVirtualDisks:$hasVirtualDisks
            & $addVmLog 'Post-export structural check OK (.vmcx/.xml and VHDX files verified).' 'INFO'

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
            New-RestoreInstructionFile -Metadata $metadata `
                -BackupModeUsed $Mode `
                -BackupFormat $BackupFormat `
                -ArchiveFileName $archiveFileName `
                -ArchiveFullPath $archiveFullPath `
                -OutputPath $restoreDocPath
            & $addVmLog 'Generated restore instructions (RESTORE-INSTRUCTIONS.txt).' 'INFO'

            # Step 5: Embed copy logs inside the backup package
            & $addVmLog 'Embedding copy logs into backup package (Backup-Copy.log).' 'INFO'
            $vmCopyLogPath = Join-Path -Path $stagingDir -ChildPath 'Backup-Copy.log'
            Set-Content -Path $vmCopyLogPath -Value $vmCopyLogLines -Encoding UTF8

            if (-not $DisableDiskLog -and -not [string]::IsNullOrWhiteSpace($GlobalLogPath) -and (Test-Path -Path $GlobalLogPath)) {
                $embeddedGlobalLog = Join-Path -Path $stagingDir -ChildPath (Split-Path -Path $GlobalLogPath -Leaf)
                Copy-Item -Path $GlobalLogPath -Destination $embeddedGlobalLog -Force
            }

            # Step 6 & Safeguard 7: Package output & verify archive integrity
            switch ($BackupFormat) {
                'Folder' {
                    & $addVmLog "Uncompressed backup folder ready at '$archiveFullPath' (no ZIP, no password)." 'SUCCESS'
                }
                'Zip' {
                    & $addVmLog "Creating unencrypted native .NET Zip64 archive '$archiveFullPath' (Compression: $Level)..." 'INFO'
                    Compress-BackupDirectory -SourceDirectory $stagingDir `
                        -DestinationZipPath $archiveFullPath `
                        -Level $Level `
                        -VerifyZip:(-not $SkipVerify)
                    & $addVmLog 'Unencrypted ZIP archive created and verified successfully.' 'SUCCESS'
                }
                'ZipAES' {
                    & $addVmLog "Creating native .NET AES-256 encrypted archive '$archiveFullPath' (Compression: $Level)..." 'INFO'
                    Compress-AndEncryptBackupNative -SourceDirectory $stagingDir `
                        -DestinationEncryptedPath $archiveFullPath `
                        -Password $Password `
                        -Level $Level `
                        -SkipVerify:$SkipVerify
                    & $addVmLog 'Encrypted archive created and HMAC-SHA256 verified successfully.' 'SUCCESS'
                }
            }

            # Safeguard 6: Minimum valid backup size enforcement
            $outputBytes = Get-BackupItemSizeBytes -Path $archiveFullPath
            $outputSizeMB = [math]::Round(($outputBytes / 1MB), 2)
            $effectiveMinBytes = if ($hasVirtualDisks) { $MinValidBytes } else { [int64]1 }
            if ($outputBytes -lt $effectiveMinBytes) {
                $minThresholdMB = [math]::Round(($effectiveMinBytes / 1MB), 2)
                throw "Backup output '$archiveFullPath' ($outputSizeMB MB) is smaller than the minimum valid threshold ($minThresholdMB MB). Aborting before retention cleanup."
            }
            $backupVerified = $true
            & $addVmLog "Minimum size validation OK ($outputSizeMB MB >= $([math]::Round(($effectiveMinBytes / 1MB), 2)) MB)." 'INFO'

            # Step 7: Cleanup temporary staging folder (only when archived to .zip / .zip.aes)
            if ($BackupFormat -ne 'Folder' -and -not $RetainStaging -and (Test-Path -Path $stagingDir)) {
                Remove-Item -Path $stagingDir -Recurse -Force
                & $addVmLog 'Removed temporary staging directory.' 'INFO'
            }

            # Step 8 / Safeguard 8: Backup-first count- & size-guarded retention cleanup
            Invoke-HyperVSafeRetentionCleanup -DirectoryPath $TargetBackupDir `
                -SafeVMName $safeVmName `
                -CurrentBackupPath $archiveFullPath `
                -KeepCount $KeepCopies `
                -MinimumValidBytes $effectiveMinBytes `
                -LogCallback $addVmLog
        }
        catch {
            $status = 'Failed'
            $errorMessage = $_.Exception.Message
            & $addVmLog "Backup failed: $errorMessage" 'ERROR'

            # Safeguard 8b: Clean up incomplete/unverified artifacts from THIS failed session
            if (-not $backupVerified) {
                if ($BackupFormat -ne 'Folder' -and (Test-Path -Path $stagingDir)) {
                    Remove-Item -Path $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
                    & $addVmLog "CLEANUP ON FAILURE: Removed incomplete staging directory '$stagingDir'." 'WARN'
                }
                if (Test-Path -Path $archiveFullPath) {
                    Remove-Item -Path $archiveFullPath -Recurse -Force -ErrorAction SilentlyContinue
                    & $addVmLog "CLEANUP ON FAILURE: Removed unverified/incomplete backup artifact '$archiveFullPath'." 'WARN'
                }
            }
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

        $archiveSizeMB = [math]::Round(((Get-BackupItemSizeBytes -Path $archiveFullPath) / 1MB), 2)
        $finalState = (Get-VM -Name $vm.Name).State.ToString()

        return [PSCustomObject]@{
            VMName        = $vm.Name
            BackupMode    = $Mode
            Format        = $BackupFormat
            OriginalState = $originalState
            FinalState    = $finalState
            ArchivePath   = $archiveFullPath
            ArchiveSizeMB = $archiveSizeMB
            DurationSec   = [math]::Round($sw.Elapsed.TotalSeconds, 1)
            Status        = $status
            Error         = $errorMessage
        }
    }

    function Get-HyperVVMInventory {
        [CmdletBinding()]
        [OutputType([pscustomobject[]])]
        param ()

        $vms = @(Get-VM | Sort-Object -Property Name)
        $inventory = [System.Collections.Generic.List[pscustomobject]]::new()

        foreach ($vm in $vms) {
            $disks = @(Get-VMHardDiskDrive -VMName $vm.Name -ErrorAction SilentlyContinue)
            $diskBytes = 0L
            foreach ($d in $disks) {
                if (-not [string]::IsNullOrWhiteSpace($d.Path) -and (Test-Path -Path $d.Path -PathType Leaf)) {
                    $diskBytes += (Get-Item -Path $d.Path).Length
                }
            }

            $switches = @((Get-VMNetworkAdapter -VMName $vm.Name -ErrorAction SilentlyContinue).SwitchName | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
            $checkpoints = @(Get-VMSnapshot -VMName $vm.Name -ErrorAction SilentlyContinue).Count

            $memBytes = if ($vm.MemoryAssigned -gt 0) { $vm.MemoryAssigned } else { $vm.MemoryStartup }

            $inventory.Add([PSCustomObject]@{
                    VMName      = $vm.Name
                    State       = $vm.State.ToString()
                    Gen         = "Gen$($vm.Generation)"
                    CPU         = $vm.ProcessorCount
                    MemoryGB    = [math]::Round(($memBytes / 1GB), 2)
                    Disks       = $disks.Count
                    DiskSizeGB  = [math]::Round(($diskBytes / 1GB), 2)
                    Checkpoints = $checkpoints
                    vSwitch     = if ($switches.Count -gt 0) { $switches -join ', ' } else { '-' }
                    Uptime      = if ($vm.State -eq 'Running') { $vm.Uptime.ToString('dd\.hh\:mm\:ss') } else { '-' }
                    VMId        = $vm.Id.ToString()
                })
        }

        return ,$inventory.ToArray()
    }

    #endregion Helper Functions

    # Zero-parameter or -Help / -h safe exit before UAC elevation
    if ($Help -or ($PSBoundParameters.Count -eq 0 -and -not $MyInvocation.ExpectingInput)) {
        Show-ScriptHelp
        exit 0
    }

    if ($null -ne $ZipPassword -and ($NoEncrypt -or $NoZip)) {
        throw 'Cannot combine -ZipPassword with -NoEncrypt or -NoZip.'
    }

    $backupFormat = if ($NoZip) {
        'Folder'
    }
    elseif ($NoEncrypt) {
        'Zip'
    }
    else {
        'ZipAES'
    }

    if (-not $SkipAdminCheck -and -not (Test-IsAdministrator)) {
        Invoke-UacElevation -BoundParameters $PSBoundParameters
    }

    # Load native .NET ZipFile assembly when ZIP archiving is enabled
    if ($backupFormat -ne 'Folder') {
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
    }

    # Resolve default log path (C:\Logi by default)
    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        $LogPath = Join-Path -Path $LogDir -ChildPath "${RunTimestamp}-${ScriptName}-${env:COMPUTERNAME}-${env:USERNAME}.log"
    }

    $formatSummary = switch ($backupFormat) {
        'ZipAES' { '100% Native .NET Zip64 + AES-256' }
        'Zip'    { '100% Native .NET Zip64 (Unencrypted)' }
        'Folder' { 'Uncompressed Folder (No ZIP, No Password)' }
    }
    $compressionSummary = if ($backupFormat -eq 'Folder') { 'None (NoZip)' } else { $CompressionLevel }
    $minValidBytes = [int64]$MinValidSizeMB * 1MB
    $minFreeBytes = [int64]$MinFreeSpaceMB * 1MB

    Write-Log -Message "=== Starting $ScriptName v$ScriptVersion ($formatSummary) ===" -Level 'INFO' -FilePath $LogPath -DisableDiskLog:$NoLog
    Write-Log -Message "BackupMode: $BackupMode | Format: $backupFormat | BackupPath: $BackupPath | CompressionLevel: $compressionSummary" -Level 'INFO' -FilePath $LogPath -DisableDiskLog:$NoLog
    Write-Log -Message "Safeguards: RetentionCount=$RetentionCount | MinValidSize=${MinValidSizeMB}MB | MinFreeSpace=${MinFreeSpaceMB}MB | LogPath=$LogPath" -Level 'INFO' -FilePath $LogPath -DisableDiskLog:$NoLog

    # Verify Hyper-V module availability
    if (-not (Get-Module -ListAvailable -Name 'Hyper-V')) {
        throw 'The Hyper-V PowerShell module is not installed on this machine. Install RSAT-Hyper-V-Tools or the Hyper-V role.'
    }
    Import-Module -Name 'Hyper-V' -ErrorAction Stop

    # Safeguard 2b: Verify Hyper-V Virtual Machine Management service (vmms) is Running
    $vmmsService = Get-Service -Name 'vmms' -ErrorAction SilentlyContinue
    if ($null -eq $vmmsService) {
        throw 'Hyper-V Virtual Machine Management service (vmms) was not found on this host.'
    }
    if ($vmmsService.Status -ne 'Running') {
        if ($PSCmdlet.ShouldProcess('vmms', 'Start Hyper-V Virtual Machine Management service')) {
            Write-Log -Message "Hyper-V service 'vmms' is '$($vmmsService.Status)'. Attempting to start..." -Level 'WARN' -FilePath $LogPath -DisableDiskLog:$NoLog
            Start-Service -Name 'vmms' -ErrorAction Stop
            $vmmsService.WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
            Write-Log -Message "Hyper-V service 'vmms' started successfully." -Level 'SUCCESS' -FilePath $LogPath -DisableDiskLog:$NoLog
        }
    }
    else {
        Write-Log -Message "Hyper-V service 'vmms' status check OK (Running)." -Level 'INFO' -FilePath $LogPath -DisableDiskLog:$NoLog
    }

    # Read-only VM inventory listing mode
    if ($ListVMs) {
        Write-Log -Message 'Querying Hyper-V virtual machine inventory...' -Level 'INFO' -FilePath $LogPath -DisableDiskLog:$NoLog
        $inventory = Get-HyperVVMInventory
        Write-Host ''
        Write-Host "=== Hyper-V Virtual Machines on $env:COMPUTERNAME (Total: $($inventory.Count)) ===" -ForegroundColor Cyan
        if ($inventory.Count -eq 0) {
            Write-Host 'No Hyper-V virtual machines found on this host.' -ForegroundColor Yellow
        }
        else {
            $inventory | Format-Table -AutoSize VMName, State, Gen, CPU, MemoryGB, Disks, DiskSizeGB, Checkpoints, vSwitch, Uptime
        }
        if ($PassThru) {
            $inventory
        }
        exit 0
    }

    # Ensure backup directory exists and verify write/delete permissions (Safeguard 2c)
    if (-not (Test-Path -Path $BackupPath)) {
        if ($PSCmdlet.ShouldProcess($BackupPath, 'Create backup destination directory')) {
            New-Item -Path $BackupPath -ItemType Directory -Force | Out-Null
            Write-Log -Message "Created backup destination directory: $BackupPath" -Level 'INFO' -FilePath $LogPath -DisableDiskLog:$NoLog
        }
    }

    if (-not $WhatIfPreference) {
        if (Test-Path -Path $BackupPath -PathType Container) {
            Test-DirectoryWritePermission -DirectoryPath $BackupPath -Label 'BackupPath'
            Write-Log -Message "Write/delete permission check OK on '$BackupPath'." -Level 'INFO' -FilePath $LogPath -DisableDiskLog:$NoLog
        }
        if (-not $NoLog) {
            $resolvedLogDir = Split-Path -Path $LogPath -Parent
            if (-not [string]::IsNullOrWhiteSpace($resolvedLogDir) -and (Test-Path -Path $resolvedLogDir -PathType Container)) {
                Test-DirectoryWritePermission -DirectoryPath $resolvedLogDir -Label 'LogDir'
            }
        }
    }

    if ($backupFormat -eq 'ZipAES') {
        $decryptorSource = Join-Path -Path $PSScriptRoot -ChildPath 'Decrypt-HyperVBackup.ps1'
        if ((Test-Path -Path $decryptorSource -PathType Leaf) -and (Test-Path -Path $BackupPath)) {
            $decryptorTarget = Join-Path -Path $BackupPath -ChildPath 'Decrypt-HyperVBackup.ps1'
            if ($PSCmdlet.ShouldProcess($decryptorTarget, 'Copy native decryption helper script to backup directory')) {
                Copy-Item -Path $decryptorSource -Destination $decryptorTarget -Force
            }
        }

        # Obtain encryption password securely if not supplied via parameter
        if ($null -eq $ZipPassword -and -not $WhatIfPreference) {
            $ZipPassword = Read-Host -Prompt 'Enter AES-256 encryption password' -AsSecureString
            $confirmPwd = Read-Host -Prompt 'Confirm AES-256 encryption password' -AsSecureString

            $p1 = $null
            $p2 = $null
            try {
                $p1 = ConvertFrom-SecureStringToBytes -SecureValue $ZipPassword
                $p2 = ConvertFrom-SecureStringToBytes -SecureValue $confirmPwd
                if ($p1.Length -eq 0) {
                    throw 'Encryption password cannot be empty. Use -NoEncrypt or -NoZip to create a backup without a password.'
                }
                $match = ($p1.Length -eq $p2.Length)
                if ($match) {
                    for ($i = 0; $i -lt $p1.Length; $i++) {
                        if ($p1[$i] -ne $p2[$i]) { $match = $false }
                    }
                }
                if (-not $match) {
                    throw 'Password confirmation did not match. Aborting backup.'
                }
            }
            finally {
                if ($null -ne $p1) { [Array]::Clear($p1, 0, $p1.Length) }
                if ($null -ne $p2) { [Array]::Clear($p2, 0, $p2.Length) }
            }
        }
        elseif ($null -eq $ZipPassword -and $WhatIfPreference) {
            $ZipPassword = ConvertTo-SecureString -String 'WhatIfPlaceholder' -AsPlainText -Force
        }
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

    # Safeguard 1: Single-instance execution lock (Global Named Mutex)
    $mutex = $null
    $mutexAcquired = $false
    $mutexName = 'Global\Backup-HyperVVM-Lock'

    try {
        if (-not $SkipMutex -and -not $WhatIfPreference) {
            $mutex = [System.Threading.Mutex]::new($false, $mutexName)
            $waitMs = $MutexTimeoutSeconds * 1000
            try {
                $mutexAcquired = $mutex.WaitOne($waitMs, $false)
            }
            catch [System.Threading.AbandonedMutexException] {
                $mutexAcquired = $true
                Write-Log -Message "Acquired abandoned Global Mutex '$mutexName' from a previously crashed run." -Level 'WARN' -FilePath $LogPath -DisableDiskLog:$NoLog
            }

            if (-not $mutexAcquired) {
                throw "Another instance of Backup-HyperVVM is already running (Mutex '$mutexName' is locked)."
            }
            Write-Log -Message "Single-instance Mutex lock acquired ('$mutexName')." -Level 'INFO' -FilePath $LogPath -DisableDiskLog:$NoLog
        }

        foreach ($targetVm in $vmQueue) {
            $index++
            $pct = [int](($index / $total) * 100)
            Write-Progress -Activity 'Backing up Hyper-V Virtual Machines' -Status "Processing $targetVm ($index of $total)" -PercentComplete $pct

            try {
                $result = Backup-SingleHyperVVM -Name $targetVm `
                    -Mode $BackupMode `
                    -BackupFormat $backupFormat `
                    -TargetBackupDir $BackupPath `
                    -Password $ZipPassword `
                    -Level $CompressionLevel `
                    -LeaveStopped:$KeepStopped `
                    -StopTimeoutSec $ShutdownTimeoutSeconds `
                    -ForceStop:$ForceShutdown `
                    -RetainStaging:$KeepUncompressed `
                    -SkipVerify:$SkipArchiveVerification `
                    -KeepCopies $RetentionCount `
                    -MinValidBytes $minValidBytes `
                    -MinFreeBytes $minFreeBytes `
                    -BypassDiskSpaceCheck:$SkipDiskSpaceCheck `
                    -GlobalLogPath $LogPath `
                    -DisableDiskLog:$NoLog
                $results.Add($result)
            }
            catch {
                $hasFailures = $true
                $results.Add([PSCustomObject]@{
                        VMName        = $targetVm
                        BackupMode    = $BackupMode
                        Format        = $backupFormat
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
    }
    finally {
        if ($mutexAcquired -and $null -ne $mutex) {
            try {
                $mutex.ReleaseMutex()
            }
            catch {}
        }
        if ($null -ne $mutex) {
            $mutex.Dispose()
        }
    }

    Write-Progress -Activity 'Backing up Hyper-V Virtual Machines' -Completed

    Write-Host ''
    Write-Host '=== Backup Summary ===' -ForegroundColor Cyan
    $results | Format-Table -AutoSize VMName, BackupMode, Format, OriginalState, FinalState, ArchiveSizeMB, DurationSec, Status

    Write-Log -Message "=== Finished $ScriptName (Total: $total, Failures: $($hasFailures)) ===" -Level $(if ($hasFailures) { 'WARN' } else { 'SUCCESS' }) -FilePath $LogPath -DisableDiskLog:$NoLog

    if ($PassThru) {
        $results
    }

    if ($hasFailures) {
        exit 1
    }
}

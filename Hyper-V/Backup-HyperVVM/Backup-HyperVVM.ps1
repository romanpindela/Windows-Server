<#
================================================================================
  Script Name : Backup-HyperVVM.ps1
  Author      : Roman Pindela
  Contact     : roman.pindela@gmail.com
  Version     : 1.1.0
  Release Date: 2026-11-17
  License     : MIT
  Repository  : https://github.com/romanpindela/Windows-Server

  DESCRIPTION:
    100% native Microsoft PowerShell/.NET automation tool for creating complete,
    self-contained, AES-256-CBC + HMAC-SHA256 encrypted ZIP backups (.zip.aes)
    of Hyper-V virtual machines on Windows Server (2016/2019/2022/2025) and
    Windows 10/11 Pro — with zero third-party dependencies.

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
    4. 100% Native .NET Zip64 Compression & AES-256 + HMAC-SHA256 Encryption:
       Uses System.IO.Compression.ZipFile (supports >2 GB VHDX files) combined
       with streaming AES-256-CBC + HMAC-SHA256 (PBKDF2 100,000 iterations).
       Accepts [SecureString] (-ZipPassword) or prompts securely via
       Read-Host -AsSecureString, verifies HMAC integrity, and zeroes BSTR
       credentials in finally {}.
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
    Creates a complete, native .NET AES-256 encrypted ZIP backup (.zip.aes) of
    one or more Hyper-V virtual machines in Hot or Cold mode.

.DESCRIPTION
    Automates full Hyper-V virtual machine backup on a Hyper-V host using only
    built-in Microsoft Windows/PowerShell/.NET components:
    - Validates Administrator privileges via SID S-1-5-32-544.
    - Supports single or multiple VMs via -VMName or pipeline input.
    - Supports Hot backup (live Export-VM) and Cold backup (graceful shutdown,
      Export-VM, and automatic restart in try/finally).
    - Exports all VM configuration files, virtual hard disks, and checkpoints.
    - Generates VM-Metadata.json and RESTORE-INSTRUCTIONS.txt tailored to the
      backed-up VM inside the archive.
    - Includes Backup-Copy.log inside the archive and writes full audit logs
      to C:\Logs\.
    - Compresses via .NET ZipFile (Zip64) and encrypts with AES-256-CBC +
      HMAC-SHA256 into C:\DANE\Backup\<VMName>_<timestamp>.zip.aes.

.PARAMETER VMName
    One or more Hyper-V virtual machine names to back up. Supports pipeline input.
    Aliases: -Name

.PARAMETER BackupMode
    Backup mode: 'Hot' (live export without stopping the VM) or 'Cold' (stops
    the VM before export and restarts it afterward unless -KeepStopped is set).
    Default: 'Hot'.
    Aliases: -Mode

.PARAMETER BackupPath
    Destination directory for the final encrypted .zip.aes backup archives.
    Default: 'C:\DANE\Backup'.

.PARAMETER ZipPassword
    Encryption password as a [SecureString]. If omitted during interactive runs,
    the script prompts securely via Read-Host -AsSecureString.
    Aliases: -Password

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
    and verifying the encrypted archive.

.PARAMETER SkipArchiveVerification
    Switch parameter. Skips the post-encryption HMAC-SHA256 verification pass.

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
    $pwd = Read-Host "Enter Encryption Password" -AsSecureString
    C:\Scripts\Backup-HyperVVM.ps1 -VMName "DC01" -BackupMode Cold -ZipPassword $pwd
    Performs a Cold backup of DC01, includes restore instructions and copy logs,
    and saves an AES-256 encrypted .zip.aes archive to C:\DANE\Backup.

.EXAMPLE
    C:\Scripts\Backup-HyperVVM.ps1 -VMName "APP01","SQL01" -BackupMode Hot -CompressionLevel Fastest
    Performs a Hot backup of APP01 and SQL01, prompting securely for the password.

.EXAMPLE
    C:\Scripts\Decrypt-HyperVBackup.ps1 -ArchivePath "C:\DANE\Backup\DC01_20261117-220000.zip.aes" -DestinationPath "C:\Restore\DC01"
    Decrypts and extracts the encrypted VM backup archive for restoration.

.NOTES
    Author       : Roman Pindela
    Email        : roman.pindela@gmail.com
    GitHub       : https://github.com/romanpindela
    Version      : 1.1.0
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

    $ScriptVersion = '1.1.0'
    $ScriptName = 'Backup-HyperVVM'
    $RunTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

    #region Helper Functions

    function Show-ScriptHelp {
        [CmdletBinding()]
        param ()

        Write-Host ''
        Write-Host '================================================================================' -ForegroundColor Cyan
        Write-Host "  $ScriptName.ps1  (v$ScriptVersion)" -ForegroundColor White
        Write-Host '  100% Native Hyper-V VM Hot/Cold Backup with .NET AES-256 Encrypted ZIP' -ForegroundColor Gray
        Write-Host '================================================================================' -ForegroundColor Cyan
        Write-Host ''
        Write-Host 'SYNTAX:' -ForegroundColor Yellow
        Write-Host '  .\Backup-HyperVVM.ps1 -VMName <string[]> [-BackupMode Hot|Cold]' -ForegroundColor White
        Write-Host '                        [-BackupPath <string>] [-ZipPassword <SecureString>]' -ForegroundColor White
        Write-Host '                        [-CompressionLevel Optimal|Fastest|NoCompression]' -ForegroundColor White
        Write-Host '                        [-KeepStopped] [-ForceShutdown] [-KeepUncompressed]' -ForegroundColor White
        Write-Host '                        [-LogPath <string>] [-NoLog] [-PassThru]' -ForegroundColor White
        Write-Host '  .\Backup-HyperVVM.ps1 [-Help | -h]' -ForegroundColor White
        Write-Host ''
        Write-Host 'PARAMETERS:' -ForegroundColor Yellow
        Write-Host '  -VMName <string[]>          Target Hyper-V VM name(s) (aliases: -Name; pipeline supported)'
        Write-Host '  -BackupMode <Hot|Cold>      Hot = live export; Cold = stop VM, export, restart (default: Hot)'
        Write-Host '  -BackupPath <string>        Target folder for encrypted .zip.aes (default: C:\DANE\Backup)'
        Write-Host '  -ZipPassword <SecureString> Encryption password; prompts securely if omitted'
        Write-Host '  -CompressionLevel <enum>    Optimal, Fastest, or NoCompression (default: Optimal)'
        Write-Host '  -KeepStopped                (Cold mode) Do not restart VM after backup'
        Write-Host '  -ShutdownTimeoutSeconds     Graceful shutdown wait in seconds (default: 300)'
        Write-Host '  -ForceShutdown              Force TurnOff if graceful shutdown times out'
        Write-Host '  -KeepUncompressed           Keep staging folder after archive creation'
        Write-Host '  -SkipArchiveVerification    Skip post-encryption HMAC-SHA256 integrity test'
        Write-Host '  -LogPath <string>           Custom log path (default: C:\Logs\<timestamp>-Backup-HyperVVM-*.logs)'
        Write-Host '  -NoLog                      Disable disk logging'
        Write-Host '  -PassThru                   Output structured [PSCustomObject] results to pipeline'
        Write-Host '  -Help / -h                  Display this help screen and exit'
        Write-Host ''
        Write-Host 'SECURE PASSWORD EXAMPLES:' -ForegroundColor Yellow
        Write-Host '  # Interactive secure prompt (recommended):' -ForegroundColor DarkGray
        Write-Host '  $pwd = Read-Host "Enter Encryption Password" -AsSecureString' -ForegroundColor Green
        Write-Host '  C:\Scripts\Backup-HyperVVM.ps1 -VMName "DC01" -BackupMode Cold -ZipPassword $pwd' -ForegroundColor Green
        Write-Host ''
        Write-Host '  # Scheduled Task (DPAPI per-user/machine encrypted secret):' -ForegroundColor DarkGray
        Write-Host '  # 1. Save once: Read-Host -AsSecureString | Export-Clixml C:\Scripts\zip.cred' -ForegroundColor DarkGray
        Write-Host '  # 2. Load:      $pwd = Import-Clixml C:\Scripts\zip.cred' -ForegroundColor Green
        Write-Host '  C:\Scripts\Backup-HyperVVM.ps1 -VMName "APP01","DB01" -BackupMode Hot -ZipPassword $pwd' -ForegroundColor Green
        Write-Host ''
        Write-Host 'DECRYPT & RESTORE EXAMPLE:' -ForegroundColor Yellow
        Write-Host '  C:\Scripts\Decrypt-HyperVBackup.ps1 -ArchivePath "C:\DANE\Backup\DC01_20261117-220000.zip.aes" -DestinationPath "C:\Restore\DC01"' -ForegroundColor Green
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
            [Microsoft.HyperV.PowerShell.VirtualMachine]$VM,

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
                [PSCustomObject]@{
                    Name        = $_.Name
                    SwitchName  = $_.SwitchName
                    MacAddress  = $_.MacAddress
                    DynamicMac  = $_.DynamicMacAddressEnabled
                    VlanSetting = (Get-VMNetworkAdapterVlan -VMNetworkAdapter $_ -ErrorAction SilentlyContinue).OperationMode
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
  Encrypted File   : $ArchiveFileName (Native .NET AES-256-CBC + HMAC-SHA256)

  ORIGINAL NETWORK ADAPTERS:
$nicSummary

  ORIGINAL VIRTUAL DISKS:
$diskSummary
================================================================================

1. DECRYPT & EXTRACT THE BACKUP ARCHIVE (100% Native PowerShell)
--------------------------------------------------------------------------------
Use Decrypt-HyperVBackup.ps1 (located in C:\DANE\Backup\ or C:\Scripts\):

  .\Decrypt-HyperVBackup.ps1 -ArchivePath "C:\DANE\Backup\$ArchiveFileName" -DestinationPath "C:\Restore\$vmName"

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
                $toRead = [int][Math]::Min($buffer.Length, $remaining)
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

            if (Test-Path -Path $tempZipPath) {
                Remove-Item -Path $tempZipPath -Force
            }
            if (Test-Path -Path $DestinationEncryptedPath) {
                Remove-Item -Path $DestinationEncryptedPath -Force
            }

            $zipLevel = [System.IO.Compression.CompressionLevel]::$Level
            [System.IO.Compression.ZipFile]::CreateFromDirectory($SourceDirectory, $tempZipPath, $zipLevel, $false)

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
            [string]$TargetBackupDir,

            [Parameter(Mandatory = $true)]
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
        $archiveFileName = "${safeVmName}_${vmTimestamp}.zip.aes"
        $archiveFullPath = Join-Path -Path $TargetBackupDir -ChildPath $archiveFileName
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

            if (-not $PSCmdlet.ShouldProcess($vm.Name, "Perform $Mode Hyper-V backup to $archiveFullPath")) {
                return [PSCustomObject]@{
                    VMName        = $vm.Name
                    BackupMode    = $Mode
                    OriginalState = $originalState
                    FinalState    = $originalState
                    ArchivePath   = $archiveFullPath
                    ArchiveSizeMB = 0
                    DurationSec   = 0
                    Status        = 'WhatIf'
                    Error         = $null
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
            New-RestoreInstructionFile -Metadata $metadata -BackupModeUsed $Mode -ArchiveFileName $archiveFileName -OutputPath $restoreDocPath
            & $addVmLog 'Generated restore instructions (RESTORE-INSTRUCTIONS.txt).' 'INFO'

            # Step 5: Embed copy logs inside the backup package
            & $addVmLog 'Embedding copy logs into backup package (Backup-Copy.log).' 'INFO'
            $vmCopyLogPath = Join-Path -Path $stagingDir -ChildPath 'Backup-Copy.log'
            Set-Content -Path $vmCopyLogPath -Value $vmCopyLogLines -Encoding UTF8

            if (-not $DisableDiskLog -and -not [string]::IsNullOrWhiteSpace($GlobalLogPath) -and (Test-Path -Path $GlobalLogPath)) {
                $embeddedGlobalLog = Join-Path -Path $stagingDir -ChildPath (Split-Path -Path $GlobalLogPath -Leaf)
                Copy-Item -Path $GlobalLogPath -Destination $embeddedGlobalLog -Force
            }

            # Step 6: Compress via .NET ZipFile (Zip64) & encrypt via AES-256-CBC + HMAC-SHA256
            & $addVmLog "Creating native .NET AES-256 encrypted archive '$archiveFullPath' (Compression: $Level)..." 'INFO'
            Compress-AndEncryptBackupNative -SourceDirectory $stagingDir `
                -DestinationEncryptedPath $archiveFullPath `
                -Password $Password `
                -Level $Level `
                -SkipVerify:$SkipVerify
            & $addVmLog 'Encrypted archive created and HMAC-SHA256 verified successfully.' 'SUCCESS'

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

        $archiveSizeMB = if (Test-Path -Path $archiveFullPath) {
            [math]::Round(((Get-Item -Path $archiveFullPath).Length / 1MB), 2)
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
            ArchivePath   = $archiveFullPath
            ArchiveSizeMB = $archiveSizeMB
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

    # Load native .NET ZipFile assembly
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    # Resolve default log path
    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        $LogPath = "C:\Logs\${RunTimestamp}-${ScriptName}-${env:COMPUTERNAME}-${env:USERNAME}.logs"
    }

    Write-Log -Message "=== Starting $ScriptName v$ScriptVersion (100% Native .NET Zip64 + AES-256) ===" -Level 'INFO' -FilePath $LogPath -DisableDiskLog:$NoLog
    Write-Log -Message "BackupMode: $BackupMode | BackupPath: $BackupPath | CompressionLevel: $CompressionLevel" -Level 'INFO' -FilePath $LogPath -DisableDiskLog:$NoLog

    # Verify Hyper-V module availability
    if (-not (Get-Module -ListAvailable -Name 'Hyper-V')) {
        throw 'The Hyper-V PowerShell module is not installed on this machine. Install RSAT-Hyper-V-Tools or the Hyper-V role.'
    }
    Import-Module -Name 'Hyper-V' -ErrorAction Stop

    # Ensure backup directory exists and copy Decrypt-HyperVBackup.ps1 if available alongside script
    if (-not (Test-Path -Path $BackupPath)) {
        if ($PSCmdlet.ShouldProcess($BackupPath, 'Create backup destination directory')) {
            New-Item -Path $BackupPath -ItemType Directory -Force | Out-Null
            Write-Log -Message "Created backup destination directory: $BackupPath" -Level 'INFO' -FilePath $LogPath -DisableDiskLog:$NoLog
        }
    }

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

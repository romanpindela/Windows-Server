<#
================================================================================
  Script Name : enable-hyper-v-remote-management-for-server.ps1
  Author      : Roman Pindela
  Contact     : roman.pindela@gmail.com
  Version     : 1.0.0
  Release Date: 2026-10-18
  License     : MIT
  Repository  : https://github.com/romanpindela/Windows-Server

  DESCRIPTION:
    Enterprise-grade PowerShell automation tool that configures a Windows
    Server (or Windows 10/11 Pro) Hyper-V host for remote management via
    Hyper-V Manager (virtmgmt.msc), PowerShell Remoting, and Server Manager
    in a Workgroup (non-domain) or LAN/VPN environment (e.g., WireGuard,
    OpenVPN, IPSec). Works seamlessly on both English and Polish Windows
    server editions.

    Key Capabilities:
    1. Zero-Parameter Interactive Help (-Help / -h):
       Displays complete syntax, parameter reference, practical examples,
       version, and author details when run without arguments or with -Help,
       without triggering an unnecessary UAC prompt.
    2. PowerShell Remoting & WinRM Listener Initialization:
       Executes 'Enable-PSRemoting -SkipNetworkProfileCheck -Force' to ensure
       the WinRM HTTP listener (TCP 5985) is fully enabled even when network
       interfaces (such as WireGuard VPN tunnels) are marked as 'Public'.
    3. WSMan CredSSP Server Role:
       Enables the CredSSP Server authentication role:
       'Enable-WSManCredSSP -Role Server -Force'
       allowing delegated NTLM authentication from remote Workgroup clients.
    4. Network Profile Hardening (-SetPrivateNetworkProfile):
       Optionally sets active network adapters (including WireGuard VPN)
       to 'Private' category to avoid Windows Firewall public profile blocks.
    5. Comprehensive Windows Firewall Provisioning:
       - Enables language-independent firewall rules for WMI, WinRM,
         VM-Monitoring, and Hyper-V Management Clients.
       - Creates an explicit inbound rule ('Allow-HyperV-WinRM-VPN') allowing
         TCP ports 5985 (WinRM HTTP), 5986 (WinRM HTTPS), 135 (RPC/DCOM),
         445 (SMB), and 2179 (Hyper-V VMConnect) across all network profiles
         (Domain, Private, Public) and any remote IP/VPN subnet.
    6. Server Manager Remoting:
       Enables 'Configure-SMRemoting.exe -Enable' on Windows Server editions
       (safely bypassed if running on desktop editions).
    7. Diagnostic & Audit Mode (-Status):
       Inspects and reports the current state of WinRM, listeners, CredSSP,
       firewall rules, network categories, and Hyper-V services without
       modifying the operating system.
    8. Multi-Language UAC Auto-Elevation:
       Verifies Administrator privileges using the well-known Windows SID
       (S-1-5-32-544 / BuiltInAdministratorsSid) for 100% compatibility across
       Polish ("Administratorzy") and English ("Administrators") editions,
       and automatically prompts for elevation while preserving CLI parameters.
    9. Detailed Audit Logging:
       Logs all operations with UTF-8 timestamps to:
       C:\Logs\<yyyyMMdd_HHmmss>-enable-hyper-v-remote-management-for-server-<ComputerName>-<UserName>.logs
================================================================================
.SYNOPSIS
    Configures a Hyper-V Server host for remote management via Hyper-V Manager,
    WinRM, and PowerShell Remoting in Workgroup and VPN environments.

.DESCRIPTION
    Automates the complete host-side configuration required to accept remote
    connections from Hyper-V Manager (virtmgmt.msc), PowerShell Direct/Remoting,
    and Server Manager across LAN and VPN (e.g. WireGuard) subnets:
    - Running without parameters or with -Help / -h displays full help, syntax,
      parameter descriptions, examples, version, and author information.
    - Running with -Enable (or simply executing as Administrator) enables WinRM
      with -SkipNetworkProfileCheck, configures WSMan CredSSP Server role,
      switches network categories to Private (if requested), sets language-
      independent firewall rules, creates an explicit VPN rule for TCP ports
      5985, 5986, 135, 445, 2179, restarts WinRM, and prints a final audit.
    - Includes -Status for read-only audits and -DryRun for previewing changes.

.PARAMETER Enable
    Switch parameter. Triggers the live server configuration workflow.
    Aliases: -Configure, -Apply

.PARAMETER SetPrivateNetworkProfile
    Switch parameter. Switches all active network connection profiles
    (including WireGuard or VPN adapters) from 'Public' to 'Private'.
    Default: True (enabled by default for reliable remoting).
    Aliases: -SetPrivate

.PARAMETER SkipConfigureSMRemoting
    Switch parameter. Skips execution of Configure-SMRemoting.exe even if present.

.PARAMETER RestartWinRM
    Switch parameter. Restarts the WinRM service after applying configuration.
    Default: True.

.PARAMETER Status
    Switch parameter. Audits and displays current WinRM service status,
    active listeners, CredSSP server status, firewall rules, and network profiles
    without making any changes.
    Aliases: -Check, -Verify, -Info

.PARAMETER DryRun
    Switch parameter. Simulates all configuration steps without modifying the OS.
    Aliases: -Simulate, -Preview

.PARAMETER SkipAdminCheck
    Switch parameter. Skips automatic UAC Administrator privilege elevation check.

.PARAMETER PassThru
    Switch parameter. Returns the configuration summary object to the PowerShell pipeline.

.PARAMETER LogPath
    Custom file path for the execution log file.
    Default: C:\Logs\<yyyyMMdd_HHmmss>-enable-hyper-v-remote-management-for-server-<ComputerName>-<UserName>.logs
    Aliases: -l, -Log

.PARAMETER NoLog
    Switch parameter. Disables writing execution logs to disk.

.PARAMETER Help
    Switch parameter (-Help / -h). Displays this help guide and exits.
    Aliases: -h

.EXAMPLE
    .\enable-hyper-v-remote-management-for-server.ps1
    Displays the help guide, usage syntax, parameter reference, examples,
    version, and author information without requiring elevated privileges.

.EXAMPLE
    .\enable-hyper-v-remote-management-for-server.ps1 -Enable
    Executes the full server configuration: enables WinRM (-SkipNetworkProfileCheck),
    enables CredSSP Server role, sets network profiles to Private, creates explicit
    VPN firewall rules (TCP 5985, 5986, 135, 445, 2179), and restarts WinRM.

.EXAMPLE
    .\enable-hyper-v-remote-management-for-server.ps1 -Status
    Displays a comprehensive audit of current WinRM listeners, CredSSP server role,
    network profiles, and firewall rules without making changes.

.EXAMPLE
    .\enable-hyper-v-remote-management-for-server.ps1 -Enable -DryRun
    Simulates the server configuration in Dry-Run mode without altering the system.

.NOTES
    Author      : Roman Pindela
    Contact     : roman.pindela@gmail.com
    GitHub      : https://github.com/romanpindela/Windows-Server
    Version     : 1.0.0
    Compatible  : Windows Server 2016/2019/2022/2025, Windows 10/11 Pro (EN/PL)
    Privileges  : Requires Administrator privileges (auto-elevates via UAC using SID).
#>

[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
param (
    [Parameter(Mandatory = $false)]
    [Alias("Configure", "Apply")]
    [switch]$Enable,

    [Parameter(Mandatory = $false)]
    [Alias("SetPrivate")]
    [bool]$SetPrivateNetworkProfile = $true,

    [Parameter(Mandatory = $false)]
    [switch]$SkipConfigureSMRemoting,

    [Parameter(Mandatory = $false)]
    [bool]$RestartWinRM = $true,

    [Parameter(Mandatory = $false)]
    [Alias("Check", "Verify", "Info")]
    [switch]$Status,

    [Parameter(Mandatory = $false)]
    [Alias("Simulate", "Preview")]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [switch]$SkipAdminCheck,

    [Parameter(Mandatory = $false)]
    [switch]$PassThru,

    [Parameter(Mandatory = $false)]
    [Alias("l", "Log")]
    [string]$LogPath,

    [Parameter(Mandatory = $false)]
    [switch]$NoLog,

    [Parameter(Mandatory = $false)]
    [Alias("h")]
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ==============================================================================
# SCRIPT METADATA & CONFIGURATION
# ==============================================================================
$SCRIPT_INFO = @{
    Name        = "enable-hyper-v-remote-management-for-server"
    FileName    = "enable-hyper-v-remote-management-for-server.ps1"
    Version     = "1.0.0"
    Author      = "Roman Pindela"
    Contact     = "roman.pindela@gmail.com"
    GitHub      = "https://github.com/romanpindela/Windows-Server"
    ReleaseDate = "2026-10-18"
    License     = "MIT"
}

$script:ActiveLogFile = $null
$script:StartTime = Get-Date

# ==============================================================================
# LOGGING & CONSOLE OUTPUT FUNCTIONS
# ==============================================================================
function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "SUCCESS", "WARN", "ERROR", "STEP", "HEADER", "DETAIL")]
        [string]$Level = "INFO",

        [Parameter(Mandatory = $false)]
        [ConsoleColor]$Color = [ConsoleColor]::White
    )

    $colorMap = @{
        "INFO"    = [ConsoleColor]::White
        "SUCCESS" = [ConsoleColor]::Green
        "WARN"    = [ConsoleColor]::Yellow
        "ERROR"   = [ConsoleColor]::Red
        "STEP"    = [ConsoleColor]::Cyan
        "HEADER"  = [ConsoleColor]::Cyan
        "DETAIL"  = [ConsoleColor]::Gray
    }

    $effectiveColor = if ($PSBoundParameters.ContainsKey("Color")) {
        $Color
    }
    else {
        $colorMap[$Level]
    }

    try { [Console]::CursorLeft = 0 } catch {}
    Write-Host $Message -ForegroundColor $effectiveColor

    if (-not $NoLog -and -not [string]::IsNullOrWhiteSpace($script:ActiveLogFile)) {
        try {
            $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            $cleanMessage = $Message -replace "^\r?\n", ""
            $logEntry = "[$timestamp] [$Level] $cleanMessage`r`n"
            [System.IO.File]::AppendAllText($script:ActiveLogFile, $logEntry, [System.Text.Encoding]::UTF8)
        }
        catch {}
    }
}

function Initialize-LogFile {
    if ($NoLog) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        $defaultLogDir = "C:\Logs"
        if (-not (Test-Path -Path $defaultLogDir)) {
            try {
                New-Item -Path $defaultLogDir -ItemType Directory -Force | Out-Null
            }
            catch {
                $defaultLogDir = [System.IO.Path]::GetTempPath()
            }
        }
        $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
        $computerName = [System.Environment]::MachineName
        $userName = [System.Environment]::UserName
        $script:ActiveLogFile = Join-Path -Path $defaultLogDir -ChildPath "$timestamp-$($SCRIPT_INFO.Name)-$computerName-$userName.logs"
    }
    else {
        $parentDir = [System.IO.Path]::GetDirectoryName($LogPath)
        if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path -Path $parentDir)) {
            New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
        }
        $script:ActiveLogFile = $LogPath
    }
}

function Protect-FilePathInput {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PathValue,

        [Parameter(Mandatory = $true)]
        [string]$ParameterName
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        throw "Validation Error: Parameter '$ParameterName' cannot be empty or whitespace."
    }

    if ($PathValue.Length -gt 260) {
        throw "Validation Error: Parameter '$ParameterName' exceeds maximum path length of 260 characters."
    }

    if ($PathValue -match '[`$;&|><*?"\r\n]') {
        throw "Security Alert: Parameter '$ParameterName' ('$PathValue') contains illegal or potentially dangerous characters."
    }
}

# ==============================================================================
# HELP & DOCUMENTATION DISPLAY
# ==============================================================================
function Show-HelpGuide {
    try { [Console]::CursorLeft = 0 } catch {}
    Write-Host @"
================================================================================
  $($SCRIPT_INFO.Name) - v$($SCRIPT_INFO.Version)
  Author : $($SCRIPT_INFO.Author) | Contact: $($SCRIPT_INFO.Contact)
  GitHub : $($SCRIPT_INFO.GitHub)
  Date   : $($SCRIPT_INFO.ReleaseDate) | License: $($SCRIPT_INFO.License)
================================================================================
DESCRIPTION:
  Enterprise-grade PowerShell script that configures a Hyper-V Host (Windows
  Server 2016/2019/2022/2025 or Windows 10/11 Pro) to accept remote management
  sessions from Hyper-V Manager (virtmgmt.msc), PowerShell Remoting, and Server
  Manager across Workgroup, LAN, and VPN subnets (e.g. WireGuard, OpenVPN, IPSec).

  Why This Script Is Needed on the Hyper-V Host:
  1. WinRM Public Profile Check: In environments with VPN tunnels (like WireGuard),
     the network interface is often identified as 'Public'. Standard 'Enable-PSRemoting'
     aborts with an error unless -SkipNetworkProfileCheck is explicitly used.
  2. LocalSubnet Firewall Restriction: Built-in Windows Firewall rules restrict
     WinRM HTTP (TCP 5985) to 'LocalSubnet' only. Clients connecting across VPN
     tunnels are dropped unless explicit 'RemoteAddress Any' rules are configured.
  3. CredSSP Authentication: Remote Workgroup Hyper-V management requires the
     CredSSP Server role ('Enable-WSManCredSSP -Role Server -Force') on the host.

  Core Capabilities:
  1. Zero-Parameter Help (-Help / -h): Displays syntax, parameter reference,
     examples, version, and author details without triggering UAC elevation.
  2. PowerShell Remoting: Executes 'Enable-PSRemoting -SkipNetworkProfileCheck -Force'.
  3. CredSSP Server Role: Executes 'Enable-WSManCredSSP -Role Server -Force'.
  4. Network Profile Category: Switches active Public adapters to Private.
  5. Language-Independent Firewall Rules: Enables WMI, WinRM, and Hyper-V rule
     groups across English & Polish Windows Server editions.
  6. Dedicated VPN Firewall Inbound Rule: Creates 'Allow-HyperV-WinRM-VPN' for
     TCP ports 5985, 5986, 135, 445, 2179 (Profile: Any, RemoteAddress: Any).
  7. Server Manager Remoting: Invokes 'Configure-SMRemoting.exe -Enable'.
  8. WinRM Service Restart & Health Verification: Applies settings and validates listeners.
  9. Language-Independent UAC Elevation: Uses Windows SID (S-1-5-32-544).
 10. Audit Logging: Writes timestamped logs to C:\Logs\...

SYNTAX:
  # 1. Display Help (Default when run without parameters):
  .\enable-hyper-v-remote-management-for-server.ps1 [-Help | -h]

  # 2. Configure Local Hyper-V Server Host (Live Mode):
  .\enable-hyper-v-remote-management-for-server.ps1 -Enable
      [-SetPrivateNetworkProfile <`$true|`$false>] [-SkipConfigureSMRemoting]
      [-RestartWinRM <`$true|`$false>] [-DryRun]

  # 3. Audit Current Remote Management Host Configuration (Read-Only):
  .\enable-hyper-v-remote-management-for-server.ps1 -Status

PARAMETERS:
  -Enable                     : Executes the host configuration workflow (WinRM,
                                CredSSP, Firewall, Network Profiles).
  -SetPrivateNetworkProfile   : Switches Public network profiles to Private (Default: `$true).
  -SkipConfigureSMRemoting    : Skips Configure-SMRemoting.exe execution.
  -RestartWinRM               : Restarts WinRM service after configuration (Default: `$true).
  -Status                     : Audits WinRM listeners, CredSSP, and Firewall rules.
  -DryRun                     : Simulates all operations without modifying the OS.
  -SkipAdminCheck             : Skips UAC elevation check.
  -PassThru                   : Returns structured summary object to pipeline.
  -LogPath <String>           : Custom log file path (Default: C:\Logs\...).
  -NoLog                      : Disables file logging.
  -Help / -h                  : Displays this help screen.

PRACTICAL EXAMPLES:
  1. Display help, author, and version info:
     .\enable-hyper-v-remote-management-for-server.ps1

  2. Configure Hyper-V host for remote management (Live):
     .\enable-hyper-v-remote-management-for-server.ps1 -Enable

  3. Simulate configuration in Dry-Run mode:
     .\enable-hyper-v-remote-management-for-server.ps1 -Enable -DryRun

  4. Audit current host configuration without changes:
     .\enable-hyper-v-remote-management-for-server.ps1 -Status

FIRST RUN / UNBLOCKING NOTE:
  After downloading this script from GitHub, unblock it before running:
     Unblock-File -Path .\enable-hyper-v-remote-management-for-server.ps1
================================================================================
"@ -ForegroundColor Yellow
}

# ==============================================================================
# ZERO-PARAMETER & HELP CHECK
# ==============================================================================
$hasActionTrigger = $Enable -or $Status

if ($Help -or (-not $hasActionTrigger)) {
    Show-HelpGuide
    return
}

# ==============================================================================
# INPUT VALIDATION
# ==============================================================================
if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
    $LogPath = $LogPath.Trim()
    Protect-FilePathInput -PathValue $LogPath -ParameterName "LogPath"
}

# ==============================================================================
# UAC AUTO-ELEVATION (LANGUAGE-INDEPENDENT SID VERIFICATION)
# ==============================================================================
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$adminSid = New-Object Security.Principal.SecurityIdentifier([Security.Principal.WellKnownSidType]::BuiltInAdministratorsSid, $null)

$isAdmin = $principal.IsInRole($adminSid)

if (-not $isAdmin -and -not $SkipAdminCheck) {
    Write-Host "Missing Administrator privileges. Requesting elevation..." -ForegroundColor Yellow

    $relaunchArgs = [System.Collections.Generic.List[string]]::new()
    $relaunchArgs.Add("-NoProfile")
    $relaunchArgs.Add("-ExecutionPolicy")
    $relaunchArgs.Add("Bypass")
    $relaunchArgs.Add("-File")
    $relaunchArgs.Add("`"$PSCommandPath`"")

    if ($Enable) { $relaunchArgs.Add("-Enable") }
    if (-not $SetPrivateNetworkProfile) { $relaunchArgs.Add("-SetPrivateNetworkProfile:`$false") }
    if ($SkipConfigureSMRemoting) { $relaunchArgs.Add("-SkipConfigureSMRemoting") }
    if (-not $RestartWinRM) { $relaunchArgs.Add("-RestartWinRM:`$false") }
    if ($Status) { $relaunchArgs.Add("-Status") }
    if ($DryRun) { $relaunchArgs.Add("-DryRun") }
    if ($PassThru) { $relaunchArgs.Add("-PassThru") }
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        $relaunchArgs.Add("-LogPath")
        $relaunchArgs.Add("`"$LogPath`"")
    }
    if ($NoLog) { $relaunchArgs.Add("-NoLog") }

    Start-Process powershell.exe -ArgumentList ($relaunchArgs -join " ") -Verb RunAs
    exit
}

# ==============================================================================
# INITIALIZE LOGGING & ENVIRONMENT BANNER
# ==============================================================================
Initialize-LogFile

$osCim = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
$csCim = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
$osCaption = if ($osCim) { $osCim.Caption.Trim() } else { [System.Environment]::OSVersion.VersionString }
$osVersion = if ($osCim) { "$($osCim.Version) (Build $($osCim.BuildNumber))" } else { "Unknown" }
$domainOrWorkgroup = if ($csCim) {
    if ($csCim.PartOfDomain) { "Domain ($($csCim.Domain))" } else { "Workgroup ($($csCim.Workgroup))" }
} else { "Unknown" }

Write-Log "================================================================================" -Level HEADER
Write-Log "  $($SCRIPT_INFO.Name) v$($SCRIPT_INFO.Version) - Initialization" -Level HEADER
Write-Log "================================================================================" -Level HEADER
Write-Log "  Author / Contact     : $($SCRIPT_INFO.Author) ($($SCRIPT_INFO.Contact))" -Level DETAIL
Write-Log "  Host / Current User  : $([System.Environment]::MachineName) \ $([System.Environment]::UserName)" -Level DETAIL
Write-Log "  Operating System     : $osCaption [$osVersion]" -Level DETAIL
Write-Log "  Network Membership   : $domainOrWorkgroup" -Level DETAIL
Write-Log "  Elevated Admin (SID) : $isAdmin (S-1-5-32-544 Verified)" -Level DETAIL
Write-Log "  Operation Mode       : $(if ($Status) { 'STATUS AUDIT (Read-Only)' } elseif ($DryRun) { 'DRY-RUN SIMULATION (Host Mode)' } else { 'LIVE HOST CONFIGURATION' })" -Level INFO
if (-not $NoLog -and $script:ActiveLogFile) {
    Write-Log "  Active Log File      : $script:ActiveLogFile" -Level DETAIL
}
Write-Log "================================================================================" -Level HEADER

# ==============================================================================
# AUDIT & STATUS FUNCTION
# ==============================================================================
function Get-ServerManagementStatus {
    $winrmSvc = Get-Service -Name "WinRM" -ErrorAction SilentlyContinue
    $winrmStatus = if ($null -ne $winrmSvc) { [string]$winrmSvc.Status } else { "NotFound" }
    $winrmStartType = if ($null -ne $winrmSvc) { [string]$winrmSvc.StartType } else { "Unknown" }

    $credSspServerAuth = $false
    try {
        $sAuth = Get-Item -Path "WSMan:\localhost\Service\Auth\CredSSP" -ErrorAction SilentlyContinue
        if ($null -ne $sAuth) { $credSspServerAuth = ($sAuth.Value -eq "true") }
    } catch {}

    $listeners = @()
    try {
        $listeners = @(Get-ChildItem -Path "WSMan:\localhost\Listener" -ErrorAction SilentlyContinue | ForEach-Object {
            "$($_.Keys -join '/') (Port: $(Get-ItemProperty -LiteralPath $_.PSPath -Name Port -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Port -ErrorAction SilentlyContinue))"
        })
    } catch {}

    $customVpnRule = Get-NetFirewallRule -Name "Allow-HyperV-WinRM-VPN" -ErrorAction SilentlyContinue
    $vpnRuleStatus = if ($null -ne $customVpnRule) { "Enabled=$($customVpnRule.Enabled)" } else { "Not Present" }

    $netProfiles = @()
    try {
        $netProfiles = @(Get-NetConnectionProfile -ErrorAction SilentlyContinue | ForEach-Object {
            "$($_.InterfaceAlias): $($_.NetworkCategory)"
        })
    } catch {}

    $port5985Open = $false
    try {
        $tcpConn = Get-NetTCPConnection -LocalPort 5985 -State Listen -ErrorAction SilentlyContinue
        if ($null -ne $tcpConn -and $tcpConn.Count -gt 0) {
            $port5985Open = $true
        }
    } catch {}

    return [PSCustomObject]@{
        ComputerName        = [System.Environment]::MachineName
        WinRMServiceStatus  = $winrmStatus
        WinRMStartType      = $winrmStartType
        WinRMPort5985Listen = $port5985Open
        CredSSPServerAuth   = $credSspServerAuth
        WSManListeners      = ($listeners -join "; ")
        VpnFirewallRule     = $vpnRuleStatus
        NetworkProfiles     = ($netProfiles -join "; ")
    }
}

function Show-StatusReport {
    param ([PSCustomObject]$StatusObj)

    Write-Log "`n--------------------------------------------------------------------------------" -Level HEADER
    Write-Log "  HYPER-V SERVER REMOTE MANAGEMENT AUDIT REPORT" -Level STEP
    Write-Log "--------------------------------------------------------------------------------" -Level HEADER
    Write-Log "  WinRM Service Status        : $($StatusObj.WinRMServiceStatus) (StartType: $($StatusObj.WinRMStartType))" -Level $(if ($StatusObj.WinRMServiceStatus -eq 'Running') { 'SUCCESS' } else { 'WARN' })
    Write-Log "  WinRM Port 5985 Listening   : $(if ($StatusObj.WinRMPort5985Listen) { 'Yes (Active Listening)' } else { 'No / Not Bound' })" -Level $(if ($StatusObj.WinRMPort5985Listen) { 'SUCCESS' } else { 'WARN' })
    Write-Log "  WSMan CredSSP Server Auth   : $(if ($StatusObj.CredSSPServerAuth) { 'Enabled' } else { 'Disabled' })" -Level $(if ($StatusObj.CredSSPServerAuth) { 'SUCCESS' } else { 'WARN' })
    Write-Log "  Active WSMan Listeners      : $(if ($StatusObj.WSManListeners) { $StatusObj.WSManListeners } else { '(None)' })" -Level INFO
    Write-Log "  VPN Firewall Rule (Port 5985): $($StatusObj.VpnFirewallRule)" -Level $(if ($StatusObj.VpnFirewallRule -match 'Enabled=True') { 'SUCCESS' } else { 'WARN' })
    Write-Log "  Active Network Profiles     : $(if ($StatusObj.NetworkProfiles) { $StatusObj.NetworkProfiles } else { '(None Detected)' })" -Level DETAIL
    Write-Log "--------------------------------------------------------------------------------`n" -Level HEADER
}

if ($Status) {
    $report = Get-ServerManagementStatus
    Show-StatusReport -StatusObj $report
    if ($PassThru) { return $report }
    return
}

# ==============================================================================
# LIVE CONFIGURATION WORKFLOW
# ==============================================================================
$totalSteps = 5
$stepResults = [ordered]@{
    PSRemotingAction     = "Unchanged"
    CredSSPServerAction  = "Unchanged"
    NetworkProfileAction = "Unchanged"
    FirewallRulesAction  = "Unchanged"
    VpnRuleAction        = "Unchanged"
    SMRemotingAction     = "Unchanged"
    WinRMRestartAction   = "Unchanged"
}

# ------------------------------------------------------------------------------
# STEP 1: ENABLE POWERSHELL REMOTING (WINRM)
# ------------------------------------------------------------------------------
Write-Log "`n[STEP 1/$totalSteps] Enabling PowerShell Remoting & WinRM Listener..." -Level STEP
Write-Log "  [i] Using -SkipNetworkProfileCheck so Public/VPN interfaces do not abort listener creation." -Level DETAIL

if ($DryRun) {
    Write-Log "  [DRY-RUN] Would execute: Enable-PSRemoting -SkipNetworkProfileCheck -Force" -Level WARN
    $stepResults.PSRemotingAction = "Simulated Enable-PSRemoting"
}
else {
    try {
        Enable-PSRemoting -SkipNetworkProfileCheck -Force -ErrorAction Stop | Out-Null
        Write-Log "  [+] PowerShell Remoting enabled with -SkipNetworkProfileCheck." -Level SUCCESS
        $stepResults.PSRemotingAction = "Enabled (WinRM HTTP 5985 Active)"
    }
    catch {
        Write-Log "  [!] Enable-PSRemoting reported: $($_.Exception.Message)" -Level WARN
        $stepResults.PSRemotingAction = "Warning ($($_.Exception.Message))"
    }
}

# ------------------------------------------------------------------------------
# STEP 2: ENABLE CREDSSP SERVER ROLE
# ------------------------------------------------------------------------------
Write-Log "`n[STEP 2/$totalSteps] Enabling WSMan CredSSP Server Role..." -Level STEP

if ($DryRun) {
    Write-Log "  [DRY-RUN] Would execute: Enable-WSManCredSSP -Role Server -Force" -Level WARN
    $stepResults.CredSSPServerAction = "Simulated Enable-WSManCredSSP"
}
else {
    try {
        Enable-WSManCredSSP -Role Server -Force -ErrorAction Stop | Out-Null
        Write-Log "  [+] WSMan CredSSP Server role enabled successfully." -Level SUCCESS
        $stepResults.CredSSPServerAction = "Enabled (Role: Server)"
    }
    catch {
        Write-Log "  [!] Enable-WSManCredSSP reported: $($_.Exception.Message)" -Level WARN
        $stepResults.CredSSPServerAction = "Warning ($($_.Exception.Message))"
    }
}

# ------------------------------------------------------------------------------
# STEP 3: NETWORK CONNECTION CATEGORY (PRIVATE PROFILE HARDENING)
# ------------------------------------------------------------------------------
Write-Log "`n[STEP 3/$totalSteps] Inspecting & Hardening Network Connection Profiles..." -Level STEP

if ($SetPrivateNetworkProfile) {
    $activeProfiles = @(Get-NetConnectionProfile -ErrorAction SilentlyContinue)
    $switchedCount = 0
    foreach ($prof in $activeProfiles) {
        Write-Log "  [*] Adapter '$($prof.InterfaceAlias)' (Network: '$($prof.Name)') -> Category: $($prof.NetworkCategory)" -Level INFO
        if ($prof.NetworkCategory -eq "Public") {
            if ($DryRun) {
                Write-Log "      [DRY-RUN] Would switch adapter '$($prof.InterfaceAlias)' from Public to Private." -Level WARN
                $switchedCount++
            }
            else {
                try {
                    Set-NetConnectionProfile -InterfaceIndex $prof.InterfaceIndex -NetworkCategory Private -ErrorAction Stop
                    Write-Log "      [+] Switched adapter '$($prof.InterfaceAlias)' to Private." -Level SUCCESS
                    $switchedCount++
                }
                catch {
                    Write-Log "      [!] Could not change network category: $($_.Exception.Message)" -Level WARN
                }
            }
        }
    }
    $stepResults.NetworkProfileAction = if ($switchedCount -gt 0) { "Switched $switchedCount Public profile(s) to Private" } else { "All active profiles already Private/Domain" }
}
else {
    Write-Log "  [i] -SetPrivateNetworkProfile is disabled; network categories left unchanged." -Level DETAIL
    $stepResults.NetworkProfileAction = "Skipped by parameter"
}

# ------------------------------------------------------------------------------
# STEP 4: COMPREHENSIVE FIREWALL PROVISIONING & DEDICATED VPN RULE
# ------------------------------------------------------------------------------
Write-Log "`n[STEP 4/$totalSteps] Configuring Windows Firewall Rules (WMI, WinRM, Hyper-V & WireGuard VPN)..." -Level STEP

# 4A. Language-independent rule names + English/Polish DisplayGroups
$fwRuleNamePatterns = @("WINRM-*", "WMI-*", "VM-Monitoring-*", "Hyper-V-*")
$enabledRuleCount = 0

foreach ($pattern in $fwRuleNamePatterns) {
    $matchingRules = @(Get-NetFirewallRule -Name $pattern -ErrorAction SilentlyContinue)
    if ($matchingRules.Count -gt 0) {
        if ($DryRun) {
            Write-Log "  [DRY-RUN] Would enable $($matchingRules.Count) firewall rules matching Name '$pattern'." -Level WARN
            $enabledRuleCount += $matchingRules.Count
        }
        else {
            $matchingRules | Enable-NetFirewallRule -ErrorAction SilentlyContinue
            $matchingRules | Set-NetFirewallRule -Profile Any -RemoteAddress Any -ErrorAction SilentlyContinue
            $enabledRuleCount += $matchingRules.Count
            Write-Log "  [+] Enabled & opened $($matchingRules.Count) rule(s) matching Name '$pattern'." -Level SUCCESS
        }
    }
}

$fwDisplayGroups = @(
    "Windows Management Instrumentation (WMI)",
    "Instrumentacja zarzadzania systemu Windows (WMI)",
    "Windows Remote Management",
    "Zdalne zarzadzanie systemem Windows",
    "Hyper-V Management Clients",
    "Klienci zarzadzania funkcji Hyper-V",
    "Hyper-V"
)
foreach ($grp in $fwDisplayGroups) {
    $grpRules = @(Get-NetFirewallRule -DisplayGroup $grp -ErrorAction SilentlyContinue)
    if ($grpRules.Count -gt 0) {
        if ($DryRun) {
            Write-Log "  [DRY-RUN] Would enable DisplayGroup '$grp' ($($grpRules.Count) rules)." -Level WARN
        }
        else {
            $grpRules | Enable-NetFirewallRule -ErrorAction SilentlyContinue
            $grpRules | Set-NetFirewallRule -Profile Any -RemoteAddress Any -ErrorAction SilentlyContinue
            Write-Log "  [+] Enabled Firewall DisplayGroup '$grp' ($($grpRules.Count) rules, RemoteAddress: Any)." -Level SUCCESS
        }
    }
}
$stepResults.FirewallRulesAction = "Configured ($enabledRuleCount standard rules opened)"

# 4B. Explicit Dedicated Inbound Rule for VPN / All Subnets
$vpnRuleName = "Allow-HyperV-WinRM-VPN"
$vpnPorts = @(5985, 5986, 135, 445, 2179)
Write-Log "  [*] Provisioning dedicated inbound rule '$vpnRuleName' for TCP ports: $($vpnPorts -join ', ')..." -Level INFO

if ($DryRun) {
    Write-Log "  [DRY-RUN] Would create/update rule '$vpnRuleName' (TCP: 5985, 5986, 135, 445, 2179 | Profile: Any | RemoteAddress: Any)." -Level WARN
    $stepResults.VpnRuleAction = "Simulated (TCP 5985, 5986, 135, 445, 2179)"
}
else {
    try {
        Remove-NetFirewallRule -Name $vpnRuleName -ErrorAction SilentlyContinue
        New-NetFirewallRule -Name $vpnRuleName `
            -DisplayName "Hyper-V & WinRM Remote Management (VPN)" `
            -Description "Allows remote management of Hyper-V, WinRM, RPC, and VMConnect over LAN and VPN tunnels (e.g. WireGuard)." `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort $vpnPorts `
            -Action Allow `
            -Profile Any `
            -RemoteAddress Any `
            -ErrorAction Stop | Out-Null
        Write-Log "  [+] Successfully created rule '$vpnRuleName' (Ports: $($vpnPorts -join ', ') | Profiles: Any | RemoteAddress: Any)." -Level SUCCESS
        $stepResults.VpnRuleAction = "Active (Ports: 5985, 5986, 135, 445, 2179 Allowed)"
    }
    catch {
        Write-Log "  [!] Failed to create rule '$vpnRuleName': $($_.Exception.Message)" -Level WARN
        $stepResults.VpnRuleAction = "Warning ($($_.Exception.Message))"
    }
}

# 4C. Server Manager Remoting (Configure-SMRemoting.exe)
if (-not $SkipConfigureSMRemoting) {
    $smRemotingExe = Join-Path -Path $env:SystemRoot -ChildPath "System32\Configure-SMRemoting.exe"
    if (Test-Path -LiteralPath $smRemotingExe -PathType Leaf) {
        if ($DryRun) {
            Write-Log "  [DRY-RUN] Would execute: Configure-SMRemoting.exe -Enable" -Level WARN
            $stepResults.SMRemotingAction = "Simulated Configure-SMRemoting"
        }
        else {
            Write-Log "  [*] Executing: Configure-SMRemoting.exe -Enable..." -Level INFO
            try {
                $smOut = & $smRemotingExe -Enable 2>&1
                Write-Log "  [+] Configure-SMRemoting completed: $($smOut -join ' ')" -Level SUCCESS
                $stepResults.SMRemotingAction = "Enabled (Server Manager remoting ready)"
            }
            catch {
                Write-Log "  [!] Configure-SMRemoting error: $($_.Exception.Message)" -Level WARN
                $stepResults.SMRemotingAction = "Warning ($($_.Exception.Message))"
            }
        }
    }
    else {
        Write-Log "  [i] Configure-SMRemoting.exe not present on this Windows edition (skipped)." -Level DETAIL
        $stepResults.SMRemotingAction = "Not Present (Desktop Edition)"
    }
}
else {
    $stepResults.SMRemotingAction = "Skipped by parameter"
}

# ------------------------------------------------------------------------------
# STEP 5: RESTART WINRM SERVICE & HEALTH VERIFICATION
# ------------------------------------------------------------------------------
Write-Log "`n[STEP 5/$totalSteps] Restarting WinRM Service & Verifying Listener State..." -Level STEP

if ($RestartWinRM) {
    if ($DryRun) {
        Write-Log "  [DRY-RUN] Would restart 'WinRM' service." -Level WARN
        $stepResults.WinRMRestartAction = "Simulated Restart"
    }
    else {
        Write-Log "  [*] Restarting WinRM service..." -Level INFO
        try {
            Restart-Service -Name "WinRM" -Force -ErrorAction Stop
            Write-Log "  [+] WinRM service restarted successfully." -Level SUCCESS
            $stepResults.WinRMRestartAction = "Restarted & Running"
        }
        catch {
            Write-Log "  [!] Failed to restart WinRM service: $($_.Exception.Message)" -Level WARN
            $stepResults.WinRMRestartAction = "Warning ($($_.Exception.Message))"
        }
    }
}
else {
    $stepResults.WinRMRestartAction = "Skipped by parameter"
}

# Final Health Check
$finalAudit = Get-ServerManagementStatus

# ==============================================================================
# FINAL EXECUTION SUMMARY
# ==============================================================================
$elapsed = (Get-Date) - $script:StartTime
$durationFormatted = "{0:mm}m {0:ss}.{0:fff}s" -f $elapsed

Write-Log "`n================================================================================" -Level HEADER
Write-Log "  HYPER-V SERVER REMOTE MANAGEMENT CONFIGURATION SUMMARY" -Level HEADER
Write-Log "================================================================================" -Level HEADER
Write-Log "  Script & Version          : $($SCRIPT_INFO.FileName) v$($SCRIPT_INFO.Version)" -Level INFO
Write-Log "  Execution Mode            : $(if ($DryRun) { 'DRY-RUN (Simulation Only)' } else { 'LIVE CONFIGURATION (Host Mode)' })" -Level INFO
Write-Log "  Hyper-V Host ComputerName : $($finalAudit.ComputerName)" -Level SUCCESS
Write-Log "  1. PowerShell Remoting    : $($stepResults.PSRemotingAction)" -Level SUCCESS
Write-Log "  2. CredSSP Server Role    : $($stepResults.CredSSPServerAction)" -Level SUCCESS
Write-Log "  3. Network Profiles       : $($stepResults.NetworkProfileAction)" -Level INFO
Write-Log "  4. Firewall Standard Rules: $($stepResults.FirewallRulesAction)" -Level SUCCESS
Write-Log "  5. Dedicated VPN Rule     : $($stepResults.VpnRuleAction)" -Level SUCCESS
Write-Log "  6. Server Manager Remoting: $($stepResults.SMRemotingAction)" -Level INFO
Write-Log "  7. WinRM Service & Port   : Status=$($finalAudit.WinRMServiceStatus) | Port 5985 Listening=$(if ($finalAudit.WinRMPort5985Listen) { 'YES (Active)' } else { 'NO' })" -Level $(if ($finalAudit.WinRMPort5985Listen) { 'SUCCESS' } else { 'WARN' })
Write-Log "  Total Duration            : $durationFormatted" -Level DETAIL
if (-not $NoLog -and $script:ActiveLogFile) {
    Write-Log "  Execution Log File        : $script:ActiveLogFile" -Level INFO
}

Write-Log "`n--------------------------------------------------------------------------------" -Level HEADER
Write-Log "  NEXT STEPS: CONNECTING FROM CLIENT WORKSTATION (Hyper-V Manager)" -Level STEP
Write-Log "--------------------------------------------------------------------------------" -Level HEADER
Write-Log "  From your client computer (Windows 10/11):" -Level INFO
Write-Log "  1. Ensure the client is configured using enable-hyper-v-remote-management.ps1:" -Level DETAIL
Write-Log "     .\enable-hyper-v-remote-management.ps1 -ServerName '$($finalAudit.ComputerName)' -ServerIP '<Host-IP>'" -Level DETAIL
Write-Log "  2. Open Hyper-V Manager (virtmgmt.msc)." -Level DETAIL
Write-Log "  3. Click 'Connect to Server...' -> 'Another computer:' -> enter '$($finalAudit.ComputerName)'." -Level SUCCESS
Write-Log "  4. Check 'Connect as another user' -> 'Set User...' -> '$($finalAudit.ComputerName)\Administrator'." -Level SUCCESS
Write-Log "================================================================================`n" -Level HEADER

if ($PassThru) {
    return [PSCustomObject]@{
        ScriptName          = $SCRIPT_INFO.Name
        ScriptVersion       = $SCRIPT_INFO.Version
        HostComputerName    = $finalAudit.ComputerName
        WinRMStatus         = $finalAudit.WinRMServiceStatus
        WinRMPort5985Listen = $finalAudit.WinRMPort5985Listen
        CredSSPServerAuth   = $finalAudit.CredSSPServerAuth
        VpnFirewallRule     = $finalAudit.VpnFirewallRule
        NetworkProfiles     = $finalAudit.NetworkProfiles
        DurationSeconds     = [math]::Round($elapsed.TotalSeconds, 2)
        LogFile             = $script:ActiveLogFile
    }
}

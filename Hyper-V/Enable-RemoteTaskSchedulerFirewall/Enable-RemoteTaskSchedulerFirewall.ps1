<#
================================================================================
  Script Name : Enable-RemoteTaskSchedulerFirewall.ps1
  Author      : Roman Pindela
  Contact     : roman.pindela@gmail.com
  Version     : 1.0.0
  Last Modified: 2026-11-18
  License     : MIT
  Repository  : https://github.com/romanpindela/Windows-Server

  DESCRIPTION:
    Enterprise-grade PowerShell tool that configures, audits, and manages
    Windows Defender Firewall rules on a Hyper-V Server (or Windows Server /
    Windows 10/11 Pro) host to allow remote Task Scheduler management via
    Microsoft Management Console (taskschd.msc / RSAT) from an admin station.

    Key Capabilities:
    1. Zero-Parameter Interactive Help (-Help / -h):
       Displays complete syntax, parameter reference, practical examples,
       version, and author details when run without arguments or with -Help,
       without triggering an unnecessary UAC prompt.
    2. Language-Independent Built-In Firewall Provisioning:
       Locates the native "Remote Scheduled Tasks Management" firewall rules
       using language-independent rule names (RemoteTask-*) and Windows
       Firewall API resource group (@FirewallAPI.dll,-33252), with English
       and Polish display group fallbacks.
    3. Optional Network Profile & Subnet Scoping (-FirewallProfile / -RemoteAddress):
       Preserves built-in Windows defaults by default, or applies explicit
       profiles (Domain, Private, Public, Any) and remote IP/CIDR addresses
       (e.g., Any or 10.10.1.0/24 for WireGuard/OpenVPN/routed management).
    4. Reversible Rollback (-Disable) & Read-Only Audit (-Status):
       Cleanly disables RemoteTask-* rules when remote MMC access is no longer
       required, or inspects rule state, RPC/Schedule services, and TCP 135.
    5. Safe Simulation (-WhatIf & -DryRun) + Progress Indicator:
       Supports PowerShell ShouldProcess (-WhatIf / -Confirm) alongside -DryRun,
       and displays step-by-step progress via Write-Progress.
    6. Multi-Language UAC Auto-Elevation (PS 5.1 & PS 7+):
       Verifies Administrator privileges via Well-Known SID S-1-5-32-544 and
       re-launches the active PowerShell host (powershell.exe or pwsh.exe)
       elevated while preserving CLI parameters.
    7. Detailed Audit Logging:
       Writes UTF-8 timestamped logs to:
       C:\Logs\<yyyyMMdd-HHmmss>-Enable-RemoteTaskSchedulerFirewall-<Host>-<User>.logs
================================================================================
#>

<#
.SYNOPSIS
    Configures, audits, or disables Windows Defender Firewall rules on a Hyper-V
    host for remote MMC Task Scheduler (taskschd.msc) management.

.DESCRIPTION
    Enables, disables, or audits the built-in Windows Defender Firewall rules
    required by Microsoft Management Console (taskschd.msc / RSAT) to connect
    remotely to a Hyper-V Server or Windows Server host:
    - RemoteTask-RPCSS-In-TCP         (TCP 135 - RPC Endpoint Mapper)
    - RemoteTask-RPCSS-In-TCP-NoScope (TCP 135 - RPC Endpoint Mapper, Domain)
    - RemoteTask-In-TCP               (RPC Dynamic Ports - Task Scheduler)
    - RemoteTask-In-TCP-NoScope       (RPC Dynamic Ports - Task Scheduler, Domain)

    Works identically on English and Polish Windows Server / Windows 10/11
    editions by matching language-independent rule names and resource IDs.

.PARAMETER Enable
    Switch parameter. Enables the Remote Scheduled Tasks Management firewall
    rules and verifies prerequisite services (Schedule, RpcSs).
    Aliases: -Configure, -Apply

.PARAMETER Disable
    Switch parameter. Disables the Remote Scheduled Tasks Management firewall
    rules for clean security rollback.
    Aliases: -Block, -Revert

.PARAMETER Status
    Switch parameter. Performs a read-only audit of RemoteTask-* firewall rules,
    Schedule/RpcSs services, TCP port 135 listener, and network profiles.
    Aliases: -Check, -Verify, -Info

.PARAMETER FirewallProfile
    Optional array of firewall profiles to apply when -Enable is specified.
    Valid values: Preserve, Domain, Private, Public, Any.
    Default: @('Preserve') (keeps built-in Windows rule profile assignments).

.PARAMETER RemoteAddress
    Optional array of remote IP addresses, CIDR subnets, 'LocalSubnet', or 'Any'
    to apply when -Enable is specified (useful for VPN tunnels or routed VLANs).

.PARAMETER DryRun
    Switch parameter. Simulates all changes without modifying firewall rules.
    Aliases: -Simulate, -Preview

.PARAMETER SkipAdminCheck
    Switch parameter. Skips automatic UAC Administrator privilege verification
    and elevation.

.PARAMETER PassThru
    Switch parameter. Returns a structured [PSCustomObject] report to the
    PowerShell pipeline.

.PARAMETER LogPath
    Custom file path for the execution log file.
    Default: C:\Logs\<yyyyMMdd-HHmmss>-Enable-RemoteTaskSchedulerFirewall-<ComputerName>-<UserName>.logs
    Aliases: -l, -Log

.PARAMETER NoLog
    Switch parameter. Disables writing execution logs to disk.

.PARAMETER Help
    Switch parameter (-Help / -h). Displays this help guide and exits safely.
    Aliases: -h

.EXAMPLE
    .\Enable-RemoteTaskSchedulerFirewall.ps1
    Displays the built-in help guide without requiring Administrator elevation.

.EXAMPLE
    .\Enable-RemoteTaskSchedulerFirewall.ps1 -Status
    Audits current Remote Task Scheduler firewall rules, services, and RPC
    port 135 state without making changes.

.EXAMPLE
    .\Enable-RemoteTaskSchedulerFirewall.ps1 -Enable
    Enables all built-in Remote Scheduled Tasks Management firewall rules using
    Windows default profile and subnet scoping.

.EXAMPLE
    .\Enable-RemoteTaskSchedulerFirewall.ps1 -Enable -FirewallProfile Private,Domain -RemoteAddress Any
    Enables the rules for Private and Domain profiles and allows connections
    from any remote IP address (recommended when managing over WireGuard/VPN).

.EXAMPLE
    .\Enable-RemoteTaskSchedulerFirewall.ps1 -Enable -WhatIf
    Previews all firewall rule changes using standard PowerShell ShouldProcess.

.EXAMPLE
    .\Enable-RemoteTaskSchedulerFirewall.ps1 -Disable
    Disables all Remote Scheduled Tasks Management firewall rules.

.NOTES
    Author       : Roman Pindela
    Contact      : roman.pindela@gmail.com
    GitHub       : https://github.com/romanpindela/Windows-Server
    Version      : 1.0.0
    Last Modified: 2026-11-18
    License      : MIT
    Compatible   : Windows Server 2016/2019/2022/2025, Windows 10/11 Pro (EN/PL)
    PowerShell   : Windows PowerShell 5.1 and PowerShell 7+
    Privileges   : Administrator (auto-elevates via UAC using SID S-1-5-32-544)
#>

[CmdletBinding(DefaultParameterSetName = 'Help', SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param (
    [Parameter(Mandatory = $true, ParameterSetName = 'Enable')]
    [Alias('Configure', 'Apply')]
    [switch]$Enable,

    [Parameter(Mandatory = $true, ParameterSetName = 'Disable')]
    [Alias('Block', 'Revert')]
    [switch]$Disable,

    [Parameter(Mandatory = $true, ParameterSetName = 'Status')]
    [Alias('Check', 'Verify', 'Info')]
    [switch]$Status,

    [Parameter(Mandatory = $false, ParameterSetName = 'Enable')]
    [ValidateNotNullOrEmpty()]
    [string[]]$FirewallProfile = @('Preserve'),

    [Parameter(Mandatory = $false, ParameterSetName = 'Enable')]
    [ValidateNotNullOrEmpty()]
    [string[]]$RemoteAddress,

    [Parameter(Mandatory = $false, ParameterSetName = 'Enable')]
    [Parameter(Mandatory = $false, ParameterSetName = 'Disable')]
    [Parameter(Mandatory = $false, ParameterSetName = 'Status')]
    [Alias('Simulate', 'Preview')]
    [switch]$DryRun,

    [Parameter(Mandatory = $false, ParameterSetName = 'Enable')]
    [Parameter(Mandatory = $false, ParameterSetName = 'Disable')]
    [Parameter(Mandatory = $false, ParameterSetName = 'Status')]
    [switch]$SkipAdminCheck,

    [Parameter(Mandatory = $false, ParameterSetName = 'Enable')]
    [Parameter(Mandatory = $false, ParameterSetName = 'Disable')]
    [Parameter(Mandatory = $false, ParameterSetName = 'Status')]
    [switch]$PassThru,

    [Parameter(Mandatory = $false, ParameterSetName = 'Enable')]
    [Parameter(Mandatory = $false, ParameterSetName = 'Disable')]
    [Parameter(Mandatory = $false, ParameterSetName = 'Status')]
    [ValidateNotNullOrEmpty()]
    [Alias('l', 'Log')]
    [string]$LogPath,

    [Parameter(Mandatory = $false, ParameterSetName = 'Enable')]
    [Parameter(Mandatory = $false, ParameterSetName = 'Disable')]
    [Parameter(Mandatory = $false, ParameterSetName = 'Status')]
    [switch]$NoLog,

    [Parameter(Mandatory = $false, ParameterSetName = 'Help')]
    [Alias('h')]
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ==============================================================================
# SCRIPT METADATA & CONFIGURATION
# ==============================================================================
$SCRIPT_INFO = @{
    Name         = 'Enable-RemoteTaskSchedulerFirewall'
    FileName     = 'Enable-RemoteTaskSchedulerFirewall.ps1'
    Version      = '1.0.0'
    Author       = 'Roman Pindela'
    Contact      = 'roman.pindela@gmail.com'
    GitHub       = 'https://github.com/romanpindela/Windows-Server'
    LastModified = '2026-11-18'
    License      = 'MIT'
}

$script:ActiveLogFile = $null
$script:StartTime = Get-Date
$script:ProgressId = 1
$script:ProgressActivity = 'Remote Task Scheduler Firewall Management'
$script:FirewallGroupResource = '@FirewallAPI.dll,-33252'

# ==============================================================================
# HELPER FUNCTIONS (APPROVED POWERSHELL VERBS)
# ==============================================================================
function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'SUCCESS', 'WARN', 'ERROR', 'STEP', 'HEADER', 'DETAIL')]
        [string]$Level = 'INFO',

        [Parameter(Mandatory = $false)]
        [ConsoleColor]$Color = [ConsoleColor]::White
    )

    $colorMap = @{
        'INFO'    = [ConsoleColor]::White
        'SUCCESS' = [ConsoleColor]::Green
        'WARN'    = [ConsoleColor]::Yellow
        'ERROR'   = [ConsoleColor]::Red
        'STEP'    = [ConsoleColor]::Cyan
        'HEADER'  = [ConsoleColor]::Cyan
        'DETAIL'  = [ConsoleColor]::Gray
    }

    $effectiveColor = if ($PSBoundParameters.ContainsKey('Color')) {
        $Color
    }
    else {
        $colorMap[$Level]
    }

    try { [Console]::CursorLeft = 0 } catch { Out-Null }
    Write-Host $Message -ForegroundColor $effectiveColor

    if (-not $NoLog -and -not [string]::IsNullOrWhiteSpace($script:ActiveLogFile)) {
        try {
            $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            $cleanMessage = $Message -replace '^\r?\n', ''
            $logEntry = "[$timestamp] [$Level] $cleanMessage`r`n"
            [System.IO.File]::AppendAllText($script:ActiveLogFile, $logEntry, [System.Text.Encoding]::UTF8)
        }
        catch {
            Write-Verbose "Unable to append log entry: $($_.Exception.Message)"
        }
    }
}

function Initialize-LogFile {
    [CmdletBinding()]
    param ()

    if ($NoLog) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        $defaultLogDir = 'C:\Logs'
        if (-not (Test-Path -LiteralPath $defaultLogDir)) {
            try {
                New-Item -Path $defaultLogDir -ItemType Directory -Force -WhatIf:$false | Out-Null
            }
            catch {
                $defaultLogDir = [System.IO.Path]::GetTempPath()
            }
        }

        $timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
        $computerName = [System.Environment]::MachineName
        $userName = [System.Environment]::UserName
        $script:ActiveLogFile = Join-Path -Path $defaultLogDir -ChildPath "$timestamp-$($SCRIPT_INFO.Name)-$computerName-$userName.logs"
    }
    else {
        $parentDir = [System.IO.Path]::GetDirectoryName($LogPath)
        if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path -LiteralPath $parentDir)) {
            New-Item -Path $parentDir -ItemType Directory -Force -WhatIf:$false | Out-Null
        }
        $script:ActiveLogFile = $LogPath
    }
}

function Test-ValidFilePathInput {
    [CmdletBinding()]
    [OutputType([bool])]
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

    return $true
}

function Resolve-CommaSeparatedInput {
    [CmdletBinding()]
    [OutputType([string[]])]
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$Values
    )

    $resolved = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $Values) {
        if ([string]::IsNullOrWhiteSpace($item)) {
            continue
        }
        foreach ($token in ($item -split ',')) {
            $trimmed = $token.Trim()
            if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
                $resolved.Add($trimmed)
            }
        }
    }

    return @($resolved.ToArray())
}

function Resolve-FirewallProfileInput {
    [CmdletBinding()]
    [OutputType([string[]])]
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$ProfileValues
    )

    $validProfiles = @('Preserve', 'Domain', 'Private', 'Public', 'Any')
    $normalized = @(Resolve-CommaSeparatedInput -Values $ProfileValues)

    if ($normalized.Count -eq 0) {
        throw "Validation Error: Parameter 'FirewallProfile' cannot be empty."
    }

    $canonical = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $normalized) {
        $match = $validProfiles | Where-Object { $_ -ieq $entry } | Select-Object -First 1
        if ($null -eq $match) {
            throw "Validation Error: Invalid FirewallProfile '$entry'. Allowed values: $($validProfiles -join ', ')."
        }
        if (-not $canonical.Contains($match)) {
            $canonical.Add($match)
        }
    }

    if (($canonical -contains 'Preserve') -and ($canonical.Count -gt 1)) {
        throw "Validation Error: 'Preserve' cannot be combined with explicit profile names in -FirewallProfile."
    }

    return @($canonical.ToArray())
}

function Resolve-RemoteAddressInput {
    [CmdletBinding()]
    [OutputType([string[]])]
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$AddressList
    )

    $allowedKeywords = @('Any', 'LocalSubnet', 'Defaultgateway', 'DHCP', 'DNS', 'WINS', 'Intranet', 'Internet')
    $ipOrCidrPattern = '^[0-9a-fA-F:\.\-\/]+$'
    $normalized = @(Resolve-CommaSeparatedInput -Values $AddressList)

    if ($normalized.Count -eq 0) {
        throw "Validation Error: Parameter 'RemoteAddress' cannot be empty."
    }

    foreach ($entry in $normalized) {
        $keywordMatch = $allowedKeywords | Where-Object { $_ -ieq $entry } | Select-Object -First 1
        if (($null -eq $keywordMatch) -and ($entry -notmatch $ipOrCidrPattern)) {
            throw "Validation Error: Invalid RemoteAddress entry '$entry'. Use IPv4/IPv6, CIDR (e.g. 10.10.1.0/24), IP range, 'LocalSubnet', or 'Any'."
        }
    }

    return @($normalized)
}

function Show-ScriptHelp {
    [CmdletBinding()]
    param ()

    try { [Console]::CursorLeft = 0 } catch { Out-Null }
    Write-Host @"
================================================================================
  $($SCRIPT_INFO.Name) - v$($SCRIPT_INFO.Version)
  Author : $($SCRIPT_INFO.Author) | Contact: $($SCRIPT_INFO.Contact)
  GitHub : $($SCRIPT_INFO.GitHub)
  Date   : $($SCRIPT_INFO.LastModified) | License: $($SCRIPT_INFO.License)
================================================================================
DESCRIPTION:
  Enterprise-grade PowerShell tool that configures, audits, and manages
  Windows Defender Firewall rules on a Hyper-V Server (or Windows Server /
  Windows 10/11 Pro) host so an administrator can manage Task Scheduler
  remotely via MMC (taskschd.msc / RSAT) from an admin workstation.

  Targeted Language-Independent Firewall Rules (@FirewallAPI.dll,-33252):
  - RemoteTask-RPCSS-In-TCP         (TCP 135 - RPC Endpoint Mapper)
  - RemoteTask-RPCSS-In-TCP-NoScope (TCP 135 - RPC Endpoint Mapper, Domain)
  - RemoteTask-In-TCP               (RPC Dynamic Ports - Task Scheduler)
  - RemoteTask-In-TCP-NoScope       (RPC Dynamic Ports - Task Scheduler, Domain)

  Key Capabilities:
  1. Zero-Parameter Help (-Help / -h): Displays syntax, parameter reference,
     examples, version, and author details without triggering UAC elevation.
  2. Language-Independent Discovery: Works on English & Polish Windows editions
     via rule Name patterns (RemoteTask-*) and @FirewallAPI.dll,-33252.
  3. Flexible Profile & Subnet Scoping: Optionally adjusts -FirewallProfile
     and -RemoteAddress (essential for WireGuard VPN or routed admin VLANs).
  4. Reversible & Auditable: Provides -Status (read-only) and -Disable modes.
  5. Safe Simulation: Supports both -WhatIf / -Confirm and -DryRun.
  6. Dual PowerShell Compatibility: Supports Windows PowerShell 5.1 & PS 7+.
  7. Audit Logging: Writes UTF-8 logs to C:\Logs\...

SYNTAX:
  # 1. Display Help (Default when run without parameters):
  .\Enable-RemoteTaskSchedulerFirewall.ps1 [-Help | -h]

  # 2. Audit Current Firewall & Service State (Read-Only):
  .\Enable-RemoteTaskSchedulerFirewall.ps1 -Status [-PassThru] [-NoLog]

  # 3. Enable Firewall Rules for MMC taskschd.msc (Default Windows Scope):
  .\Enable-RemoteTaskSchedulerFirewall.ps1 -Enable [-WhatIf] [-DryRun]

  # 4. Enable Firewall Rules for VPN / Cross-Subnet Management:
  .\Enable-RemoteTaskSchedulerFirewall.ps1 -Enable
      [-FirewallProfile <Preserve|Domain|Private|Public|Any>]
      [-RemoteAddress <String[]>] [-WhatIf] [-DryRun]

  # 5. Disable Firewall Rules (Security Rollback):
  .\Enable-RemoteTaskSchedulerFirewall.ps1 -Disable [-WhatIf] [-DryRun]

PARAMETERS:
  -Enable               Enables Remote Scheduled Tasks Management rules.
                        Aliases: -Configure, -Apply
  -Disable              Disables Remote Scheduled Tasks Management rules.
                        Aliases: -Block, -Revert
  -Status               Read-only audit of rules, services, and TCP 135.
                        Aliases: -Check, -Verify, -Info
  -FirewallProfile      Target profile(s): Preserve, Domain, Private, Public, Any.
                        Default: Preserve
  -RemoteAddress        Optional IP/CIDR list, 'LocalSubnet', or 'Any'.
  -DryRun               Simulates changes without modifying firewall rules.
                        Aliases: -Simulate, -Preview
  -WhatIf               Standard PowerShell ShouldProcess simulation.
  -SkipAdminCheck       Skips UAC Administrator privilege verification.
  -PassThru             Returns structured [PSCustomObject] result to pipeline.
  -LogPath <String>     Custom log file path (Default: C:\Logs\...).
  -NoLog                Disables file logging.
  -Help / -h            Displays this help screen and exits cleanly.

PRACTICAL EXAMPLES:
  1. Display help and syntax safely:
     .\Enable-RemoteTaskSchedulerFirewall.ps1

  2. Audit current Remote Task Scheduler firewall status:
     .\Enable-RemoteTaskSchedulerFirewall.ps1 -Status

  3. Enable MMC Task Scheduler firewall rules on Hyper-V host (LAN/LocalSubnet):
     .\Enable-RemoteTaskSchedulerFirewall.ps1 -Enable

  4. Enable rules for Private & Domain profiles across VPN/routed subnets:
     .\Enable-RemoteTaskSchedulerFirewall.ps1 -Enable -FirewallProfile Private,Domain -RemoteAddress Any

  5. Preview changes without modifying the firewall:
     .\Enable-RemoteTaskSchedulerFirewall.ps1 -Enable -RemoteAddress 10.10.1.0/24 -WhatIf

  6. Disable Remote Task Scheduler firewall rules:
     .\Enable-RemoteTaskSchedulerFirewall.ps1 -Disable

FIRST RUN / UNBLOCKING NOTE:
  After downloading this script from GitHub, unblock it before running:
     Unblock-File -Path .\Enable-RemoteTaskSchedulerFirewall.ps1
================================================================================
"@ -ForegroundColor Yellow
}

function Test-IsAdministrator {
    [CmdletBinding()]
    [OutputType([bool])]
    param ()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $adminSid = New-Object Security.Principal.SecurityIdentifier(
        [Security.Principal.WellKnownSidType]::BuiltInAdministratorsSid,
        $null
    )
    return $principal.IsInRole($adminSid)
}

function Invoke-UacElevation {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $false)]
        [string[]]$NormalizedProfiles,

        [Parameter(Mandatory = $false)]
        [string[]]$NormalizedRemoteAddresses
    )

    if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Relaunch PowerShell with Administrator privileges via UAC')) {
        return
    }

    Write-Host 'Missing Administrator privileges. Requesting UAC elevation (SID S-1-5-32-544)...' -ForegroundColor Yellow

    $relaunchArgs = [System.Collections.Generic.List[string]]::new()
    $relaunchArgs.Add('-NoProfile')
    $relaunchArgs.Add('-ExecutionPolicy')
    $relaunchArgs.Add('Bypass')
    $relaunchArgs.Add('-File')
    $relaunchArgs.Add("`"$PSCommandPath`"")

    if ($Enable) { $relaunchArgs.Add('-Enable') }
    if ($Disable) { $relaunchArgs.Add('-Disable') }
    if ($Status) { $relaunchArgs.Add('-Status') }
    if ($null -ne $NormalizedProfiles -and @($NormalizedProfiles).Count -gt 0 -and $PSBoundParameters.ContainsKey('FirewallProfile')) {
        $relaunchArgs.Add('-FirewallProfile')
        $relaunchArgs.Add(($NormalizedProfiles -join ','))
    }
    if ($null -ne $NormalizedRemoteAddresses -and @($NormalizedRemoteAddresses).Count -gt 0) {
        $relaunchArgs.Add('-RemoteAddress')
        $relaunchArgs.Add(($NormalizedRemoteAddresses -join ','))
    }
    if ($DryRun) { $relaunchArgs.Add('-DryRun') }
    if ($WhatIfPreference) { $relaunchArgs.Add('-WhatIf') }
    if ($PassThru) { $relaunchArgs.Add('-PassThru') }
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        $relaunchArgs.Add('-LogPath')
        $relaunchArgs.Add("`"$LogPath`"")
    }
    if ($NoLog) { $relaunchArgs.Add('-NoLog') }

    $psExecutable = if ($PSVersionTable.PSVersion.Major -ge 6) { 'pwsh.exe' } else { 'powershell.exe' }
    Start-Process -FilePath $psExecutable -ArgumentList ($relaunchArgs -join ' ') -Verb RunAs
    exit 0
}

function Get-RemoteTaskFirewallRule {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param ()

    $rules = @(Get-NetFirewallRule -Name 'RemoteTask-*' -ErrorAction SilentlyContinue)

    if ($rules.Count -eq 0) {
        $rules = @(Get-NetFirewallRule -Group $script:FirewallGroupResource -ErrorAction SilentlyContinue)
    }

    if ($rules.Count -eq 0) {
        $fallbackGroups = @(
            'Remote Scheduled Tasks Management',
            'Zdalne zarządzanie zaplanowanymi zadaniami',
            'Zdalne zarzadzanie zaplanowanymi zadaniami'
        )
        foreach ($groupName in $fallbackGroups) {
            $matched = @(Get-NetFirewallRule -DisplayGroup $groupName -ErrorAction SilentlyContinue)
            if ($matched.Count -gt 0) {
                $rules = $matched
                break
            }
        }
    }

    $enrichedRules = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($rule in $rules) {
        $portFilter = $rule | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
        $addrFilter = $rule | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue

        $enrichedRules.Add([PSCustomObject]@{
            Name          = $rule.Name
            DisplayName   = $rule.DisplayName
            DisplayGroup  = $rule.DisplayGroup
            Group         = $rule.Group
            Enabled       = [string]$rule.Enabled
            Direction     = [string]$rule.Direction
            Action        = [string]$rule.Action
            Profile       = [string]$rule.Profile
            Protocol      = if ($portFilter) { [string]$portFilter.Protocol } else { 'Unknown' }
            LocalPort     = if ($portFilter) { ($portFilter.LocalPort -join ',') } else { 'Unknown' }
            RemoteAddress = if ($addrFilter) { ($addrFilter.RemoteAddress -join ',') } else { 'Unknown' }
        })
    }

    return @($enrichedRules.ToArray())
}

function Get-RemoteTaskSchedulerStatus {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param ()

    $rules = @(Get-RemoteTaskFirewallRule)
    $enabledCount = @($rules | Where-Object { $_.Enabled -eq 'True' }).Count

    $scheduleSvc = Get-Service -Name 'Schedule' -ErrorAction SilentlyContinue
    $rpcSsSvc = Get-Service -Name 'RpcSs' -ErrorAction SilentlyContinue

    $port135Listening = $false
    try {
        $tcp135 = @(Get-NetTCPConnection -LocalPort 135 -State Listen -ErrorAction SilentlyContinue)
        $port135Listening = ($tcp135.Count -gt 0)
    }
    catch {
        $port135Listening = $false
    }

    $netProfiles = @()
    try {
        $netProfiles = @(Get-NetConnectionProfile -ErrorAction SilentlyContinue | ForEach-Object {
            "$($_.InterfaceAlias): $($_.NetworkCategory)"
        })
    }
    catch {
        $netProfiles = @()
    }

    return [PSCustomObject]@{
        ComputerName          = [System.Environment]::MachineName
        TotalRulesFound       = $rules.Count
        EnabledRulesCount     = $enabledCount
        AllRulesEnabled       = ($rules.Count -gt 0 -and $enabledCount -eq $rules.Count)
        Rules                 = $rules
        ScheduleServiceStatus = if ($scheduleSvc) { [string]$scheduleSvc.Status } else { 'NotFound' }
        ScheduleStartType     = if ($scheduleSvc) { [string]$scheduleSvc.StartType } else { 'Unknown' }
        RpcSsServiceStatus    = if ($rpcSsSvc) { [string]$rpcSsSvc.Status } else { 'NotFound' }
        Port135Listening      = $port135Listening
        NetworkProfiles       = ($netProfiles -join '; ')
    }
}

function Show-StatusReport {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$StatusObject
    )

    Write-Log "`n--------------------------------------------------------------------------------" -Level HEADER
    Write-Log '  REMOTE TASK SCHEDULER (MMC) FIREWALL & SERVICE AUDIT' -Level STEP
    Write-Log '--------------------------------------------------------------------------------' -Level HEADER
    Write-Log "  Host ComputerName        : $($StatusObject.ComputerName)" -Level INFO
    Write-Log "  Task Scheduler (Schedule): $($StatusObject.ScheduleServiceStatus) (StartType: $($StatusObject.ScheduleStartType))" -Level $(if ($StatusObject.ScheduleServiceStatus -eq 'Running') { 'SUCCESS' } else { 'WARN' })
    Write-Log "  RPC Service (RpcSs)      : $($StatusObject.RpcSsServiceStatus)" -Level $(if ($StatusObject.RpcSsServiceStatus -eq 'Running') { 'SUCCESS' } else { 'WARN' })
    Write-Log "  RPC Port 135 Listening   : $(if ($StatusObject.Port135Listening) { 'Yes (Active)' } else { 'No' })" -Level $(if ($StatusObject.Port135Listening) { 'SUCCESS' } else { 'WARN' })
    Write-Log "  Firewall Rules Enabled   : $($StatusObject.EnabledRulesCount) / $($StatusObject.TotalRulesFound)" -Level $(if ($StatusObject.AllRulesEnabled) { 'SUCCESS' } else { 'WARN' })
    Write-Log "  Active Network Profiles  : $(if ($StatusObject.NetworkProfiles) { $StatusObject.NetworkProfiles } else { '(None Detected)' })" -Level DETAIL
    Write-Log '--------------------------------------------------------------------------------' -Level HEADER

    foreach ($rule in $StatusObject.Rules) {
        $ruleLevel = if ($rule.Enabled -eq 'True') { 'SUCCESS' } else { 'WARN' }
        Write-Log ("  [{0}] {1} | Profile: {2} | Port: {3} | RemoteAddress: {4}" -f `
            $(if ($rule.Enabled -eq 'True') { 'ENABLED ' } else { 'DISABLED' }),
            $rule.Name,
            $rule.Profile,
            $rule.LocalPort,
            $rule.RemoteAddress) -Level $ruleLevel
    }

    Write-Log "--------------------------------------------------------------------------------`n" -Level HEADER
}

function Enable-RemoteTaskFirewall {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]]$Rules,

        [Parameter(Mandatory = $false)]
        [string[]]$TargetProfiles,

        [Parameter(Mandatory = $false)]
        [string[]]$TargetRemoteAddresses,

        [Parameter(Mandatory = $false)]
        [switch]$IsDryRun
    )

    $applyProfile = ($null -ne $TargetProfiles) -and (@($TargetProfiles).Count -gt 0) -and ($TargetProfiles -notcontains 'Preserve')
    $applyRemoteAddress = ($null -ne $TargetRemoteAddresses) -and (@($TargetRemoteAddresses).Count -gt 0)

    $modifiedCount = 0
    $simulatedCount = 0

    foreach ($rule in $Rules) {
        $detailParts = [System.Collections.Generic.List[string]]::new()
        $detailParts.Add('Enable=True')
        if ($applyProfile) { $detailParts.Add("Profile=$($TargetProfiles -join ',')") }
        if ($applyRemoteAddress) { $detailParts.Add("RemoteAddress=$($TargetRemoteAddresses -join ',')") }
        $actionDesc = $detailParts -join ' | '

        if ($IsDryRun) {
            Write-Log "  [DRY-RUN] Would update rule '$($rule.Name)' ($($rule.DisplayName)) -> $actionDesc" -Level WARN
            $simulatedCount++
            continue
        }

        if ($PSCmdlet.ShouldProcess($rule.Name, "Enable and configure Remote Scheduled Tasks rule ($actionDesc)")) {
            Enable-NetFirewallRule -Name $rule.Name -ErrorAction Stop

            $setParams = @{
                Name        = $rule.Name
                ErrorAction = 'Stop'
            }
            if ($applyProfile) {
                $setParams['Profile'] = $TargetProfiles
            }
            if ($applyRemoteAddress) {
                $setParams['RemoteAddress'] = $TargetRemoteAddresses
            }

            if ($applyProfile -or $applyRemoteAddress) {
                Set-NetFirewallRule @setParams
            }

            Write-Log "  [+] Enabled rule '$($rule.Name)' ($actionDesc)" -Level SUCCESS
            $modifiedCount++
        }
        else {
            $simulatedCount++
        }
    }

    return [PSCustomObject]@{
        ModifiedCount  = $modifiedCount
        SimulatedCount = $simulatedCount
    }
}

function Disable-RemoteTaskFirewall {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]]$Rules,

        [Parameter(Mandatory = $false)]
        [switch]$IsDryRun
    )

    $modifiedCount = 0
    $simulatedCount = 0

    foreach ($rule in $Rules) {
        if ($IsDryRun) {
            Write-Log "  [DRY-RUN] Would disable rule '$($rule.Name)' ($($rule.DisplayName))" -Level WARN
            $simulatedCount++
            continue
        }

        if ($PSCmdlet.ShouldProcess($rule.Name, "Disable Remote Scheduled Tasks rule '$($rule.DisplayName)'")) {
            Disable-NetFirewallRule -Name $rule.Name -ErrorAction Stop
            Write-Log "  [+] Disabled rule '$($rule.Name)' ($($rule.DisplayName))" -Level SUCCESS
            $modifiedCount++
        }
        else {
            $simulatedCount++
        }
    }

    return [PSCustomObject]@{
        ModifiedCount  = $modifiedCount
        SimulatedCount = $simulatedCount
    }
}

function Invoke-RemoteTaskSchedulerWorkflow {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Enable', 'Disable', 'Status')]
        [string]$Mode,

        [Parameter(Mandatory = $false)]
        [string[]]$TargetProfiles,

        [Parameter(Mandatory = $false)]
        [string[]]$TargetRemoteAddresses,

        [Parameter(Mandatory = $false)]
        [switch]$IsDryRun,

        [Parameter(Mandatory = $false)]
        [bool]$IsAdminSession = $false,

        [Parameter(Mandatory = $false)]
        [bool]$RemoteAddressWasSpecified = $false
    )

    begin {
        # Pre-load read-only modules with WhatIf temporarily suppressed to keep -WhatIf output clean
        $savedWhatIfPreference = $WhatIfPreference
        $WhatIfPreference = $false
        try {
            foreach ($mod in @('CimCmdlets', 'NetSecurity', 'NetTCPIP', 'NetConnection')) {
                Import-Module -Name $mod -ErrorAction SilentlyContinue
            }
        }
        finally {
            $WhatIfPreference = $savedWhatIfPreference
        }

        Initialize-LogFile

        $osCim = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        $csCim = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
        $osCaption = if ($osCim) { $osCim.Caption.Trim() } else { [System.Environment]::OSVersion.VersionString }
        $osVersion = if ($osCim) { "$($osCim.Version) (Build $($osCim.BuildNumber))" } else { 'Unknown' }
        $domainOrWorkgroup = if ($csCim) {
            if ($csCim.PartOfDomain) { "Domain ($($csCim.Domain))" } else { "Workgroup ($($csCim.Workgroup))" }
        }
        else {
            'Unknown'
        }

        $operationModeLabel = if ($Mode -eq 'Status') {
            'STATUS AUDIT (Read-Only)'
        }
        elseif ($IsDryRun -or $WhatIfPreference) {
            if ($Mode -eq 'Disable') { 'SIMULATION (-Disable)' } else { 'SIMULATION (-Enable)' }
        }
        elseif ($Mode -eq 'Disable') {
            'LIVE FIREWALL ROLLBACK (-Disable)'
        }
        else {
            'LIVE FIREWALL PROVISIONING (-Enable)'
        }

        Write-Log '================================================================================' -Level HEADER
        Write-Log "  $($SCRIPT_INFO.Name) v$($SCRIPT_INFO.Version) - Initialization" -Level HEADER
        Write-Log '================================================================================' -Level HEADER
        Write-Log "  Author / Contact     : $($SCRIPT_INFO.Author) ($($SCRIPT_INFO.Contact))" -Level DETAIL
        Write-Log "  Host / Current User  : $([System.Environment]::MachineName) \ $([System.Environment]::UserName)" -Level DETAIL
        Write-Log "  Operating System     : $osCaption [$osVersion]" -Level DETAIL
        Write-Log "  PowerShell Edition   : $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion)" -Level DETAIL
        Write-Log "  Network Membership   : $domainOrWorkgroup" -Level DETAIL
        Write-Log "  Elevated Admin (SID) : $IsAdminSession (S-1-5-32-544 Verified)" -Level DETAIL
        Write-Log "  Operation Mode       : $operationModeLabel" -Level INFO
        if (-not $NoLog -and $script:ActiveLogFile) {
            Write-Log "  Active Log File      : $script:ActiveLogFile" -Level DETAIL
        }
        Write-Log '================================================================================' -Level HEADER

        $workflowResult = $null
    }

    process {
        try {
            $totalSteps = if ($Mode -eq 'Status') { 2 } else { 4 }

            # ------------------------------------------------------------------
            # STEP 1: DISCOVER FIREWALL RULES & SERVICES
            # ------------------------------------------------------------------
            Write-Progress -Id $script:ProgressId -Activity $script:ProgressActivity -Status 'Step 1: Auditing Remote Scheduled Tasks firewall rules and services...' -PercentComplete ([int](100 / $totalSteps))
            Write-Log "`n[STEP 1/$totalSteps] Discovering Remote Scheduled Tasks Management rules & services..." -Level STEP

            $preAudit = Get-RemoteTaskSchedulerStatus
            if ($preAudit.TotalRulesFound -eq 0) {
                throw "No built-in Remote Scheduled Tasks Management firewall rules (RemoteTask-* / $script:FirewallGroupResource) were found on this host."
            }

            Write-Log "  [+] Located $($preAudit.TotalRulesFound) language-independent firewall rule(s)." -Level SUCCESS

            if ($Mode -eq 'Status') {
                Write-Progress -Id $script:ProgressId -Activity $script:ProgressActivity -Status 'Step 2: Rendering status report...' -PercentComplete 100
                Show-StatusReport -StatusObject $preAudit
                $workflowResult = $preAudit
                return
            }

            # ------------------------------------------------------------------
            # STEP 2: VERIFY PREREQUISITE WINDOWS SERVICES
            # ------------------------------------------------------------------
            Write-Progress -Id $script:ProgressId -Activity $script:ProgressActivity -Status 'Step 2: Checking Task Scheduler and RPC services...' -PercentComplete ([int](200 / $totalSteps))
            Write-Log "`n[STEP 2/$totalSteps] Verifying prerequisite services (Schedule & RpcSs)..." -Level STEP
            Write-Log "  [*] Task Scheduler (Schedule) : $($preAudit.ScheduleServiceStatus) (StartType: $($preAudit.ScheduleStartType))" -Level $(if ($preAudit.ScheduleServiceStatus -eq 'Running') { 'SUCCESS' } else { 'WARN' })
            Write-Log "  [*] RPC Service (RpcSs)       : $($preAudit.RpcSsServiceStatus)" -Level $(if ($preAudit.RpcSsServiceStatus -eq 'Running') { 'SUCCESS' } else { 'WARN' })
            Write-Log "  [*] TCP Port 135 (RPC-EPMAP)  : $(if ($preAudit.Port135Listening) { 'Listening' } else { 'Not Listening' })" -Level $(if ($preAudit.Port135Listening) { 'SUCCESS' } else { 'WARN' })

            if ($Mode -eq 'Enable' -and $preAudit.ScheduleServiceStatus -ne 'Running') {
                Write-Log "  [!] Warning: 'Schedule' service is not currently Running. Remote MMC connections require the Task Scheduler service to be active." -Level WARN
            }

            # ------------------------------------------------------------------
            # STEP 3: APPLY FIREWALL CHANGES (-Enable or -Disable)
            # ------------------------------------------------------------------
            Write-Progress -Id $script:ProgressId -Activity $script:ProgressActivity -Status 'Step 3: Applying Windows Defender Firewall configuration...' -PercentComplete ([int](300 / $totalSteps))
            $actionSummary = $null

            if ($Mode -eq 'Enable') {
                Write-Log "`n[STEP 3/$totalSteps] Enabling Remote Scheduled Tasks Management firewall rules..." -Level STEP
                $actionSummary = Enable-RemoteTaskFirewall `
                    -Rules $preAudit.Rules `
                    -TargetProfiles $TargetProfiles `
                    -TargetRemoteAddresses $TargetRemoteAddresses `
                    -IsDryRun:$IsDryRun
            }
            elseif ($Mode -eq 'Disable') {
                Write-Log "`n[STEP 3/$totalSteps] Disabling Remote Scheduled Tasks Management firewall rules..." -Level STEP
                $actionSummary = Disable-RemoteTaskFirewall `
                    -Rules $preAudit.Rules `
                    -IsDryRun:$IsDryRun
            }

            # ------------------------------------------------------------------
            # STEP 4: POST-CONFIGURATION VERIFICATION
            # ------------------------------------------------------------------
            Write-Progress -Id $script:ProgressId -Activity $script:ProgressActivity -Status 'Step 4: Verifying final firewall state...' -PercentComplete 100
            Write-Log "`n[STEP 4/$totalSteps] Running post-configuration firewall verification..." -Level STEP

            $postAudit = Get-RemoteTaskSchedulerStatus
            Show-StatusReport -StatusObject $postAudit

            $elapsed = (Get-Date) - $script:StartTime
            $workflowResult = [PSCustomObject]@{
                ScriptName            = $SCRIPT_INFO.Name
                ScriptVersion         = $SCRIPT_INFO.Version
                ComputerName          = $postAudit.ComputerName
                Action                = $Mode
                Simulated             = [bool]($IsDryRun -or $WhatIfPreference)
                ModifiedRulesCount    = if ($actionSummary) { $actionSummary.ModifiedCount } else { 0 }
                SimulatedRulesCount   = if ($actionSummary) { $actionSummary.SimulatedCount } else { 0 }
                TotalRulesFound       = $postAudit.TotalRulesFound
                EnabledRulesCount     = $postAudit.EnabledRulesCount
                AllRulesEnabled       = $postAudit.AllRulesEnabled
                ScheduleServiceStatus = $postAudit.ScheduleServiceStatus
                RpcSsServiceStatus    = $postAudit.RpcSsServiceStatus
                Port135Listening      = $postAudit.Port135Listening
                NetworkProfiles       = $postAudit.NetworkProfiles
                Rules                 = $postAudit.Rules
                DurationSeconds       = [math]::Round($elapsed.TotalSeconds, 2)
                LogFile               = $script:ActiveLogFile
            }
        }
        catch {
            Write-Log "`n[ERROR] Execution failed: $($_.Exception.Message)" -Level ERROR
            throw
        }
        finally {
            Write-Progress -Id $script:ProgressId -Activity $script:ProgressActivity -Completed
        }
    }

    end {
        if ($null -ne $workflowResult -and $Mode -ne 'Status') {
            $elapsed = (Get-Date) - $script:StartTime
            $durationFormatted = '{0:mm}m {0:ss}.{0:fff}s' -f $elapsed

            Write-Log '================================================================================' -Level HEADER
            Write-Log '  EXECUTION SUMMARY & ADMIN NEXT STEPS' -Level HEADER
            Write-Log '================================================================================' -Level HEADER
            Write-Log "  Script & Version         : $($SCRIPT_INFO.FileName) v$($SCRIPT_INFO.Version)" -Level INFO
            Write-Log "  Host ComputerName        : $($workflowResult.ComputerName)" -Level SUCCESS
            Write-Log "  Rules Enabled            : $($workflowResult.EnabledRulesCount) / $($workflowResult.TotalRulesFound)" -Level $(if ($workflowResult.AllRulesEnabled) { 'SUCCESS' } else { 'INFO' })
            Write-Log "  Total Duration           : $durationFormatted" -Level DETAIL
            if (-not $NoLog -and $script:ActiveLogFile) {
                Write-Log "  Execution Log File       : $script:ActiveLogFile" -Level INFO
            }

            if ($Mode -eq 'Enable') {
                Write-Log "`n  Connecting from Admin Workstation (e.g., RPINDELA-PC):" -Level STEP
                Write-Log '  1. Press Win+R and run: taskschd.msc' -Level DETAIL
                Write-Log "  2. Right-click 'Task Scheduler (Local)' -> 'Connect to Another Computer...'." -Level DETAIL
                Write-Log "  3. Enter '$($workflowResult.ComputerName)' or its IP address and click OK." -Level SUCCESS

                $hasLocalSubnetRule = @($workflowResult.Rules | Where-Object { $_.RemoteAddress -eq 'LocalSubnet' }).Count -gt 0
                if ($hasLocalSubnetRule -and -not $RemoteAddressWasSpecified) {
                    Write-Log "`n  [i] Tip: Built-in Private/Public rules limit RemoteAddress to 'LocalSubnet'." -Level WARN
                    Write-Log '      If connecting via VPN or another subnet, re-run with:' -Level WARN
                    Write-Log "      .\$($SCRIPT_INFO.FileName) -Enable -FirewallProfile Private,Domain -RemoteAddress Any" -Level DETAIL
                }
            }
            Write-Log "================================================================================`n" -Level HEADER
        }

        return $workflowResult
    }
}

# ==============================================================================
# MAIN ENTRYPOINT
# ==============================================================================
$hasActionTrigger = $Enable -or $Disable -or $Status

if ($Help -or ($PSBoundParameters.Count -eq 0) -or (-not $hasActionTrigger)) {
    Show-ScriptHelp
    exit 0
}

if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
    $LogPath = $LogPath.Trim()
    $null = Test-ValidFilePathInput -PathValue $LogPath -ParameterName 'LogPath'
}

$resolvedProfiles = @(Resolve-FirewallProfileInput -ProfileValues $FirewallProfile)
$resolvedRemoteAddresses = if ($PSBoundParameters.ContainsKey('RemoteAddress')) {
    @(Resolve-RemoteAddressInput -AddressList $RemoteAddress)
}
else {
    $null
}

$isAdmin = Test-IsAdministrator
if (-not $isAdmin -and -not $SkipAdminCheck) {
    Invoke-UacElevation -NormalizedProfiles $resolvedProfiles -NormalizedRemoteAddresses $resolvedRemoteAddresses
}

$selectedMode = if ($Enable) { 'Enable' } elseif ($Disable) { 'Disable' } else { 'Status' }

$executionOutput = Invoke-RemoteTaskSchedulerWorkflow `
    -Mode $selectedMode `
    -TargetProfiles $resolvedProfiles `
    -TargetRemoteAddresses $resolvedRemoteAddresses `
    -IsDryRun:$DryRun `
    -IsAdminSession $isAdmin `
    -RemoteAddressWasSpecified $PSBoundParameters.ContainsKey('RemoteAddress')

if ($PassThru -and $null -ne $executionOutput) {
    return $executionOutput
}

<#
================================================================================
  Script Name : manage-processes.ps1
  Author      : Roman Pindela
  Contact     : roman.pindela@gmail.com
  GitHub      : https://github.com/romanpindela
  Version     : 1.0.0
  Release Date: 2026-10-13
  License     : MIT
  Repository  : https://github.com/romanpindela/Windows-Server

  DESCRIPTION:
    Comprehensive, enterprise-grade process management and diagnostic utility
    for Windows 10, Windows 11, and Windows Server (2016 - 2025).

    Provides deep visibility into running processes:
      - Resource consumption: RAM (Working Set & Private Bytes), CPU time,
        and Disk I/O (Read/Write transfer counts).
      - Binary details: Full executable path, command-line arguments,
        digital publisher/manufacturer name, and file description.
      - Network listeners: Identifies processes binding to local listening
        TCP/UDP ports, resolving well-known service names (HTTP, HTTPS, RDP, DNS,
        SMB, SQL, etc.).
      - Autostart / Startup detection: Correlates running processes with system
        startup mechanisms, including Registry Run/RunOnce (machine & user),
        Windows Startup Folders, Automatic Windows Services, and Task Scheduler
        tasks triggered by Boot or User Logon.
      - Process lifecycle management: Graceful application termination or
        forceful kill, with optional recursive process tree elimination.
      - Interactive console UI with live search, column sorting, and filter toggles.
      - Non-interactive snapshot mode with CLI filtering and JSON export.

    Running without parameters displays the help menu with author, version,
    syntax, and practical usage examples.

================================================================================
.SYNOPSIS
    Advanced process inspection, resource monitoring, autostart detection,
    network port correlation, and process lifecycle management tool.

.DESCRIPTION
    manage-processes.ps1 delivers comprehensive process management and diagnostics.
    Designed for system administrators, security analysts, and power users,
    it correlates running processes with resource metrics (CPU, RAM, Disk I/O),
    listening network ports (TCP/UDP), and persistence/startup configurations
    (Registry Run, Startup Folders, Auto-Services, Task Scheduler).
    Features interactive console navigation, instant CLI snapshots, and safe
    process termination (graceful close vs force kill with tree support).

.PARAMETER Interactive
    Switch parameter (-i, -Interactive). Launches the interactive console shell
    with real-time query searching, filter toggling, and keyboard management controls.

.PARAMETER Snapshot
    Switch parameter (-s, -l, -Snapshot, -List, -ListOnly). Outputs active process
    diagnostics table directly to console and exits immediately.

.PARAMETER Terminate
    Specifies a Process ID (PID) or process name pattern to terminate gracefully
    (attempts window close before stopping).
    Aliases: -t, -Stop.

.PARAMETER Kill
    Specifies a Process ID (PID) or process name pattern to forcefully kill immediately.
    Aliases: -k, -ForceKill.

.PARAMETER KillTree
    Switch parameter (-tree, -kt). Terminates the specified process and all of its
    child subprocesses recursively.

.PARAMETER Force
    Switch parameter (-f, -Quiet). Suppresses interactive confirmation prompts
    when stopping or killing processes.

.PARAMETER Filter
    Wildcard pattern or search query to filter processes by Process Name,
    Executable Path, Company/Publisher, or File Description.
    Aliases: -q, -Pattern, -Name.

.PARAMETER Port
    Filters processes listening on a specific TCP or UDP port number (e.g. 80, 443, 3389).
    Alias: -p.

.PARAMETER ListeningOnly
    Switch parameter (-net, -Listening). Displays only processes actively listening
    on network ports (TCP/UDP).

.PARAMETER StartupOnly
    Switch parameter (-boot, -Startup). Displays only processes identified as
    configured to launch with system boot, user logon, or task scheduler.

.PARAMETER SortBy
    Sorts process results by specified metric: 'Memory' (default), 'CPU',
    'Disk', 'Name', or 'PID'.

.PARAMETER Top
    Limits output to the top N processes matching the filter criteria.

.PARAMETER AsJson
    Switch parameter. Outputs process diagnostics in structured JSON format,
    ideal for CI/CD pipelines, remote auditing, or SIEM integration.

.PARAMETER Help
    Switch parameter (-h, -Help). Displays the interactive help guide,
    syntax, author info, and practical examples.

.PARAMETER LogPath
    Custom path for the activity log file.
    Default: C:\Logs\<yyyyMMdd_HHmmss>-<ComputerName>-<UserName>-Manage-Processes.txt
    Alias: -Log.

.EXAMPLE
    .\manage-processes.ps1
    Displays the help guide, author information, and syntax overview (default safe behavior).

.EXAMPLE
    .\manage-processes.ps1 -Help
    Displays detailed help guide, parameter documentation, and examples.

.EXAMPLE
    .\manage-processes.ps1 -Interactive
    Launches interactive CLI console with search, filtering, and process controls.

.EXAMPLE
    .\manage-processes.ps1 -Snapshot
    Takes a one-off snapshot of all running processes sorted by Memory.

.EXAMPLE
    .\manage-processes.ps1 -Snapshot -Filter "*chrome*"
    Lists all active Google Chrome processes with memory, CPU, and Disk I/O details.

.EXAMPLE
    .\manage-processes.ps1 -Snapshot -ListeningOnly
    Lists all running processes associated with listening network ports (TCP/UDP).

.EXAMPLE
    .\manage-processes.ps1 -Snapshot -Port 443
    Identifies which process is listening on network port 443 (HTTPS).

.EXAMPLE
    .\manage-processes.ps1 -Snapshot -StartupOnly
    Lists all active processes configured to start on boot, logon, or task scheduler.

.EXAMPLE
    .\manage-processes.ps1 -Snapshot -SortBy CPU -Top 10
    Displays the top 10 processes consuming the most CPU time.

.EXAMPLE
    .\manage-processes.ps1 -Terminate 5412
    Gracefully terminates process with PID 5412.

.EXAMPLE
    .\manage-processes.ps1 -Kill "notepad" -Force
    Forcefully terminates all processes named 'notepad' without prompt.

.EXAMPLE
    .\manage-processes.ps1 -Kill 8120 -KillTree -Force
    Forcefully terminates process 8120 and all of its spawned child processes.

.EXAMPLE
    .\manage-processes.ps1 -Snapshot -ListeningOnly -AsJson
    Exports active network-listening processes to JSON format.

.NOTES
    Author      : Roman Pindela
    Contact     : roman.pindela@gmail.com
    GitHub      : https://github.com/romanpindela
    Version     : 1.0.0
    Compatible  : Windows 10, Windows 11, Windows Server 2016/2019/2022/2025
    Privileges  : Requires Administrator privileges for inspecting complete system
                  process details, listening sockets, and process termination.
                  Automatically checks language-independent Well-Known SID (S-1-5-32-544)
                  and prompts for elevation via UAC when required.
#>

[CmdletBinding(DefaultParameterSetName = "Default")]
param (
    [Parameter(Mandatory = $false, ParameterSetName = "InteractiveSet")]
    [Alias("i")]
    [switch]$Interactive,

    [Parameter(Mandatory = $false, ParameterSetName = "SnapshotSet")]
    [Alias("s", "l", "List", "ListOnly")]
    [switch]$Snapshot,

    [Parameter(Mandatory = $false, ParameterSetName = "TerminateSet")]
    [Alias("t", "Stop")]
    [string]$Terminate,

    [Parameter(Mandatory = $false, ParameterSetName = "KillSet")]
    [Alias("k", "ForceKill")]
    [string]$Kill,

    [Parameter(Mandatory = $false, ParameterSetName = "KillSet")]
    [Parameter(Mandatory = $false, ParameterSetName = "TerminateSet")]
    [Alias("tree", "kt")]
    [switch]$KillTree,

    [Parameter(Mandatory = $false)]
    [Alias("f", "Quiet")]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [Alias("q", "Pattern", "Name")]
    [string]$Filter = "",

    [Parameter(Mandatory = $false)]
    [Alias("p")]
    [int]$Port = 0,

    [Parameter(Mandatory = $false)]
    [Alias("net", "Listening")]
    [switch]$ListeningOnly,

    [Parameter(Mandatory = $false)]
    [Alias("boot", "Startup")]
    [switch]$StartupOnly,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Memory", "CPU", "Disk", "Name", "PID", IgnoreCase = $true)]
    [string]$SortBy = "Memory",

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 10000)]
    [int]$Top = 0,

    [Parameter(Mandatory = $false, ParameterSetName = "SnapshotSet")]
    [switch]$AsJson,

    [Parameter(Mandatory = $false, ParameterSetName = "HelpSet")]
    [Parameter(Mandatory = $false, ParameterSetName = "Default")]
    [Alias("h")]
    [switch]$Help,

    [Parameter(Mandatory = $false)]
    [Alias("Log")]
    [string]$LogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# ==============================================================================
# SCRIPT METADATA & GLOBALS
# ==============================================================================
$SCRIPT_INFO = @{
    Name        = "Manage-Processes"
    ScriptFile  = "manage-processes.ps1"
    Version     = "1.0.0"
    Author      = "Roman Pindela"
    Contact     = "roman.pindela@gmail.com"
    GitHub      = "https://github.com/romanpindela"
    Repository  = "https://github.com/romanpindela/Windows-Server"
    ReleaseDate = "2026-10-13"
}

$script:ActiveLogFile = $null

# Protected Windows core system processes (termination guards)
$script:CriticalProcesses = @(
    'system', 'idle', 'registry', 'smss', 'csrss', 'wininit', 'services',
    'lsass', 'lsm', 'svchost', 'winlogon', 'fontdrvhost', 'dwm'
)

# Known network port to service mapping
$script:KnownPortServices = @{
    20   = "FTP-Data"
    21   = "FTP-Control"
    22   = "SSH"
    23   = "Telnet"
    25   = "SMTP"
    53   = "DNS"
    67   = "DHCP-Server"
    68   = "DHCP-Client"
    80   = "HTTP"
    88   = "Kerberos"
    110  = "POP3"
    123  = "NTP"
    135  = "MS-RPC"
    137  = "NetBIOS-NS"
    138  = "NetBIOS-DGM"
    139  = "NetBIOS-SSN"
    143  = "IMAP"
    389  = "LDAP"
    443  = "HTTPS"
    445  = "Microsoft-DS/SMB"
    465  = "SMTPS"
    587  = "SMTP-Submission"
    636  = "LDAPS"
    993  = "IMAPS"
    995  = "POP3S"
    1433 = "MS-SQL Server"
    1434 = "MS-SQL Monitor"
    1521 = "Oracle-DB"
    2049 = "NFS"
    3306 = "MySQL/MariaDB"
    3389 = "MS-RDP"
    5000 = "UPnP / Flask-Dev"
    5432 = "PostgreSQL"
    5985 = "WinRM-HTTP"
    5986 = "WinRM-HTTPS"
    8080 = "HTTP-Proxy / Tomcat"
    8443 = "HTTPS-Alt"
}

# ==============================================================================
# LOGGING SYSTEM
# ==============================================================================
function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ConsoleColor]$Color = [ConsoleColor]::White
    )

    try { [Console]::CursorLeft = 0 } catch {}
    Write-Host "$Message" -ForegroundColor $Color

    if (-not [string]::IsNullOrWhiteSpace($script:ActiveLogFile)) {
        try {
            $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            $logLine = "[$timestamp] $Message`r`n"
            [System.IO.File]::AppendAllText($script:ActiveLogFile, $logLine, [System.Text.Encoding]::UTF8)
        }
        catch {}
    }
}

function Initialize-Logging {
    param ([string]$CustomPath)

    if ([string]::IsNullOrWhiteSpace($CustomPath)) {
        $defaultLogDir = "C:\Logs"
        $timeMarker = (Get-Date).ToString("yyyyMMdd_HHmmss")
        $compName   = $env:COMPUTERNAME
        $userName   = $env:USERNAME
        $scriptName = $SCRIPT_INFO.Name
        $logFileName = "${timeMarker}-${compName}-${userName}-${scriptName}.txt"
        $CustomPath  = Join-Path ($defaultLogDir) ($logFileName)
    }

    try {
        $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CustomPath)
        $logDirectory = [System.IO.Path]::GetDirectoryName($resolvedPath)
        if (-not [string]::IsNullOrWhiteSpace($logDirectory) -and -not [System.IO.Directory]::Exists($logDirectory)) {
            [System.IO.Directory]::CreateDirectory($logDirectory) | Out-Null
        }
        $script:ActiveLogFile = $resolvedPath
        return $resolvedPath
    }
    catch {
        return $null
    }
}

# ==============================================================================
# INPUT SANITIZATION & SECURITY
# ==============================================================================
function Assert-SafeInput {
    param (
        [string]$InputString,
        [string]$ParamName
    )

    if ([string]::IsNullOrWhiteSpace($InputString)) { return }

    # Block injection control characters and dangerous execution tokens
    $dangerousTokens = @(";", "|", "`"", "`$", "&", "`r", "`n")
    foreach ($token in $dangerousTokens) {
        if ($InputString.Contains($token)) {
            throw "Security Alert: Parameter '$ParamName' contains invalid character or potential injection token ('$token')."
        }
    }
}

# ==============================================================================
# ELEVATION & PRIVILEGE VERIFICATION (LANGUAGE-INDEPENDENT)
# ==============================================================================
function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $adminSid = New-Object Security.Principal.SecurityIdentifier([Security.Principal.WellKnownSidType]::BuiltInAdministratorsSid, $null)
    return $principal.IsInRole($adminSid)
}

function Assert-AdministratorElevation {
    param (
        [switch]$Strict
    )

    if (-not (Test-IsAdmin)) {
        Write-Host "Notice: Administrator privileges recommended for complete system inspection." -ForegroundColor Yellow
        Write-Host "Attempting elevation via UAC..." -ForegroundColor Yellow

        $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
        foreach ($entry in $PSBoundParameters.GetEnumerator()) {
            if ($entry.Key -in @('Strict')) { continue }
            if ($entry.Value -is [switch] -and $entry.Value.IsPresent) {
                $argList += "-$($entry.Key)"
            }
            elseif ($entry.Value -isnot [switch] -and -not [string]::IsNullOrWhiteSpace($entry.Value)) {
                $argList += "-$($entry.Key)"
                $argList += "`"$($entry.Value)`""
            }
        }

        $argumentsString = $argList -join " "
        try {
            Start-Process powershell.exe -ArgumentList $argumentsString -Verb RunAs -ErrorAction Stop
            Exit 0
        }
        catch {
            Write-Host "Notice: UAC elevation was not available or cancelled. Proceeding with current privileges..." -ForegroundColor DarkYellow
        }
    }
}

# ==============================================================================
# HELP GUIDE
# ==============================================================================
function Show-HelpGuide {
    try { [Console]::CursorLeft = 0 } catch {}
    Write-Host @"
================================================================================
  $($SCRIPT_INFO.Name) - v$($SCRIPT_INFO.Version)
  Author: $($SCRIPT_INFO.Author) | Contact: $($SCRIPT_INFO.Contact)
  GitHub: $($SCRIPT_INFO.GitHub)
================================================================================
DESCRIPTION:
  Enterprise diagnostic and management utility for Windows processes.
  Inspects memory (RAM WorkingSet / Private bytes), CPU time, Disk I/O,
  full executable paths, software publisher/vendor metadata, listening
  network sockets (TCP/UDP), and system startup / autostart mechanisms.
  Provides safe process termination (graceful close vs force kill with tree).

USAGE:
  .\$($SCRIPT_INFO.ScriptFile) -Interactive
  .\$($SCRIPT_INFO.ScriptFile) -Snapshot [-Filter <query>] [-Port <port>] [-ListeningOnly] [-StartupOnly]
  .\$($SCRIPT_INFO.ScriptFile) -Terminate <PID|Name> [-KillTree] [-Force]
  .\$($SCRIPT_INFO.ScriptFile) -Kill <PID|Name> [-KillTree] [-Force]
  .\$($SCRIPT_INFO.ScriptFile) -h | -Help

PARAMETERS:
  -Interactive, -i     : Launches interactive full-screen CLI console.
  -Snapshot, -s, -l    : Outputs active processes table / snapshot and exits.
  -Terminate, -t       : Gracefully closes process by PID or Name (CloseMainWindow fallback).
  -Kill, -k            : Forcefully terminates process by PID or Name.
  -KillTree, -kt       : Recursively terminates process and all child subprocesses.
  -Force, -f           : Bypasses confirmation prompts for process termination.
  -Filter, -q          : Filters processes by Name, Path, Publisher, or Description.
  -Port, -p            : Filters processes listening on a specific TCP/UDP port (e.g. 80, 443).
  -ListeningOnly, -net : Filters view to processes binding to listening network ports.
  -StartupOnly, -boot  : Filters view to autostart processes (Registry, Startup Folders,
                         Auto-Services, Task Scheduler Boot/Logon).
  -SortBy              : Sorts results by 'Memory' (default), 'CPU', 'Disk', 'Name', or 'PID'.
  -Top <n>             : Limits output to top N records (e.g. -Top 20).
  -AsJson              : Outputs diagnostics snapshot in structured JSON format.
  -LogPath, -Log       : Custom activity log path (Default: C:\Logs\<DateTime>-...-Manage-Processes.txt).
  -Help, -h            : Displays this help menu, author info, and practical examples.

IMPORTANT:
  After downloading from GitHub, unblock the script before execution:
    Unblock-File -Path .\$($SCRIPT_INFO.ScriptFile)

EXAMPLES:
  # 1. Safe default help view
  .\$($SCRIPT_INFO.ScriptFile)

  # 2. Interactive management console
  .\$($SCRIPT_INFO.ScriptFile) -Interactive

  # 3. Snapshot of all active processes sorted by RAM
  .\$($SCRIPT_INFO.ScriptFile) -Snapshot

  # 4. Search processes by publisher or name
  .\$($SCRIPT_INFO.ScriptFile) -Snapshot -Filter "*chrome*"

  # 5. List processes listening on network ports (TCP/UDP)
  .\$($SCRIPT_INFO.ScriptFile) -Snapshot -ListeningOnly

  # 6. Check which process is bound to port 443 (HTTPS) or 3389 (RDP)
  .\$($SCRIPT_INFO.ScriptFile) -Snapshot -Port 443
  .\$($SCRIPT_INFO.ScriptFile) -Snapshot -Port 3389

  # 7. Audit autostart / startup applications
  .\$($SCRIPT_INFO.ScriptFile) -Snapshot -StartupOnly

  # 8. Top 15 CPU consumers
  .\$($SCRIPT_INFO.ScriptFile) -Snapshot -SortBy CPU -Top 15

  # 9. Graceful termination of process
  .\$($SCRIPT_INFO.ScriptFile) -Terminate 4120

  # 10. Force kill process tree
  .\$($SCRIPT_INFO.ScriptFile) -Kill 9824 -KillTree -Force

  # 11. Export listening services to JSON
  .\$($SCRIPT_INFO.ScriptFile) -Snapshot -ListeningOnly -AsJson
================================================================================
"@ -ForegroundColor Yellow
}

# ==============================================================================
# HELPER: BYTE FORMATTING
# ==============================================================================
function Format-ByteSize {
    param ([double]$Bytes)

    if ($Bytes -ge 1GB) {
        return "{0:N2} GB" -f ($Bytes / 1GB)
    }
    elseif ($Bytes -ge 1MB) {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    }
    elseif ($Bytes -ge 1KB) {
        return "{0:N2} KB" -f ($Bytes / 1KB)
    }
    else {
        return "{0:N0} B" -f $Bytes
    }
}

# ==============================================================================
# NETWORK LISTENING PORT MAPPER
# ==============================================================================
function Get-ListeningNetworkMap {
    [CmdletBinding()]
    param ()

    $netMap = @{}

    # 1. Query TCP Listening connections
    try {
        $tcpList = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue
        if ($tcpList) {
            foreach ($tcp in $tcpList) {
                $pidNum = [int]$tcp.OwningProcess
                if ($pidNum -le 0) { continue }

                if (-not $netMap.ContainsKey($pidNum)) {
                    $netMap[$pidNum] = @{
                        Ports     = [System.Collections.Generic.List[int]]::new()
                        Summaries = [System.Collections.Generic.List[string]]::new()
                        Details   = [System.Collections.Generic.List[PSCustomObject]]::new()
                    }
                }

                $port = [int]$tcp.LocalPort
                if (-not $netMap[$pidNum].Ports.Contains($port)) {
                    $netMap[$pidNum].Ports.Add($port)
                }

                $svc = if ($script:KnownPortServices.ContainsKey($port)) { " ($($script:KnownPortServices[$port]))" } else { "" }
                $addr = if ($tcp.LocalAddress -eq "0.0.0.0" -or $tcp.LocalAddress -eq "::") { "*" } else { $tcp.LocalAddress }
                $summary = "TCP:${port}${svc}"
                if (-not $netMap[$pidNum].Summaries.Contains($summary)) {
                    $netMap[$pidNum].Summaries.Add($summary)
                }

                $netMap[$pidNum].Details.Add([PSCustomObject]@{
                    Protocol     = "TCP"
                    LocalAddress = $tcp.LocalAddress
                    LocalPort    = $port
                    Service      = if ($script:KnownPortServices.ContainsKey($port)) { $script:KnownPortServices[$port] } else { "Custom/Dynamic" }
                })
            }
        }
    }
    catch {}

    # 2. Query UDP Endpoints
    try {
        $udpList = Get-NetUDPEndpoint -ErrorAction SilentlyContinue
        if ($udpList) {
            foreach ($udp in $udpList) {
                $pidNum = [int]$udp.OwningProcess
                if ($pidNum -le 0) { continue }

                if (-not $netMap.ContainsKey($pidNum)) {
                    $netMap[$pidNum] = @{
                        Ports     = [System.Collections.Generic.List[int]]::new()
                        Summaries = [System.Collections.Generic.List[string]]::new()
                        Details   = [System.Collections.Generic.List[PSCustomObject]]::new()
                    }
                }

                $port = [int]$udp.LocalPort
                if (-not $netMap[$pidNum].Ports.Contains($port)) {
                    $netMap[$pidNum].Ports.Add($port)
                }

                $svc = if ($script:KnownPortServices.ContainsKey($port)) { " ($($script:KnownPortServices[$port]))" } else { "" }
                $summary = "UDP:${port}${svc}"
                if (-not $netMap[$pidNum].Summaries.Contains($summary)) {
                    $netMap[$pidNum].Summaries.Add($summary)
                }

                $netMap[$pidNum].Details.Add([PSCustomObject]@{
                    Protocol     = "UDP"
                    LocalAddress = $udp.LocalAddress
                    LocalPort    = $port
                    Service      = if ($script:KnownPortServices.ContainsKey($port)) { $script:KnownPortServices[$port] } else { "Custom/Dynamic" }
                })
            }
        }
    }
    catch {}

    return $netMap
}

# ==============================================================================
# AUTOSTART / STARTUP MAPPER
# ==============================================================================
function Get-AutostartMap {
    [CmdletBinding()]
    param ()

    $result = @{
        Paths       = @{}
        Names       = @{}
        ServicePids = @{}
    }

    $registerItem = {
        param ([string]$RawPath, [string]$Reason)
        if ([string]::IsNullOrWhiteSpace($RawPath)) { return }

        $clean = $RawPath.Trim('"', "'", ' ')
        if ($clean -match '(?i)([a-zA-Z]:\\[^",\r\n]+\.exe)') {
            $clean = $Matches[1]
        }
        elseif ($clean -match '(?i)^([^\s]+\.exe)') {
            $clean = $Matches[1]
        }

        $norm = $clean.ToLower().Trim()
        if (-not $result.Paths.ContainsKey($norm)) {
            $result.Paths[$norm] = [System.Collections.Generic.List[string]]::new()
        }
        if (-not $result.Paths[$norm].Contains($Reason)) {
            $result.Paths[$norm].Add($Reason)
        }

        try {
            $fileName = [System.IO.Path]::GetFileNameWithoutExtension($clean).ToLower()
            if (-not [string]::IsNullOrWhiteSpace($fileName)) {
                if (-not $result.Names.ContainsKey($fileName)) {
                    $result.Names[$fileName] = [System.Collections.Generic.List[string]]::new()
                }
                if (-not $result.Names[$fileName].Contains($Reason)) {
                    $result.Names[$fileName].Add($Reason)
                }
            }
        }
        catch {}
    }

    # 1. Registry Run & RunOnce locations
    $regLocations = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce"
    )

    foreach ($loc in $regLocations) {
        if (Test-Path $loc) {
            try {
                $props = Get-ItemProperty -Path $loc -ErrorAction SilentlyContinue
                if ($props) {
                    $tag = if ($loc -like "*HKLM*") { "Reg:HKLM-Run" } else { "Reg:HKCU-Run" }
                    foreach ($p in $props.PSObject.Properties) {
                        if ($p.Name -notmatch '^(PS|Default$)' -and $p.Value -is [string]) {
                            & $registerItem $p.Value "$tag ($($p.Name))"
                        }
                    }
                }
            }
            catch {}
        }
    }

    # 2. Startup Folders
    $startupDirs = @(
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup",
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    )

    $wscript = $null
    try { $wscript = New-Object -ComObject WScript.Shell } catch {}

    foreach ($sdir in $startupDirs) {
        if (Test-Path $sdir) {
            try {
                $shortcuts = Get-ChildItem -Path $sdir -Filter "*.lnk" -ErrorAction SilentlyContinue
                if ($shortcuts -and $wscript) {
                    foreach ($sc in $shortcuts) {
                        try {
                            $scObj = $wscript.CreateShortcut($sc.FullName)
                            if ($scObj -and $scObj.TargetPath) {
                                & $registerItem $scObj.TargetPath "StartupFolder ($($sc.BaseName))"
                            }
                        }
                        catch {}
                    }
                }
                $directExes = Get-ChildItem -Path $sdir -Filter "*.exe" -ErrorAction SilentlyContinue
                if ($directExes) {
                    foreach ($de in $directExes) {
                        & $registerItem $de.FullName "StartupFolder ($($de.BaseName))"
                    }
                }
            }
            catch {}
        }
    }

    # 3. Windows Auto-Start Services
    try {
        $services = Get-CimInstance Win32_Service -Filter "StartMode = 'Auto'" -ErrorAction SilentlyContinue
        if ($services) {
            foreach ($svc in $services) {
                if ($svc.ProcessId -gt 0) {
                    $spid = [int]$svc.ProcessId
                    if (-not $result.ServicePids.ContainsKey($spid)) {
                        $result.ServicePids[$spid] = [System.Collections.Generic.List[string]]::new()
                    }
                    $svcReason = "AutoService: $($svc.Name)"
                    if (-not $result.ServicePids[$spid].Contains($svcReason)) {
                        $result.ServicePids[$spid].Add($svcReason)
                    }
                }
                if ($svc.PathName) {
                    & $registerItem $svc.PathName "AutoService: $($svc.Name)"
                }
            }
        }
    }
    catch {}

    # 4. Scheduled Tasks (Boot / Logon Triggers)
    try {
        $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue
        if ($tasks) {
            foreach ($tsk in $tasks) {
                $trigText = ($tsk.Triggers | Out-String)
                if ($trigText -match 'Boot|Logon') {
                    $trigMode = if ($trigText -match 'Boot') { "Boot" } else { "Logon" }
                    if ($tsk.Actions) {
                        foreach ($act in $tsk.Actions) {
                            if ($act.Execute) {
                                & $registerItem $act.Execute "TaskScheduler: $($tsk.TaskName) [$trigMode]"
                            }
                        }
                    }
                }
            }
        }
    }
    catch {}

    return $result
}

# ==============================================================================
# PROCESS ENRICHMENT & DIAGNOSTICS COLLECTOR
# ==============================================================================
function Get-EnrichedProcesses {
    [CmdletBinding()]
    param (
        [hashtable]$NetMap = @{},
        [hashtable]$AutostartMap = @{}
    )

    # Fast indexed dictionary of CimInstance Win32_Process
    $cimMap = @{}
    try {
        $cimProcs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue
        if ($cimProcs) {
            foreach ($cp in $cimProcs) {
                $cimMap[[int]$cp.ProcessId] = $cp
            }
        }
    }
    catch {}

    $diagProcs = @(Get-Process -ErrorAction SilentlyContinue)
    $list = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($proc in $diagProcs) {
        $pidNum = [int]$proc.Id
        $cim = if ($cimMap.ContainsKey($pidNum)) { $cimMap[$pidNum] } else { $null }

        # Resolve Executable Path
        $path = ""
        try {
            if ($proc.Path) { $path = $proc.Path }
        } catch {}
        if (-not $path -and $cim -and $cim.ExecutablePath) {
            $path = $cim.ExecutablePath
        }
        if (-not $path) { $path = "-" }

        # Resolve Publisher / Company & Description
        $company = "-"
        $desc = "-"
        try { if ($proc.Company) { $company = $proc.Company.Trim() } } catch {}
        try { if ($proc.Description) { $desc = $proc.Description.Trim() } } catch {}

        if (($company -eq "-" -or $desc -eq "-") -and $path -ne "-" -and (Test-Path $path)) {
            try {
                $fvi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($path)
                if ($company -eq "-" -and $fvi.CompanyName) { $company = $fvi.CompanyName.Trim() }
                if ($desc -eq "-" -and $fvi.FileDescription) { $desc = $fvi.FileDescription.Trim() }
            } catch {}
        }

        # Memory Metrics
        $wsBytes = 0L
        $privBytes = 0L
        try { $wsBytes = [int64]$proc.WorkingSet64 } catch {}
        try { $privBytes = [int64]$proc.PrivateMemorySize64 } catch {}

        # Disk I/O Metrics (from Win32_Process)
        $ioRead = [uint64]0
        $ioWrite = [uint64]0
        if ($cim) {
            try { $ioRead = [uint64]$cim.ReadTransferCount } catch {}
            try { $ioWrite = [uint64]$cim.WriteTransferCount } catch {}
        }
        $ioTotal = $ioRead + $ioWrite

        # CPU Metrics
        $cpuSec = 0.0
        $cpuFormatted = "00:00:00"
        try {
            if ($null -ne $proc.TotalProcessorTime) {
                $tpt = $proc.TotalProcessorTime
                $cpuSec = [math]::Round($tpt.TotalSeconds, 2)
                $cpuFormatted = "{0:D2}:{1:D2}:{2:D2}" -f [int]$tpt.TotalHours, $tpt.Minutes, $tpt.Seconds
            }
        } catch {}

        # Network Listening Metrics
        $hasNet = ($NetMap -and $NetMap.ContainsKey($pidNum) -and $NetMap[$pidNum].Ports.Count -gt 0)
        $netPorts = if ($hasNet) { $NetMap[$pidNum].Ports } else { @() }
        $netSummary = if ($hasNet) { ($NetMap[$pidNum].Summaries -join ", ") } else { "-" }
        $netDetails = if ($hasNet) { $NetMap[$pidNum].Details } else { @() }

        # Autostart Metrics
        $reasons = [System.Collections.Generic.List[string]]::new()
        if ($AutostartMap) {
            if ($AutostartMap.ServicePids.ContainsKey($pidNum)) {
                foreach ($r in $AutostartMap.ServicePids[$pidNum]) {
                    if (-not $reasons.Contains($r)) { $reasons.Add($r) }
                }
            }
            if ($path -ne "-") {
                $normP = $path.ToLower().Trim()
                if ($AutostartMap.Paths.ContainsKey($normP)) {
                    foreach ($r in $AutostartMap.Paths[$normP]) {
                        if (-not $reasons.Contains($r)) { $reasons.Add($r) }
                    }
                }
            }
            $normN = $proc.ProcessName.ToLower()
            if ($AutostartMap.Names.ContainsKey($normN)) {
                foreach ($r in $AutostartMap.Names[$normN]) {
                    if (-not $reasons.Contains($r)) { $reasons.Add($r) }
                }
            }
        }
        $isAutostart = ($reasons.Count -gt 0)
        $autostartSummary = if ($isAutostart) { ($reasons -join " | ") } else { "-" }

        # Command Line & Parent PID
        $cmdLine = if ($cim -and $cim.CommandLine) { $cim.CommandLine } else { "-" }
        $parentPid = if ($cim -and $cim.ParentProcessId) { [int]$cim.ParentProcessId } else { 0 }

        # Health / Responding Status
        $responding = $true
        try { $responding = $proc.Responding } catch {}

        $list.Add([PSCustomObject]@{
            PID                 = $pidNum
            Name                = $proc.ProcessName
            Path                = $path
            CommandLine         = $cmdLine
            Company             = $company
            Description         = $desc
            WorkingSetBytes     = $wsBytes
            WorkingSetFormatted = Format-ByteSize $wsBytes
            PrivateBytes        = $privBytes
            PrivateFormatted    = Format-ByteSize $privBytes
            CPUSeconds          = $cpuSec
            CPUTimeFormatted    = $cpuFormatted
            DiskReadBytes       = $ioRead
            DiskWriteBytes      = $ioWrite
            DiskTotalBytes      = $ioTotal
            DiskIOSummary       = "R: $(Format-ByteSize $ioRead) | W: $(Format-ByteSize $ioWrite)"
            IsListening         = $hasNet
            ListeningPorts      = $netPorts
            ListeningSummary    = $netSummary
            ListeningDetails    = $netDetails
            IsAutostart         = $isAutostart
            AutostartSummary    = $autostartSummary
            ParentPID           = $parentPid
            Responding          = $responding
        })
    }

    return $list
}

# ==============================================================================
# FILTERING & SORTING ENGINE
# ==============================================================================
function Filter-EnrichedProcesses {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[PSCustomObject]]$ProcessList,

        [string]$FilterQuery = "",
        [int]$PortFilter = 0,
        [switch]$ListeningOnly,
        [switch]$StartupOnly,
        [string]$SortBy = "Memory",
        [int]$TopLimit = 0
    )

    $filtered = $ProcessList

    # 1. Listening Filter
    if ($ListeningOnly) {
        $filtered = @($filtered | Where-Object { $_.IsListening -eq $true })
    }

    # 2. Port Filter
    if ($PortFilter -gt 0) {
        $filtered = @($filtered | Where-Object { $_.ListeningPorts -contains $PortFilter })
    }

    # 3. Autostart Filter
    if ($StartupOnly) {
        $filtered = @($filtered | Where-Object { $_.IsAutostart -eq $true })
    }

    # 4. Search Query (Name, Path, Publisher, Description, CommandLine)
    if (-not [string]::IsNullOrWhiteSpace($FilterQuery) -and $FilterQuery -ne "*") {
        $cleanQ = $FilterQuery.Trim().Trim('*')
        $filtered = @($filtered | Where-Object {
            $_.Name -like "*$cleanQ*" -or
            $_.Path -like "*$cleanQ*" -or
            $_.Company -like "*$cleanQ*" -or
            $_.Description -like "*$cleanQ*" -or
            $_.CommandLine -like "*$cleanQ*"
        })
    }

    # 5. Sorting
    switch ($SortBy.ToLower()) {
        "cpu"    { $filtered = @($filtered | Sort-Object -Property CPUSeconds -Descending) }
        "disk"   { $filtered = @($filtered | Sort-Object -Property DiskTotalBytes -Descending) }
        "name"   { $filtered = @($filtered | Sort-Object -Property Name, PID) }
        "pid"    { $filtered = @($filtered | Sort-Object -Property PID) }
        default  { $filtered = @($filtered | Sort-Object -Property WorkingSetBytes -Descending) }
    }

    # 6. Top N Limit
    $filteredArray = @($filtered)
    if ($TopLimit -gt 0 -and $filteredArray.Count -gt $TopLimit) {
        $filtered = @($filteredArray | Select-Object -First $TopLimit)
    }

    return @($filtered)
}

# ==============================================================================
# CONSOLE RENDERING SYSTEM
# ==============================================================================
function Render-ProcessView {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        $Processes,

        [string]$HeaderBanner = ""
    )

    $procList = @($Processes)
    $count = $procList.Count

    if ($HeaderBanner) {
        Write-Host $HeaderBanner -ForegroundColor Cyan
    }

    Write-Host ("=" * 120) -ForegroundColor Cyan
    Write-Host (" {0,-4} | {1,-7} | {2,-25} | {3,-20} | {4,-10} | {5,-24} | {6}" -f `
        "No.", "PID", "Process Name", "RAM (WS / Priv)", "CPU Time", "Disk I/O (Read/Write)", "Tags") -ForegroundColor Yellow
    Write-Host ("=" * 120) -ForegroundColor Cyan

    for ($i = 0; $i -lt $count; $i++) {
        $p = $procList[$i]
        $rowNum = $i + 1

        # Tags summary
        $tags = [System.Collections.Generic.List[string]]::new()
        if ($p.IsListening) { $tags.Add("[NET]") }
        if ($p.IsAutostart) { $tags.Add("[AUTO]") }
        if (-not $p.Responding) { $tags.Add("[HUNG]") }
        $tagsStr = if ($tags.Count -gt 0) { $tags -join " " } else { "-" }

        # Color based on role
        $rowColor = [ConsoleColor]::White
        if ($p.IsListening) { $rowColor = [ConsoleColor]::Cyan }
        elseif ($p.IsAutostart) { $rowColor = [ConsoleColor]::Green }
        if (-not $p.Responding) { $rowColor = [ConsoleColor]::Red }

        # Line 1: Primary Metrics
        Write-Host (" {0,-4} | {1,-7} | {2,-25} | {3,-20} | {4,-10} | {5,-24} | {6}" -f `
            $rowNum,
            $p.PID,
            ($p.Name.PadRight(25).Substring(0, [math]::Min(25, $p.Name.Length))),
            ("$($p.WorkingSetFormatted) / $($p.PrivateFormatted)"),
            $p.CPUTimeFormatted,
            $p.DiskIOSummary,
            $tagsStr) -ForegroundColor $rowColor

        # Line 2: Executable Path
        Write-Host ("        -> Path      : {0}" -f $p.Path) -ForegroundColor DarkGray

        # Line 3: Vendor / Publisher & Description
        Write-Host ("        -> Publisher : {0} | Description: {1}" -f $p.Company, $p.Description) -ForegroundColor DarkGray

        # Line 4: Network Listeners (if present)
        if ($p.IsListening) {
            Write-Host ("        -> Network   : {0}" -f $p.ListeningSummary) -ForegroundColor Magenta
        }

        # Line 5: Autostart Details (if present)
        if ($p.IsAutostart) {
            Write-Host ("        -> Autostart : {0}" -f $p.AutostartSummary) -ForegroundColor DarkYellow
        }

        # Separator line
        Write-Host ("-" * 120) -ForegroundColor DarkGray
    }
}

# ==============================================================================
# PROCESS MANAGEMENT (TERMINATE / FORCE KILL / TREE)
# ==============================================================================
function Stop-ManagedProcess {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Target,

        [switch]$ForceKill,
        [switch]$KillTree,
        [switch]$BypassConfirmation
    )

    # 1. Match processes by PID or Name pattern
    $matched = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()
    $parsedPid = 0

    if ([int]::TryParse($Target, [ref]$parsedPid)) {
        try {
            $proc = Get-Process -Id $parsedPid -ErrorAction Stop
            $matched.Add($proc)
        }
        catch {
            Write-Log "[ERROR] No active process found with PID $parsedPid." Red
            return
        }
    }
    else {
        $cleanTarget = $Target.Trim()
        if ($cleanTarget.EndsWith(".exe", [System.StringComparison]::OrdinalIgnoreCase)) {
            $cleanTarget = [System.IO.Path]::GetFileNameWithoutExtension($cleanTarget)
        }

        $allProcs = @(Get-Process -ErrorAction SilentlyContinue)
        foreach ($ap in $allProcs) {
            if ($ap.ProcessName -like $cleanTarget -or $ap.ProcessName -ieq $cleanTarget) {
                $matched.Add($ap)
            }
        }

        if ($matched.Count -eq 0) {
            Write-Log "[ERROR] No active processes match pattern '$Target'." Red
            return
        }
    }

    # 2. Iterate and process each matched target
    foreach ($p in $matched) {
        $pidNum = $p.Id
        $procName = $p.ProcessName.ToLower()

        # Guard against terminating critical Windows processes
        if ($pidNum -le 4 -or $procName -in @('system', 'idle')) {
            Write-Log "[SECURITY] PID $pidNum ($procName) is a protected Windows Kernel system process. Termination is prohibited." Red
            continue
        }

        if ($procName -in $script:CriticalProcesses) {
            Write-Log "[WARNING] '$procName' (PID $pidNum) is a critical Windows system process!" Red
            Write-Log "          Terminating this process will likely cause a Windows crash (BSOD) or immediate restart." Yellow
            if (-not $BypassConfirmation) {
                $confirm = Read-Host "Are you absolutely sure you want to terminate $procName? Type 'YES-FORCE' to confirm"
                if ($confirm -cne "YES-FORCE") {
                    Write-Log "[ABORTED] Termination of critical process cancelled by user." Yellow
                    continue
                }
            }
        }
        elseif (-not $BypassConfirmation -and $matched.Count -gt 1) {
            $confirm = Read-Host "Confirm terminating '$($p.ProcessName)' (PID $pidNum)? [y/N]"
            if ($confirm -notmatch '^(y|yes)$') {
                Write-Log "[SKIPPED] Process PID $pidNum skipped." Yellow
                continue
            }
        }

        # Execution logic: Tree kill vs Standard kill vs Graceful close
        $actionName = if ($KillTree) { "Tree-Kill" } elseif ($ForceKill) { "Force-Kill" } else { "Graceful-Close" }
        Write-Log "[ACTION] Initiating $actionName for '$($p.ProcessName)' (PID: $pidNum)..." Cyan

        try {
            if ($KillTree) {
                # Use taskkill.exe /F /T /PID to recursively eliminate tree
                $cmdOutput = & taskkill.exe /F /T /PID $pidNum 2>&1
                Write-Log "  [+] Process tree terminated for PID $pidNum ($cmdOutput)" Green
            }
            elseif ($ForceKill) {
                Stop-Process -Id $pidNum -Force -ErrorAction Stop
                Write-Log "  [+] Process '$($p.ProcessName)' (PID: $pidNum) forcefully killed." Green
            }
            else {
                # Attempt graceful window close first
                $gracefullyClosed = $false
                try {
                    if ($p.MainWindowHandle -ne [IntPtr]::Zero) {
                        $p.CloseMainWindow() | Out-Null
                        Start-Sleep -Milliseconds 1500
                        if (-not (Get-Process -Id $pidNum -ErrorAction SilentlyContinue)) {
                            $gracefullyClosed = $true
                        }
                    }
                } catch {}

                if ($gracefullyClosed) {
                    Write-Log "  [+] Process '$($p.ProcessName)' (PID: $pidNum) closed gracefully via window message." Green
                }
                else {
                    Stop-Process -Id $pidNum -ErrorAction Stop
                    Write-Log "  [+] Process '$($p.ProcessName)' (PID: $pidNum) terminated." Green
                }
            }
        }
        catch {
            Write-Log "  [!] Failed to terminate process PID $($pidNum): $_" Red
        }
    }
}

# ==============================================================================
# DETAILED PROCESS INSPECTOR MODAL
# ==============================================================================
function Show-ProcessDetailModal {
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Proc
    )

    Clear-Host
    Write-Host ("=" * 100) -ForegroundColor Cyan
    Write-Host (" PROCESS INSPECTION CARD: {0} (PID: {1})" -f $Proc.Name, $Proc.PID) -ForegroundColor Cyan
    Write-Host ("=" * 100) -ForegroundColor Cyan
    Write-Host ""
    Write-Host ("  Process Name    : {0}" -f $Proc.Name) -ForegroundColor White
    Write-Host ("  Process ID (PID): {0}" -f $Proc.PID) -ForegroundColor White
    Write-Host ("  Parent PID      : {0}" -f $Proc.ParentPID) -ForegroundColor White
    Write-Host ("  Responding      : {0}" -f $(if ($Proc.Responding) { "Yes (Healthy)" } else { "NO (Hung/Frozen)" })) -ForegroundColor $(if ($Proc.Responding) { "Green" } else { "Red" })
    Write-Host ""
    Write-Host ("  Executable Path : {0}" -f $Proc.Path) -ForegroundColor Yellow
    Write-Host ("  Command Line    : {0}" -f $Proc.CommandLine) -ForegroundColor DarkYellow
    Write-Host ""
    Write-Host ("  Publisher/Vendor: {0}" -f $Proc.Company) -ForegroundColor Cyan
    Write-Host ("  Description     : {0}" -f $Proc.Description) -ForegroundColor Cyan
    Write-Host ""
    Write-Host ("  Physical RAM WS : {0} ({1:N0} bytes)" -f $Proc.WorkingSetFormatted, $Proc.WorkingSetBytes) -ForegroundColor Green
    Write-Host ("  Private Memory  : {0} ({1:N0} bytes)" -f $Proc.PrivateFormatted, $Proc.PrivateBytes) -ForegroundColor Green
    Write-Host ("  Total CPU Time  : {0} ({1:N2} seconds)" -f $Proc.CPUTimeFormatted, $Proc.CPUSeconds) -ForegroundColor Green
    Write-Host ("  Disk Read I/O   : {0}" -f (Format-ByteSize $Proc.DiskReadBytes)) -ForegroundColor Green
    Write-Host ("  Disk Write I/O  : {0}" -f (Format-ByteSize $Proc.DiskWriteBytes)) -ForegroundColor Green
    Write-Host ""
    Write-Host ("  NETWORK STATUS  : {0}" -f $(if ($Proc.IsListening) { "Actively Listening on Network Ports" } else { "No Listening Sockets" })) -ForegroundColor $(if ($Proc.IsListening) { "Magenta" } else { "DarkGray" })
    if ($Proc.IsListening) {
        Write-Host "    Bound Sockets :" -ForegroundColor Magenta
        foreach ($d in $Proc.ListeningDetails) {
            Write-Host ("      • [{0}] {1}:{2} -> Service: {3}" -f $d.Protocol, $d.LocalAddress, $d.LocalPort, $d.Service) -ForegroundColor White
        }
    }
    Write-Host ""
    Write-Host ("  AUTOSTART STATUS: {0}" -f $(if ($Proc.IsAutostart) { "Registered Startup / Autostart Program" } else { "Not Identified as Startup Item" })) -ForegroundColor $(if ($Proc.IsAutostart) { "DarkYellow" } else { "DarkGray" })
    if ($Proc.IsAutostart) {
        Write-Host ("    Startup Sources: {0}" -f $Proc.AutostartSummary) -ForegroundColor DarkYellow
    }
    Write-Host ""
    Write-Host ("=" * 100) -ForegroundColor Cyan
    Write-Host "Press [Enter] to return to the interactive console..." -ForegroundColor Yellow
    [void][System.Console]::ReadLine()
}

# ==============================================================================
# INTERACTIVE CONSOLE SESSION
# ==============================================================================
function Start-InteractiveProcessSession {
    param (
        [string]$InitialFilter = "",
        [int]$InitialPort = 0,
        [switch]$InitialListeningOnly,
        [switch]$InitialStartupOnly,
        [string]$InitialSortBy = "Memory"
    )

    # Maximize console scrollback buffer for smooth full-view navigation
    try {
        if ($Host.UI.RawUI.BufferSize.Height -lt 9000) {
            $buf = $Host.UI.RawUI.BufferSize
            $buf.Height = 9000
            $Host.UI.RawUI.BufferSize = $buf
        }
    } catch {}

    $currentFilter   = $InitialFilter
    $currentPort     = $InitialPort
    $currentNetOnly  = $InitialListeningOnly.IsPresent
    $currentBootOnly = $InitialStartupOnly.IsPresent
    $currentSort     = if ($InitialSortBy) { $InitialSortBy } else { "Memory" }

    # Pre-cache autostart map for high performance during session
    Write-Host "Caching system autostart signatures (Registry, Startup Folders, Services, Tasks)..." -ForegroundColor Cyan
    $cachedAutostartMap = Get-AutostartMap

    while ($true) {
        Clear-Host

        # 1. Gather live network and process state
        $liveNetMap = Get-ListeningNetworkMap
        $allEnriched = Get-EnrichedProcesses -NetMap $liveNetMap -AutostartMap $cachedAutostartMap

        # 2. Filter & Sort
        $filterParams = @{
            ProcessList   = $allEnriched
            FilterQuery   = $currentFilter
            PortFilter    = $currentPort
            ListeningOnly = $currentNetOnly
            StartupOnly   = $currentBootOnly
            SortBy        = $currentSort
        }
        $displayList = Filter-EnrichedProcesses @filterParams

        # 3. Header & Filter Status
        $totalAll = $allEnriched.Count
        $totalMatched = $displayList.Count
        $filterText = if ($currentFilter) { "'$currentFilter'" } else { "None (*)" }
        $portText   = if ($currentPort -gt 0) { "$currentPort" } else { "All" }
        $netText    = if ($currentNetOnly) { "Listening Only" } else { "All" }
        $bootText   = if ($currentBootOnly) { "Autostart Only" } else { "All" }

        Write-Host ("=" * 120) -ForegroundColor Cyan
        Write-Host " PROCESS MANAGER - INTERACTIVE CONTROL CONSOLE" -ForegroundColor Cyan
        Write-Host (" ACTIVE FILTERS: [Query: {0}] | [Port: {1}] | [Net: {2}] | [Autostart: {3}] | [Sort: {4}]" -f `
            $filterText, $portText, $netText, $bootText, $currentSort) -ForegroundColor Yellow
        Write-Host (" Legend: [NET] Network Listener (Cyan) | [AUTO] Startup Item (Green) | [HUNG] Frozen (Red) | Showing: {0} / {1}" -f `
            $totalMatched, $totalAll) -ForegroundColor DarkGray
        Write-Host ("=" * 120) -ForegroundColor Cyan

        # 4. Render Table
        Render-ProcessView -Processes $displayList

        Write-Host ""
        Write-Host ("  Total items displayed: {0} processes" -f $totalMatched) -ForegroundColor Cyan
        Write-Host ("  " + ("=" * 115)) -ForegroundColor DarkCyan

        # 5. Interactive Commands Guide
        Write-Host "ACTIONS & COMMANDS:" -ForegroundColor Yellow
        Write-Host "  Search & Filters  :" -ForegroundColor DarkGray
        Write-Host "    [s <query>]      Search name, path, publisher (e.g. 's chrome', 's *' to clear)"
        Write-Host "    [p <port>]       Filter by listening port (e.g. 'p 80', 'p 443', 'p 0' to clear)"
        Write-Host "    [net]            Toggle Network Listening filter (Listening Only <-> All)"
        Write-Host "    [boot]           Toggle Autostart filter (Startup Items Only <-> All)"
        Write-Host "    [sort <metric>]  Sort: 'sort mem', 'sort cpu', 'sort disk', 'sort name', 'sort pid'"
        Write-Host "  Process Control   :" -ForegroundColor DarkGray
        Write-Host "    [i <nr|pid>]     Inspect full details / card for process (e.g. 'i 1' or 'i 5420')"
        Write-Host "    [t <nr|pid>]     Gracefully terminate process (e.g. 't 2' or 't 1280')"
        Write-Host "    [k <nr|pid>]     Force kill process (e.g. 'k 3' or 'k 4100')"
        Write-Host "    [kt <nr|pid>]    Force kill process and its entire process tree"
        Write-Host "  Session Controls  :" -ForegroundColor DarkGray
        Write-Host "    [r] Refresh live processes  |  [c] Re-cache autostart signatures  |  [q] Exit console"
        Write-Host ""

        $rawInput = Read-Host "Enter command"
        if ($null -ne $rawInput) {
            $rawInput = $rawInput.Trim()
        }

        if ([string]::IsNullOrWhiteSpace($rawInput) -or $rawInput -ieq 'r') {
            continue
        }

        if ($rawInput -ieq 'q') {
            break
        }

        if ($rawInput -ieq 'c') {
            Write-Host "Refreshing autostart cache..." -ForegroundColor Cyan
            $cachedAutostartMap = Get-AutostartMap
            continue
        }

        if ($rawInput -ieq 'net') {
            $currentNetOnly = -not $currentNetOnly
            continue
        }

        if ($rawInput -ieq 'boot') {
            $currentBootOnly = -not $currentBootOnly
            continue
        }

        # Command Tokenizer
        $parts = $rawInput -split '\s+', 2
        $cmd = $parts[0].ToLower()
        $arg = if ($parts.Count -gt 1) { $parts[1].Trim() } else { "" }

        # Helper to resolve table index or PID to PSCustomObject
        $resolveTarget = {
            param ([string]$InputTarget)
            $targetNum = 0
            if ([int]::TryParse($InputTarget, [ref]$targetNum)) {
                # Check if it corresponds to row number 1..Count
                if ($targetNum -ge 1 -and $targetNum -le $displayList.Count) {
                    return $displayList[$targetNum - 1]
                }
                # Else look up by PID in all processes
                $byPid = $allEnriched | Where-Object { $_.PID -eq $targetNum } | Select-Object -First 1
                if ($byPid) { return $byPid }
            }
            return $null
        }

        switch ($cmd) {
            "s" {
                if ($arg -eq "*" -or [string]::IsNullOrWhiteSpace($arg)) {
                    $currentFilter = ""
                } else {
                    $currentFilter = $arg
                }
            }
            "p" {
                $pNum = 0
                if ([int]::TryParse($arg, [ref]$pNum)) {
                    $currentPort = $pNum
                } else {
                    $currentPort = 0
                }
            }
            "sort" {
                switch ($arg.ToLower()) {
                    "cpu"   { $currentSort = "CPU" }
                    "disk"  { $currentSort = "Disk" }
                    "name"  { $currentSort = "Name" }
                    "pid"   { $currentSort = "PID" }
                    default { $currentSort = "Memory" }
                }
            }
            "i" {
                if (-not $arg) {
                    Write-Host "Specify row number or PID to inspect (e.g. 'i 1')." -ForegroundColor Yellow
                    Start-Sleep -Seconds 1
                    continue
                }
                $targetObj = & $resolveTarget $arg
                if ($targetObj) {
                    Show-ProcessDetailModal -Proc $targetObj
                } else {
                    Write-Host "Process '$arg' not found." -ForegroundColor Red
                    Start-Sleep -Seconds 1
                }
            }
            "t" {
                if (-not $arg) {
                    Write-Host "Specify row number or PID to terminate (e.g. 't 1')." -ForegroundColor Yellow
                    Start-Sleep -Seconds 1
                    continue
                }
                $targetObj = & $resolveTarget $arg
                $targetIdentifier = if ($targetObj) { "$($targetObj.PID)" } else { $arg }
                Stop-ManagedProcess -Target $targetIdentifier
                Write-Host "Press [Enter] to refresh..." -ForegroundColor DarkGray
                [void][System.Console]::ReadLine()
            }
            "k" {
                if (-not $arg) {
                    Write-Host "Specify row number or PID to kill (e.g. 'k 1')." -ForegroundColor Yellow
                    Start-Sleep -Seconds 1
                    continue
                }
                $targetObj = & $resolveTarget $arg
                $targetIdentifier = if ($targetObj) { "$($targetObj.PID)" } else { $arg }
                Stop-ManagedProcess -Target $targetIdentifier -ForceKill
                Write-Host "Press [Enter] to refresh..." -ForegroundColor DarkGray
                [void][System.Console]::ReadLine()
            }
            "kt" {
                if (-not $arg) {
                    Write-Host "Specify row number or PID to tree-kill (e.g. 'kt 1')." -ForegroundColor Yellow
                    Start-Sleep -Seconds 1
                    continue
                }
                $targetObj = & $resolveTarget $arg
                $targetIdentifier = if ($targetObj) { "$($targetObj.PID)" } else { $arg }
                Stop-ManagedProcess -Target $targetIdentifier -ForceKill -KillTree
                Write-Host "Press [Enter] to refresh..." -ForegroundColor DarkGray
                [void][System.Console]::ReadLine()
            }
            default {
                Write-Host "Unknown command '$cmd'. Type 's', 'p', 'i', 't', 'k', 'kt', 'net', 'boot', 'r', or 'q'." -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    }
}

# ==============================================================================
# MAIN CONTROLLER & DISPATCHER
# ==============================================================================
try {
    # 1. Safe default: Help display without parameters
    if ($PSBoundParameters.Count -eq 0 -or $Help) {
        Show-HelpGuide
        Exit 0
    }

    # 2. Input Security Assertions
    Assert-SafeInput -InputString $Filter -ParamName "Filter"
    Assert-SafeInput -InputString $Terminate -ParamName "Terminate"
    Assert-SafeInput -InputString $Kill -ParamName "Kill"

    # 3. Administrative Privileges Verification & Auto-Elevation
    if ($Terminate -or $Kill) {
        Assert-AdministratorElevation -Strict
    }
    else {
        Assert-AdministratorElevation
    }

    # 4. Logging Initialization
    $null = Initialize-Logging -CustomPath $LogPath

    # 5. Route: Process Termination / Kill (Non-interactive)
    if ($Terminate) {
        Stop-ManagedProcess -Target $Terminate -KillTree:$KillTree -BypassConfirmation:$Force
        Exit 0
    }

    if ($Kill) {
        Stop-ManagedProcess -Target $Kill -ForceKill -KillTree:$KillTree -BypassConfirmation:$Force
        Exit 0
    }

    # 6. Route: Interactive Console Mode
    if ($Interactive) {
        Start-InteractiveProcessSession `
            -InitialFilter $Filter `
            -InitialPort $Port `
            -InitialListeningOnly:$ListeningOnly `
            -InitialStartupOnly:$StartupOnly `
            -InitialSortBy $SortBy
        Exit 0
    }

    # 7. Route: Snapshot / List Mode (Default when action parameters provided)
    if ($Snapshot -or $PSCmdlet.ParameterSetName -eq "SnapshotSet" -or $Filter -or $Port -gt 0 -or $ListeningOnly -or $StartupOnly) {
        Write-Log "Collecting listening network sockets and system autostart signatures..." Cyan
        $netMap = Get-ListeningNetworkMap
        $autostartMap = Get-AutostartMap
        $allProcs = Get-EnrichedProcesses -NetMap $netMap -AutostartMap $autostartMap

        $filteredProcs = Filter-EnrichedProcesses `
            -ProcessList $allProcs `
            -FilterQuery $Filter `
            -PortFilter $Port `
            -ListeningOnly:$ListeningOnly `
            -StartupOnly:$StartupOnly `
            -SortBy $SortBy `
            -TopLimit $Top

        if ($AsJson) {
            $jsonOutput = $filteredProcs | ConvertTo-Json -Depth 4
            Write-Output $jsonOutput
            Exit 0
        }

        $filteredArray = @($filteredProcs)
        $banner = "PROCESS DIAGNOSTICS SNAPSHOT - {0} matching processes found (Sorted by {1})" -f $filteredArray.Count, $SortBy
        Render-ProcessView -Processes $filteredArray -HeaderBanner $banner

        Write-Log "Snapshot complete. Listed $($filteredArray.Count) process(es)." Green
        Exit 0
    }

    # Fallback to help guide
    Show-HelpGuide
    Exit 0
}
catch {
    Write-Log "[FATAL] Execution failed: $_" Red
    Exit 1
}

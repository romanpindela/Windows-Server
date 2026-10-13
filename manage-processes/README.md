# Windows Process Manager (`manage-processes.ps1`)

[![PowerShell Version](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-blue.svg)](https://microsoft.com/powershell)
[![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011%20%7C%20Server-lightgrey.svg)](https://www.microsoft.com/windows)
[![Version](https://img.shields.io/badge/Version-1.0.0-green.svg)](https://github.com/romanpindela)
[![Author](https://img.shields.io/badge/Author-Roman%20Pindela-orange.svg)](mailto:roman.pindela@gmail.com)
[![License](https://img.shields.io/badge/License-MIT-purple.svg)](https://opensource.org/licenses/MIT)

An enterprise-grade process management, performance diagnostics, autostart detection, and network socket correlation utility for Windows Desktop and Windows Server environments.

Designed for systems administrators, DevOps engineers, and security analysts, this tool delivers actionable insights into running processes, identifying high-resource consumers, rogue background tasks, listening network daemons, and system autostart persistence mechanisms.

---

## 🌟 Key Features

- **Comprehensive Multi-Line Process Diagnostics**:
  - **Line 1 (Core Metrics)**: `No.` | `PID` | `Process Name` | `RAM (Working Set / Private Bytes)` | `CPU Time` | `Disk I/O (Read/Write Transfer)` | `Tags ([NET], [AUTO], [HUNG])`
  - **Line 2 (Location)**: Executable binary path (`-> Path: C:\...`)
  - **Line 3 (Metadata)**: Verified vendor/publisher and file description (`-> Publisher: Google LLC | Description: Google Chrome`)
  - **Line 4 (Network Listeners)**: Sockets bound to listening ports (`-> Network: TCP:80 (HTTP), TCP:443 (HTTPS), UDP:53 (DNS)`)
  - **Line 5 (Autostart Persistence)**: Origin of automatic startup (`-> Autostart: Reg:HKLM-Run | AutoService: WinDefend | TaskScheduler: ...`)
- **Listening Network Service & Port Correlation**:
  - Automatically correlates running processes with active listening TCP connections and UDP endpoints (`Get-NetTCPConnection` / `Get-NetUDPEndpoint`).
  - Resolves well-known system ports (HTTP, HTTPS, SSH, DNS, RDP, SMB, MySQL, MSSQL, WinRM, etc.).
  - Direct filtering by specific port number (`-Port 443`) or network daemons only (`-ListeningOnly`).
- **Autostart & Persistence Mechanism Detection**:
  - Detects and tags processes launched automatically with the operating system or user logon:
    - **Registry Run & RunOnce** (`HKLM` and `HKCU`, including 32-bit `WOW6432Node` keys).
    - **Windows Startup Folders** (All Users ProgramData Startup and Current User AppData Startup).
    - **Automatic Windows Services** (processes hosting services with `StartMode = 'Auto'`).
    - **Task Scheduler** (tasks scheduled with `At startup / Boot` or `At log on` triggers).
  - Instant autostart audit switch (`-StartupOnly`).
- **Process Lifecycle Management (Stop / Kill / Tree)**:
  - **Graceful Termination (`-Terminate`)**: Attempts clean application shutdown via window close message (`CloseMainWindow`), cleanly releasing database locks and cached files before falling back to stop.
  - **Forceful Termination (`-Kill`)**: Immediately terminates stubborn or unresponsive processes.
  - **Process Tree Kill (`-KillTree` / `-kt`)**: Recursively terminates parent processes and all spawned child subprocesses using native `taskkill.exe /F /T /PID`.
  - **Critical Process Safety Guards**: Protects critical Windows kernel processes (`system`, `idle`, `smss`, `csrss`, `wininit`, `services`, `lsass`, `winlogon`, `svchost`) against accidental termination, preventing system crashes and Blue Screens of Death (BSOD).
- **Dual Operating Modes**:
  - **Interactive Management Console (`-Interactive`)**: Full-screen console shell with real-time query searching, instant filter toggling (`[net]`, `[boot]`), sorting, process inspection cards, and single-keystroke termination commands.
  - **Non-Interactive Snapshot Mode (`-Snapshot`)**: Outputs structured process tables directly to standard output, supporting top-N limits, custom sort orders, and `-AsJson` formatting for CI/CD pipelines and SIEM ingestion.
- **Enterprise CleanCode & Security**:
  - **Safe-by-Default**: Running without parameters outputs the help guide and parameter syntax, preventing accidental execution.
  - **Language-Independent Elevation**: Uses Well-Known SID verification (`S-1-5-32-544` / `BuiltInAdministratorsSid`) ensuring flawless privilege detection across localized Windows versions (English, Polish, German, etc.).
  - **Input Sanitization**: Validates parameters against command injection tokens and invalid path characters.
  - **Automated Logging**: Timestamped logging to `C:\Logs\<DateTime>-<Host>-<User>-Manage-Processes.txt` (or custom `-LogPath`).

---

## 📋 System Requirements

- **Operating System**: Windows 10, Windows 11, Windows Server 2016 / 2019 / 2022 / 2025 (x64 / ARM64).
- **PowerShell**: Windows PowerShell 5.1 or PowerShell Core 7.x+.
- **Privileges**: Administrator privileges recommended for complete inspection of system services, listening sockets, and process termination (script automatically requests UAC elevation when necessary).

---

## 🚀 Quick Start

### 1. Unblock the Script
Before initial execution, unblock the script to satisfy Windows execution policies:

```powershell
Unblock-File -Path .\manage-processes.ps1
```

### 2. View Built-in Help
Executing the script without parameters displays the built-in guide:

```powershell
.\manage-processes.ps1
```

Or explicitly via the `-Help` switch:

```powershell
.\manage-processes.ps1 -Help
```

---

## 💻 Usage Examples

### 1. Interactive Console Mode
Launch the live management console to browse, filter, search, and manage processes interactively:

```powershell
.\manage-processes.ps1 -Interactive
```

Inside the interactive console:
- `s <query>` : Filter processes by name, executable path, or publisher (e.g. `s chrome`, `s python`, `s *` to reset).
- `p <port>` : Filter by listening port (e.g. `p 80`, `p 443`, `p 0` to reset).
- `net` : Toggle Network-only filter (shows only processes listening on TCP/UDP sockets).
- `boot` : Toggle Autostart-only filter (shows only boot/logon/service startup programs).
- `sort <metric>` : Switch sort metric (`sort mem`, `sort cpu`, `sort disk`, `sort name`, `sort pid`).
- `i <nr|pid>` : Open detailed Process Inspection Card (shows full command line, parent PID, bound sockets, etc.).
- `t <nr|pid>` : Gracefully terminate process by table row number or PID.
- `k <nr|pid>` : Force kill process by table row number or PID.
- `kt <nr|pid>` : Force kill process and its entire child process tree.
- `r` : Refresh live process metrics.
- `c` : Re-cache autostart signatures.
- `q` : Quit interactive console.

---

### 2. Non-Interactive Snapshot Inspection

#### Snapshot of all processes sorted by Memory (Default)
```powershell
.\manage-processes.ps1 -Snapshot
```

#### Filter processes by Name, Path, or Publisher
```powershell
.\manage-processes.ps1 -Snapshot -Filter "*edge*"
.\manage-processes.ps1 -Snapshot -Filter "*Microsoft*"
.\manage-processes.ps1 -Snapshot -Filter "*Python*"
```

#### List only processes listening on network ports (TCP/UDP)
```powershell
.\manage-processes.ps1 -Snapshot -ListeningOnly
```

#### Find which process is listening on a specific port
```powershell
# Identify process listening on HTTP (80)
.\manage-processes.ps1 -Snapshot -Port 80

# Identify process listening on HTTPS (443)
.\manage-processes.ps1 -Snapshot -Port 443

# Identify process listening on RDP (3389)
.\manage-processes.ps1 -Snapshot -Port 3389
```

#### Inspect Autostart & Persistence Programs
```powershell
# List all active processes that were launched via Registry Run, Startup Folder, Auto-Service, or Scheduler
.\manage-processes.ps1 -Snapshot -StartupOnly
```

#### Find Top Resource Consumers
```powershell
# Top 10 CPU consumers
.\manage-processes.ps1 -Snapshot -SortBy CPU -Top 10

# Top 10 Disk I/O consumers (Read/Write transfer volume)
.\manage-processes.ps1 -Snapshot -SortBy Disk -Top 10

# Top 15 Memory consumers
.\manage-processes.ps1 -Snapshot -SortBy Memory -Top 15
```

#### Export Diagnostics to JSON
```powershell
# Export network listeners to JSON file
.\manage-processes.ps1 -Snapshot -ListeningOnly -AsJson | Out-File -FilePath "C:\Logs\network_listeners.json" -Encoding UTF8

# Export autostart processes to JSON
.\manage-processes.ps1 -Snapshot -StartupOnly -AsJson
```

---

### 3. Process Management & Termination

#### Graceful Process Termination
```powershell
# Terminate process by PID (attempts window close before stopping)
.\manage-processes.ps1 -Terminate 5412

# Terminate process by name
.\manage-processes.ps1 -Terminate "notepad" -Force
```

#### Force Kill Process
```powershell
# Forcefully kill process by PID
.\manage-processes.ps1 -Kill 8920 -Force

# Forcefully kill all processes matching a name pattern
.\manage-processes.ps1 -Kill "chrome" -Force
```

#### Force Kill Process Tree (Parent + Child Subprocesses)
```powershell
# Kills process 10420 and all subprocesses spawned by it
.\manage-processes.ps1 -Kill 10420 -KillTree -Force
```

---

## ⚙️ Parameters Reference

| Parameter | Alias | Type | Description |
|:---|:---:|:---:|:---|
| `-Interactive` | `-i` | Switch | Launches the interactive full-screen CLI control console. |
| `-Snapshot` | `-s`, `-l` | Switch | Outputs process diagnostics table to stdout and exits. |
| `-Terminate` | `-t`, `-Stop` | String | Gracefully terminates process by PID or Name pattern. |
| `-Kill` | `-k`, `-ForceKill` | String | Forcefully terminates process by PID or Name pattern. |
| `-KillTree` | `-tree`, `-kt` | Switch | Kills process and all spawned child subprocesses recursively. |
| `-Force` | `-f`, `-Quiet` | Switch | Suppresses interactive confirmation prompts. |
| `-Filter` | `-q`, `-Pattern` | String | Wildcard query filtering Name, Path, Publisher, or Description. |
| `-Port` | `-p` | Int | Filters processes listening on the specified TCP/UDP port. |
| `-ListeningOnly` | `-net` | Switch | Displays only processes actively listening on network ports. |
| `-StartupOnly` | `-boot` | Switch | Displays only processes identified as autostart items. |
| `-SortBy` | — | String | Sorts by `Memory` (default), `CPU`, `Disk`, `Name`, or `PID`. |
| `-Top` | — | Int | Limits output to the top N processes matching criteria. |
| `-AsJson` | — | Switch | Formats output in structured JSON for automation. |
| `-LogPath` | `-Log` | String | Custom log file path (Default: `C:\Logs\<Timestamp>-...txt`). |
| `-Help` | `-h` | Switch | Displays help guide, author information, and examples. |

---

## 🔒 Security & Safety Controls

1. **Kernel & Core Process Shielding**:
   - Critical operating system processes (`system`, `idle`, `smss`, `csrss`, `wininit`, `services`, `lsass`, `winlogon`, `svchost`) are shielded against accidental termination.
   - PIDs `0` and `4` are strictly blocked from termination.
   - Core system binaries trigger an explicit confirmation barrier (`'YES-FORCE'`) with severe warnings before any termination attempt.
2. **Language-Independent SID Elevation**:
   - Elevation status is validated via Well-Known SID `S-1-5-32-544` (`BuiltInAdministratorsSid`), ensuring consistency across multilingual operating systems (Polish, English, German, etc.).
   - Automatically prompts for UAC elevation when necessary and preserves all CLI parameters.
3. **Safe Parameter Parsing**:
   - Defends against command injection by sanitizing path and target parameters against dangerous tokens (`;`, `|`, `"`, `$`, `&`, newlines).

---

## 👤 Author & License

- **Author**: Roman Pindela
- **Email**: [roman.pindela@gmail.com](mailto:roman.pindela@gmail.com)
- **GitHub**: [https://github.com/romanpindela](https://github.com/romanpindela)
- **Repository**: [https://github.com/romanpindela/Windows-Server](https://github.com/romanpindela/Windows-Server)
- **License**: MIT License

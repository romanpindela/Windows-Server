# Backup-HyperVVM

[![PowerShell Version](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-blue.svg)](https://microsoft.com/powershell)
[![Platform](https://img.shields.io/badge/Platform-Windows%20Server%202016--2025%20%7C%20Win%2010%2F11%20Pro-lightgrey.svg)](https://www.microsoft.com/windows-server)
[![Version](https://img.shields.io/badge/Version-1.1.0-green.svg)](https://github.com/romanpindela/Windows-Server)
[![License](https://img.shields.io/badge/License-MIT-purple.svg)](https://opensource.org/licenses/MIT)

---

## Overview

`Backup-HyperVVM.ps1` is a **100% native Microsoft** PowerShell/.NET automation script designed for **Windows Server Hyper-V hosts** (including Hyper-V Server Core without GUI; recommended deployment path: `C:\Scripts\Backup-HyperVVM.ps1`). With **zero third-party dependencies**, it creates complete, self-contained, **AES-256-CBC + HMAC-SHA256 encrypted ZIP backups** (`.zip.aes`) of one or more Hyper-V virtual machines in `C:\DANE\Backup`, complete with VM configuration, virtual hard disks, checkpoints, hardware/vSwitch metadata, step-by-step restore instructions, and copy execution logs.

The companion script [`Decrypt-HyperVBackup.ps1`](Decrypt-HyperVBackup.ps1) is automatically copied to `C:\DANE\Backup\` to verify HMAC-SHA256 integrity, decrypt, and extract any `.zip.aes` archive using only built-in .NET APIs.

---

## Technical Architecture

```mermaid
flowchart TD
    A["Start Backup-HyperVVM.ps1"] --> B{"-Help or 0 params?"}
    B -- Yes --> C["Show-ScriptHelp & Exit 0"]
    B -- No --> D{"Admin SID S-1-5-32-544?"}
    D -- No --> E["UAC Auto-Elevation"]
    D -- Yes --> F["Acquire [SecureString] Password"]
    F --> G{"BackupMode?"}
    G -- Hot --> H["Live Export-VM (No Downtime)"]
    G -- Cold --> I["Stop-VM (Graceful / Timeout) -> Export-VM -> Start-VM"]
    H --> J["Generate VM-Metadata.json & RESTORE-INSTRUCTIONS.txt"]
    I --> J
    J --> K["Embed Backup-Copy.log & C:\Logs snapshot"]
    K --> L["Native .NET ZipFile (Zip64 >2 GB)"]
    L --> M["Streaming AES-256-CBC + HMAC-SHA256 (.zip.aes) & Verify"]
    M --> N["Remove Staging Folder -> Output Summary"]
```

### Archive Contents (`<VMName>_<yyyyMMdd-HHmmss>.zip.aes`)

```text
<VMName>_<yyyyMMdd-HHmmss>.zip.aes (Native .NET AES-256-CBC + HMAC-SHA256)
├── <VMName>/
│   ├── Virtual Machines/          # .vmcx, .vmrs, .vmgs configuration files
│   ├── Virtual Hard Disks/        # .vhdx, .vhd, .avhdx disk images
│   └── Snapshots/                 # Checkpoints (if present)
├── VM-Metadata.json               # Hardware, CPU, RAM, disk, and vSwitch mapping
├── RESTORE-INSTRUCTIONS.txt       # Step-by-step PowerShell & Hyper-V Manager guide
├── Backup-Copy.log                # Per-VM copy operation log
└── <timestamp>-Backup-HyperVVM-*.logs  # Full host execution audit log
```

---

## Environment & Prerequisites

- **Operating System:** Windows Server 2016 / 2019 / 2022 / 2025 (Full or Server Core), Microsoft Hyper-V Server, or Windows 10 / 11 Pro (English and Polish editions supported).
- **PowerShell:** Windows PowerShell 5.1 or PowerShell 7+.
- **Built-in Microsoft Components Only (Zero Third-Party Tools):**
  - `Hyper-V` PowerShell module (`Get-VM`, `Stop-VM`, `Start-VM`, `Export-VM`)
  - `.NET` `System.IO.Compression.ZipFile` (Zip64 support for VHDX files > 2 GB)
  - `.NET` `System.Security.Cryptography` (`Rfc2898DeriveBytes` PBKDF2 100,000 iterations, `Aes` 256-bit CBC, `HMACSHA256`)
- **Recommended Deployment Path:** `C:\Scripts\Backup-HyperVVM.ps1` (and `C:\Scripts\Decrypt-HyperVBackup.ps1`)
- **Default Backup Destination:** `C:\DANE\Backup`
- **Default Audit Log Path:** `C:\Logs\<yyyyMMdd-HHmmss>-Backup-HyperVVM-<ComputerName>-<UserName>.logs`

### Unblock & Deploy

```powershell
# Deploy to C:\Scripts on the Hyper-V server
New-Item -Path "C:\Scripts" -ItemType Directory -Force | Out-Null
Copy-Item -Path ".\Backup-HyperVVM.ps1", ".\Decrypt-HyperVBackup.ps1" -Destination "C:\Scripts\" -Force
Unblock-File -Path "C:\Scripts\Backup-HyperVVM.ps1"
Unblock-File -Path "C:\Scripts\Decrypt-HyperVBackup.ps1"
```

---

## Permissions Required

- **Level:** **Admin** (Local Administrator privileges).
- **Verification:** Language-independent check against the Built-in Administrators SID (`S-1-5-32-544`).
- **Note on UAC & `-ZipPassword`:** Running without parameters or with `-Help` / `-h` exits safely without elevation. If passing `-ZipPassword` as a `[SecureString]`, launch PowerShell **As Administrator** first, as `[SecureString]` objects cannot be forwarded across a UAC relaunch.

---

## Safety & Impact

- **Hot Mode (`-BackupMode Hot`):** Performs a live `Export-VM` with zero VM downtime.
- **Cold Mode (`-BackupMode Cold`):** Gracefully shuts down running VMs before `Export-VM` and automatically restarts them in a `finally {}` block even if an error occurs (unless `-KeepStopped` is specified).
- **Simulation (`-WhatIf` / `-Confirm`):** Declares `SupportsShouldProcess = $true` so all state-changing actions can be previewed safely with `-WhatIf`.
- **Credential & Crypto Hygiene:** Passwords are accepted only as `[SecureString]`, never written to logs or console, and cleared from memory (`ZeroFreeBSTR` + `Array::Clear`) in `finally {}`. Archives use Encrypt-then-MAC (`AES-256-CBC` + `HMAC-SHA256`) with streaming 1 MB buffers for low RAM usage even on multi-gigabyte VHDX backups.

---

## Parameters

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `-VMName` (`-Name`) | `string[]` | *(Required for backup)* | One or more Hyper-V VM names (pipeline supported). |
| `-BackupMode` (`-Mode`) | `string` | `Hot` | `Hot` (live export) or `Cold` (stop, export, restart). |
| `-BackupPath` | `string` | `C:\DANE\Backup` | Destination directory for encrypted `.zip.aes` archives. |
| `-ZipPassword` (`-Password`) | `SecureString` | *(Interactive prompt)* | AES-256 encryption password. |
| `-CompressionLevel` | `string` | `Optimal` | `.NET ZipFile` compression level: `Optimal`, `Fastest`, or `NoCompression`. |
| `-KeepStopped` | `switch` | `$false` | (Cold mode) Do not restart VM after backup. |
| `-ShutdownTimeoutSeconds` | `int` | `300` | Max seconds to wait for graceful shutdown in Cold mode. |
| `-ForceShutdown` | `switch` | `$false` | Force `Stop-VM -TurnOff` if graceful shutdown times out. |
| `-KeepUncompressed` | `switch` | `$false` | Retain staging directory after archive creation. |
| `-SkipArchiveVerification` | `switch` | `$false` | Skip post-encryption HMAC-SHA256 verification. |
| `-LogPath` (`-l`, `-Log`) | `string` | `C:\Logs\<timestamp>-...logs` | Custom execution log file path. |
| `-NoLog` | `switch` | `$false` | Disable writing execution logs to disk. |
| `-SkipAdminCheck` | `switch` | `$false` | Bypass SID `S-1-5-32-544` elevation check. |
| `-PassThru` | `switch` | `$false` | Return structured `[PSCustomObject]` results to pipeline. |
| `-ListVMs` (`-List`) | `switch` | `$false` | List all Hyper-V VMs on the host with detailed specs in a table and exit. |
| `-Help` (`-h`) | `switch` | `$false` | Display help screen and exit. |

---

## Usage Examples

### 1. Display Help (Zero-Parameter Safe Run)
```powershell
C:\Scripts\Backup-HyperVVM.ps1
```

### 1b. List All Hyper-V Virtual Machines with Details
```powershell
C:\Scripts\Backup-HyperVVM.ps1 -ListVMs
```

### 2. Cold Backup with Secure Interactive Password Prompt
```powershell
$pwd = Read-Host "Enter Encryption Password" -AsSecureString
C:\Scripts\Backup-HyperVVM.ps1 -VMName "DC01" -BackupMode Cold -ZipPassword $pwd
```

### 3. Hot Backup of Multiple VMs (Prompts Securely if `-ZipPassword` Omitted)
```powershell
C:\Scripts\Backup-HyperVVM.ps1 -VMName "APP01", "SQL01" -BackupMode Hot -CompressionLevel Fastest
```

### 4. Unattended Scheduled Task Using Windows DPAPI
Store the encrypted password once under the service account that runs the Scheduled Task:
```powershell
# Run once interactively as the Scheduled Task account:
Read-Host "Enter Backup Password" -AsSecureString | Export-Clixml -Path "C:\Scripts\BackupZip.cred"
```
Then run unattended:
```powershell
$pwd = Import-Clixml -Path "C:\Scripts\BackupZip.cred"
C:\Scripts\Backup-HyperVVM.ps1 -VMName "DC01", "FILE01" -BackupMode Hot -ZipPassword $pwd
```

### 5. Decrypt & Extract a Backup Archive
```powershell
C:\Scripts\Decrypt-HyperVBackup.ps1 -ArchivePath "C:\DANE\Backup\DC01_20261117-220000.zip.aes" -DestinationPath "C:\Restore\DC01"
```

---

## Assets

- `assets/` — Reserved for screenshots and visual documentation.

---

## Logging & Troubleshooting

- **Host Audit Logs:** `C:\Logs\<yyyyMMdd-HHmmss>-Backup-HyperVVM-<ComputerName>-<UserName>.logs`
- **Embedded Archive Logs:** Every `.zip.aes` archive includes `Backup-Copy.log` and a snapshot of the host execution log.
- **Wrong Password / Corrupted File:** `Decrypt-HyperVBackup.ps1` checks the `HMAC-SHA256` signature before writing any decrypted output and fails immediately if the password is incorrect or the file was modified.

---

## Changelog

- **1.1.0 (2026-11-17):** Replaced external `7z.exe` dependency with 100% native Microsoft `.NET ZipFile` (Zip64) + streaming `AES-256-CBC` + `HMAC-SHA256` encryption (`.zip.aes`) and added `Decrypt-HyperVBackup.ps1`.
- **1.0.0 (2026-11-17):** Initial release supporting Hot/Cold Hyper-V VM backups, `Export-VM` full recovery packages, `VM-Metadata.json`, `RESTORE-INSTRUCTIONS.txt`, and embedded copy logs.

---

## Author

- **Author:** Roman Pindela
- **Email:** [roman.pindela@gmail.com](mailto:roman.pindela@gmail.com)
- **GitHub:** [https://github.com/romanpindela](https://github.com/romanpindela)
- **Repository:** [https://github.com/romanpindela/Windows-Server](https://github.com/romanpindela/Windows-Server)
- **License:** MIT

# Windows-Server

A curated collection of enterprise-grade PowerShell automation, diagnostics, and administration scripts for **Windows Server** (2016 / 2019 / 2022 / 2025) and Windows administrative environments.

All scripts follow standardized `Verb-Noun` PascalCase naming, provide safe zero-parameter help (`-Help` / `-h`), support language-independent UAC privilege verification via Windows SID (`S-1-5-32-544`), and include dedicated documentation in each script directory.

---

## Script Catalog

| Script Name | Description | Problem Solved | Category Tag | Permissions |
| :--- | :--- | :--- | :--- | :--- |
| [Backup-HyperVVM](Hyper-V/Backup-HyperVVM/README.md) | Automates full Hot/Cold Hyper-V VM backups (`Export-VM`), embeds hardware metadata, restore instructions, and copy logs, and compresses everything into an AES-256 password-protected ZIP archive. | Eliminates manual VM export steps, undocumented vSwitch mappings, and unencrypted backup archives by producing self-contained, verifiable recovery packages in `C:\DANE\Backup`. | `Hyper-V` | `Admin` |
| [Enable-HyperVRemoteManagementForServer](Hyper-V/Enable-HyperVRemoteManagementForServer/README.md) | Automates host-side WinRM, CredSSP Server, network profile, and Windows Firewall configuration for remote Hyper-V management over LAN and VPN. | Resolves WinRM `Public` network profile errors, `LocalSubnet` firewall blocks over VPN tunnels, and missing CredSSP Server configuration on standalone Workgroup Hyper-V hosts. | `Hyper-V` | `Admin` |
| [Enable-RemoteTaskSchedulerFirewall](Hyper-V/Enable-RemoteTaskSchedulerFirewall/README.md) | Configures, audits, and toggles Windows Defender Firewall rules for Remote Scheduled Tasks Management (MMC `taskschd.msc` / RSAT) on Hyper-V hosts across EN/PL OS editions. | Eliminates MMC Task Scheduler RPC connection timeouts (`RemoteTask-*` / TCP 135 & dynamic RPC ports) and supports optional subnet/VPN scoping without manual GUI firewall hunting. | `Hyper-V` | `Admin` |
| [Manage-Processes](Manage-Processes/README.md) | Provides interactive and CLI process diagnostics, RAM/CPU/Disk I/O monitoring, autostart detection, TCP/UDP port-blocker correlation, and safe process termination. | Eliminates manual correlation across Task Manager, `netstat`, services, Registry, and Task Scheduler when identifying resource hogs, persistence items, or services blocking network ports. | `Process Management` | `Admin` |
| [Manage-ScheduledTasks](Manage-ScheduledTasks/README.md) | Delivers an interactive and CLI flat-view manager for Windows Scheduled Tasks with real-time search, trigger/state filtering, and batch enable/disable by ID or wildcard name. | Overcomes deep folder nesting in Task Scheduler (`taskschd.msc`) to quickly audit upcoming tasks chronologically and toggle tasks across folders in bulk. | `Scheduled Tasks` | `Admin` |

---

## Repository Structure

```text
Windows-Server/
├── Hyper-V/
│   ├── Backup-HyperVVM/
│   │   ├── assets/
│   │   ├── Backup-HyperVVM.ps1
│   │   └── README.md
│   ├── Enable-HyperVRemoteManagementForServer/
│   │   ├── assets/
│   │   ├── Enable-HyperVRemoteManagementForServer.ps1
│   │   └── README.md
│   └── Enable-RemoteTaskSchedulerFirewall/
│       ├── assets/
│       ├── Enable-RemoteTaskSchedulerFirewall.ps1
│       └── README.md
├── Manage-Processes/
│   ├── assets/
│   ├── Manage-Processes.ps1
│   └── README.md
├── Manage-ScheduledTasks/
│   ├── assets/
│   ├── Manage-ScheduledTasks.ps1
│   └── README.md
└── README.md
```

---

## Quick Start

1. Navigate to the desired script directory and unblock the downloaded `.ps1` file if required:
   ```powershell
   Unblock-File -Path .\<ScriptName>.ps1
   ```
2. Run any script without parameters (or with `-Help`) to inspect its built-in documentation, syntax, and examples safely before execution:
   ```powershell
   .\<ScriptName>.ps1 -Help
   ```

---

## Author

- **Author:** Roman Pindela
- **Email:** [roman.pindela@gmail.com](mailto:roman.pindela@gmail.com)
- **GitHub:** [https://github.com/romanpindela](https://github.com/romanpindela)
- **Repository:** [https://github.com/romanpindela/Windows-Server](https://github.com/romanpindela/Windows-Server)
- **License:** MIT

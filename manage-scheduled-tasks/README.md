# Windows Scheduled Task Manager (`manage-scheduled-tasks.ps1`)

[![PowerShell Version](https://img.shields.io/badge/PowerShell-5.1%20%7C%207%2B-blue.svg)](https://microsoft.com/powershell)
[![Platform](https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011%20%7C%20Server-lightgrey.svg)](https://www.microsoft.com/windows)
[![Version](https://img.shields.io/badge/Version-2.7.1-green.svg)](https://github.com/romanpindela)
[![Author](https://img.shields.io/badge/Author-Roman%20Pindela-orange.svg)](mailto:roman.pindela@gmail.com)

A robust, interactive CLI management tool for Windows Scheduled Tasks. Designed for system administrators, engineers, and power users, this tool provides full visibility into scheduled tasks, execution details, action commands, triggers, and state management across Windows Desktop and Windows Server environments.

---

## 🌟 Key Features

- **Full-Width Multi-Line Layout**:
  - **Line 1**: `Nr` | `Status` (`Enabled`/`Disabled`) | `Typ` (`System`/`User`/`App`) | `Trigger` | `Task Name` | `Next run` | `Last run`
  - **Line 2**: Complete binary executable path and CLI arguments (`↳ Command    : ...`)
  - **Line 3**: Sanitized task description (`↳ Description: ...`)
  - **Line 4**: Visual horizontal separator line
- **Universal Substring Search (`s <phrase>`)**:
  - Searches task names, task paths, and executable action commands in real-time.
  - Automatically bypasses system path exclusion during active queries (e.g., `s office`, `s nvidia`, `s edge`, `s update`).
  - Clear with `s *` or `s`.
- **Accurate Trigger Parsing**:
  - Automatically extracts and formats CIM/WMI triggers into clean tags: `[Boot]`, `[Logon]`, `[Daily@HH:mm]`, `[Weekly(Days)@HH:mm]`, `[Monthly@HH:mm]`, `[Once@HH:mm]`, `[Event]`, `[Idle]`, `[Session]`, or `[OnDemand]`.
- **Chronological Sorting**:
  - Tasks are ordered chronologically by `Next Run` ascending (nearest execution first). Disabled or unscheduled tasks are neatly organized at the bottom.
- **Task Categorization & Color Palette (ANSI VT100)**:
  - `System` (Blue) — Built-in Windows & Microsoft services.
  - `User` (Green) — User-profile tasks and user SID contexts (`S-1-5-21-...`).
  - `App` (Cyan) — Third-party software (Nvidia, Adobe, Google, browsers, etc.).
- **Safe Execution & Language Agnostic Elevation**:
  - Uses language-independent Well-Known SID checking (`S-1-5-32-544`) to guarantee Administrator privileges on localized Windows editions (Polish, English, German, etc.), prompting for automatic UAC elevation if required.
  - Hashtable splatting parameter calls eliminate PowerShell CLI concatenation/whitespace parsing bugs.

---

## 📋 System Requirements

- **Operating System**: Windows 10, Windows 11, Windows Server 2016 / 2019 / 2022 / 2025.
- **PowerShell**: Windows PowerShell 5.1 or PowerShell Core (7.x+).
- **Privileges**: Elevated Administrator privileges (script auto-elevates if executed standard).

---

## 🚀 Quick Start

### 1. Interactive Console Mode (Default)
Run the script interactively to inspect, filter, search, enable, and disable tasks on the fly:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\manage-scheduled-tasks.ps1 -Interactive
```

### 2. Command-Line / Non-Interactive Mode (`-ListOnly`)
Display scheduled tasks directly to standard output and exit:

```powershell
# List only Enabled non-Microsoft tasks (default view)
.\manage-scheduled-tasks.ps1 -ListOnly

# List all Disabled tasks
.\manage-scheduled-tasks.ps1 -ListOnly -StateFilter Disabled

# List only Logon-triggered tasks
.\manage-scheduled-tasks.ps1 -ListOnly -TriggerFilter Logon

# List all tasks including system tasks
.\manage-scheduled-tasks.ps1 -ListOnly -ExcludePathPattern "" -StateFilter All
```

---

## ⌨️ Interactive Console Commands

When running in `-Interactive` mode, the prompt accepts immediate single-character and keyword commands:

| Command | Action | Description |
|---|---|---|
| `s <text>` | **Search** | Filter tasks containing `<text>` across Name, Path, or Command (e.g. `s nvidia`, `s office`). |
| `s *` or `s` | **Clear Search** | Clears the active search query and restores default task view. |
| `1..n` | **Disable Tasks** | Disables one or more tasks by their displayed ID (supports lists, e.g. `2` or `1, 4, 7`). |
| `e <id>` | **Enable Tasks** | Enables one or more tasks by ID (e.g. `e 3` or `e 1, 5`). |
| `m` | **Toggle System Tasks** | Instantly switches between hiding and showing Microsoft system tasks (`[SYS]`). |
| `f a` | **Filter State: All** | Displays all tasks regardless of state. |
| `f e` | **Filter State: Enabled** | Displays only enabled tasks (`Ready` and `Running`). |
| `f d` | **Filter State: Disabled**| Displays only disabled tasks. |
| `t a` | **Filter Trigger: All** | Clears trigger restrictions. |
| `t b` | **Filter Trigger: Boot** | Displays tasks executed at system startup. |
| `t l` | **Filter Trigger: Logon**| Displays tasks executed when a user logs on. |
| `t t` | **Filter Trigger: Time** | Displays tasks scheduled for specific times (`Daily`, `Weekly`, `Monthly`, `Once`). |
| `t e` | **Filter Trigger: Event**| Displays tasks triggered by Windows Event Log events. |
| `t o` | **Filter Trigger: OnDemand**| Displays manual/untriggered tasks (`OnDemand`). |
| `r` | **Refresh** | Re-reads tasks from Windows Task Scheduler and re-renders the list. |
| `q` | **Quit** | Exits the interactive manager. |

---

## 🖥️ Screen Layout Preview

```text
=============================================================================================================================
 SCHEDULED TASK MANAGER - KONSOLA ZARZADZANIA ZADANIAMI (WIDOK PELNY)
 AKTYWNE FILTRY: [Status: Enabled] | [Typ: Tylko Uzytkownik / Aplikacje] | [Trigger: All] | [Szukaj: 'nvidia' (Przeszukiwanie calego harmonogramu)]
 Legenda Typow: System (Niebieski) | User (Zielony) | App (Turkusowy) | Znaleziono zadan: 4
=============================================================================================================================
Nr     Status     Typ      Trigger          Nazwa zadania                              Next run           Last run          
=============================================================================================================================
[  1]  Enabled    App      [Daily@12:25]    NvDriverUpdateCheckDaily_{B2FE1952-...}   2026-09-20 12:25   2026-09-19 13:41  
       ↳ Command    : C:\Program Files\NVIDIA Corporation\NvContainer\nvcontainer.exe -d "C:\Program Files\NVIDIA Corporation\NvDriverUpdateCheck"
       ↳ Description: Checks for updated display drivers and software components.
-----------------------------------------------------------------------------------------------------------------------------
[  2]  Enabled    App      [Logon]          NvProfileUpdaterOnLogon_{B2FE1952-...}    -                  2026-09-18 08:51  
       ↳ Command    : C:\Program Files\NVIDIA Corporation\Update Core\NvProfileUpdater64.exe
       ↳ Description: Updates application profiles upon user logon.
-----------------------------------------------------------------------------------------------------------------------------

  Lacznie wyswietlono pozycji: 2 zadan
  =========================================================================================================
AKCJE I DOSTEPNE FILTRY:
  Zarzadzanie zadaniami :
    [1..n]     Wylacz zadanie po ID (np. 1 lub 1, 3, 5)
    [e <id>]   Wlacz zadanie po ID (np. e 3 lub e 1, 4)
  Wyszukiwanie fraza :
    [s <tekst>] Szukaj w nazwie, sciezce i poleceniu (np. 's nvidia', 's office', 's *' aby wyczyscic)
  Filtry przelaczane w locie :
    [m]         Przelacz filtr: Tylko wlasne (User/App) <-> Wszystkie (+Systemowe)
    [f <a|e|d>] Filtr Statusu:  [f a] All | [f e] Enabled (Wlaczone) | [f d] Disabled (Wylaczone)
    [t <mode>]  Filtr Triggera: [t a] All | [t b] Boot | [t l] Logon | [t t] Time | [t e] Event | [t o] OnDemand
  Sterowanie :
    [r] Odswiez liste  |  [q] Wyjdz z programu
```

---

## ⚙️ Parameters Reference

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-Interactive` (`-i`) | `Switch` | `False` | Opens the interactive console menu. |
| `-ListOnly` (`-l`) | `Switch` | `False` | Outputs the filtered task list and exits immediately. |
| `-StateFilter` | `String` | `'Enabled'` | Filters tasks by operational state: `'All'`, `'Enabled'`, or `'Disabled'`. |
| `-TriggerFilter` | `String` | `'All'` | Filters by trigger type: `'All'`, `'Boot'`, `'Logon'`, `'Time'`, `'Event'`, `'Idle'`, `'OnDemand'`. |
| `-ExcludePathPattern` | `String` | `'*Microsoft*'` | Wildcard path exclusion pattern. Set to `''` to include all tasks. |
| `-IncludePathPattern` | `String` | `'*'` | Wildcard path inclusion pattern. |
| `-NamePattern` | `String` | `'*'` | Wildcard task name filter for non-interactive commands. |
| `-Help` (`-h`) | `Switch` | `False` | Displays parameter help and usage examples. |

---

## 👤 Author & License

- **Author**: Roman Pindela
- **Email**: [roman.pindela@gmail.com](mailto:roman.pindela@gmail.com)
- **GitHub**: [https://github.com/romanpindela](https://github.com/romanpindela)
- **License**: MIT License. Open source and free for enterprise or personal use.

### Interactive run - Filtered Tasks
![Help Output](assets/Interactive_run_-_Filtered_Tasks.jpg)

### Interactive run - Filtered Tasks - System Tasks
![Help Output](assets/Interactive_run_-_Filtered_Tasks_-_System_Tasks.jpg)
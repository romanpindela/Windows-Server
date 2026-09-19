# Scheduled Task Manager (PowerShell)

A clean, production-grade PowerShell utility for managing, inspecting, and toggling Windows Scheduled Tasks. Compatible with both Windows client editions (Windows 10/11) and Windows Server environments across English and non-English (e.g., Polish) localized operating systems.

## Features

- **Language-Agnostic Elevation**: Uses the built-in Well-Known SID (`S-1-5-32-544`) to detect local administrators, ensuring seamless compatibility with English (`Administrators`) and Polish (`Administratorzy`) systems.
- **Automatic UAC Elevation**: Automatically re-launches with administrative privileges if executed in a standard console session.
- **Clean Architecture & Input Sanitization**: Rejects arbitrary or malformed input while allowing multiple comma-separated IDs.
- **Flexible Parameterization**: Configure custom path inclusions, path exclusions, and name patterns without hardcoding paths.
- **Safe Fallback**: Executing without parameters prints help and guidance rather than mutating state.

## Version & Author

- **Version**: `1.2.0`
- **Author**: Roman Pindela
- **Email**: [roman.pindela@gmail.com](mailto:roman.pindela@gmail.com)
- **GitHub**: [https://github.com/romanpindela](https://github.com/romanpindela)

---

## Installation & First-Time Run

When downloading PowerShell scripts directly from GitHub, Windows attaches the `Zone.Identifier` alternate data stream (marking the file as blocked from untrusted zones). You must unblock the script prior to execution:

```powershell
Unblock-File -Path ".\Manage-ScheduledTasks.ps1"



Syntax and ParametersPowerShell.\Manage-ScheduledTasks.ps1 [-Interactive | -i] [-ListOnly | -l]
                           [-ExcludePathPattern <string>]
                           [-IncludePathPattern <string>]
                           [-NamePattern <string>]
                           [-Help | -h]
ParametersParameterAliasTypeDefaultDescription-Interactive-iSwitchFalseLaunches the interactive text-based interface.-ListOnly-lSwitchFalseLists tasks and execution metadata, then exits.-ExcludePathPatternString*Microsoft*Wildcard pattern of task folder paths to exclude.-IncludePathPatternString*Wildcard pattern of task folder paths to include.-NamePatternString*Wildcard pattern to match against task names.-Help-hSwitchFalseDisplays the help manual and version details.Examples1. Launch Interactive Management ConsoleFilter out standard Microsoft background jobs and manage third-party services:PowerShell.\Manage-ScheduledTasks.ps1 -Interactive
2. List Tasks Matching a Specific Name PatternInspect any backup-related tasks non-interactively:PowerShell.\Manage-ScheduledTasks.ps1 -ListOnly -NamePattern "*Backup*"
3. Display All Tasks (Including Microsoft System Tasks)Clear exclusions to inspect the complete system schedule:PowerShell.\Manage-ScheduledTasks.ps1 -ListOnly -ExcludePathPattern ""
4. Display Help ScreenPowerShell.\Manage-ScheduledTasks.ps1 -Help
Interactive Console ControlsWhen running in -Interactive mode, the script accepts the following inputs:<ID> or <ID1>, <ID2>: Disables the specified task(s) (e.g., 3 or 1, 4, 7).e <ID>: Re-enables the specified task(s) (e.g., e 3 or e 2, 5).r: Refreshes the task list and status.q: Safely quits the interactive console.
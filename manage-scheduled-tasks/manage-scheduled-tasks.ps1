<#
.SYNOPSIS
    Interactive and automated management tool for Windows Scheduled Tasks.

.DESCRIPTION
    Lists, inspects, and modifies (enables/disables) Windows Scheduled Tasks.
    Supports filtering by path and name, interactive CLI management, and automated batch operations.
    Fully compatible with Windows Desktop (10/11) and Windows Server across Polish and English editions.

.PARAMETER Interactive
    Launches an interactive console menu allowing the operator to selectively disable, enable, and inspect tasks.

.PARAMETER ListOnly
    Lists tasks matching the filter criteria and displays execution metadata without prompting for action.

.PARAMETER ExcludePathPattern
    Wildcard pattern specifying task paths to exclude. Defaults to '*Microsoft*'.

.PARAMETER IncludePathPattern
    Wildcard pattern specifying task paths to include. Defaults to '*'.

.PARAMETER NamePattern
    Wildcard pattern filtering tasks by name. Defaults to '*'.

.PARAMETER Help
    Displays detailed usage instructions, examples, version, and author information.

.EXAMPLE
    .\manage-scheduled-tasks.ps1 -Interactive
    Launches the interactive management console with default exclusions (*Microsoft*).

.EXAMPLE
    .\manage-scheduled-tasks.ps1 -ListOnly -ExcludePathPattern ""
    Lists all scheduled tasks including system tasks.

.EXAMPLE
    .\manage-scheduled-tasks.ps1 -Help
    Displays comprehensive help and metadata.

.NOTES
    Author  : Roman Pindela
    Email   : roman.pindela@gmail.com
    GitHub  : https://github.com/romanpindela
    Version : 1.2.0
#>

[CmdletBinding()]
param (
    [Alias('i')]
    [switch]$Interactive,

    [Alias('l')]
    [switch]$ListOnly,

    [string]$ExcludePathPattern = '*Microsoft*',

    [string]$IncludePathPattern = '*',

    [string]$NamePattern = '*',

    [Alias('h')]
    [switch]$Help
)

# ----------------------------------------------------------------------
# Helper Functions
# ----------------------------------------------------------------------

function Show-ScriptHelp {
    Write-Host @"
================================================================================
 manage-scheduled-tasks.ps1 - Version 1.2.0
 Author  : Roman Pindela (roman.pindela@gmail.com)
 GitHub  : https://github.com/romanpindela
================================================================================

DESCRIPTION:
  Inspects, lists, and toggles Windows Scheduled Tasks with language-agnostic
  elevation checks and safe CLI handling.

SYNTAX & PARAMETERS:
  .\manage-scheduled-tasks.ps1 [-Interactive | -i]
      Runs an interactive CLI console to disable/enable tasks by index.

  .\manage-scheduled-tasks.ps1 [-ListOnly | -l]
      Outputs a formatted table of tasks matching filtering rules and exits.

  .\manage-scheduled-tasks.ps1 [-ExcludePathPattern <string>] [-IncludePathPattern <string>] [-NamePattern <string>]
      Customizes task filtering criteria (default Exclude: '*Microsoft*').

  .\manage-scheduled-tasks.ps1 [-Help | -h]
      Displays this help information.

SECURITY & ELEVATION:
  Modifying scheduled tasks requires administrative privileges. If launched in an
  unelevated shell, the script requests UAC elevation automatically.

EXAMPLES:
  .\manage-scheduled-tasks.ps1 -Interactive
  .\manage-scheduled-tasks.ps1 -ListOnly -NamePattern "*Backup*"
  .\manage-scheduled-tasks.ps1 -Interactive -ExcludePathPattern ""
================================================================================
"@ -ForegroundColor Cyan
}

function Assert-AdministratorPrivileges {
    [CmdletBinding()]
    param()

    # Check if the script is already running with Administrator privileges using SID (language-independent)
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $adminSid = New-Object Security.Principal.SecurityIdentifier([Security.Principal.WellKnownSidType]::BuiltInAdministratorsSid,$null)

    $isAdmin = $principal.IsInRole($adminSid)

    if (-not $isAdmin) {
        # If not running as Admin, prompt for UAC consent and relaunch the script with elevated privileges
        Write-Host "Missing Administrator privileges. Requesting elevation..." -ForegroundColor Yellow
        $boundArgs = @()
        foreach ($key in $PSBoundParameters.Keys) {$val = $PSBoundParameters[$key]
            if ($val -is [switch]) {
                if ($val.IsPresent) { $boundArgs += "-$key" }
            } else {
                $boundArgs += "-$key `"$val`""
            }
        }
        $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" " + ($boundArgs -join ' ')
        Start-Process powershell.exe -ArgumentList $argList -Verb RunAs
        Exit
    }
}

function Get-FilteredTasks {
    [CmdletBinding()]
    param (
        [string]$IncludePath,
        [string]$ExcludePath,
        [string]$TaskNameFilter
    )

    try {
        $tasks = Get-ScheduledTask -ErrorAction Stop | Where-Object {
            $_.TaskPath -like$IncludePath -and
            $_.TaskName -like$TaskNameFilter -and
            ([string]::IsNullOrEmpty($ExcludePath) -or ($_.TaskPath -notlike$ExcludePath))
        }
    } catch {
        Write-Error "Failed to query scheduled tasks: $_"
        return @()
    }

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()$counter = 1

    foreach ($task in$tasks) {
        $info =$null
        try {
            $info =$task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
        } catch {}

        $lastRun = if ($info -and$info.LastRunTime -and $info.LastRunTime.Year -gt 1999) {$info.LastRunTime.ToString("yyyy-MM-dd HH:mm")
        } else {
            "Never"
        }

        $nextRun = if ($info -and$info.NextRunTime -and $info.NextRunTime.Year -gt 1999) {$info.NextRunTime.ToString("yyyy-MM-dd HH:mm")
        } else {
            "None"
        }

        $results.Add([PSCustomObject]@{
            Id          = $counter
            TaskName    = $task.TaskName
            TaskPath    = $task.TaskPath
            State       = $task.State
            LastRunTime = $lastRun
            NextRunTime = $nextRun
            LastResult  = if ($info) {$info.LastTaskResult } else { "N/A" }
        })
        $counter++
    }

    return $results
}

function Start-InteractiveSession {
    [CmdletBinding()]
    param (
        [string]$IncludePath,
        [string]$ExcludePath,
        [string]$TaskNameFilter
    )

    do {
        Clear-Host
        Write-Host "================================================================================" -ForegroundColor Cyan
        Write-Host " SCHEDULED TASK MANAGER - INTERACTIVE CONSOLE" -ForegroundColor Cyan
        Write-Host " Filter: Exclude='$ExcludePath', Include='$IncludePath', Name='$TaskNameFilter'" -ForegroundColor DarkGray
        Write-Host "================================================================================" -ForegroundColor Cyan

        $taskList = Get-FilteredTasks -IncludePath$IncludePath -ExcludePath $ExcludePath -TaskNameFilter$TaskNameFilter

        if ($taskList.Count -eq 0) {
            Write-Host "No tasks matched the current filtering criteria." -ForegroundColor Yellow
        } else {
            $taskList | Select-Object Id, State, TaskName, LastRunTime, NextRunTime, LastResult | Format-Table -AutoSize
        }

        Write-Host "`nActions:" -ForegroundColor Yellow
        Write-Host "  [1..n]     Disable task by ID (supports lists, e.g. '1, 3, 5')"
        Write-Host "  [e <id>]   Enable task by ID (e.g. 'e 3' or 'e 1, 4')"
        Write-Host "  [r]        Refresh task list"
        Write-Host "  [q]        Quit application"

        $rawInput = (Read-Host "`nEnter command").Trim()

        if ([string]::IsNullOrWhiteSpace($rawInput) -or$rawInput -ieq 'r') {
            continue
        }

        if ($rawInput -ieq 'q') {
            break
        }

        # Handle ENABLE command: "e 1, 2"
        if ($rawInput -match '^(?i:e)\s+(.+)$') {$targetIds = $matches[1] -split '[,;\s]+' \vert{} Where-Object {$_ -match '^\d+$' } \vert{} ForEach-Object { [int]$_ }

            if ($targetIds.Count -eq 0) {
                Write-Host "Invalid identifier(s). Please enter numeric IDs." -ForegroundColor Red
                Start-Sleep -Seconds 2
                continue
            }

            foreach ($id in$targetIds) {
                $target =$taskList | Where-Object { $_.Id -eq$id }
                if ($null -ne$target) {
                    try {
                        Enable-ScheduledTask -TaskName $target.TaskName -TaskPath$target.TaskPath -ErrorAction Stop | Out-Null
                        Write-Host "Enabled: [$($target.Id)] $($target.TaskName)" -ForegroundColor Green
                    } catch {
                        Write-Host "Error enabling task [$($target.TaskName)]:$_" -ForegroundColor Red
                    }
                } else {
                    Write-Host "ID '$id' not found in active list." -ForegroundColor DarkYellow
                }
            }
            Start-Sleep -Seconds 2
            continue
        }

        # Handle DISABLE command: "1, 2, 3"
        $tokens =$rawInput -split '[,;\s]+'
        $invalidTokens =$tokens | Where-Object { $_ -notmatch '^\d+$' }

        if ($invalidTokens.Count -gt 0) {
            Write-Host "Unrecognized input detected: $($invalidTokens -join ', '). Enter numbers, 'e <id>', 'r', or 'q'." -ForegroundColor Red
            Start-Sleep -Seconds 2
            continue
        }

        $targetIds = $tokens \vert{} ForEach-Object { [int]$_ }

        foreach ($id in$targetIds) {
            $target =$taskList | Where-Object { $_.Id -eq$id }
            if ($null -ne$target) {
                try {
                    Disable-ScheduledTask -TaskName $target.TaskName -TaskPath$target.TaskPath -ErrorAction Stop | Out-Null
                    Write-Host "Disabled: [$($target.Id)] $($target.TaskName)" -ForegroundColor Green
                } catch {
                    Write-Host "Error disabling task [$($target.TaskName)]:$_" -ForegroundColor Red
                }
            } else {
                Write-Host "ID '$id' not found in active list." -ForegroundColor DarkYellow
            }
        }

        Start-Sleep -Seconds 2

    } while ($true)

    Clear-Host
    Write-Host "Task manager session terminated." -ForegroundColor Cyan
}

# ----------------------------------------------------------------------
# Main Execution Controller
# ----------------------------------------------------------------------

# Ensure UTF-8 output rendering
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Display help and safe exit if invoked with -Help, -h, or without parameters
if ($Help -or ($PSBoundParameters.Count -eq 0)) {
    Show-ScriptHelp
    Exit 0
}

# Enforce Administrator privileges for operational commands
Assert-AdministratorPrivileges

if ($ListOnly) {
    $tasks = Get-FilteredTasks -IncludePath$IncludePathPattern -ExcludePath $ExcludePathPattern -TaskNameFilter$NamePattern
    if ($tasks.Count -gt 0) {$tasks | Select-Object Id, State, TaskName, TaskPath, LastRunTime, NextRunTime, LastResult | Format-Table -AutoSize
    } else {
        Write-Host "No tasks matched the criteria." -ForegroundColor Yellow
    }
    Exit 0
}

if ($Interactive) {
    Start-InteractiveSession -IncludePath $IncludePathPattern -ExcludePath $ExcludePathPattern -TaskNameFilter$NamePattern
    Exit 0
}
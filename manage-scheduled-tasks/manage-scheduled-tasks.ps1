<#
.SYNOPSIS
    Interactive and automated management tool for Windows Scheduled Tasks.
.DESCRIPTION
    Lists, inspects, and modifies (enables/disables) Windows Scheduled Tasks.
    Supports filtering by path and name, interactive CLI management, and automated operations.
    Compatible with Windows Desktop (10/11) and Windows Server across Polish and English editions.
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
);

function Show-ScriptHelp {
    Write-Host "================================================================================" -ForegroundColor Cyan;
    Write-Host " manage-scheduled-tasks.ps1 - Version 1.2.0" -ForegroundColor Cyan;
    Write-Host " Author  : Roman Pindela (roman.pindela@gmail.com)" -ForegroundColor Cyan;
    Write-Host " GitHub  : https://github.com/romanpindela" -ForegroundColor Cyan;
    Write-Host "================================================================================" -ForegroundColor Cyan;
    Write-Host "";
    Write-Host "DESCRIPTION:";
    Write-Host "  Inspects, lists, and toggles Windows Scheduled Tasks with language-agnostic";
    Write-Host "  elevation checks and safe CLI handling.";
    Write-Host "";
    Write-Host "SYNTAX & PARAMETERS:";
    Write-Host "  .\manage-scheduled-tasks.ps1 -Interactive";
    Write-Host "      Runs an interactive CLI console to disable/enable tasks by index.";
    Write-Host "";
    Write-Host "  .\manage-scheduled-tasks.ps1 -ListOnly";
    Write-Host "      Outputs a formatted table of tasks matching filtering rules and exits.";
    Write-Host "";
    Write-Host "  .\manage-scheduled-tasks.ps1 -ExcludePathPattern <string> -IncludePathPattern <string> -NamePattern <string>";
    Write-Host "      Customizes task filtering criteria (default Exclude: '*Microsoft*').";
    Write-Host "";
    Write-Host "  .\manage-scheduled-tasks.ps1 -Help";
    Write-Host "      Displays this help information.";
    Write-Host "";
    Write-Host "EXAMPLES:";
    Write-Host "  .\manage-scheduled-tasks.ps1 -Interactive";
    Write-Host "  .\manage-scheduled-tasks.ps1 -ListOnly -NamePattern '*Backup*'";
    Write-Host "  .\manage-scheduled-tasks.ps1 -Interactive -ExcludePathPattern ''";
    Write-Host "================================================================================" -ForegroundColor Cyan;
};

function Assert-AdministratorPrivileges {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent();
    $principal = New-Object Security.Principal.WindowsPrincipal($identity);
    $adminSid = New-Object Security.Principal.SecurityIdentifier([Security.Principal.WellKnownSidType]::BuiltInAdministratorsSid,$null);

    $isAdmin = $principal.IsInRole($adminSid);

    if (-not $isAdmin) {
        Write-Host "Missing Administrator privileges. Requesting elevation..." -ForegroundColor Yellow;
        $boundArgs = @();
        $keys = @($PSBoundParameters.Keys);
        for ($i = 0; $i -lt $keys.Count; $i++) {
            $k =$keys[$i];$val = $PSBoundParameters[$k];
            if ($val -is [switch]) {
                if ($val.IsPresent) { $boundArgs += "-$k"; };
            } else {
                $boundArgs += "-$k `"$val`"";
            };
        };
        $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" " + ($boundArgs -join ' ');
        Start-Process powershell.exe -ArgumentList $argList -Verb RunAs;
        Exit;
    };
};


function Get-FilteredTasks {
    param (
        [string]$IncludePath,
        [string]$ExcludePath,
        [string]$TaskNameFilter
    );

    if ([string]::IsNullOrWhiteSpace($TaskNameFilter)) { $TaskNameFilter = '*' };
    if ([string]::IsNullOrWhiteSpace($IncludePath)) { $IncludePath = '*' };

    try {
        $raw = Get-ScheduledTask -ErrorAction Stop | Where-Object {
            $_.TaskPath -like$IncludePath -and
            $_.TaskName -like$TaskNameFilter -and
            ([string]::IsNullOrEmpty($ExcludePath) -or ($_.TaskPath -notlike$ExcludePath))
        };
    } catch {
        Write-Error "Failed to query scheduled tasks: $_";
        return @();
    };

    $tasks = @($raw);$results = New-Object System.Collections.Generic.List[PSCustomObject];

    for ($i = 0; $i -lt$tasks.Count; $i++) {$task = $tasks[$i];
        $info =$null;
        try {
            $info =$task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue;
        } catch {};

        $lastRun = "Never";
        if ($info -and $info.LastRunTime -and$info.LastRunTime.Year -gt 1999) {
            $lastRun =$info.LastRunTime.ToString("yyyy-MM-dd HH:mm");
        };

        $nextRun = "None";
        if ($info -and $info.NextRunTime -and$info.NextRunTime.Year -gt 1999) {
            $nextRun =$info.NextRunTime.ToString("yyyy-MM-dd HH:mm");
        };

        $lastRes = "N/A";
        if ($info) {
            $lastRes =$info.LastTaskResult;
        };

        $item = [PSCustomObject]@{
            Id          = ($i + 1);
            TaskName    = $task.TaskName;
            TaskPath    = $task.TaskPath;
            State       = $task.State;
            LastRunTime = $lastRun;
            NextRunTime = $nextRun;
            LastResult  = $lastRes;
        };

        $results.Add($item);
    };

    return $results;
};

function Start-InteractiveSession {
    param (
        [string]$IncludePath,
        [string]$ExcludePath,
        [string]$TaskNameFilter
    );

    while ($true) {
        Clear-Host;
        Write-Host "================================================================================" -ForegroundColor Cyan;
        Write-Host " SCHEDULED TASK MANAGER - INTERACTIVE CONSOLE" -ForegroundColor Cyan;
        Write-Host " Filter: Exclude='$ExcludePath', Include='$IncludePath', Name='$TaskNameFilter'" -ForegroundColor DarkGray;
        Write-Host "================================================================================" -ForegroundColor Cyan;

        $taskList = Get-FilteredTasks -IncludePath$IncludePath -ExcludePath $ExcludePath -TaskNameFilter$TaskNameFilter;

        if ($taskList.Count -eq 0) {
            Write-Host "No tasks matched the current filtering criteria." -ForegroundColor Yellow;
        } else {
            $taskList | Select-Object Id, State, TaskName, LastRunTime, NextRunTime, LastResult | Format-Table -AutoSize;
        };

        Write-Host "";
        Write-Host "Actions:" -ForegroundColor Yellow;
        Write-Host "  [1..n]     Disable task by ID (supports lists: 1 or 1, 3, 5)";
        Write-Host "  [e <id>]   Enable task by ID (e.g. e 3 or e 1, 4)";
        Write-Host "  [r]        Refresh task list";
        Write-Host "  [q]        Quit application";
        Write-Host "";

        $rawInput = Read-Host "Enter command";
        if ($null -ne$rawInput) {
            $rawInput =$rawInput.Trim();
        };

        if ([string]::IsNullOrWhiteSpace($rawInput) -or$rawInput -ieq 'r') {
            continue;
        };

        if ($rawInput -ieq 'q') {
            break;
        };

        if ($rawInput -match '^(?i:e)\s+(.+)$') {
            $subStr =$matches[1];
            $tokens = @($subStr -split '[,;\s]+' | Where-Object { $_ -match '^\d+$' });

            if ($tokens.Count -eq 0) {
                Write-Host "Invalid identifier(s). Please enter numeric IDs." -ForegroundColor Red;
                Start-Sleep -Seconds 2;
                continue;
            };

            for ($j = 0; $j -lt$tokens.Count; $j++) {$id = [int]$tokens[$j];
                $target =$null;
                for ($k = 0; $k -lt $taskList.Count; $k++) {
                    if ($taskList[$k].Id -eq $id) {$target = $taskList[$k];
                        break;
                    };
                };

                if ($target) {
                    try {
                        Enable-ScheduledTask -TaskName $target.TaskName -TaskPath$target.TaskPath -ErrorAction Stop | Out-Null;
                        Write-Host "Enabled: [$($target.Id)] $($target.TaskName)" -ForegroundColor Green;
                    } catch {
                        Write-Host "Error enabling task [$($target.TaskName)]:$_" -ForegroundColor Red;
                    };
                } else {
                    Write-Host "ID '$id' not found in active list." -ForegroundColor DarkYellow;
                };
            };
            Start-Sleep -Seconds 2;
            continue;
        };

        $allTokens = @($rawInput -split '[,;\s]+');
        $invalidTokens = @($allTokens | Where-Object { $_ -notmatch '^\d+$' });

        if ($invalidTokens.Count -gt 0) {
            $joinedErr =$invalidTokens -join ', ';
            Write-Host "Unrecognized input: $joinedErr. Enter numbers, 'e <id>', 'r', or 'q'." -ForegroundColor Red;
            Start-Sleep -Seconds 2;
            continue;
        };

        for ($j = 0; $j -lt$allTokens.Count; $j++) {$id = [int]$allTokens[$j];
            $target =$null;
            for ($k = 0; $k -lt $taskList.Count; $k++) {
                if ($taskList[$k].Id -eq $id) {$target = $taskList[$k];
                    break;
                };
            };

            if ($target) {
                try {
                    Disable-ScheduledTask -TaskName $target.TaskName -TaskPath $target.TaskPath -ErrorAction Stop | Out-Null;
                    Write-Host "Disabled: [$($target.Id)] $($target.TaskName)" -ForegroundColor Green;
                } catch {
                    Write-Host "Error disabling task [$($target.TaskName)]:$_" -ForegroundColor Red;
                };
            } else {
                Write-Host "ID '$id' not found in active list." -ForegroundColor DarkYellow;
            };
        };
        Start-Sleep -Seconds 2;
    };

    Clear-Host;
    Write-Host "Task manager session terminated." -ForegroundColor Cyan;
};

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8;

if ($Help -or ($PSBoundParameters.Count -eq 0)) {
    Show-ScriptHelp;
    Exit 0;
};

Assert-AdministratorPrivileges;

if ($ListOnly) {
    $tasks = Get-FilteredTasks -IncludePath$IncludePathPattern -ExcludePath $ExcludePathPattern -TaskNameFilter$NamePattern;
    if ($tasks.Count -gt 0) {$tasks | Select-Object Id, State, TaskName, TaskPath, LastRunTime, NextRunTime, LastResult | Format-Table -AutoSize;
    } else {
        Write-Host "No tasks matched the criteria." -ForegroundColor Yellow;
    };
    Exit 0;
};

if ($Interactive) {
    Start-InteractiveSession -IncludePath $IncludePathPattern -ExcludePath $ExcludePathPattern -TaskNameFilter$NamePattern;
    Exit 0;
};
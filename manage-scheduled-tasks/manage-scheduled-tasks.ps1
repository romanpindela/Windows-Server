<#
.SYNOPSIS
    Interactive and automated management tool for Windows Scheduled Tasks.
.DESCRIPTION
    Lists, inspects, and modifies (enables/disables) Windows Scheduled Tasks.
    Formatted with a structured multi-line view:
      Line 1: Task ID, State, Task Name, Next Run, Last Run
      Line 2: Full Detailed Command (gray)
      Line 3: Task Description (dark cyan / olive)
      Line 4: Separator line
    Sorts tasks by Next Run ascending, with Disabled/unscheduled tasks at the bottom.
.PARAMETER Interactive
    Launches an interactive console menu.
.PARAMETER ListOnly
    Lists matching scheduled tasks and exits.
.PARAMETER StateFilter
    Filters tasks by status ('All', 'Enabled', 'Disabled'). Defaults to 'All'.
.PARAMETER ExcludePathPattern
    Wildcard pattern of task folder paths to exclude. Defaults to '*Microsoft*'.
.PARAMETER IncludePathPattern
    Wildcard pattern of task folder paths to include. Defaults to '*'.
.PARAMETER NamePattern
    Wildcard pattern to match against task names. Defaults to '*'.
.PARAMETER Help
    Displays this help menu.
.NOTES
    Author  : Roman Pindela
    Email   : roman.pindela@gmail.com
    GitHub  : https://github.com/romanpindela
    Version : 1.7.0
#>
[CmdletBinding()]
param (
    [Alias('i')]
    [switch]$Interactive,

    [Alias('l')]
    [switch]$ListOnly,

    [ValidateSet('All', 'Enabled', 'Disabled')]
    [string]$StateFilter = 'All',

    [string]$ExcludePathPattern = '*Microsoft*',
    [string]$IncludePathPattern = '*',
    [string]$NamePattern = '*',

    [Alias('h')]
    [switch]$Help
);

function Show-ScriptHelp {
    Write-Host "================================================================================" -ForegroundColor Cyan;
    Write-Host " manage-scheduled-tasks.ps1 - Version 1.7.0" -ForegroundColor Cyan;
    Write-Host " Author  : Roman Pindela (roman.pindela@gmail.com)" -ForegroundColor Cyan;
    Write-Host " GitHub  : https://github.com/romanpindela" -ForegroundColor Cyan;
    Write-Host "================================================================================" -ForegroundColor Cyan;
    Write-Host "";
    Write-Host "DESCRIPTION:";
    Write-Host "  Inspects, lists, and toggles Windows Scheduled Tasks with language-agnostic";
    Write-Host "  elevation checks, chronological sorting, command inspection, and description lines.";
    Write-Host "";
    Write-Host "SYNTAX & PARAMETERS:";
    Write-Host "  .\manage-scheduled-tasks.ps1 -Interactive";
    Write-Host "      Runs an interactive CLI console to disable/enable and filter tasks.";
    Write-Host "";
    Write-Host "  .\manage-scheduled-tasks.ps1 -ListOnly [-StateFilter <All|Enabled|Disabled>]";
    Write-Host "      Outputs tasks matching filtering rules and exits.";
    Write-Host "";
    Write-Host "  .\manage-scheduled-tasks.ps1 -Help";
    Write-Host "      Displays this help information.";
    Write-Host "";
    Write-Host "EXAMPLES:";
    Write-Host "  .\manage-scheduled-tasks.ps1 -Interactive";
    Write-Host "  .\manage-scheduled-tasks.ps1 -ListOnly -StateFilter Disabled";
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
        [string]$TaskNameFilter,
        [string]$CurrentStateFilter
    );

    if ([string]::IsNullOrWhiteSpace($TaskNameFilter)) {$TaskNameFilter = '*' };
    if ([string]::IsNullOrWhiteSpace($IncludePath)) {$IncludePath = '*' };
    if ([string]::IsNullOrWhiteSpace($CurrentStateFilter)) {$CurrentStateFilter = 'All' };

    try {
        $raw = Get-ScheduledTask -ErrorAction Stop | Where-Object {
            $_.TaskPath -like$IncludePath -and
            $_.TaskName -like$TaskNameFilter -and
            ([string]::IsNullOrEmpty($ExcludePath) -or ($_.TaskPath -notlike$ExcludePath)) -and
            ($CurrentStateFilter -ieq 'All' -or $_.State.ToString() -ieq$CurrentStateFilter)
        };
    } catch {
        Write-Error "Failed to query scheduled tasks: $_";
        return @();
    };

    $rawList = @($raw);$tempList = New-Object System.Collections.Generic.List[PSCustomObject];

    for ($i = 0; $i -lt$rawList.Count; $i++) {$task = $rawList[$i];
        $info =$null;
        try {
            $info =$task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue;
        } catch {};

        # Daty wykonania i surowa data do sortowania
        $rawNextDate = [DateTime]::MaxValue;
        $nextRun = "-";

        if ($task.State -eq 'Disabled') {$nextRun = "Disabled";
            $rawNextDate = [DateTime]::MaxValue;
        } elseif ($info -and $info.NextRunTime -and$info.NextRunTime.Year -gt 1999) {
            $nextRun =$info.NextRunTime.ToString("yyyy-MM-dd HH:mm");
            $rawNextDate =$info.NextRunTime;
        };

        $lastRun = "-";
        if ($info -and $info.LastRunTime -and$info.LastRunTime.Year -gt 1999) {
            $lastRun =$info.LastRunTime.ToString("yyyy-MM-dd HH:mm");
        };

        # Pobieranie pelnego polecenia
        $actionSummary = @();
        if ($task.Actions -and$task.Actions.Count -gt 0) {
            for ($a = 0; $a -lt$task.Actions.Count; $a++) {$act = $task.Actions[$a];
                if ($act.Execute) {
                    $rawExe =$act.Execute;
                    $args = if ($act.Arguments) { " $($act.Arguments.Trim())" } else { "" };
                    $actionSummary += "$rawExe$args";
                } elseif ($act.ClassId) {$actionSummary += "COM: $($act.ClassId)";
                } else {
                    $actionSummary += "CustomAction";
                };
            };
        };
        $actionDisplay = if ($actionSummary.Count -gt 0) {$actionSummary -join ' | ' } else { "(Brak zdefiniowanego polecenia)" };

        # Pobieranie opisu zadania
        $desc = "-";
        if (-not [string]::IsNullOrWhiteSpace($task.Description)) {
            $desc = ($task.Description -replace "[\r\n]+", " ").Trim();
        };

        $tempList.Add([PSCustomObject]@{
            State        = $task.State.ToString();
            TaskName     = $task.TaskName;
            NextRun      = $nextRun;
            LastRun      = $lastRun;
            RawNextDate  = $rawNextDate;
            Command      = $actionDisplay;
            Description  = $desc;
            TaskPath     = $task.TaskPath;
            FullTaskName = $task.TaskName;
        });
    };

    # Sortowanie: 1) Aktywne wg daty uruchomienia, 2) Zadania bez daty / Disabled na koncu
    $sorted =$tempList | Sort-Object -Property @{
        Expression = { if ($_.State -ieq 'Disabled') { 1 } else { 0 } }
    }, @{
        Expression = { $_.RawNextDate }
    }, @{
        Expression = { $_.TaskName }
    };

    $finalList = New-Object System.Collections.Generic.List[PSCustomObject];$counter = 1;
    foreach ($item in $sorted) {$item | Add-Member -MemberType NoteProperty -Name "Id" -Value $counter -Force;
        $finalList.Add($item);$counter++;
    };

    return $finalList;
};

function Render-TwoLineTable {
    param (
        [System.Collections.Generic.List[PSCustomObject]]$TaskList
    );

    if ($TaskList.Count -eq 0) {
        Write-Host "No tasks matched the current filtering criteria." -ForegroundColor Yellow;
        return;
    };

    # Naglowek tabeli
    Write-Host ("{0,-6} {1,-10} {2,-50} {3,-18} {4,-18}" -f "Nr", "Status", "Nazwa zadania", "Next Run", "Last Run") -ForegroundColor DarkGray;
    Write-Host ("=" * 115) -ForegroundColor DarkGray;

    # Sekwencje ANSI VT100
    $esc = [char]27;
    $cReset   = "$esc[0m";
    $cCyan    = "$esc[36;1m";
    $cYellow  = "$esc[33;1m";
    $cDarkYel = "$esc[33m";
    $cGray    = "$esc[37m";
    $cDarkGry = "$esc[90m";
    $cDarkCyn = "$esc[36m";

    for ($i = 0; $i -lt$TaskList.Count; $i++) {$t = $TaskList[$i];

        # Kolor daty NextRun
        $colNext =$cGray;
        if ($t.NextRun -ieq 'Disabled') {
            $colNext =$cDarkYel;
        } elseif ($t.NextRun -ne '-') {
            $colNext =$cYellow;
        };

        $nrStr    = ("[{0,3}]" -f $t.Id).PadRight(6);
        $stateStr = ($t.State).PadRight(10);
        $nameStr  = ($t.TaskName).PadRight(50);
        $nextStr  = ($t.NextRun).PadRight(18);
        $lastStr  = ($t.LastRun).PadRight(18);

        # WIERSZ 1: Nr, Status, Nazwa zadania (Cyan) | Next Run (Zolty/Ciemnozolty) | Last Run (Ciemnoszary)
        Write-Host "${cCyan}${nrStr}${stateStr} ${nameStr}${cReset} ${colNext}${nextStr}${cReset}${cDarkGry}${lastStr}${cReset}";

        # WIERSZ 2: Polecenie szczegolowe (jasnoszary)
        Write-Host "       ↳ Cmd : ${cGray}$($t.Command)${cReset}";

        # WIERSZ 3: Opis zadania (ciemny turkus / dark cyan)
        Write-Host "       ↳ Desc: ${cDarkCyn}$($t.Description)${cReset}";

        # WIERSZ 4: Linia podzialu miedzy zadaniami
        Write-Host ("-" * 115) -ForegroundColor DarkGray;
    };
};

function Start-InteractiveSession {
    param (
        [string]$IncludePath,
        [string]$ExcludePath,
        [string]$TaskNameFilter,
        [string]$InitialStateFilter
    );

    $currentState = if ([string]::IsNullOrWhiteSpace($InitialStateFilter)) { 'All' } else {$InitialStateFilter };

    while ($true) {
        Clear-Host;
        Write-Host "==========================================================================================================" -ForegroundColor Cyan;
        Write-Host " SCHEDULED TASK MANAGER - INTERACTIVE CONSOLE" -ForegroundColor Cyan;
        Write-Host " Filter: State='$currentState', Exclude='$ExcludePath', Include='$IncludePath', Name='$TaskNameFilter'" -ForegroundColor DarkGray;
        Write-Host "==========================================================================================================" -ForegroundColor Cyan;

        $taskList = Get-FilteredTasks -IncludePath $IncludePath -ExcludePath$ExcludePath -TaskNameFilter $TaskNameFilter -CurrentStateFilter$currentState;

        Render-TwoLineTable -TaskList $taskList;

        Write-Host "";
        Write-Host "Actions:" -ForegroundColor Yellow;
        Write-Host "  [1..n]     Disable task by ID (supports lists: 1 or 1, 3, 5)";
        Write-Host "  [e <id>]   Enable task by ID (e.g. e 3 or e 1, 4)";
        Write-Host "  [f <a|e|d>] Filter State: [f a] All | [f e] Enabled | [f d] Disabled";
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

        if ($rawInput -match '^(?i:f)\s+([aedAED])$') {
            $flag =$matches[1].ToLower();
            if ($flag -eq 'a') {$currentState = 'All'; };
            if ($flag -eq 'e') {$currentState = 'Enabled'; };
            if ($flag -eq 'd') {$currentState = 'Disabled'; };
            continue;
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
                        Enable-ScheduledTask -TaskName $target.FullTaskName -TaskPath$target.TaskPath -ErrorAction Stop | Out-Null;
                        Write-Host "Enabled: [$($target.Id)] $($target.FullTaskName)" -ForegroundColor Green;
                    } catch {
                        Write-Host "Error enabling task [$($target.FullTaskName)]:$_" -ForegroundColor Red;
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
            Write-Host "Unrecognized input: $joinedErr. Enter numbers, 'e <id>', 'f <a|e|d>', 'r', or 'q'." -ForegroundColor Red;
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
                    Disable-ScheduledTask -TaskName $target.FullTaskName -TaskPath$target.TaskPath -ErrorAction Stop | Out-Null;
                    Write-Host "Disabled: [$($target.Id)] $($target.FullTaskName)" -ForegroundColor Green;
                } catch {
                    Write-Host "Error disabling task [$($target.FullTaskName)]:$_" -ForegroundColor Red;
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

if ($ListOnly) {$tasks = Get-FilteredTasks -IncludePath $IncludePathPattern -ExcludePath$ExcludePathPattern -TaskNameFilter $NamePattern -CurrentStateFilter$StateFilter;
    Render-TwoLineTable -TaskList $tasks;
    Exit 0;
};

if ($Interactive) {
    Start-InteractiveSession -IncludePath $IncludePathPattern -ExcludePath$ExcludePathPattern -TaskNameFilter $NamePattern -InitialStateFilter$StateFilter;
    Exit 0;
};
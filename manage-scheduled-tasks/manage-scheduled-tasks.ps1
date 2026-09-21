<#
.SYNOPSIS
    Interactive and automated management tool for Windows Scheduled Tasks.
.DESCRIPTION
    Lists, inspects, and modifies (enables/disables) Windows Scheduled Tasks.
    Formatted with a structured multi-line view:
      Line 1: Nr | Status | Typ | Trigger | Nazwa zadania | Next run | Last run
      Line 2: Command
      Line 3: Description
      Line 4: Separator
    Features:
      - Splatting-based parameter passing (immune to whitespace/token concatenation bugs)
      - Direct substring search [s <fraza>] across TaskName, TaskPath, and Command
      - Auto-bypass of path exclusion when actively searching
      - Full-list display (no pagination cutoff)
      - Detailed trigger parser (Daily@HH:mm, Weekly, Boot, Logon, Event, Idle, OnDemand)
      - Chronological sorting by Next Run ascending (Disabled at bottom)
      - Interactive toggling of Microsoft system tasks [m]
      - State filtering: [f a] All | [f e] Enabled | [f d] Disabled
      - Trigger filtering: [t a] All | [t b] Boot | [t l] Logon | [t t] Time | [t e] Event | [t o] OnDemand
      - Pure ANSI VT100 color formatting
.PARAMETER Interactive
    Launches an interactive console menu with search and live filtering.
.PARAMETER ListOnly
    Lists matching scheduled tasks and exits.
.PARAMETER StateFilter
    Filters tasks by status ('All', 'Enabled', 'Disabled'). Defaults to 'Enabled'.
.PARAMETER TriggerFilter
    Filters tasks by trigger type ('All', 'Boot', 'Logon', 'Time', 'Event', 'Idle', 'OnDemand'). Defaults to 'All'.
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
    Version : 2.7.1
#>
[CmdletBinding()]
param (
    [Alias('i')]
    [switch]$Interactive,

    [Alias('l')]
    [switch]$ListOnly,

    [ValidateSet('All', 'Enabled', 'Disabled')]
    [string]$StateFilter = 'Enabled',

    [ValidateSet('All', 'Boot', 'Logon', 'Time', 'Event', 'Idle', 'OnDemand')]
    [string]$TriggerFilter = 'All',

    [string]$ExcludePathPattern = '*Microsoft*',
    [string]$IncludePathPattern = '*',
    [string]$NamePattern = '*',

    [Alias('h')]
    [switch]$Help
);

function Show-ScriptHelp {
    Write-Host "================================================================================" -ForegroundColor Cyan;
    Write-Host " manage-scheduled-tasks.ps1 - Version 2.7.1" -ForegroundColor Cyan;
    Write-Host " Author  : Roman Pindela (roman.pindela@gmail.com)" -ForegroundColor Cyan;
    Write-Host " GitHub  : https://github.com/romanpindela" -ForegroundColor Cyan;
    Write-Host "================================================================================" -ForegroundColor Cyan;
    Write-Host "";
    Write-Host "OPIS:";
    Write-Host "  Zarzadzanie zadaniami harmonogramu Windows Task Scheduler z podzialem na typy";
    Write-Host "  (System / User / App), filtrowaniem wyzwalaczy, bezposrednim wyszukiwaniem fraza i widokiem pelnej listy.";
    Write-Host "";
    Write-Host "SKLADNIA & PARAMETRY:";
    Write-Host "  .\manage-scheduled-tasks.ps1 -Interactive";
    Write-Host "      Uruchamia interaktywna konsole CLI.";
    Write-Host "";
    Write-Host "  .\manage-scheduled-tasks.ps1 -ListOnly [-StateFilter <All|Enabled|Disabled>] [-NamePattern '*fraza*']";
    Write-Host "      Wypisuje przefiltrowane zadania do konsoli i konczy dzialanie.";
    Write-Host "";
    Write-Host "  .\manage-scheduled-tasks.ps1 -Help";
    Write-Host "      Wyswietla te pomoc.";
    Write-Host "================================================================================" -ForegroundColor Cyan;
};

function Assert-AdministratorPrivileges {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent();
    $principal = New-Object Security.Principal.WindowsPrincipal($identity);
    $adminSid = New-Object Security.Principal.SecurityIdentifier([Security.Principal.WellKnownSidType]::BuiltInAdministratorsSid, $null);

    $isAdmin = $principal.IsInRole($adminSid);

    if (-not $isAdmin) {
        Write-Host "Brak uprawnien administratora. Ponowne uruchamianie z podniesionymi uprawnieniami..." -ForegroundColor Yellow;
        $boundArgs = @();
        $keys = @($PSBoundParameters.Keys);
        for ($i = 0; $i -lt $keys.Count; $i++) {
            $k = $keys[$i];
            $val = $PSBoundParameters[$k];
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

function Get-DetailedTriggerSummary {
    param ($Triggers)

    if (-not $Triggers -or$Triggers.Count -eq 0) {
        return "OnDemand";
    };

    $summaries = New-Object System.Collections.Generic.List[string];

    for ($i = 0; $i -lt $Triggers.Count; $i++) {
        $trig =$Triggers[$i];$rawType = "";
        if ($trig.CimClass -and$trig.CimClass.CimClassName) {
            $rawType =$trig.CimClass.CimClassName;
        } elseif ($trig.PSObject -and$trig.PSObject.TypeNames) {
            $rawType = ($trig.PSObject.TypeNames -join " ");
        } else {
            $rawType =$trig.ToString();
        };

        $timeStr = "";
        if ($trig.StartBoundary) {
            try {
                $parsedDate = [DateTime]::Parse($trig.StartBoundary);
                $timeStr = "@" + $parsedDate.ToString("HH:mm");
            } catch {};
        };

        if ($rawType -match 'Boot') {$summaries.Add("Boot");
        } elseif ($rawType -match 'Logon') {$summaries.Add("Logon");
        } elseif ($rawType -match 'Daily') {
            $summaries.Add("Daily$timeStr");
        } elseif ($rawType -match 'Weekly') {$days = "";
            if ($trig.DaysOfWeek) {$days = "($($trig.DaysOfWeek))"; };
            $summaries.Add("Weekly$days$timeStr");
        } elseif ($rawType -match 'Monthly') {
            $summaries.Add("Monthly$timeStr");
        } elseif ($rawType -match 'Time|Once') {
            $summaries.Add("Once$timeStr");
        } elseif ($rawType -match 'Event') {$summaries.Add("Event");
        } elseif ($rawType -match 'Idle') {$summaries.Add("Idle");
        } elseif ($rawType -match 'Session') {$summaries.Add("Session");
        } else {
            if ($timeStr) {
                $summaries.Add("Time$timeStr");
            } else {
                $summaries.Add("Custom");
            };
        };
    };

    if ($summaries.Count -eq 0) {
        return "OnDemand";
    };

    $unique = @($summaries | Select-Object -Unique);
    return ($unique -join ",");
};

function Test-TriggerMatch {
    param (
        [string]$TriggerSummary,
        [string]$SelectedFilter
    );

    if ([string]::IsNullOrWhiteSpace($SelectedFilter) -or$SelectedFilter -ieq 'All') {
        return $true;
    };

    if ($SelectedFilter -ieq 'Time') {
        return ($TriggerSummary -match '(Time|Daily|Weekly|Monthly|Once)');
    };

    if ($SelectedFilter -ieq 'OnDemand' -or$SelectedFilter -ieq 'Manual') {
        return ($TriggerSummary -match '(OnDemand|Manual)');
    };

    return ($TriggerSummary -like "*$SelectedFilter*");
};

function Get-FilteredTasks {
    [CmdletBinding()]
    param (
        [string]$IncludePath = '*',
        [string]$ExcludePath = '',
        [string]$SearchQuery = '',
        [string]$CurrentStateFilter = 'All',
        [string]$CurrentTriggerFilter = 'All'
    );

    $term = if ($SearchQuery) {$SearchQuery.Trim().Trim('*') } else { "" };

    try {
        $allTasks = @(Get-ScheduledTask -ErrorAction Stop);
    } catch {
        Write-Error "Blad odpytywania harmonogramu zadan: $_";
        return @();
    };

    $tempList = New-Object System.Collections.Generic.List[PSCustomObject];

    for ($idx = 0; $idx -lt$allTasks.Count; $idx++) {$task = $allTasks[$idx];

        # 1. Sprawdzenie sciezki Include
        if ($IncludePath -ne '*' -and $task.TaskPath -notlike$IncludePath) {
            continue;
        };

        # 2. Pobranie pelnego polecenia
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
        $actionDisplay = if ($actionSummary.Count -gt 0) {$actionSummary -join ' | ' } else { "(Brak polecenia)" };

        # 3. FILTR WYSZUKIWANIA FRAZY (SearchQuery):
        if ($term -ne '') {
            $inName = ($task.TaskName -and ($task.TaskName.IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0));
            $inPath = ($task.TaskPath -and ($task.TaskPath.IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0));
            $inCmd  = ($actionDisplay -and ($actionDisplay.IndexOf($term, [System.StringComparison]::OrdinalIgnoreCase) -ge 0));

            if (-not ($inName -or $inPath -or$inCmd)) {
                continue;
            };
        } else {
            # Jesli NIE ma aktywnego wyszukiwania, respektujemy wykluczenie sciezki
            if (-not [string]::IsNullOrEmpty($ExcludePath) -and ($task.TaskPath -like$ExcludePath)) {
                continue;
            };

            # Filtr stanu (Enabled / Disabled) respektujemy tylko gdy nie szukamy konkretnej frazy
            $rawStateStr = "$($task.State)";
            if ($CurrentStateFilter -ieq 'Disabled') {
                if ($rawStateStr -ne 'Disabled') { continue; };
            } elseif ($CurrentStateFilter -ieq 'Enabled') {
                if ($rawStateStr -eq 'Disabled') { continue; };
            };
        };

        # 4. Pobranie i weryfikacja wyzwalaczy
        $trigSummary = Get-DetailedTriggerSummary -Triggers$task.Triggers;
        if (-not (Test-TriggerMatch -TriggerSummary $trigSummary -SelectedFilter$CurrentTriggerFilter)) {
            continue;
        };

        # 5. Informacje o czasach wykonania
        $info =$null;
        try {
            $info =$task | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue;
        } catch {};

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

        # 6. Opis zadania
        $desc = "-";
        if (-not [string]::IsNullOrWhiteSpace($task.Description)) {
            $desc = ($task.Description -replace "[\r\n]+", " ").Trim();
        };

        # 7. Klasyfikacja typu (System / User / App)
        $taskType = "App";
        if ($task.TaskPath -like "*\Microsoft\*" -or $task.Author -like "*Microsoft*") {
            $taskType = "System";
        } elseif ($task.TaskPath -match 'S-1-5-21-' -or $task.TaskName -match 'S-1-5-21-' -or$actionDisplay -like "*\Users\*") {
            $taskType = "User";
        };

        $displayStatus = if ($task.State -eq 'Disabled') { "Disabled" } else { "Enabled" };

        $tempList.Add([PSCustomObject]@{
            State         = $displayStatus;
            RawState      = "$($task.State)";
            TaskType      = $taskType;
            TriggerType   = $trigSummary;
            TaskName      = $task.TaskName;
            NextRun       = $nextRun;
            LastRun       = $lastRun;
            RawNextDate   = $rawNextDate;
            Command       = $actionDisplay;
            Description   = $desc;
            TaskPath      = $task.TaskPath;
            FullTaskName  = $task.TaskName;
        });
    };

    # Sortowanie chronologiczne wg daty nastepnego uruchomienia
    $sorted =$tempList | Sort-Object -Property @{
        Expression = { if ($_.RawState -ieq 'Disabled') { 1 } else { 0 } }
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
        Write-Host "";
        Write-Host "  [!] Brak zadan spelniajacych biezace kryteria wyszukiwania i filtrowania." -ForegroundColor Yellow;
        Write-Host "";
        return;
    };

    Write-Host ("{0,-6} {1,-10} {2,-8} {3,-16} {4,-42} {5,-18} {6,-18}" -f "Nr", "Status", "Typ", "Trigger", "Nazwa zadania", "Next run", "Last run") -ForegroundColor DarkGray;
    Write-Host ("=" * 125) -ForegroundColor DarkGray;

    $esc = [char]27;
    $cReset   = "$esc[0m";
    $cCyan    = "$esc[36;1m";
    $cBlue    = "$esc[94m";
    $cGreen   = "$esc[32;1m";
    $cYellow  = "$esc[33;1m";
    $cDarkYel = "$esc[33m";
    $cGray    = "$esc[37m";
    $cDarkGry = "$esc[90m";
    $cDarkCyn = "$esc[36m";
    $cMagenta = "$esc[35;1m";

    for ($i = 0; $i -lt$TaskList.Count; $i++) {$t = $TaskList[$i];

        $colNext =$cGray;
        if ($t.NextRun -ieq 'Disabled') {
            $colNext =$cDarkYel;
        } elseif ($t.NextRun -ne '-') {
            $colNext =$cYellow;
        };

        $colType =$cCyan;
        if ($t.TaskType -eq "System") {
            $colType =$cBlue;
        } elseif ($t.TaskType -eq "User") {
            $colType =$cGreen;
        };

        $colStatus = if ($t.State -eq 'Enabled') { $cGreen } else {$cDarkYel };

        $nrStr    = ("[{0,3}]" -f $t.Id).PadRight(6);
        $stateStr = ($t.State).PadRight(10);
        $typeStr  = ($t.TaskType).PadRight(8);
        $trigStr  = ("[" + $t.TriggerType + "]").PadRight(16);
        $nameStr  = ($t.TaskName).PadRight(42);
        $nextStr  = ($t.NextRun).PadRight(18);
        $lastStr  = ($t.LastRun).PadRight(18);

        # WIERSZ 1
        Write-Host "${cCyan}${nrStr}${cReset} ${colStatus}${stateStr}${cReset}${colType}${typeStr}${cReset}${cMagenta}${trigStr}${cReset}${cCyan}${nameStr}${cReset} ${colNext}${nextStr}${cReset}${cDarkGry}${lastStr}${cReset}";

        # WIERSZ 2: Command
        Write-Host "       ↳ Command    : ${cGray}$($t.Command)${cReset}";

        # WIERSZ 3: Description
        Write-Host "       ↳ Description: ${cDarkCyn}$($t.Description)${cReset}";

        # WIERSZ 4: Separator
        Write-Host ("-" * 125) -ForegroundColor DarkGray;
    };
};

function Start-InteractiveSession {
    param (
        [string]$IncludePath,
        [string]$ExcludePath,
        [string]$TaskNameFilter,
        [string]$InitialStateFilter,
        [string]$InitialTriggerFilter
    );

    try {
        if ($Host.UI.RawUI.BufferSize.Height -lt 9000) {
            $buffer =$Host.UI.RawUI.BufferSize;
            $buffer.Height = 9000;
            $Host.UI.RawUI.BufferSize =$buffer;
        };
    } catch {};

    $currentState = if ([string]::IsNullOrWhiteSpace($InitialStateFilter)) { 'Enabled' } else { $InitialStateFilter };$currentTrigger = if ([string]::IsNullOrWhiteSpace($InitialTriggerFilter)) { 'All' } else {$InitialTriggerFilter };
    $currentExclude = if ($null -eq $ExcludePath) { '*Microsoft*' } else {$ExcludePath };
    $currentSearch = if ([string]::IsNullOrWhiteSpace($TaskNameFilter) -or $TaskNameFilter -eq '*') { "" } else { $TaskNameFilter.Trim().Trim('*') };

    while ($true) {
        Clear-Host;
        
        # Bezpieczne przekazanie parametrow (splatting uniemozliwia sklejanie ciagow)
        $filterParams = @{
            IncludePath          = $IncludePath
            ExcludePath          = $currentExclude
            SearchQuery          = $currentSearch
            CurrentStateFilter   = $currentState
            CurrentTriggerFilter = $currentTrigger
        };
        $taskList = Get-FilteredTasks @filterParams;

        $totalTasks =$taskList.Count;
        $msStatusText = if ([string]::IsNullOrEmpty($currentExclude)) { "Wszystkie (+System)" } else { "Tylko Uzytkownik / Aplikacje" };
        $searchStatusText = if ([string]::IsNullOrEmpty($currentSearch)) { "Brak (*)" } else { "'$currentSearch' (Przeszukiwanie calego harmonogramu)" };

        Write-Host "=============================================================================================================================" -ForegroundColor Cyan;
        Write-Host " SCHEDULED TASK MANAGER - KONSOLA ZARZADZANIA ZADANIAMI (WIDOK PELNY)" -ForegroundColor Cyan;
        Write-Host " AKTYWNE FILTRY: [Status: $currentState] \vert{} [Typ:$msStatusText] | [Trigger: $currentTrigger] \vert{} [Szukaj:$searchStatusText]" -ForegroundColor Yellow;
        Write-Host " Legenda Typow: System (Niebieski) | User (Zielony) | App (Turkusowy) | Znaleziono zadan: $totalTasks" -ForegroundColor DarkGray;
        Write-Host "=============================================================================================================================" -ForegroundColor Cyan;

        Render-TwoLineTable -TaskList $taskList;

        Write-Host "";
        Write-Host ("  Lacznie wyswietlono pozycji: $totalTasks zadan") -ForegroundColor Cyan;
        Write-Host ("  " + ("=" * 105)) -ForegroundColor DarkCyan;

        Write-Host "AKCJE I DOSTEPNE FILTRY:" -ForegroundColor Yellow;
        Write-Host "  Zarzadzanie zadaniami :" -ForegroundColor DarkGray;
        Write-Host "    [1..n]     Wylacz zadanie po ID (np. 1 lub 1, 3, 5)";
        Write-Host "    [e <id>]   Wlacz zadanie po ID (np. e 3 lub e 1, 4)";
        Write-Host "  Wyszukiwanie fraza :" -ForegroundColor DarkGray;
        Write-Host "    [s <tekst>] Szukaj w nazwie, sciezce i poleceniu (np. 's nvidia', 's office', 's *' aby wyczyscic)";
        Write-Host "  Filtry przelaczane w locie :" -ForegroundColor DarkGray;
        Write-Host "    [m]         Przelacz filtr: Tylko wlasne (User/App) <-> Wszystkie (+Systemowe)";
        Write-Host "    [f <a|e|d>] Filtr Statusu:  [f a] All | [f e] Enabled (Wlaczone) | [f d] Disabled (Wylaczone)";
        Write-Host "    [t <mode>]  Filtr Triggera: [t a] All | [t b] Boot | [t l] Logon | [t t] Time | [t e] Event | [t o] OnDemand";
        Write-Host "  Sterowanie :" -ForegroundColor DarkGray;
        Write-Host "    [r] Odswiez liste  |  [q] Wyjdz z programu";
        Write-Host "";

        $rawInput = Read-Host "Wprowadz polecenie";
        if ($null -ne$rawInput) {
            $rawInput =$rawInput.Trim();
        };

        if ([string]::IsNullOrWhiteSpace($rawInput) -or$rawInput -ieq 'r') {
            continue;
        };

        if ($rawInput -ieq 'q') {
            break;
        };

        # 1. WYSZUKIWANIE: 's <fraza>' LUB 's' / 's *'
        $parts =$rawInput -split '\s+', 2;
        $cmdToken =$parts[0].ToLower();

        if ($cmdToken -eq 's') {$phrase = if ($parts.Count -gt 1) {$parts[1].Trim() } else { "" };
            if ($phrase -eq '*' -or $phrase -eq '') {$currentSearch = "";
            } else {
                $currentSearch =$phrase.Trim('*');
            };
            continue;
        };

        # 2. PRZELACZANIE SYSTEMOWYCH: m
        if ($rawInput -ieq 'm') {
            if ([string]::IsNullOrEmpty($currentExclude)) {$currentExclude = '*Microsoft*';
            } else {
                $currentExclude = '';
            };
            continue;
        };

        # 3. FILTR STATUSU: f a / f e / f d
        if ($cmdToken -eq 'f' -and$parts.Count -gt 1) {
            $flag =$parts[1].Trim().ToLower();
            if ($flag -eq 'a') {$currentState = 'All'; continue; };
            if ($flag -eq 'e') {$currentState = 'Enabled'; continue; };
            if ($flag -eq 'd') {$currentState = 'Disabled'; continue; };
        } elseif ($rawInput -match '^(?i:f)([aedAED])$') {
            $flag =$matches[1].ToLower();
            if ($flag -eq 'a') {$currentState = 'All'; continue; };
            if ($flag -eq 'e') {$currentState = 'Enabled'; continue; };
            if ($flag -eq 'd') {$currentState = 'Disabled'; continue; };
        };

        # 4. FILTR TRIGGERA: t b / t l / t t / t e / t o / t a
        if ($cmdToken -eq 't' -and$parts.Count -gt 1) {
            $tflag =$parts[1].Trim().ToLower();
            if ($tflag -eq 'a') {$currentTrigger = 'All'; continue; };
            if ($tflag -eq 'b') {$currentTrigger = 'Boot'; continue; };
            if ($tflag -eq 'l') {$currentTrigger = 'Logon'; continue; };
            if ($tflag -eq 't') {$currentTrigger = 'Time'; continue; };
            if ($tflag -eq 'e') {$currentTrigger = 'Event'; continue; };
            if ($tflag -eq 'o') {$currentTrigger = 'OnDemand'; continue; };
        } elseif ($rawInput -match '^(?i:t)([abletoABLETO])$') {
            $tflag =$matches[1].ToLower();
            if ($tflag -eq 'a') {$currentTrigger = 'All'; continue; };
            if ($tflag -eq 'b') {$currentTrigger = 'Boot'; continue; };
            if ($tflag -eq 'l') {$currentTrigger = 'Logon'; continue; };
            if ($tflag -eq 't') {$currentTrigger = 'Time'; continue; };
            if ($tflag -eq 'e') {$currentTrigger = 'Event'; continue; };
            if ($tflag -eq 'o') {$currentTrigger = 'OnDemand'; continue; };
        };

        # 5. WLACZANIE ZADANIA: e <id>
        if ($cmdToken -eq 'e' -and$parts.Count -gt 1) {
            $subStr =$parts[1];
            $tokens = @($subStr -split '[,;\s]+' | Where-Object { $_ -match '^\d+$' });

            if ($tokens.Count -eq 0) {
                Write-Host "Nieprawidlowy identyfikator. Wpisz numery ID." -ForegroundColor Red;
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
                        Enable-ScheduledTask -TaskName $target.FullTaskName -TaskPath $target.TaskPath -ErrorAction Stop | Out-Null;
                        Write-Host "Wlaczono: [$($target.Id)] $($target.FullTaskName)" -ForegroundColor Green;
                    } catch {
                        Write-Host "Blad podczas wlaczania [$($target.FullTaskName)]:$_" -ForegroundColor Red;
                    };
                } else {
                    Write-Host "ID '$id' nie znaleziono na aktywnej liscie." -ForegroundColor DarkYellow;
                };
            };
            Start-Sleep -Seconds 2;
            continue;
        };

        # 6. WYLACZANIE ZADANIA: numery ID (np. 1 lub 1, 3, 5)
        $allTokens = @($rawInput -split '[,;\s]+');
        $invalidTokens = @($allTokens | Where-Object { $_ -notmatch '^\d+$' });

        if ($invalidTokens.Count -gt 0) {
            $joinedErr =$invalidTokens -join ', ';
            Write-Host "Nierozpoznane polecenie: '$joinedErr'. Wpisz 's <fraza>', 'f <a|e|d>', 't <mode>', 'm', 'e <id>' lub numery ID." -ForegroundColor Red;
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
                    Disable-ScheduledTask -TaskName $target.FullTaskName -TaskPath $target.TaskPath -ErrorAction Stop | Out-Null;
                    Write-Host "Wylaczono: [$($target.Id)] $($target.FullTaskName)" -ForegroundColor Green;
                } catch {
                    Write-Host "Blad podczas wylaczania [$($target.FullTaskName)]:$_" -ForegroundColor Red;
                };
            } else {
                Write-Host "ID '$id' nie znaleziono na aktywnej liscie." -ForegroundColor DarkYellow;
            };
        };
        Start-Sleep -Seconds 2;
    };

    Clear-Host;
    Write-Host "Sesja menedzera zadan zakonczona." -ForegroundColor Cyan;
};

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8;

if ($Help -or ($PSBoundParameters.Count -eq 0)) {
    Show-ScriptHelp;
    Exit 0;
};

Assert-AdministratorPrivileges;

if ($ListOnly) {$cliParams = @{
        IncludePath          = $IncludePathPattern
        ExcludePath          = $ExcludePathPattern
        SearchQuery          = $NamePattern
        CurrentStateFilter   = $StateFilter
        CurrentTriggerFilter = $TriggerFilter
    };
    $tasks = Get-FilteredTasks @cliParams;
    Render-TwoLineTable -TaskList $tasks;
    Exit 0;
};

if ($Interactive) {$interactiveParams = @{
        IncludePath          = $IncludePathPattern
        ExcludePath          = $ExcludePathPattern
        TaskNameFilter       = $NamePattern
        InitialStateFilter   = $StateFilter
        InitialTriggerFilter = $TriggerFilter
    };
    Start-InteractiveSession @interactiveParams;
    Exit 0;
};
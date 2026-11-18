<#
.SYNOPSIS
    Registers or overwrites dedicated Windows Task Scheduler jobs for monthly Hot
    backups of Hyper-V VMs (SQL2022, Unify, Elektrimont ESET Protect) and enables
    Task Scheduler execution history.

.DESCRIPTION
    Creates or cleanly replaces individual Windows Task Scheduler tasks for each
    Hyper-V virtual machine using native Task Scheduler COM MonthlyDOW triggers:
    - Backup-HyperVVM-SQL2022                   : 1st Sunday of every month at 14:00
    - Backup-HyperVVM-Unify                     : 2nd Sunday of every month at 14:00
    - Backup-HyperVVM-Elektrimont-ESET-Protect  : 3rd Sunday of every month at 14:00

    Each task runs Backup-HyperVVM.ps1 in Hot mode without password (-NoEncrypt
    by default, or -NoZip if specified), saves backups to C:\DANE\Backup (keeping
    1 valid copy per VM, deleting the previous copy only after the new backup
    succeeds and passes verification), writes audit logs to C:\Logi, and executes
    under NT AUTHORITY\SYSTEM with highest privileges.

    Can also register a single custom VM task when -VMName and -WeekOfMonth are
    explicitly supplied. Additionally enables the
    'Microsoft-Windows-TaskScheduler/Operational' event log.

.PARAMETER ScriptPath
    Full path to Backup-HyperVVM.ps1.
    Default: 'C:\Scripts\Backup-HyperVVM\Backup-HyperVVM.ps1'.

.PARAMETER BackupPath
    Destination directory passed to Backup-HyperVVM.ps1 (-BackupPath).
    Default: 'C:\DANE\Backup'.

.PARAMETER LogDir
    Audit log directory passed to Backup-HyperVVM.ps1 (-LogDir).
    Default: 'C:\Logi'.

.PARAMETER RetentionCount
    Number of valid backup copies per VM to retain in BackupPath.
    Default: 1.

.PARAMETER NoZip
    Switch parameter. Registers the scheduled task(s) to use -NoZip (uncompressed
    folder, no password) instead of -NoEncrypt (unencrypted .zip, no password).

.PARAMETER VMName
    Optional single VM name to register individually instead of the 3 default
    VMs (SQL2022, Unify, Elektrimont ESET Protect).

.PARAMETER WeekOfMonth
    Week of the month (1 = 1st, 2 = 2nd, 3 = 3rd, 4 = 4th Sunday) when -VMName
    is specified. Default: 1.

.PARAMETER ScheduleTime
    Time of day in HH:mm format for the Sunday backup trigger. Default: '14:00'.

.PARAMETER TaskFolder
    Task Scheduler folder path where tasks are registered. Default: '\'.

.PARAMETER Help
    Displays detailed help and usage examples. Alias: -h.

.EXAMPLE
    .\Register-Backup-HyperVVM.ps1
    Registers all 3 monthly Sunday tasks (SQL2022 -> 1st Sunday 14:00,
    Unify -> 2nd Sunday 14:00, Elektrimont ESET Protect -> 3rd Sunday 14:00)
    and enables Task Scheduler execution history.

.EXAMPLE
    .\Register-Backup-HyperVVM.ps1 -VMName "APP01" -WeekOfMonth 4 -ScheduleTime "16:00"
    Registers a dedicated monthly task for APP01 on the 4th Sunday at 16:00.

.NOTES
    Author       : Roman Pindela
    Email        : roman.pindela@gmail.com
    GitHub       : https://github.com/romanpindela
    Version      : 1.0.0
    Release Date : 2026-11-18
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param (
    [Parameter(Mandatory = $false, HelpMessage = 'Full path to Backup-HyperVVM.ps1.')]
    [ValidateNotNullOrEmpty()]
    [string]$ScriptPath = 'C:\Scripts\Backup-HyperVVM\Backup-HyperVVM.ps1',

    [Parameter(Mandatory = $false, HelpMessage = 'Backup destination directory.')]
    [ValidateNotNullOrEmpty()]
    [string]$BackupPath = 'C:\DANE\Backup',

    [Parameter(Mandatory = $false, HelpMessage = 'Audit log directory.')]
    [ValidateNotNullOrEmpty()]
    [string]$LogDir = 'C:\Logi',

    [Parameter(Mandatory = $false, HelpMessage = 'Number of valid backup copies per VM to retain.')]
    [ValidateRange(0, 3650)]
    [int]$RetentionCount = 1,

    [Parameter(Mandatory = $false, HelpMessage = 'Use -NoZip (uncompressed folder) instead of -NoEncrypt (.zip).')]
    [switch]$NoZip,

    [Parameter(Mandatory = $false, HelpMessage = 'Optional single VM name to register individually.')]
    [ValidateNotNullOrEmpty()]
    [string]$VMName,

    [Parameter(Mandatory = $false, HelpMessage = 'Sunday of the month (1-4) when -VMName is specified.')]
    [ValidateRange(1, 4)]
    [int]$WeekOfMonth = 1,

    [Parameter(Mandatory = $false, HelpMessage = 'Execution time in HH:mm format.')]
    [ValidatePattern('^(?:[01]\d|2[0-3]):[0-5]\d$')]
    [string]$ScheduleTime = '14:00',

    [Parameter(Mandatory = $false, HelpMessage = 'Task Scheduler folder path.')]
    [ValidateNotNullOrEmpty()]
    [string]$TaskFolder = '\',

    [Alias('h')]
    [Parameter(Mandatory = $false, HelpMessage = 'Displays help and script information.')]
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Help.IsPresent) {
    Get-Help -Name $MyInvocation.MyCommand.Path -Detailed
    exit 0
}

# Verify Administrator privileges using universal SID S-1-5-32-544
$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principalCheck = [System.Security.Principal.WindowsPrincipal]::new($identity)
$adminSid = [System.Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
if (-not $principalCheck.IsInRole($adminSid)) {
    throw 'Administrator privileges (SID S-1-5-32-544) are required to register scheduled tasks and enable Task Scheduler history.'
}

function Register-MonthlySundayHyperVBackupTask {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true)]
        [object]$RootFolder,

        [Parameter(Mandatory = $true)]
        [string]$TaskName,

        [Parameter(Mandatory = $true)]
        [string]$TargetVMName,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 4)]
        [int]$SundayWeekNumber,

        [Parameter(Mandatory = $true)]
        [string]$AtTime,

        [Parameter(Mandatory = $true)]
        [string]$BackupScriptPath,

        [Parameter(Mandatory = $true)]
        [string]$TargetBackupPath,

        [Parameter(Mandatory = $true)]
        [string]$TargetLogDir,

        [Parameter(Mandatory = $true)]
        [int]$KeepCopies,

        [Parameter()]
        [switch]$UseNoZip
    )

    $weekLabels = @{
        1 = '1st Sunday'
        2 = '2nd Sunday'
        3 = '3rd Sunday'
        4 = '4th Sunday'
    }
    $weeksBitmaskMap = @{
        1 = 1   # 0x01 = First week
        2 = 2   # 0x02 = Second week
        3 = 4   # 0x04 = Third week
        4 = 8   # 0x08 = Fourth week
    }

    $formatFlag = if ($UseNoZip) { '-NoZip' } else { '-NoEncrypt' }
    $psArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$BackupScriptPath`" -VMName `"$TargetVMName`" -BackupMode Hot $formatFlag -BackupPath `"$TargetBackupPath`" -LogDir `"$TargetLogDir`" -RetentionCount $KeepCopies"
    $weekLabel = $weekLabels[$SundayWeekNumber]
    $description = "Monthly Hyper-V Hot backup (no password, $formatFlag, keep $KeepCopies copy) for VM '$TargetVMName' executed every $weekLabel of the month at $AtTime. Logs: $TargetLogDir."

    if (-not $PSCmdlet.ShouldProcess($TaskName, "Register monthly task ($weekLabel at $AtTime) for VM '$TargetVMName'")) {
        return
    }

    # Remove existing task with the same name for clean overwrite
    try {
        $existing = $RootFolder.GetTask($TaskName)
        if ($null -ne $existing) {
            Write-Host "[INFO] Existing task '$TaskName' found. Removing old definition before recreating..." -ForegroundColor Yellow
            $RootFolder.DeleteTask($TaskName, 0)
        }
    }
    catch {
        # Task does not exist yet
    }

    $service = New-Object -ComObject Schedule.Service
    $service.Connect()
    $taskDef = $service.NewTask(0)

    $taskDef.RegistrationInfo.Description = $description
    $taskDef.RegistrationInfo.Author = 'Roman Pindela'

    # Principal: NT AUTHORITY\SYSTEM with Highest privileges
    $taskDef.Principal.UserId = 'NT AUTHORITY\SYSTEM'
    $taskDef.Principal.LogonType = 5   # TASK_LOGON_SERVICE_ACCOUNT
    $taskDef.Principal.RunLevel = 1    # TASK_RUNLEVEL_HIGHEST

    # Settings: resilient for long-running VHDX export & server restarts
    $taskDef.Settings.Enabled = $true
    $taskDef.Settings.AllowDemandStart = $true
    $taskDef.Settings.DisallowStartIfOnBatteries = $false
    $taskDef.Settings.StopIfGoingOnBatteries = $false
    $taskDef.Settings.StartWhenAvailable = $true
    $taskDef.Settings.ExecutionTimeLimit = 'PT12H'
    $taskDef.Settings.MultipleInstances = 2   # TASK_INSTANCES_IGNORE_NEW

    # Trigger: TASK_TRIGGER_MONTHLYDOW (5) -> Specific Sunday of every month at AtTime
    $trigger = $taskDef.Triggers.Create(5)
    $startDate = (Get-Date).ToString('yyyy-MM-dd')
    $trigger.StartBoundary = "${startDate}T${AtTime}:00"
    $trigger.DaysOfWeek = 1                                    # 0x01 = Sunday
    $trigger.WeeksOfMonth = $weeksBitmaskMap[$SundayWeekNumber]
    $trigger.MonthsOfYear = 4095                               # 0x0FFF = All 12 months
    $trigger.Enabled = $true

    # Action: Execute PowerShell with Backup-HyperVVM.ps1
    $action = $taskDef.Actions.Create(0)   # TASK_ACTION_EXEC
    $action.Path = 'powershell.exe'
    $action.Arguments = $psArgs

    # TASK_CREATE_OR_UPDATE (6), TASK_LOGON_SERVICE_ACCOUNT (5)
    [void]$RootFolder.RegisterTaskDefinition($TaskName, $taskDef, 6, 'NT AUTHORITY\SYSTEM', $null, 5)
    Write-Host "[SUCCESS] Registered task '$TaskName' -> VM: '$TargetVMName' | Schedule: $weekLabel at $AtTime | Mode: Hot ($formatFlag)" -ForegroundColor Green
}

# Build target task list (single custom VM if -VMName passed, otherwise the 3 standard VMs)
$tasksToRegister = if (-not [string]::IsNullOrWhiteSpace($VMName)) {
    $safeTaskSuffix = ($VMName -replace '[^A-Za-z0-9._-]+', '-').Trim('-')
    @(
        [PSCustomObject]@{
            TaskName    = "Backup-HyperVVM-$safeTaskSuffix"
            VMName      = $VMName
            WeekOfMonth = $WeekOfMonth
            AtTime      = $ScheduleTime
        }
    )
}
else {
    @(
        [PSCustomObject]@{
            TaskName    = 'Backup-HyperVVM-SQL2022'
            VMName      = 'SQL2022'
            WeekOfMonth = 1
            AtTime      = $ScheduleTime
        },
        [PSCustomObject]@{
            TaskName    = 'Backup-HyperVVM-Unify'
            VMName      = 'Unify'
            WeekOfMonth = 2
            AtTime      = $ScheduleTime
        },
        [PSCustomObject]@{
            TaskName    = 'Backup-HyperVVM-Elektrimont-ESET-Protect'
            VMName      = 'Elektrimont ESET Protect'
            WeekOfMonth = 3
            AtTime      = $ScheduleTime
        }
    )
}

if (-not (Test-Path -Path $ScriptPath -PathType Leaf)) {
    Write-Host "[WARN] Target backup script not found at '$ScriptPath'. Tasks will still reference this path." -ForegroundColor Yellow
}

$schedulerService = New-Object -ComObject Schedule.Service
$schedulerService.Connect()

$normalizedFolder = if ($TaskFolder -eq '\') { '\' } else { "\" + $TaskFolder.Trim('\') }
try {
    $targetFolder = $schedulerService.GetFolder($normalizedFolder)
}
catch {
    $root = $schedulerService.GetFolder('\')
    $targetFolder = $root.CreateFolder($normalizedFolder.TrimStart('\'))
}

foreach ($entry in $tasksToRegister) {
    Register-MonthlySundayHyperVBackupTask `
        -RootFolder $targetFolder `
        -TaskName $entry.TaskName `
        -TargetVMName $entry.VMName `
        -SundayWeekNumber $entry.WeekOfMonth `
        -AtTime $entry.AtTime `
        -BackupScriptPath $ScriptPath `
        -TargetBackupPath $BackupPath `
        -TargetLogDir $LogDir `
        -KeepCopies $RetentionCount `
        -UseNoZip:$NoZip
}

# Enable Task Scheduler Operational Event Log (Execution History)
$taskHistoryLogName = 'Microsoft-Windows-TaskScheduler/Operational'
try {
    $logConfig = New-Object System.Diagnostics.Eventing.Reader.EventLogConfiguration($taskHistoryLogName)
    if (-not $logConfig.IsEnabled) {
        if ($PSCmdlet.ShouldProcess($taskHistoryLogName, 'Enable Task Scheduler Operational event log')) {
            $logConfig.IsEnabled = $true
            $logConfig.SaveChanges()
            Write-Host "[SUCCESS] Enabled Task Scheduler execution history log ('$taskHistoryLogName')." -ForegroundColor Green
        }
    }
    else {
        Write-Host "[INFO] Task Scheduler execution history log ('$taskHistoryLogName') is already enabled." -ForegroundColor Gray
    }
}
catch {
    Write-Host "[WARN] .NET EventLogConfiguration failed ($_); attempting fallback via wevtutil.exe..." -ForegroundColor Yellow
    $null = & wevtutil.exe sl $taskHistoryLogName /e:true 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[SUCCESS] Enabled Task Scheduler execution history log via wevtutil.exe." -ForegroundColor Green
    }
    else {
        Write-Host "[WARN] Could not enable Task Scheduler history log automatically (exit code: $LASTEXITCODE)." -ForegroundColor Yellow
    }
}

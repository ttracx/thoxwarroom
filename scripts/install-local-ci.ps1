[CmdletBinding()]
param(
    [string]$RepoPath = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
    [string]$TaskName = 'THOX-WarRoom-CI',
    [ValidateRange(1, 30)]
    [int]$IntervalDays = 1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoPath = (Resolve-Path -LiteralPath $RepoPath).Path
$Runner = Join-Path $RepoPath 'scripts\local-ci.ps1'
if (-not (Test-Path -LiteralPath $Runner)) {
    throw "Local CI runner is missing: $Runner"
}

$argument = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File ' +
    ('"{0}" -RepoPath "{1}"' -f $Runner, $RepoPath)
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argument -WorkingDirectory $RepoPath
$trigger = New-ScheduledTaskTrigger -Daily -At 07:45
$principal = New-ScheduledTaskPrincipal `
    -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) `
    -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet `
    -MultipleInstances IgnoreNew `
    -StartWhenAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit (New-TimeSpan -Hours 2) `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries

$task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings
Register-ScheduledTask -TaskName $TaskName -InputObject $task -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName

Write-Host "Installed scheduled task: $TaskName"
Write-Host "Runner: $Runner"

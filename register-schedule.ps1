<#
.SYNOPSIS
    backup2ecm 자동 실행 스케줄 등록/해제 스크립트

.DESCRIPTION
    Windows 작업 스케줄러에 매일 지정 시각(기본 18:00, 퇴근 시간)에
    backup2ecm.ps1 을 실행하는 작업을 등록합니다.

    네트워크 드라이브(Y: 등)는 로그인한 사용자 세션에서만 연결되므로,
    작업은 "사용자가 로그온한 경우에만 실행" 방식으로 등록됩니다.

.PARAMETER Time
    매일 실행할 시각 (기본 '18:00')

.PARAMETER Mode
    backup(기본) 또는 restore

.PARAMETER Remove
    등록된 스케줄 작업을 삭제

.EXAMPLE
    .\register-schedule.ps1                    # 매일 18:00 백업 등록
    .\register-schedule.ps1 -Time 08:30 -Mode restore   # 출근 시 받아오기 등록
    .\register-schedule.ps1 -Remove            # 백업 스케줄 삭제
    .\register-schedule.ps1 -Mode restore -Remove       # 받아오기 스케줄 삭제
#>
[CmdletBinding()]
param(
    [string]$Time = '18:00',

    [ValidateSet('backup', 'restore')]
    [string]$Mode = 'backup',

    [switch]$Remove
)

$ErrorActionPreference = 'Stop'

$taskName   = "Backup2ECM_$Mode"
$scriptPath = Join-Path $PSScriptRoot 'backup2ecm.ps1'

if ($Remove) {
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "스케줄 작업 삭제 완료: $taskName"
    }
    else {
        Write-Host "삭제할 스케줄 작업이 없습니다: $taskName"
    }
    return
}

if (-not (Test-Path -LiteralPath $scriptPath)) {
    Write-Error "backup2ecm.ps1 을 찾을 수 없습니다: $scriptPath"
    exit 1
}

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument (
    '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Mode {1}' -f $scriptPath, $Mode
)

$trigger = New-ScheduledTaskTrigger -Daily -At $Time

# Interactive: 로그온 세션에서 실행 -> 네트워크 드라이브(Y:) 사용 가능
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 4) `
    -MultipleInstances IgnoreNew

Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger $trigger `
    -Principal $principal `
    -Settings $settings `
    -Description "원본폴더와 ECM 백업폴더 동기화 ($Mode) - backup2ecm" `
    -Force | Out-Null

Write-Host "스케줄 등록 완료: 매일 $Time 에 '$Mode' 실행 (작업 이름: $taskName)"
Write-Host "확인: 작업 스케줄러(taskschd.msc) 또는 Get-ScheduledTask -TaskName $taskName"

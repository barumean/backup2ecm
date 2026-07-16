<#
.SYNOPSIS
    원본폴더 <-> ECM 백업폴더 동기화 스크립트 (robocopy 기반)

.DESCRIPTION
    config.json 에 정의된 폴더 쌍(원본폴더/ECM폴더)을 대상으로
    - backup  : 원본폴더 -> ECM폴더 로 새/변경 파일만 복사 (퇴근 시 백업)
    - restore : ECM폴더 -> 원본폴더 로 새/변경 파일만 복사 (받아오기)
    를 수행합니다. 기본 동작은 어떤 파일도 삭제하지 않습니다.

.PARAMETER Mode
    backup(기본) 또는 restore

.PARAMETER PairName
    config.json 의 pairs 중 특정 name 만 실행하고 싶을 때 지정

.PARAMETER Mirror
    대상 폴더를 원본과 완전히 동일하게 맞춤(대상에만 있는 파일 삭제, robocopy /MIR).
    삭제가 발생하므로 꼭 필요할 때만 사용하세요.

.PARAMETER DryRun
    실제 복사 없이 어떤 파일이 복사될지 목록만 출력(robocopy /L)

.EXAMPLE
    .\backup2ecm.ps1                       # 전체 쌍 백업 (원본 -> ECM)
    .\backup2ecm.ps1 -Mode restore         # 전체 쌍 받아오기 (ECM -> 원본)
    .\backup2ecm.ps1 -PairName 송교항_성과품 -DryRun
#>
[CmdletBinding()]
param(
    [ValidateSet('backup', 'restore')]
    [string]$Mode = 'backup',

    [string]$PairName,

    [switch]$Mirror,

    [switch]$DryRun,

    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json')
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- 설정 로드
if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Write-Error "설정 파일을 찾을 수 없습니다: $ConfigPath"
    exit 1
}
$config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json

$pairs = @($config.pairs | Where-Object { $_.enabled -ne $false })
if ($PairName) {
    $pairs = @($pairs | Where-Object { $_.name -eq $PairName })
    if ($pairs.Count -eq 0) {
        Write-Error "config.json 에서 name='$PairName' 인 폴더 쌍을 찾을 수 없습니다."
        exit 1
    }
}
if ($pairs.Count -eq 0) {
    Write-Error "실행할 폴더 쌍이 없습니다. config.json 의 pairs 를 확인하세요."
    exit 1
}

# ---------------------------------------------------------------- 로그 준비
$logFolderName = if ($config.logFolder) { [string]$config.logFolder } else { 'logs' }
$logFolder = if ([System.IO.Path]::IsPathRooted($logFolderName)) { $logFolderName }
             else { Join-Path $PSScriptRoot $logFolderName }
New-Item -ItemType Directory -Path $logFolder -Force | Out-Null

$stamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
$logFile = Join-Path $logFolder ("{0}_{1}.log" -f $Mode, $stamp)

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
}

# 오래된 로그 정리
$keepDays = if ($config.logKeepDays) { [int]$config.logKeepDays } else { 30 }
Get-ChildItem -LiteralPath $logFolder -Filter '*.log' -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$keepDays) } |
    Remove-Item -Force -ErrorAction SilentlyContinue

# ---------------------------------------------------------------- 실행
Write-Log "===== backup2ecm 시작 (Mode=$Mode, Mirror=$Mirror, DryRun=$DryRun) ====="

$excludeFiles = @($config.excludeFiles | Where-Object { $_ })
$excludeDirs  = @($config.excludeDirs  | Where-Object { $_ })
$hadError     = $false

foreach ($pair in $pairs) {
    if ($Mode -eq 'backup') {
        $src = [string]$pair.source
        $dst = [string]$pair.ecm
    }
    else {
        $src = [string]$pair.ecm
        $dst = [string]$pair.source
    }

    Write-Log "--- [$($pair.name)] $src  ==>  $dst"

    # 원본 확인
    if (-not (Test-Path -LiteralPath $src)) {
        Write-Log "오류: 원본 경로에 접근할 수 없습니다: $src (네트워크 드라이브 연결 여부를 확인하세요)"
        $hadError = $true
        continue
    }

    # 대상 드라이브/공유 확인 (대상 폴더 자체는 robocopy 가 생성함)
    $dstRoot = [System.IO.Path]::GetPathRoot($dst)
    if ($dstRoot -and -not (Test-Path -LiteralPath $dstRoot)) {
        Write-Log "오류: 대상 드라이브에 접근할 수 없습니다: $dstRoot (네트워크 드라이브 연결 여부를 확인하세요)"
        $hadError = $true
        continue
    }

    # robocopy 옵션 구성
    #  /E   : 하위 폴더 포함(빈 폴더 포함)
    #  /XO  : 대상이 더 최신이면 건너뜀 (새/변경 파일만 복사)
    #  /FFT : FAT 시간 방식 비교(네트워크 드라이브 타임스탬프 오차 2초 허용)
    #  /R /W: 실패 시 재시도 2회, 5초 간격
    $rcArgs = @($src, $dst, '/E', '/FFT', '/R:2', '/W:5', '/NP', '/NDL', "/LOG+:$logFile", '/TEE')

    if ($Mirror) { $rcArgs += '/MIR' } else { $rcArgs += '/XO' }
    if ($DryRun) { $rcArgs += '/L' }

    if ($excludeFiles.Count -gt 0) { $rcArgs += '/XF'; $rcArgs += $excludeFiles }
    if ($excludeDirs.Count  -gt 0) { $rcArgs += '/XD'; $rcArgs += $excludeDirs }

    & robocopy @rcArgs | Out-Null
    $rc = $LASTEXITCODE

    # robocopy 종료 코드: 0~7 = 정상(복사됨/변경없음 등), 8 이상 = 오류
    if ($rc -ge 8) {
        Write-Log "결과: 오류 발생 (robocopy 코드 $rc) - 자세한 내용은 로그를 확인하세요."
        $hadError = $true
    }
    elseif ($rc -eq 0) {
        Write-Log "결과: 변경 사항 없음 (이미 최신 상태)"
    }
    else {
        Write-Log "결과: 완료 (robocopy 코드 $rc - 파일 복사/갱신됨)"
    }
}

Write-Log "===== backup2ecm 종료 ====="
Write-Log "로그 파일: $logFile"

if ($hadError) { exit 1 } else { exit 0 }

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
    try {
        if ($Mode -eq 'backup') {
            $src = [string]$pair.source
            $dst = [string]$pair.ecm
        }
        else {
            $src = [string]$pair.ecm
            $dst = [string]$pair.source
        }

        Write-Log "--- [$($pair.name)] $src  ==>  $dst"

        # 원본 확인 (네트워크/ECM 드라이브 오류가 나도 예외 대신 false 처리)
        if (-not (Test-Path -LiteralPath $src -ErrorAction SilentlyContinue)) {
            Write-Log "오류: 원본 경로에 접근할 수 없습니다: $src (네트워크 드라이브 연결 여부를 확인하세요)"
            $hadError = $true
            continue
        }

        # 대상 드라이브/공유 확인 - 실패해도 중단하지 않고 복사를 시도함
        # (ECM/WebDAV 드라이브는 루트 확인이 안 되어도 실제 복사는 되는 경우가 있고,
        #  실패하더라도 robocopy 가 더 정확한 오류를 로그에 남김)
        $dstRoot = $null
        try { $dstRoot = [System.IO.Path]::GetPathRoot($dst) } catch { }
        if ($dstRoot -and -not (Test-Path -LiteralPath $dstRoot -ErrorAction SilentlyContinue)) {
            Write-Log "주의: 대상 드라이브($dstRoot)가 이 세션에서 확인되지 않습니다. 그래도 복사를 시도합니다."
        }

        # robocopy 상세 로그는 쌍(pair)별 별도 파일에 기록 (인코딩/파일 잠금 충돌 방지)
        $safeName = ([string]$pair.name) -replace '[\\/:*?"<>|]', '_'
        $rcLog    = Join-Path $logFolder ("{0}_{1}_{2}_robocopy.log" -f $Mode, $stamp, $safeName)

        # robocopy 옵션 구성
        #  /E   : 하위 폴더 포함(빈 폴더 포함)
        #  /XO  : 대상이 더 최신이면 건너뜀 (새/변경 파일만 복사)
        #  /FFT : FAT 시간 방식 비교(네트워크 드라이브 타임스탬프 오차 2초 허용)
        #  /R /W: 실패 시 재시도 2회, 5초 간격
        $rcArgs = @($src, $dst, '/E', '/FFT', '/R:2', '/W:5', '/NP', '/NDL', "/LOG:$rcLog", '/TEE')

        if ($Mirror) { $rcArgs += '/MIR' } else { $rcArgs += '/XO' }
        if ($DryRun) { $rcArgs += '/L' }

        if ($excludeFiles.Count -gt 0) { $rcArgs += '/XF'; $rcArgs += $excludeFiles }
        if ($excludeDirs.Count  -gt 0) { $rcArgs += '/XD'; $rcArgs += $excludeDirs }

        $shownCmd = ($rcArgs | ForEach-Object { if ("$_" -match '\s') { '"{0}"' -f $_ } else { "$_" } }) -join ' '
        Write-Log "robocopy 실행: robocopy $shownCmd"

        # 출력을 숨기지 않음 -> 실행 창에서 진행 상황/오류를 바로 볼 수 있음
        & robocopy @rcArgs
        $rc = $LASTEXITCODE

        # robocopy 종료 코드: 0~7 = 정상(복사됨/변경없음 등), 8 이상 = 오류
        if ($rc -ge 8) {
            Write-Log "결과: 오류 발생 (robocopy 코드 $rc) - 상세 로그: $rcLog"
            $hadError = $true
        }
        elseif ($rc -eq 0) {
            Write-Log "결과: 변경 사항 없음 (이미 최신 상태)"
        }
        else {
            Write-Log "결과: 완료 (robocopy 코드 $rc - 파일 복사/갱신됨) - 상세 로그: $rcLog"
        }
    }
    catch {
        Write-Log ("예외 발생 [{0}]: {1}" -f $pair.name, $_.Exception.Message)
        Write-Log ("위치: " + $_.InvocationInfo.PositionMessage)
        $hadError = $true
    }
}

Write-Log "===== backup2ecm 종료 ====="
Write-Log "로그 파일: $logFile"

if ($hadError) { exit 1 } else { exit 0 }

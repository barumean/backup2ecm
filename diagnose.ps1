<#
.SYNOPSIS
    backup2ecm 진단 정보 수집 스크립트

.DESCRIPTION
    네트워크/ECM 드라이브 연결 상태와 config.json 에 등록된 경로의
    접근 가능 여부를 검사하여 logs\diagnose_*.txt 파일로 저장합니다.
    저장된 파일을 그대로 전달하면 문제 검토가 가능합니다.

    실행: diagnose.bat 더블클릭 (또는 .\diagnose.ps1)
#>
$ErrorActionPreference = 'Continue'

$logFolder = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Path $logFolder -Force | Out-Null
$outFile = Join-Path $logFolder ("diagnose_{0}.txt" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

$lines = New-Object System.Collections.Generic.List[string]
function Say {
    param([string]$Text = '')
    Write-Host $Text
    $lines.Add($Text)
}
function Section {
    param([string]$Title)
    Say ''
    Say ('=' * 60)
    Say "## $Title"
    Say ('=' * 60)
}

Say ("backup2ecm 진단 - {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Say ("컴퓨터: $env:COMPUTERNAME / 사용자: $env:USERDOMAIN\$env:USERNAME")
Say ("PowerShell 버전: " + $PSVersionTable.PSVersion)
Say ("OS: " + [System.Environment]::OSVersion.VersionString)

# ---------------------------------------------------------------- 관리자 권한 여부
Section '실행 권한'
try {
    $identity  = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    $isAdmin   = $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    Say "관리자 권한으로 실행 중: $isAdmin"
    Say "(참고: 관리자 권한 세션에서는 일반 세션에서 연결한 네트워크 드라이브가 안 보일 수 있습니다)"
}
catch { Say "확인 실패: $($_.Exception.Message)" }

# ---------------------------------------------------------------- 네트워크 드라이브 목록
Section '네트워크 드라이브 연결 상태 (net use)'
try { (net use 2>&1) | ForEach-Object { Say ([string]$_) } }
catch { Say "확인 실패: $($_.Exception.Message)" }

Section 'PowerShell 에서 보이는 드라이브 (Get-PSDrive)'
try {
    Get-PSDrive -PSProvider FileSystem | ForEach-Object {
        Say ("{0}:  Root={1}  DisplayRoot={2}" -f $_.Name, $_.Root, $_.DisplayRoot)
    }
}
catch { Say "확인 실패: $($_.Exception.Message)" }

Section 'WebDAV 서비스 상태 (WebClient)'
try {
    $svc = Get-Service -Name WebClient -ErrorAction SilentlyContinue
    if ($svc) { Say ("WebClient 서비스: {0} (시작 유형 참고)" -f $svc.Status) }
    else      { Say 'WebClient 서비스 없음' }
}
catch { Say "확인 실패: $($_.Exception.Message)" }

# ---------------------------------------------------------------- config.json 경로 검사
Section 'config.json 에 등록된 경로 접근 검사'
$configPath = Join-Path $PSScriptRoot 'config.json'
if (-not (Test-Path -LiteralPath $configPath)) {
    Say "config.json 이 없습니다: $configPath"
}
else {
    $config = $null
    try { $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { Say "config.json 읽기 실패: $($_.Exception.Message)" }

    foreach ($pair in @($config.pairs)) {
        if (-not $pair) { continue }
        Say ''
        Say "--- [$($pair.name)]"
        foreach ($info in @(
            @{ Label = '원본(source)'; Path = [string]$pair.source },
            @{ Label = '백업(ecm)   '; Path = [string]$pair.ecm }
        )) {
            $p = $info.Path
            Say ("{0}: {1}" -f $info.Label, $p)

            # 1) Test-Path
            $tp = $false
            try { $tp = Test-Path -LiteralPath $p -ErrorAction SilentlyContinue } catch { }
            Say ("    Test-Path            : $tp")

            # 2) .NET Directory.Exists
            $de = $false
            try { $de = [System.IO.Directory]::Exists($p) } catch { }
            Say ("    Directory.Exists     : $de")

            # 3) 드라이브 루트
            $root = $null
            try { $root = [System.IO.Path]::GetPathRoot($p) } catch { }
            if ($root) {
                $rootOk = $false
                try { $rootOk = [System.IO.Directory]::Exists($root) } catch { }
                Say ("    루트($root) 접근      : $rootOk")
            }

            # 4) 실제 목록 조회 시도 (가장 확실한 검사)
            try {
                $items = [System.IO.Directory]::GetFileSystemEntries($p)
                Say ("    폴더 목록 조회       : 성공 (항목 {0}개)" -f $items.Count)
            }
            catch {
                Say ("    폴더 목록 조회       : 실패 - {0}: {1}" -f $_.Exception.GetType().Name, $_.Exception.Message)
            }

            # 5) cmd 를 통한 조회 (PowerShell 과 결과가 다른 경우 원인 판별에 도움)
            try {
                cmd /c dir /b "$p" > $null 2>&1
                Say ("    cmd dir 조회         : ExitCode=$LASTEXITCODE (0=성공)")
            }
            catch { Say ("    cmd dir 조회         : 실패 - $($_.Exception.Message)") }
        }
    }
}

# ---------------------------------------------------------------- 저장
Say ''
Say ('=' * 60)
Say "진단 완료. 이 내용이 아래 파일로 저장되었습니다:"
Say "  $outFile"
Say "이 파일을 그대로 전달해 주세요."

Set-Content -LiteralPath $outFile -Value ($lines -join "`r`n") -Encoding UTF8

Write-Host ''
Read-Host 'Enter 키를 누르면 창이 닫힙니다'

<#
.SYNOPSIS
    backup2ecm 간단 GUI

.DESCRIPTION
    원하는 폴더(원본)와 백업 폴더를 화면에서 지정/관리하고,
    버튼 클릭으로 백업(원본->백업폴더) / 받아오기(백업폴더->원본)를 실행합니다.
    설정은 config.json 에 저장되므로 스케줄 자동 실행과 그대로 공유됩니다.

    실행: backup2ecm-gui.bat 더블클릭 (또는 .\backup2ecm-gui.ps1)
#>
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:configPath = Join-Path $PSScriptRoot 'config.json'
$script:enginePath = Join-Path $PSScriptRoot 'backup2ecm.ps1'

# ---------------------------------------------------------------- 설정 로드/저장
function Get-DefaultConfig {
    [pscustomobject]@{
        pairs        = @()
        logFolder    = 'logs'
        logKeepDays  = 30
        excludeFiles = @('~$*', '*.tmp', '*.bak', 'Thumbs.db', 'desktop.ini')
        excludeDirs  = @('$RECYCLE.BIN', 'System Volume Information')
    }
}

if (Test-Path -LiteralPath $script:configPath) {
    $script:config = Get-Content -LiteralPath $script:configPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
else {
    $script:config = Get-DefaultConfig
}

$script:pairs = New-Object System.Collections.ArrayList
foreach ($p in @($script:config.pairs)) {
    if ($p) { [void]$script:pairs.Add($p) }
}

function Save-Config {
    $script:config.pairs = @($script:pairs.ToArray())
    $json = $script:config | ConvertTo-Json -Depth 5
    Set-Content -LiteralPath $script:configPath -Value $json -Encoding UTF8
}

# ---------------------------------------------------------------- 폴더 쌍 입력 창
function Show-PairDialog {
    param($ExistingPair)   # $null 이면 새로 추가

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = if ($ExistingPair) { '폴더 쌍 수정' } else { '폴더 쌍 추가' }
    $dlg.Size            = New-Object System.Drawing.Size(560, 220)
    $dlg.StartPosition   = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox     = $false
    $dlg.MinimizeBox     = $false

    $lblName = New-Object System.Windows.Forms.Label
    $lblName.Text = '이름'
    $lblName.Location = New-Object System.Drawing.Point(15, 18)
    $lblName.AutoSize = $true

    $txtName = New-Object System.Windows.Forms.TextBox
    $txtName.Location = New-Object System.Drawing.Point(95, 15)
    $txtName.Size = New-Object System.Drawing.Size(340, 23)

    $lblSrc = New-Object System.Windows.Forms.Label
    $lblSrc.Text = '원본 폴더'
    $lblSrc.Location = New-Object System.Drawing.Point(15, 53)
    $lblSrc.AutoSize = $true

    $txtSrc = New-Object System.Windows.Forms.TextBox
    $txtSrc.Location = New-Object System.Drawing.Point(95, 50)
    $txtSrc.Size = New-Object System.Drawing.Size(340, 23)

    $btnSrc = New-Object System.Windows.Forms.Button
    $btnSrc.Text = '찾아보기...'
    $btnSrc.Location = New-Object System.Drawing.Point(445, 49)
    $btnSrc.Size = New-Object System.Drawing.Size(85, 25)

    $lblDst = New-Object System.Windows.Forms.Label
    $lblDst.Text = '백업 폴더'
    $lblDst.Location = New-Object System.Drawing.Point(15, 88)
    $lblDst.AutoSize = $true

    $txtDst = New-Object System.Windows.Forms.TextBox
    $txtDst.Location = New-Object System.Drawing.Point(95, 85)
    $txtDst.Size = New-Object System.Drawing.Size(340, 23)

    $btnDst = New-Object System.Windows.Forms.Button
    $btnDst.Text = '찾아보기...'
    $btnDst.Location = New-Object System.Drawing.Point(445, 84)
    $btnDst.Size = New-Object System.Drawing.Size(85, 25)

    $pickFolder = {
        param($textBox)
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        if ($textBox.Text -and (Test-Path -LiteralPath $textBox.Text)) {
            $fbd.SelectedPath = $textBox.Text
        }
        if ($fbd.ShowDialog($dlg) -eq [System.Windows.Forms.DialogResult]::OK) {
            $textBox.Text = $fbd.SelectedPath
        }
    }
    $btnSrc.Add_Click({ & $pickFolder $txtSrc })
    $btnDst.Add_Click({ & $pickFolder $txtDst })

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = '확인'
    $btnOk.Location = New-Object System.Drawing.Point(350, 130)
    $btnOk.Size = New-Object System.Drawing.Size(85, 28)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = '취소'
    $btnCancel.Location = New-Object System.Drawing.Point(445, 130)
    $btnCancel.Size = New-Object System.Drawing.Size(85, 28)
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $btnOk.Add_Click({
        if (-not $txtName.Text.Trim() -or -not $txtSrc.Text.Trim() -or -not $txtDst.Text.Trim()) {
            [System.Windows.Forms.MessageBox]::Show($dlg, '이름, 원본 폴더, 백업 폴더를 모두 입력하세요.', 'backup2ecm',
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
        if ($txtSrc.Text.Trim() -eq $txtDst.Text.Trim()) {
            [System.Windows.Forms.MessageBox]::Show($dlg, '원본 폴더와 백업 폴더가 같습니다.', 'backup2ecm',
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
        $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $dlg.Close()
    })

    $dlg.Controls.AddRange(@($lblName, $txtName, $lblSrc, $txtSrc, $btnSrc, $lblDst, $txtDst, $btnDst, $btnOk, $btnCancel))
    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnCancel

    if ($ExistingPair) {
        $txtName.Text = $ExistingPair.name
        $txtSrc.Text  = $ExistingPair.source
        $txtDst.Text  = $ExistingPair.ecm
    }

    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return [pscustomobject]@{
            name    = $txtName.Text.Trim()
            enabled = $true
            source  = $txtSrc.Text.Trim()
            ecm     = $txtDst.Text.Trim()
        }
    }
    return $null
}

# ---------------------------------------------------------------- 메인 창
$form = New-Object System.Windows.Forms.Form
$form.Text          = 'Backup2ECM - 폴더 백업'
$form.Size          = New-Object System.Drawing.Size(820, 480)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize   = New-Object System.Drawing.Size(700, 380)

$list = New-Object System.Windows.Forms.ListView
$list.View          = 'Details'
$list.FullRowSelect = $true
$list.GridLines     = $true
$list.MultiSelect   = $false
$list.HideSelection = $false
$list.Location      = New-Object System.Drawing.Point(12, 12)
$list.Size          = New-Object System.Drawing.Size(780, 330)
$list.Anchor        = 'Top,Left,Right,Bottom'
[void]$list.Columns.Add('이름', 130)
[void]$list.Columns.Add('원본 폴더', 310)
[void]$list.Columns.Add('백업 폴더', 310)

function Refresh-List {
    $list.Items.Clear()
    foreach ($p in $script:pairs) {
        $item = New-Object System.Windows.Forms.ListViewItem([string]$p.name)
        [void]$item.SubItems.Add([string]$p.source)
        [void]$item.SubItems.Add([string]$p.ecm)
        [void]$list.Items.Add($item)
    }
}

function Get-SelectedIndex {
    if ($list.SelectedIndices.Count -gt 0) { return $list.SelectedIndices[0] }
    return -1
}

# --- 버튼들
function New-Btn {
    param([string]$Text, [int]$X, [int]$Width = 95, [string]$Anchor = 'Bottom,Left')
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Size = New-Object System.Drawing.Size($Width, 32)
    $b.Location = New-Object System.Drawing.Point($X, 352)
    $b.Anchor = $Anchor
    return $b
}

$btnAdd    = New-Btn '추가'   12
$btnEdit   = New-Btn '수정'   112
$btnDel    = New-Btn '삭제'   212
$btnDry    = New-Btn '미리보기' 452 105 'Bottom,Right'
$btnPull   = New-Btn '받아오기' 567 105 'Bottom,Right'
$btnBackup = New-Btn '백업 실행' 682 110 'Bottom,Right'
$btnBackup.Font = New-Object System.Drawing.Font($btnBackup.Font, [System.Drawing.FontStyle]::Bold)

$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Text = '실행 버튼: 목록에서 선택한 항목만 실행, 선택하지 않으면 전체 실행됩니다. (백업: 원본→백업폴더 / 받아오기: 백업폴더→원본)'
$lblHint.Location = New-Object System.Drawing.Point(12, 396)
$lblHint.Size = New-Object System.Drawing.Size(780, 30)
$lblHint.Anchor = 'Bottom,Left,Right'
$lblHint.ForeColor = [System.Drawing.Color]::DimGray

$btnAdd.Add_Click({
    $new = Show-PairDialog $null
    if ($new) {
        [void]$script:pairs.Add($new)
        Save-Config
        Refresh-List
    }
})

$editSelected = {
    $i = Get-SelectedIndex
    if ($i -lt 0) {
        [System.Windows.Forms.MessageBox]::Show($form, '수정할 항목을 먼저 선택하세요.', 'backup2ecm') | Out-Null
        return
    }
    $updated = Show-PairDialog $script:pairs[$i]
    if ($updated) {
        $script:pairs[$i] = $updated
        Save-Config
        Refresh-List
    }
}
$btnEdit.Add_Click($editSelected)
$list.Add_DoubleClick($editSelected)

$btnDel.Add_Click({
    $i = Get-SelectedIndex
    if ($i -lt 0) {
        [System.Windows.Forms.MessageBox]::Show($form, '삭제할 항목을 먼저 선택하세요.', 'backup2ecm') | Out-Null
        return
    }
    $name = $script:pairs[$i].name
    $answer = [System.Windows.Forms.MessageBox]::Show($form, "'$name' 항목을 목록에서 삭제할까요?`r`n(실제 폴더/파일은 삭제되지 않습니다)", 'backup2ecm',
        [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
        $script:pairs.RemoveAt($i)
        Save-Config
        Refresh-List
    }
})

# --- 실행 (새 PowerShell 창에서 진행 상황을 보여줌)
function Run-Engine {
    param([string]$Mode, [switch]$DryRun)

    if ($script:pairs.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show($form, "먼저 '추가' 버튼으로 폴더 쌍을 등록하세요.", 'backup2ecm') | Out-Null
        return
    }
    Save-Config

    $i = Get-SelectedIndex
    $pairArg = ''
    if ($i -ge 0) {
        $pairArg = " -PairName '{0}'" -f ($script:pairs[$i].name -replace "'", "''")
    }
    $dryArg = if ($DryRun) { ' -DryRun' } else { '' }
    $engine = $script:enginePath -replace "'", "''"

    # 엔진에서 오류가 나도 창이 바로 닫히지 않고 오류 내용을 보여주도록 try/catch 로 감쌈
    $cmd = "try { & '$engine' -Mode $Mode$pairArg$dryArg } " +
           "catch { Write-Host ''; Write-Host ('오류가 발생했습니다: ' + `$_) -ForegroundColor Red }; " +
           "Write-Host ''; Read-Host '작업이 끝났습니다. Enter 키를 누르면 창이 닫힙니다'"

    Start-Process powershell.exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $cmd)
}

$btnBackup.Add_Click({ Run-Engine -Mode backup })
$btnPull.Add_Click({ Run-Engine -Mode restore })
$btnDry.Add_Click({ Run-Engine -Mode backup -DryRun })

$form.Controls.AddRange(@($list, $btnAdd, $btnEdit, $btnDel, $btnDry, $btnPull, $btnBackup, $lblHint))

Refresh-List
[void]$form.ShowDialog()

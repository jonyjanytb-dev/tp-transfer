<#
  一键安装 Agent Bridge
  1) 装 Node 22 (若需要)
  2) 装 PI CLI (官方 installer)
  3) 装 Git for Windows (PI 的 bash 工具需要)
  4) 从 GitHub 拉 tp-transfer 仓库
  5) 提示如何启动 worker
#>
$ErrorActionPreference='Continue'
function Step($n){ Write-Host "`n=== $n ===" -ForegroundColor Cyan }

Step "1/4 检查 Node"
$nodeOk = $false
try {
  $v = (& node -v) 2>$null
  if ($v -match 'v(\d+)\.(\d+)') {
    $maj=[int]$Matches[1]; $min=[int]$Matches[2]
    if ($maj -gt 22 -or ($maj -eq 22 -and $min -ge 19)) { $nodeOk=$true; Write-Host "  Node $v 满足要求" -ForegroundColor Green }
  }
} catch {}
if (-not $nodeOk) {
  Write-Host "  安装 Node 22.19.0 ..." -ForegroundColor Yellow
  [Net.ServicePointManager]::SecurityProtocol='Tls12'
  $ProgressPreference='SilentlyContinue'
  $u='https://nodejs.org/dist/v22.19.0/node-v22.19.0-x64.msi'
  $o="$env:TEMP\node22.msi"
  (New-Object Net.WebClient).DownloadFile($u,$o)
  Start-Process msiexec -ArgumentList "/i `"$o`" /qn /norestart" -Wait
  $env:PATH = "C:\Program Files\nodejs;$env:PATH"
  Write-Host "  Node 安装完成: $((& 'C:\Program Files\nodejs\node.exe' -v) 2>&1)" -ForegroundColor Green
}

Step "2/4 安装 PI CLI"
$piCmd = $null
try { $piCmd = (Get-Command pi -ErrorAction Stop).Source } catch {}
if ($piCmd) {
  Write-Host "  PI 已安装: $piCmd" -ForegroundColor Green
} else {
  Write-Host "  用官方 installer 安装 ..." -ForegroundColor Yellow
  try {
    Invoke-RestMethod https://pi.dev/install.ps1 | Invoke-Expression
  } catch {
    Write-Host "  installer 失败，回退 npm ..." -ForegroundColor Yellow
    & 'C:\Program Files\nodejs\npm.cmd' install -g --ignore-scripts @earendil-works/pi-coding-agent
  }
  $env:PATH = "C:\Program Files\nodejs;$env:APPDATA\npm;$env:PATH"
}
try { Write-Host "  pi --version: $(& pi --version 2>&1)" -ForegroundColor Green } catch { Write-Host "  pi 调用失败" -ForegroundColor Red }

Step "3/4 检查 Git Bash (PI 的 bash 工具依赖)"
$bashFound = $false
foreach ($p in @("C:\Program Files\Git\bin\bash.exe","C:\Program Files (x86)\Git\bin\bash.exe")) {
  if (Test-Path $p) { $bashFound=$true; Write-Host "  找到: $p" -ForegroundColor Green }
}
if (-not $bashFound) {
  try { $b=(Get-Command bash -ErrorAction Stop); $bashFound=$true; Write-Host "  PATH 中: $($b.Source)" -ForegroundColor Green } catch {}
}
if (-not $bashFound) {
  Write-Host "  未找到 bash，安装 Git for Windows ..." -ForegroundColor Yellow
  [Net.ServicePointManager]::SecurityProtocol='Tls12'
  $gu='https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/Git-2.47.1-64-bit.exe'
  $go="$env:TEMP\git-setup.exe"
  try {
    (New-Object Net.WebClient).DownloadFile($gu,$go)
    Start-Process $go -ArgumentList "/VERYSILENT /NORESTART /NOCANCEL" -Wait
    Write-Host "  Git 安装完成" -ForegroundColor Green
  } catch { Write-Host "  [FAIL] Git 安装: $_" -ForegroundColor Red }
}

Step "4/4 拉取传输仓库"
$TP = "$env:USERPROFILE\tp-transfer"
if (Test-Path "$TP\from-mac\worker.ps1") {
  Write-Host "  已存在: $TP" -ForegroundColor Green
  Push-Location $TP; & git pull 2>&1 | Out-Null; Pop-Location
} else {
  try {
    & git clone --depth 1 https://github.com/jonyjanytb-dev/tp-transfer.git $TP 2>&1 | Out-Null
    Write-Host "  已克隆到 $TP" -ForegroundColor Green
  } catch {
    Write-Host "  git clone 失败，用 zip 下载 ..." -ForegroundColor Yellow
    [Net.ServicePointManager]::SecurityProtocol='Tls12'
    $z="$env:TEMP\tp.zip"
    (New-Object Net.WebClient).DownloadFile('https://github.com/jonyjanytb-dev/tp-transfer/archive/refs/heads/main.zip',$z)
    Expand-Archive $z $TP -Force
    $TP = "$TP\tp-transfer-main"
    Write-Host "  已解压到 $TP" -ForegroundColor Green
  }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " 安装完成" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "接下来："
Write-Host "  1) 设置 API Key 和模型 (二选一)"
Write-Host "     setx PI_API_KEY ""<你的key>"""
Write-Host "     setx PI_MODEL   ""deepseek/deepseek-chat"""
Write-Host "     或先跑一次 pi /login 交互式登录"
Write-Host ""
Write-Host "  2) 启动 worker:"
Write-Host "     cd $TP"
Write-Host "     powershell -ExecutionPolicy Bypass -File from-mac\worker.ps1"
Write-Host ""
Write-Host "  3) 单次测试:"
Write-Host "     powershell -ExecutionPolicy Bypass -File from-mac\worker.ps1 -Once"
Write-Host ""

@echo off
chcp 65001 >nul
setlocal
title PI CLI 安装 (Windows)
set "LOG=%~dp0PI_INSTALL.log"
echo === PI CLI Install %date% %time% === > "%LOG%"

echo [0] 现有环境 >> "%LOG%"
node -v >> "%LOG%" 2>&1
npm -v >> "%LOG%" 2>&1

echo. >> "%LOG%"
echo [1] 用 PowerShell 检测并安装 Node 22 >> "%LOG%"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Continue';" ^
  "function Log($m){ Add-Content -Path '%LOG%' -Value $m }" ^
  "$cur=$null;" ^
  "try { $cur=(& node -v 2>$null) } catch {}" ^
  "Log ('现有 node: ' + $cur);" ^
  "$need=$true;" ^
  "if ($cur -match 'v(\d+)\.(\d+)' ) {" ^
  "  $maj=[int]$Matches[1]; $min=[int]$Matches[2];" ^
  "  if ($maj -gt 22 -or ($maj -eq 22 -and $min -ge 19)) { $need=$false }" ^
  "}" ^
  "if ($need) {" ^
  "  Log '[i] 需要安装 Node 22.19+';" ^
  "  [Net.ServicePointManager]::SecurityProtocol='Tls12';" ^
  "  $ProgressPreference='SilentlyContinue';" ^
  "  $u='https://nodejs.org/dist/v22.19.0/node-v22.19.0-x64.msi';" ^
  "  $o=Join-Path $env:TEMP 'node22.msi';" ^
  "  try { (New-Object Net.WebClient).DownloadFile($u,$o); Log ('[OK] 下载 ' + $o) } catch { Log ('[FAIL] 下载: ' + $_) }" ^
  "  try { Start-Process msiexec -ArgumentList ('/i \"' + $o + '\" /qn /norestart') -Wait; Log '[OK] MSI 安装完成' } catch { Log ('[FAIL] 安装: ' + $_) }" ^
  "} else { Log '[OK] Node 版本已满足' }"

set "NPM=C:\Program Files\nodejs\npm.cmd"
if not exist "%NPM%" set "NPM=npm"

echo. >> "%LOG%"
echo [2] 安装 PI CLI >> "%LOG%"
call "%NPM%" install -g --ignore-scripts @earendil-works/pi-coding-agent >> "%LOG%" 2>&1
echo     退出码 %ERRORLEVEL% >> "%LOG%"

echo. >> "%LOG%"
echo [3] 校验 >> "%LOG%"
if exist "C:\Program Files\nodejs\pi.cmd" (
  echo [OK] C:\Program Files\nodejs\pi.cmd >> "%LOG%"
  call "C:\Program Files\nodejs\pi.cmd" --version >> "%LOG%" 2>&1
) else if exist "%APPDATA%\npm\pi.cmd" (
  echo [OK] %APPDATA%\npm\pi.cmd >> "%LOG%"
  call "%APPDATA%\npm\pi.cmd" --version >> "%LOG%" 2>&1
) else (
  echo [!] 未找到 pi.cmd >> "%LOG%"
  call "%NPM%" root -g >> "%LOG%" 2>&1
  dir /b "%APPDATA%\npm" >> "%LOG%" 2>&1
)

echo. >> "%LOG%"
echo [4] bash 工具依赖 >> "%LOG%"
where bash >> "%LOG%" 2>&1
if exist "C:\Program Files\Git\bin\bash.exe" echo [OK] Git Bash 存在 >> "%LOG%"

echo === DONE === >> "%LOG%"
type "%LOG%"

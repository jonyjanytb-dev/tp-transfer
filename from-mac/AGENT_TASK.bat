@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
title TurboPush Patch - Agent Task
set "LOG=%~dp0AGENT_RESULT.log"
echo === Agent Task %date% %time% === > "%LOG%"

set "ZIP=%~dp0TurboPush-patched-win-x64.zip"
set "TMP=%TEMP%\tp_agent"
set "OK=1"

echo [1] TurboPush 安装位置 >> "%LOG%"
for %%D in (
  "C:\Program Files\Turbo Push"
  "C:\Program Files (x86)\Turbo Push"
  "%LOCALAPPDATA%\Turbo Push"
  "%LOCALAPPDATA%\Programs\Turbo Push"
  "%USERPROFILE%\.TurboPush\bin"
) do (
  if exist "%%~D\turbopush.exe" (
    echo     FOUND %%~D >> "%LOG%"
    for %%F in ("%%~D\turbopush.exe" "%%~D\turbo_push_server.exe" "%%~D\turbo_push_kb.exe") do (
      if exist %%F for %%S in (%%F) do powershell -NoProfile -Command "$h=(Get-FileHash -Algorithm SHA256 '%%~S').Hash.ToLower(); Write-Output ('      %%~nxS  %%~zS  '+$h)" >> "%LOG%"
    )
  )
)

echo. >> "%LOG%"
echo [2] 关闭进程 >> "%LOG%"
taskkill /IM turbopush.exe /T /F >> "%LOG%" 2>&1
taskkill /IM turbo_push_server.exe /T /F >> "%LOG%" 2>&1
taskkill /IM turbo_push_kb.exe /T /F >> "%LOG%" 2>&1
ping -n 4 127.0.0.1 >nul

echo. >> "%LOG%"
echo [3] 解包补丁 >> "%LOG%"
rmdir /S /Q "%TMP%" 2>nul
mkdir "%TMP%" 2>nul
if not exist "%ZIP%" (
  echo     [FAIL] 找不到补丁包: %ZIP% >> "%LOG%"
  set "OK=0"
  goto :report
)
powershell -NoProfile -Command "Expand-Archive -Path '%ZIP%' -DestinationPath '%TMP%' -Force" >> "%LOG%" 2>&1

echo. >> "%LOG%"
echo [4] 部署 (替换 + 备份) >> "%LOG%"
for %%D in (
  "C:\Program Files\Turbo Push"
  "C:\Program Files (x86)\Turbo Push"
  "%LOCALAPPDATA%\Turbo Push"
  "%LOCALAPPDATA%\Programs\Turbo Push"
  "%USERPROFILE%\.TurboPush\bin"
) do (
  if exist "%%~D\turbopush.exe" (
    echo     --- %%~D >> "%LOG%"
    if not exist "%%~D\_orig_backup" mkdir "%%~D\_orig_backup"
    for %%F in (turbopush.exe turbo_push_server.exe turbo_push_kb.exe) do (
      if exist "%%~D\%%F" if not exist "%%~D\_orig_backup\%%F" copy /Y "%%~D\%%F" "%%~D\_orig_backup\%%F" >nul
    )
    for %%F in (turbopush.exe turbo_push_server.exe turbo_push_kb.exe) do (
      if exist "%TMP%\%%F" (
        copy /Y "%TMP%\%%F" "%%~D\%%F" >nul 2>&1
        if errorlevel 1 (echo         [FAIL] %%F >> "%LOG%") else (echo         [OK] %%F >> "%LOG%")
      )
    )
  )
)

echo. >> "%LOG%"
echo [5] 字节校验 >> "%LOG%"
for %%D in (
  "C:\Program Files\Turbo Push"
  "%LOCALAPPDATA%\Turbo Push"
) do (
  if exist "%%~D\turbopush.exe" (
    powershell -NoProfile -Command "$f='%%~D\turbopush.exe'; $fs=[IO.File]::OpenRead($f); $fs.Seek(1589488,'Begin')|Out-Null; $b=New-Object byte[] 6; $fs.Read($b,0,6)|Out-Null; $fs.Close(); $h=($b|ForEach-Object{$_.ToString('x2')}) -join ''; if($h -eq 'b801000000c3'){Write-Output '    [OK] GUI user_is_vip=恒真'}else{Write-Output ('    [!!] GUI 字节='+$h+' 期望=b801000000c3')}" >> "%LOG%"
    if exist "%%~D\turbo_push_server.exe" powershell -NoProfile -Command "$f='%%~D\turbo_push_server.exe'; $fs=[IO.File]::OpenRead($f); $fs.Seek(9684896,'Begin')|Out-Null; $b=New-Object byte[] 3; $fs.Read($b,0,3)|Out-Null; $fs.Close(); $h=($b|ForEach-Object{$_.ToString('x2')}) -join ''; if($h -eq '31c0c3'){Write-Output '    [OK] 后端 ExpiredCheck=恒否'}else{Write-Output ('    [!!] 后端字节='+$h+' 期望=31c0c3')}" >> "%LOG%"
  )
)

:report
echo. >> "%LOG%"
rmdir /S /Q "%TMP%" 2>nul
echo === DONE === >> "%LOG%"
type "%LOG%"

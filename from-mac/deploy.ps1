# TurboPush 补丁部署 - 云机侧执行
$ErrorActionPreference='Continue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$log  = Join-Path $root '..\to-mac\deploy-result.log'
function L($m){ Write-Host $m; Add-Content -Path $log -Value $m }

"=== TurboPush Deploy $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Set-Content $log

# 1. 定位安装
$dirs = @(
  "$env:ProgramFiles\Turbo Push",
  "${env:ProgramFiles(x86)}\Turbo Push",
  "$env:LOCALAPPDATA\Turbo Push",
  "$env:LOCALAPPDATA\Programs\Turbo Push",
  "$env:USERPROFILE\.TurboPush\bin"
) | Where-Object { Test-Path (Join-Path $_ 'turbopush.exe') }

L "[1] 找到 $($dirs.Count) 个安装位置:"
$dirs | ForEach-Object { L "    $_" }
if ($dirs.Count -eq 0) { L "[FAIL] 未找到 TurboPush"; exit 1 }

# 2. 备份原始哈希
L ""
L "[2] 原始哈希:"
foreach ($d in $dirs) {
  foreach ($f in @('turbopush.exe','turbo_push_server.exe')) {
    $p = Join-Path $d $f
    if (Test-Path $p) {
      $h = (Get-FileHash $p -Algorithm SHA256).Hash.ToLower()
      L ("    {0}\{1}  {2}" -f $d,$f,$h)
    }
  }
}

# 3. 关进程
L ""
L "[3] 关闭进程"
foreach ($n in @('turbopush.exe','turbo_push_server.exe','turbo_push_kb.exe')) {
  Stop-Process -Name ($n -replace '\.exe$','') -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 3

# 4. 解包补丁
L ""
L "[4] 解包补丁"
$tmp = Join-Path $env:TEMP ("tp_" + (Get-Random))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$zip = Join-Path $root 'patched-exes.zip'
if (-not (Test-Path $zip)) { L "[FAIL] 找不到 patched-exes.zip: $zip"; exit 1 }
Expand-Archive -Path $zip -DestinationPath $tmp -Force
L "    解包到 $tmp"
Get-ChildItem $tmp | ForEach-Object { L ("    " + $_.Name + "  " + $_.Length) }

# 5. 备份 + 替换
L ""
L "[5] 备份并替换"
foreach ($d in $dirs) {
  $bk = Join-Path $d '_orig_backup'
  if (-not (Test-Path $bk)) { New-Item -ItemType Directory -Path $bk -Force | Out-Null }
  foreach ($f in @('turbopush.exe','turbo_push_server.exe','turbo_push_kb.exe')) {
    $src = Join-Path $d $f
    if (Test-Path $src) {
      $bkf = Join-Path $bk $f
      if (-not (Test-Path $bkf)) { Copy-Item $src $bkf -Force }
    }
  }
  foreach ($f in @('turbopush.exe','turbo_push_server.exe')) {
    $new = Join-Path $tmp $f
    if (Test-Path $new) {
      try {
        Copy-Item $new (Join-Path $d $f) -Force -ErrorAction Stop
        L "    [OK] $d\$f"
      } catch {
        L "    [FAIL] $d\$f : $_"
      }
    }
  }
}

# 6. 字节校验
L ""
L "[6] 补丁字节校验"
foreach ($d in $dirs) {
  $g = Join-Path $d 'turbopush.exe'
  if (Test-Path $g) {
    $fs=[IO.File]::OpenRead($g); $fs.Seek(1589488,'Begin')|Out-Null
    $b=New-Object byte[] 6; $fs.Read($b,0,6)|Out-Null; $fs.Close()
    $h=($b|ForEach-Object{$_.ToString('x2')}) -join ''
    if ($h -eq 'b801000000c3') { L "    [OK] GUI user_is_vip   $d" }
    else { L "    [!!] GUI 字节=$h 期望=b801000000c3  $d" }
  }
  $s = Join-Path $d 'turbo_push_server.exe'
  if (Test-Path $s) {
    $fs=[IO.File]::OpenRead($s); $fs.Seek(9684896,'Begin')|Out-Null
    $b=New-Object byte[] 3; $fs.Read($b,0,3)|Out-Null; $fs.Close()
    $h=($b|ForEach-Object{$_.ToString('x2')}) -join ''
    if ($h -eq '31c0c3') { L "    [OK] 后端 ExpiredCheck   $d" }
    else { L "    [!!] 后端字节=$h 期望=31c0c3  $d" }
  }
}

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
L ""
"=== DONE ===" | Add-Content $log
L "结果已写入 to-mac\deploy-result.log"

<#
  PI Daemon - 云机侧长驻守护 (零认证版)
  轮询 GitHub inbox -> 投给 PI RPC -> 输出 POST 到 paste.rs
  用法: powershell -ExecutionPolicy Bypass -File pi-daemon.ps1
#>
param(
  [int]$Interval = 8,
  [string]$Repo = "jonyjanytb-dev/tp-transfer",
  [string]$WorkDir = "$env:USERPROFILE\tp-daemon",
  [switch]$Once
)

$ErrorActionPreference='Continue'
[Net.ServicePointManager]::SecurityProtocol='Tls12'
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
$LogFile = Join-Path $WorkDir 'daemon.log'
$StateFile = Join-Path $WorkDir 'state.json'
$OutFile = Join-Path $WorkDir 'outbox.jsonl'

function Log($m){
  $l="[$(Get-Date -Format 'HH:mm:ss')] $m"
  Write-Host $l
  Add-Content $LogFile $l
}

# --- 状态 ---
$state = @{ consumed = 0 }
if (Test-Path $StateFile) { try { $state = Get-Content $StateFile -Raw | ConvertFrom-Json } catch {} }

function SaveState { $state | ConvertTo-Json | Set-Content $StateFile -Encoding UTF8 }

# --- GitHub 读 ---
function GetInbox {
  try {
    $r = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/contents/from-mac/rpc/inbox.jsonl" `
         -Headers @{'User-Agent'='daemon';'Accept'='application/vnd.github.v3+json'} -TimeoutSec 25
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($r.content))
  } catch { return $null }
}

# --- paste.rs 上传 ---
function Publish($text) {
  try {
    $r = Invoke-WebRequest -Uri "https://paste.rs" -Method Post -Body $text `
         -ContentType "text/plain" -TimeoutSec 30 -UseBasicParsing
    return ($r.Content -replace '\s','')
  } catch {
    Log "  [!] publish 失败: $_"
    return $null
  }
}

Log "=== PI Daemon 启动 ==="
Log "主机: $env:COMPUTERNAME"
Log "仓库: $Repo   间隔: ${Interval}s"
Log "工作目录: $WorkDir"

# --- 检查 pi ---
$piOk = $false
try { $v = (& pi --version 2>&1); Log "pi: $v"; $piOk = $true } catch { Log "pi: [未找到]" }
$bashOk = $false
if (Test-Path "C:\Program Files\Git\bin\bash.exe") { $bashOk=$true; Log "bash: C:\Program Files\Git\bin\bash.exe" }
else { try { $b=(Get-Command bash -EA Stop).Source; $bashOk=$true; Log "bash: $b" } catch { Log "bash: [未找到]" } }

if (-not $piOk) {
  Log "[i] pi 未安装，尝试安装..."
  try { Invoke-RestMethod https://pi.dev/install.ps1 | Invoke-Expression; Log "[OK] pi 安装完成" }
  catch { Log "[FAIL] pi 安装: $_" }
}

# --- 启动 PI RPC ---
$piArgs = @()
$piArgs += '--mode','rpc','--no-session'
if ($env:PI_MODEL)   { $piArgs += '--model',$env:PI_MODEL }
if ($env:PI_API_KEY) { $piArgs += '--api-key',$env:PI_API_KEY }
$piArgs += '--tools','read,bash,edit,write,powershell'

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "cmd.exe"
$psi.Arguments = "/c pi " + ($piArgs -join ' ')
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.StandardOutputEncoding = [Text.Encoding]::UTF8
$psi.StandardErrorEncoding = [Text.Encoding]::UTF8

$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi
$proc.Start() | Out-Null
Log "[OK] PI RPC 已启动 pid=$($proc.Id)"

# 异步读 stdout（避免阻塞）
$outQueue = New-Object System.Collections.Queue
$outSync = [hashtable]::Synchronized(@{ q = New-Object System.Collections.ArrayList })
$stdoutHandler = {
  param($sender, $e)
  if ($e.Data) { $outSync.q.Add($e.Data) | Out-Null }
}
$stderrHandler = { param($sender,$e) if ($e.Data) { Add-Content $LogFile "  [pi-err] $($e.Data)" } }
$proc.add_OutputDataReceived($stdoutHandler)
$proc.add_ErrorDataReceived($stderrHandler)
$proc.BeginOutputReadLine()
$proc.BeginErrorReadLine()

# --- 主循环 ---
$inboxInit = $false
$round = 0
do {
  $round++
  try {
    $text = GetInbox
    if ($null -eq $text) { Log "[!] 读 inbox 失败"; Start-Sleep $Interval; continue }
    $lines = @($text -split "`n" | Where-Object { $_.Trim() })
    
    if (-not $inboxInit) {
      $state.consumed = $lines.Count
      SaveState
      $inboxInit = $true
      Log "inbox 初始化: $($lines.Count) 行"
    } elseif ($lines.Count -gt $state.consumed) {
      $fresh = $lines[$state.consumed..($lines.Count-1)]
      $state.consumed = $lines.Count
      SaveState
      Log "新命令 $($fresh.Count) 条"
      foreach ($ln in $fresh) {
        try { $cmd = $ln | ConvertFrom-Json } catch { Log "  [!] 非JSON"; continue }
        if ($cmd._to -and $cmd._to -ne $env:COMPUTERNAME) { Log "  跳过 _to=$($cmd._to)"; continue }
        $cmd.PSObject.Properties.Remove('_to')
        $json = $cmd | ConvertTo-Json -Compress -Depth 10
        Log "  -> PI: $($json.Substring(0,[Math]::Min(160,$json.Length)))"
        $proc.StandardInput.WriteLine($json)
        $proc.StandardInput.Flush()
      }
    }
    
    # 收集 PI 输出
    if ($outSync.q.Count -gt 0) {
      $batch = @($outSync.q); $outSync.q.Clear()
      $sb = New-Object Text.StringBuilder
      foreach ($l in $batch) {
        if (-not $l.Trim()) { continue }
        try { $rec = $l | ConvertFrom-Json } catch { continue }
        $rec | Add-Member -NotePropertyName _host -NotePropertyValue $env:COMPUTERNAME -Force
        [void]$sb.AppendLine(($rec | ConvertTo-Json -Compress -Depth 10))
        if ($rec.type -eq 'message_end') {
          $txt = ($rec.message.content | Where-Object {$_.type -eq 'text'} | ForEach-Object {$_.text}) -join ''
          Log "  <- PI: $($txt.Substring(0,[Math]::Min(200,$txt.Length)))"
        } elseif ($rec.type -eq 'agent_settled') { Log "  <- settled" }
      }
      if ($sb.Length -gt 0) {
        Add-Content $OutFile $sb.ToString()
        $url = Publish $sb.ToString()
        if ($url) { Log "  [UP] $url"; Add-Content (Join-Path $WorkDir 'published.txt') "$(Get-Date -Format o) $url" }
      }
    }
  } catch { Log "[!] 循环异常: $_" }
  
  if ($Once) { break }
  Start-Sleep $Interval
} while ($true)

Log "=== 退出 ==="
try { $proc.Kill() } catch {}

<#
  TurboPush Agent Bridge - 云机侧轮询守护
  职责: 轮询 GitHub 仓库 from-mac/tasks/ 取任务 -> 调 PI CLI 执行 -> 结果推回 to-mac/results/
  用法: powershell -ExecutionPolicy Bypass -File worker.ps1
        powershell -ExecutionPolicy Bypass -File worker.ps1 -Once      # 只跑一轮
        powershell -ExecutionPolicy Bypass -File worker.ps1 -Interval 30
#>
param(
  [int]$Interval = 20,
  [switch]$Once,
  [string]$Repo = "jonyjanytb-dev/tp-transfer",
  [string]$WorkDir = "$env:USERPROFILE\tp-agent-work",
  [string]$ApiKey = $env:PI_API_KEY,
  [string]$Model  = $env:PI_MODEL,
  [string]$GhToken = $env:GH_TOKEN
)

$ErrorActionPreference = 'Continue'
$LogFile = Join-Path $WorkDir "worker.log"
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $WorkDir "done") -Force | Out-Null

function Log($m) {
  $line = "[$(Get-Date -Format 'HH:mm:ss')] $m"
  Write-Host $line
  Add-Content -Path $LogFile -Value $line
}

# GitHub API 读取（public 仓库免认证）
function GHGet($path) {
  $u = "https://api.github.com/repos/$Repo/contents/$path"
  try {
    return Invoke-RestMethod -Uri $u -Headers @{ 'User-Agent'='tp-agent'; 'Accept'='application/vnd.github.v3+json' } -TimeoutSec 30
  } catch { return $null }
}

function GHGetRaw($path) {
  $u = "https://raw.githubusercontent.com/$Repo/main/$path"
  try {
    return Invoke-RestMethod -Uri $u -Headers @{ 'User-Agent'='tp-agent' } -TimeoutSec 30
  } catch { return $null }
}

# 用 GitHub API 把结果写回仓库
function GHPut($path, $content, $message) {
  if (-not $GhToken) { return $false }
  $u = "https://api.github.com/repos/$Repo/contents/$path"
  $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($content))
  # 先查是否已存在（需要 sha 才能更新）
  $sha = $null
  try {
    $cur = Invoke-RestMethod -Uri $u -Headers @{ 'User-Agent'='tp-agent'; 'Authorization'="Bearer $GhToken" } -TimeoutSec 30
    $sha = $cur.sha
  } catch {}
  $body = @{ message = $message; content = $b64 }
  if ($sha) { $body.sha = $sha }
  try {
    Invoke-RestMethod -Uri $u -Method Put -Headers @{
      'User-Agent'='tp-agent'; 'Authorization'="Bearer $GhToken"
      'Accept'='application/vnd.github.v3+json'
    } -Body ($body | ConvertTo-Json) -ContentType 'application/json' -TimeoutSec 60 | Out-Null
    return $true
  } catch {
    Log "  [FAIL] 回传失败: $_"
    return $false
  }
}

Log "=== Agent Bridge 启动 ==="
Log "仓库: $Repo"
Log "工作目录: $WorkDir"

# 环境自检
Log "--- 环境 ---"
$node = (Get-Command node -ErrorAction SilentlyContinue)
if ($node) { Log "node: $((& node -v) 2>&1) @ $($node.Source)" } else { Log "node: [未找到]" }
$pi = (Get-Command pi -ErrorAction SilentlyContinue)
if ($pi) { Log "pi: $($pi.Source)" } else { Log "pi: [未找到]" }
$git = (Get-Command git -ErrorAction SilentlyContinue)
if ($git) { Log "git: $($git.Source)" } else { Log "git: [未找到]" }
$bash = (Get-Command bash -ErrorAction SilentlyContinue)
if ($bash) { Log "bash: $($bash.Source)" } else { Log "bash: [未找到] (PI 的 bash 工具需要)" }

if ($ApiKey) { Log "PI_API_KEY: 已设置 (${ApiKey:0:4}...)" } else { Log "PI_API_KEY: [未设置]" }
if ($Model)  { Log "PI_MODEL: $Model" }

if (-not $Once) { Log "模式: 持续轮询 (间隔 ${Interval}s)" } else { Log "模式: 单次执行" }

$round = 0
do {
  $round++
  Log "--- 第 $round 轮 ---"

  # 拉任务清单
  $tasks = GHGet "from-mac/tasks"
  if ($null -eq $tasks) {
    Log "无法获取任务列表 (网络或路径问题)"
  } else {
    $pending = @($tasks | Where-Object { $_.type -eq 'file' -and $_.name -like '*.task' })
    Log "待处理任务: $($pending.Count)"

    foreach ($t in $pending) {
      $name = $t.name
      $doneMark = Join-Path $WorkDir "done\$name"
      if (Test-Path $doneMark) { Log "  跳过 (已完成): $name"; continue }

      Log "  >>> 执行任务: $name"
      $raw = GHGetRaw "from-mac/tasks/$name"
      if ($null -eq $raw) { Log "  [FAIL] 任务内容拉取失败"; continue }

      # 任务内容是 JSON: {"prompt":"...", "tools":"...", "timeout":600}
      try { $job = $raw | ConvertFrom-Json } catch { Log "  [FAIL] 任务 JSON 解析失败: $_"; continue }

      $prompt = $job.prompt
      $tools  = if ($job.tools)  { $job.tools }  else { "read,bash,edit,write,powershell" }
      $tmo    = if ($job.timeout) { [int]$job.timeout } else { 600 }

      Log "      prompt: $($prompt.Substring(0, [Math]::Min(120, $prompt.Length)))..."
      Log "      tools: $tools"

      # 组装 pi 命令
      $piArgs = @("-p", $prompt, "--tools", $tools, "--no-session")
      if ($ApiKey) { $piArgs += @("--api-key", $ApiKey) }
      if ($Model)  { $piArgs += @("--model", $Model) }

      $outFile = Join-Path $WorkDir "$name.out"
      $errFile = Join-Path $WorkDir "$name.err"
      $sw = [Diagnostics.Stopwatch]::StartNew()

      $proc = Start-Process -FilePath "pi" -ArgumentList $piArgs `
              -RedirectStandardOutput $outFile -RedirectStandardError $errFile `
              -NoNewWindow -PassThru
      $finished = $proc.WaitForExit($tmo * 1000)
      if (-not $finished) {
        Log "  [TIMEOUT] 超过 ${tmo}s，终止"
        try { $proc.Kill() } catch {}
      }
      $sw.Stop()
      Log "      退出码: $($proc.ExitCode)  耗时: $([int]$sw.Elapsed.TotalSeconds)s"

      $stdout = if (Test-Path $outFile) { Get-Content $outFile -Raw } else { "" }
      $stderr = if (Test-Path $errFile) { Get-Content $errFile -Raw } else { "" }

      # 写结果
      $result = [ordered]@{
        task       = $name
        host       = $env:COMPUTERNAME
        time       = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        elapsed_s  = [int]$sw.Elapsed.TotalSeconds
        exit_code  = $proc.ExitCode
        stdout     = $stdout
        stderr     = $stderr
      }
      $resultFile = Join-Path $WorkDir "$name.result.json"
      $json = $result | ConvertTo-Json -Depth 10
      $json | Set-Content $resultFile -Encoding UTF8
      Log "      结果 -> $resultFile"

      # 回传到 GitHub
      if ($GhToken) {
        $ok = GHPut "to-mac/results/$name.result.json" $json "result: $name"
        if ($ok) { Log "      [OK] 已回传 to-mac/results/$name.result.json" }
        else { Log "      [!!] 回传失败，结果保留在本地" }
      } else {
        Log "      [i] 未设置 GH_TOKEN，跳过回传（结果仅在本地）"
      }

      New-Item -ItemType File -Path $doneMark -Force | Out-Null
    }
  }

  if ($Once) { break }
  Start-Sleep -Seconds $Interval
} while ($true)

Log "=== 退出 ==="

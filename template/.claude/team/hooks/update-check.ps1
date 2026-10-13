# Karkas: checks GitHub for a newer kit version (at most once per 15 minutes; cached in between).
#   Hook mode:   update-check.ps1 -Hook -Event SessionStart|UserPromptSubmit   (reads hook JSON on stdin)
#   Plain mode:  update-check.ps1                                              (run by the heartbeat; prints one line or nothing)
# The owner is told once per new version (SessionStart always repeats the notice). Never updates anything itself.
param([switch]$Hook, [string]$Event = 'Heartbeat')
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Read-HookInput {
    $ms = New-Object System.IO.MemoryStream
    [Console]::OpenStandardInput().CopyTo($ms)
    return [System.Text.Encoding]::UTF8.GetString($ms.ToArray()).TrimStart([char]0xFEFF)
}
function Get-KarkasRoot([string]$start) {
    $d = $start
    while ($d) {
        if (Test-Path -LiteralPath (Join-Path $d '.claude\team\ORCHESTRATOR.md')) { return $d }
        $parent = Split-Path -Parent $d
        if (-not $parent -or $parent -eq $d) { break }
        $d = $parent
    }
    if ($env:CLAUDE_PROJECT_DIR) { return $env:CLAUDE_PROJECT_DIR }
    return $start
}

$cwd = (Get-Location).Path
if ($Hook) {
    try { $in = Read-HookInput | ConvertFrom-Json; if ($in.cwd) { $cwd = [string]$in.cwd } } catch { }
    if (-not $in -and $env:CLAUDE_PROJECT_DIR) { $cwd = $env:CLAUDE_PROJECT_DIR }
}
$root = Get-KarkasRoot $cwd
$manifestPath = Join-Path $root '.claude\team\kit-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) { exit 0 }
try { $m = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json } catch { exit 0 }
$installed = [string]$m.version; $repo = [string]$m.repo
if (-not $installed -or $repo -notmatch '^https://github\.com/([^/]+)/([^/]+)$') { exit 0 }
$rawUrl = if ($env:KARKAS_VERSION_URL) { $env:KARKAS_VERSION_URL } else { "https://raw.githubusercontent.com/$($Matches[1])/$($Matches[2])/main/VERSION" }

$stateDir = Join-Path $root '.claude\team\state'
$cachePath = Join-Path $stateDir 'update-check.json'
$cache = $null
if (Test-Path -LiteralPath $cachePath) { try { $cache = [IO.File]::ReadAllText($cachePath) | ConvertFrom-Json } catch { $cache = $null } }
$latest = if ($cache) { [string]$cache.latest } else { '' }
$notified = if ($cache) { [string]$cache.notified } else { '' }
$checked = if ($cache -and $cache.checked) { [datetime]$cache.checked } else { [datetime]::MinValue }

if (((Get-Date) - $checked).TotalMinutes -ge 15) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        if ($rawUrl -like 'file:*') { $v = ([IO.File]::ReadAllText(([Uri]$rawUrl).LocalPath)).Trim() }
        else { $v = ([string](Invoke-WebRequest -Uri $rawUrl -UseBasicParsing -TimeoutSec 4).Content).Trim() }
        if ($v -match '^\d+(\.\d+){1,3}$') { $latest = $v }
    } catch { }
    $checked = Get-Date
}

$isNewer = $false
try { if ($latest) { $isNewer = ([version]$latest) -gt ([version]$installed) } } catch { }
$msg = ''
if ($isNewer -and ($Event -eq 'SessionStart' -or $notified -ne $latest)) {
    $msg = "KARKAS UPDATE: kit version $latest is available on GitHub ($repo); this project has $installed. Tell the owner once, briefly and in Russian, and offer to update ('обнови каркас' — follow the kit README steps: analysis, plan, owner's 'да', then -Update). Do not update without the owner's 'да'."
    $notified = $latest
}

New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
[IO.File]::WriteAllText($cachePath, ([ordered]@{ checked = $checked.ToString('s'); installed = $installed; latest = $latest; notified = $notified } | ConvertTo-Json), $utf8)

if ($msg) {
    if ($Hook) { @{ hookSpecificOutput = @{ hookEventName = $Event; additionalContext = $msg } } | ConvertTo-Json -Compress -Depth 4 }
    else { $msg }
}
exit 0

# Karkas: PreToolUse guard for paid / generative MCP tools.
# A paid call is allowed only if docs/knowledge/ holds a file whose header has
#   Covers: <regex matching the tool name and, if the call has one, its model>
#   Verified: YYYY-MM-DD   (not older than freshness_days, default 7)
# Free calls are never blocked. Broken config -> built-in defaults + warning (fail open on config).
# Any internal error while handling a matched paid tool -> deny (fail closed).
# Every allowed paid call is appended to .claude/team/state/paid-calls.log.
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

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
function Out-Json($obj) { $obj | ConvertTo-Json -Compress -Depth 6 }
function Deny([string]$reason) {
    Out-Json @{ hookSpecificOutput = @{ hookEventName = 'PreToolUse'; permissionDecision = 'deny'; permissionDecisionReason = $reason } }
    exit 0
}

$defaults = @{
    freshness_days = 7
    free = @('balance', 'models?_explore', 'get_cost', 'quote', '^list_', '^show_', '^get_', 'status', 'jobs_wait', 'job_display', '_options$', '_presets?$', '_settings$', 'transactions', '^media_confirm$', '^media_upload', '^media_import')
    paid = @('generate', 'upscale', 'remove_background', 'create_voice', 'voice_change', 'dubbing', 'execute_preset', 'motion_control', 'reframe', 'outpaint', 'build_ai_influencer', 'shorts_studio_create', 'video_analysis_create', 'virality_predictor')
}

# ---- input (unparseable input: we cannot know the tool -> no decision) ----
try { $in = Read-HookInput | ConvertFrom-Json } catch { exit 0 }
$tool = [string]$in.tool_name
if (-not $tool -or $tool -notlike 'mcp__*') { exit 0 }
$short = ($tool -split '__')[-1]

# ---- config (broken -> defaults + warning) ----
$warn = $null
$cwd = if ($in.cwd) { [string]$in.cwd } else { (Get-Location).Path }
$root = Get-KarkasRoot $cwd
$cfg = @{ freshness_days = $defaults.freshness_days; free = @($defaults.free); paid = @($defaults.paid) }
foreach ($name in @('paid-tools.json', 'paid-tools.local.json')) {
    $path = Join-Path $root ".claude\team\$name"
    if (-not (Test-Path -LiteralPath $path)) { continue }
    try {
        $j = [IO.File]::ReadAllText($path) | ConvertFrom-Json
        if ($name -eq 'paid-tools.json') {
            if ($j.free) { $cfg.free = @($j.free) }
            if ($j.paid) { $cfg.paid = @($j.paid) }
        } else {
            if ($j.free) { $cfg.free += @($j.free) }
            if ($j.paid) { $cfg.paid += @($j.paid) }
        }
        if ($j.freshness_days) { $cfg.freshness_days = [int]$j.freshness_days }
    } catch { $warn = "Karkas paid-guard: $name is broken ($($_.Exception.Message)); using built-in defaults." }
}

function Test-Any([string]$text, $patterns) {
    foreach ($p in $patterns) { try { if ($text -match "(?i)$p") { return $true } } catch { } }
    return $false
}

if ((Test-Any $short $cfg.free) -or -not (Test-Any $short $cfg.paid)) {
    if ($warn) { Out-Json @{ systemMessage = $warn } }
    exit 0
}

# ---- matched paid tool: from here on any error denies (fail closed) ----
try {
    $model = ''
    foreach ($k in @('model', 'model_id', 'modelId', 'model_name')) {
        if ($in.tool_input -and $in.tool_input.PSObject.Properties.Name -contains $k -and $in.tool_input.$k) { $model = [string]$in.tool_input.$k; break }
    }
    $kdir = Join-Path $root 'docs\knowledge'
    $today = (Get-Date).Date
    $found = $null; $stale = @(); $nomatch = 0
    if (Test-Path -LiteralPath $kdir) {
        foreach ($f in Get-ChildItem -LiteralPath $kdir -Filter *.md -File) {
            $head = @(Get-Content -LiteralPath $f.FullName -Encoding UTF8 -TotalCount 40)
            $covers = ($head | Where-Object { $_ -match '^\s*Covers:\s*(.+?)\s*$' } | Select-Object -First 1)
            if (-not $covers) { continue }
            $rx = ([regex]::Match($covers, '^\s*Covers:\s*(.+?)\s*$')).Groups[1].Value
            $ok = $false
            try { $ok = ($short -match "(?i)$rx") -and ((-not $model) -or ($model -match "(?i)$rx")) } catch { $ok = $false }
            if (-not $ok) { $nomatch++; continue }
            $ver = ($head | Where-Object { $_ -match '^\s*Verified:\s*(\d{4}-\d{2}-\d{2})' } | Select-Object -First 1)
            if (-not $ver) { $stale += "$($f.Name) (no Verified date)"; continue }
            $d = [datetime]::ParseExact(([regex]::Match($ver, '\d{4}-\d{2}-\d{2}')).Value, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
            if (($today - $d).TotalDays -gt $cfg.freshness_days) { $stale += "$($f.Name) (Verified $($d.ToString('yyyy-MM-dd')))"; continue }
            $found = $f; break
        }
    }
    if (-not $found) {
        $what = if ($model) { "tool '$short' with model '$model'" } else { "tool '$short'" }
        $detail = if ($stale.Count) { " Matching but outdated: $($stale -join '; ')." } else { '' }
        Deny ("Karkas paid-guard: paid call blocked. Study the official documentation of the $what first (how to prompt it, parameters, limits, prices), then save docs/knowledge/<topic>.md with a header containing 'Covers: <regex matching the tool name and the model>' and 'Verified: YYYY-MM-DD' (not older than $($cfg.freshness_days) days), and retry.$detail")
    }
    $stateDir = Join-Path $root '.claude\team\state'
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    $agent = if ($in.agent_type) { [string]$in.agent_type } else { 'main' }
    $line = "{0}`t{1}`t{2}`t{3}`t{4}" -f (Get-Date -Format 's'), $tool, $(if ($model) { $model } else { '-' }), $agent, $found.Name
    [IO.File]::AppendAllText((Join-Path $stateDir 'paid-calls.log'), $line + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
    if ($warn) { Out-Json @{ systemMessage = $warn } }
    exit 0
} catch {
    Deny ("Karkas paid-guard: internal error while checking a paid call ($($_.Exception.Message)); the call is blocked for safety. Fix the knowledge file or the guard config and retry.")
}

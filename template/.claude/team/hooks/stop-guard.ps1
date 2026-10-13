# Karkas: Stop hook. Keeps the orchestrator working while there is unblocked work,
# and makes sure the 5-minute heartbeat exists in the session.
# Rules: never loops (respects stop_hook_active), never blocks while background agents run.
$ErrorActionPreference = 'SilentlyContinue'
# Project root = the folder of the CURRENT session (worktree-safe): walk up from cwd to the folder
# that contains .claude\team\ORCHESTRATOR.md. CLAUDE_PROJECT_DIR points to the main checkout even
# inside a worktree, so it is only a fallback.
function Get-KarkasRoot($hookInput) {
    if ($hookInput -and $hookInput.cwd) { $d = [string]$hookInput.cwd }
    elseif ($env:CLAUDE_PROJECT_DIR) { return $env:CLAUDE_PROJECT_DIR }
    else { $d = (Get-Location).Path }
    $start = $d
    while ($d) {
        if (Test-Path -LiteralPath (Join-Path $d '.claude\team\ORCHESTRATOR.md')) { return $d }
        $parent = Split-Path -Parent $d
        if (-not $parent -or $parent -eq $d) { break }
        $d = $parent
    }
    if ($env:CLAUDE_PROJECT_DIR) { return $env:CLAUDE_PROJECT_DIR }
    return $start
}
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

$raw = [Console]::In.ReadToEnd()
try { $in = $raw | ConvertFrom-Json } catch { exit 0 }
if ($in.stop_hook_active) { exit 0 }

$root = Get-KarkasRoot $in
$reasons = @()

# 1. Heartbeat must exist (only checkable when the harness passes session_crons)
if ($in.PSObject.Properties.Name -contains 'session_crons') {
    $crons = [string](ConvertTo-Json -InputObject @($in.session_crons) -Depth 6 -Compress)
    if (-not $crons.Contains('KARKAS HEARTBEAT')) {
        $reasons += 'No KARKAS HEARTBEAT cron in this session: create it now as described in ORCHESTRATOR.md section "Continuous work" (CronCreate, every 5 minutes).'
    }
}

# 2. Unblocked tasks in docs/project/TASKS.md (skip while background agents are running)
$bg = @($in.background_tasks).Where({ $_ -ne $null }).Count
$tasksFile = Join-Path $root 'docs\project\TASKS.md'
if ($bg -eq 0 -and (Test-Path -LiteralPath $tasksFile)) {
    $activeStatuses = 'Готова к выполнению|Выполняется|Требует доработки|Ожидает проверки'
    $rows = Get-Content -LiteralPath $tasksFile -Encoding UTF8 |
        Where-Object { $_ -match '^\|\s*T-\d+' -and $_ -match "\|\s*($activeStatuses)\s*\|" }
    if ($rows) {
        $ids = ($rows | ForEach-Object { ($_ -split '\|')[1].Trim() }) -join ', '
        $reasons += "Unblocked tasks in docs/project/TASKS.md: $ids. Continue them now (delegate, verify, integrate). If a task actually waits for the owner, set its status to 'Ждёт решения владельца'; if it runs in a background agent, set 'Выполняется в фоне'; then you may stop."
    }
}

if ($reasons.Count -gt 0) {
    @{ decision = 'block'; reason = ($reasons -join ' ') } | ConvertTo-Json -Compress
}
exit 0

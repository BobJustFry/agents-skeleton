# Karkas: Stop hook. Keeps the orchestrator working while there is unblocked work,
# and makes sure the 5-minute heartbeat exists in the session.
# Rules: never loops (respects stop_hook_active), never blocks while background agents run.
$ErrorActionPreference = 'SilentlyContinue'
# stdin from Claude Code is UTF-8; PowerShell 5.1 would decode it with the OEM code page (866) and break Cyrillic paths.
function Read-HookInput {
    $ms = New-Object System.IO.MemoryStream
    [Console]::OpenStandardInput().CopyTo($ms)
    return [System.Text.Encoding]::UTF8.GetString($ms.ToArray()).TrimStart([char]0xFEFF)
}
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

function Get-ActiveTaskIds([string]$root) {
    $f = Join-Path $root 'docs\project\TASKS.md'
    if (-not (Test-Path -LiteralPath $f)) { return @() }
    $active = 'Готова к выполнению|Выполняется|Требует доработки|Ожидает проверки'
    return @(Get-Content -LiteralPath $f -Encoding UTF8 |
        Where-Object { $_ -match '^\|\s*T-\d+' -and $_ -match "\|\s*($active)\s*\|" } |
        ForEach-Object { ($_ -split '\|')[1].Trim() })
}
$raw = Read-HookInput
try { $in = $raw | ConvertFrom-Json } catch { exit 0 }
if ($in.stop_hook_active) { exit 0 }

$root = Get-KarkasRoot $in
$reasons = @()

$ids = Get-ActiveTaskIds $root

# 1. While there is active work, the heartbeat must exist (only checkable when the harness passes session_crons)
$heartbeatOff = Test-Path -LiteralPath (Join-Path $root '.claude\team\state\heartbeat-off')
if ($ids.Count -gt 0 -and -not $heartbeatOff -and $in.PSObject.Properties.Name -contains 'session_crons') {
    $crons = [string](ConvertTo-Json -InputObject @($in.session_crons) -Depth 6 -Compress)
    if (-not $crons.Contains('KARKAS HEARTBEAT')) {
        $reasons += 'There is active work but no KARKAS HEARTBEAT cron in this session: create it now as described in ORCHESTRATOR.md section 2.1 (CronCreate, every 5 minutes).'
    }
}

# 2. Unblocked tasks (skipped while background agents/workflows run; shell tasks such as dev servers do not count)
$bg = @(@($in.background_tasks) | Where-Object { $_ -and ((ConvertTo-Json -InputObject $_ -Depth 4 -Compress) -match '(?i)agent|workflow') }).Count
if ($bg -eq 0 -and $ids.Count -gt 0) {
    $reasons += "Unblocked tasks in docs/project/TASKS.md: $($ids -join ', '). Continue them now (delegate, verify, integrate). If a task actually waits for the owner, set its status to 'Ждёт решения владельца'; if it runs in a background agent, set 'Выполняется в фоне'; then you may stop."
}

if ($reasons.Count -gt 0) {
    @{ decision = 'block'; reason = ($reasons -join ' ') } | ConvertTo-Json -Compress
}
exit 0

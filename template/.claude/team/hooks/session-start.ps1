# Karkas: SessionStart hook.
# - every start: reminds the orchestrator about the 5-minute heartbeat;
# - after compaction / resume / clear: re-injects key rules and the saved state (anti-amnesia).
# Output is phrased as facts (hook context is capped at 10,000 chars per string).
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
try { $in = $raw | ConvertFrom-Json } catch { $in = $null }
$source = if ($in -and $in.source) { [string]$in.source } else { 'startup' }
$root = Get-KarkasRoot $in
$today = Get-Date -Format 'yyyy-MM-dd'

$parts = @()
$heartbeatOff = Test-Path -LiteralPath (Join-Path $root '.claude\team\state\heartbeat-off')
if ($heartbeatOff) { $parts += "KARKAS: session event '$source', date $today. The heartbeat is switched off for this project (.claude/team/state/heartbeat-off exists); do not create it." } else {
$ids = Get-ActiveTaskIds $root
if ($ids.Count -gt 0) {
    $parts += "KARKAS: session event '$source', date $today. Active tasks: $($ids -join ', '). While there is active work the heartbeat is needed: a session cron named 'KARKAS HEARTBEAT' (CronCreate '2-59/5 * * * *', recurring, prompt text in ORCHESTRATOR.md section 2.1, created date $today); if CronList does not show it, it needs to be created silently."
} else {
    $parts += "KARKAS: session event '$source', date $today. No active tasks, so no heartbeat is needed now; it is created when active work appears (ORCHESTRATOR.md section 2.1) and removes itself when the work is done."
}
}

if ($source -ne 'startup') {
    $parts += @"
KARKAS CONTEXT RESTORE: the conversation history was compacted, resumed or cleared, so earlier details may be missing. Facts that still apply:
- You are the Chief Orchestrator; full rules are in .claude/team/ORCHESTRATOR.md (sections 1-5 and 13 hold the core rules; re-reading them now restores them exactly).
- Owner language: Russian only, brief, no fluff. Agents and internal notes: English.
- Money: only within an owner-approved budget (whole task or stage). Disputed owner decisions: argue; comply only after OWNER OVERRIDE per section 1.6.
- Official docs must be verified within 7 days (docs/knowledge/).
- Working state lives in .claude/team/state/STATE.md; agent briefs in .claude/team/state/briefs/; agent checkpoints in .claude/team/state/progress/; compaction summaries in .claude/team/state/compactions/.
"@
    $stateFile = Join-Path $root '.claude\team\state\STATE.md'
    if (Test-Path -LiteralPath $stateFile) {
        $state = [IO.File]::ReadAllText($stateFile)
        $budget = 10000 - (($parts -join "`n").Length) - 200
        if ($state.Length -gt $budget) { $state = $state.Substring(0, [Math]::Max(0, $budget)) + "`n[STATE.md truncated - read the file for the rest]" }
        $parts += "Current STATE.md:`n$state"
    } else {
        $parts += 'No .claude/team/state/STATE.md exists yet.'
    }
}

$ctx = $parts -join "`n`n"
if ($ctx.Length -gt 9900) { $ctx = $ctx.Substring(0, 9900) }
@{ hookSpecificOutput = @{ hookEventName = 'SessionStart'; additionalContext = $ctx } } | ConvertTo-Json -Compress -Depth 4
exit 0

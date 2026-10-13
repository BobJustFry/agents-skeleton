# Karkas: SubagentStart hook. Gives every subagent the date and its anti-amnesia anchors.
$ErrorActionPreference = 'SilentlyContinue'
# stdin from Claude Code is UTF-8; PowerShell 5.1 would decode it with the OEM code page (866) and break Cyrillic paths.
function Read-HookInput {
    $ms = New-Object System.IO.MemoryStream
    [Console]::OpenStandardInput().CopyTo($ms)
    return [System.Text.Encoding]::UTF8.GetString($ms.ToArray()).TrimStart([char]0xFEFF)
}
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$raw = Read-HookInput
try { $in = $raw | ConvertFrom-Json } catch { $in = $null }
$today = Get-Date -Format 'yyyy-MM-dd'
$agent = if ($in -and $in.agent_type) { [string]$in.agent_type } else { 'subagent' }
$ctx = "KARKAS: today is $today (use it for the 7-day docs freshness check). Agent: $agent. Task briefs are saved in .claude/team/state/briefs/<task-id>.md and progress checkpoints in .claude/team/state/progress/<task-id>.md. If your conversation shows a compaction summary instead of full history, the brief file and your checkpoint file hold the exact task and progress."
@{ hookSpecificOutput = @{ hookEventName = 'SubagentStart'; additionalContext = $ctx } } | ConvertTo-Json -Compress -Depth 4
exit 0

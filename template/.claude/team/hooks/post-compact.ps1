# Karkas: PostCompact hook. Archives every compaction summary so nothing is lost for good.
# Keeps the latest 30 summaries in .claude/team/state/compactions/.
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
$raw = Read-HookInput
try { $in = $raw | ConvertFrom-Json } catch { exit 0 }
$root = Get-KarkasRoot $in
if (-not $root) { exit 0 }

$dir = Join-Path $root '.claude\team\state\compactions'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$trigger = [string]$in.trigger
$agent = if ($in.agent_type) { [string]$in.agent_type } else { 'main' }
$agent = $agent -replace '[\/:*?"<>|]', '_'
$body = "# Compaction $stamp`n`n- trigger: $trigger`n- agent: $agent`n- session: $($in.session_id)`n`n## Summary`n`n$([string]$in.compact_summary)`n"
[IO.File]::WriteAllText((Join-Path $dir "$stamp-$agent.md"), $body, (New-Object System.Text.UTF8Encoding($false)))

Get-ChildItem -LiteralPath $dir -Filter '*.md' | Sort-Object Name -Descending | Select-Object -Skip 30 | Remove-Item -Force
exit 0

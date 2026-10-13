# Karkas: PostCompact hook. Archives every compaction summary so nothing is lost for good.
# Keeps the latest 30 summaries in .claude/team/state/compactions/.
$ErrorActionPreference = 'SilentlyContinue'
$raw = [Console]::In.ReadToEnd()
try { $in = $raw | ConvertFrom-Json } catch { exit 0 }
$root = $env:CLAUDE_PROJECT_DIR
if (-not $root) { $root = $in.cwd }
if (-not $root) { exit 0 }

$dir = Join-Path $root '.claude\team\state\compactions'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$trigger = [string]$in.trigger
$agent = if ($in.agent_type) { [string]$in.agent_type } else { 'main' }
$body = "# Compaction $stamp`n`n- trigger: $trigger`n- agent: $agent`n- session: $($in.session_id)`n`n## Summary`n`n$([string]$in.compact_summary)`n"
[IO.File]::WriteAllText((Join-Path $dir "$stamp-$agent.md"), $body, (New-Object System.Text.UTF8Encoding($false)))

Get-ChildItem -LiteralPath $dir -Filter '*.md' | Sort-Object Name -Descending | Select-Object -Skip 30 | Remove-Item -Force
exit 0

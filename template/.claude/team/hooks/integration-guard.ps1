# Karkas: PreToolUse guard against redundant "integration" actions (full build / full test run / deploy / dependency update).
# Matcher: Bash|PowerShell. Such a command is allowed only while the coordinator keeps the gate open:
#   .claude/team/state/integration-gate   (lines: "B-3 build,test" = batch id + allowed classes, '*' or 'all' = every class;
#                                          owner-approved: YYYY-MM-DD "<quote of the owner's message or chat>"; open-tasks-reported: yes|none)
# A gate file without a valid owner-approved line is treated as CLOSED (logged as "gate without owner approval").
# Patterns live in .claude/team/integration-commands.json (+ optional integration-commands.local.json).
# Switch the whole guard off: create .claude/team/state/integration-guard-off.
# FAIL OPEN: any internal error, unparseable input or broken config -> no decision (the command goes on).
# Subagents may not create/edit/delete the gate or the off-switch (best effort: Bash/PowerShell write-like commands, Write/Edit tools).
# Every decision about an integration command is appended to .claude/team/state/integration-guard.log.
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

# ---- input (unparseable -> no decision) ----
try { $in = Read-HookInput | ConvertFrom-Json } catch { exit 0 }
$tool = [string]$in.tool_name
$isShell = ($tool -eq 'Bash' -or $tool -eq 'PowerShell')
$isEdit = ($tool -eq 'Write' -or $tool -eq 'Edit' -or $tool -eq 'MultiEdit')
if (-not ($isShell -or $isEdit)) { exit 0 }

try {
    $isSub = [bool]$in.agent_id
    $cwd = if ($in.cwd) { [string]$in.cwd } else { (Get-Location).Path }
    $root = $null

    # ---- subagents must not open the gate or switch the guard off ----
    if ($isSub) {
        $tamper = $false
        if ($isEdit) {
            $fp = [string]$in.tool_input.file_path
            $tamper = ($fp -match '(?i)integration-(gate|guard-off)')
        } else {
            $c0 = [string]$in.tool_input.command
            $tamper = ($c0 -match '(?i)integration-(gate|guard-off)') -and ($c0 -match '(?i)(>|\b(Set-Content|Add-Content|Out-File|New-Item|Remove-Item|Copy-Item|Move-Item|Rename-Item|tee|touch|cp|mv|rm|del|erase|copy|move|ren|echo|printf|sc|ni|ri|ac)\b)')
        }
        if ($tamper) {
            Deny "Karkas integration-guard: only the coordinator may create, edit or delete .claude/team/state/integration-gate* and integration-guard-off. Do not open the gate yourself: report 'integration deferred to coordinator' instead."
        }
    }
    if ($isEdit) { exit 0 }

    $cmd = [string]$in.tool_input.command
    if (-not $cmd.Trim()) { exit 0 }
    $root = Get-KarkasRoot $cwd
    $stateDir = Join-Path $root '.claude\team\state'
    if (Test-Path -LiteralPath (Join-Path $stateDir 'integration-guard-off')) { exit 0 }

    # ---- config (missing -> nothing to guard; broken -> warning, no decision) ----
    $cfgPath = Join-Path $root '.claude\team\integration-commands.json'
    if (-not (Test-Path -LiteralPath $cfgPath)) { exit 0 }
    $patterns = @(); $allow = @(); $ttl = 12; $warn = $null
    foreach ($name in @('integration-commands.json', 'integration-commands.local.json')) {
        $path = Join-Path $root ".claude\team\$name"
        if (-not (Test-Path -LiteralPath $path)) { continue }
        try {
            $j = [IO.File]::ReadAllText($path) | ConvertFrom-Json
            if ($j.patterns) { $patterns += @($j.patterns) }
            if ($j.allow) { $allow += @($j.allow) }
            if ($j.gate_ttl_hours) { $ttl = [double]$j.gate_ttl_hours }
        } catch { $warn = "Karkas integration-guard: $name is broken ($($_.Exception.Message)); the guard is inactive until it is fixed." }
    }
    if ($warn) { Out-Json @{ systemMessage = $warn }; exit 0 }
    if (-not $patterns.Count) { exit 0 }

    # ---- helpers ----
    function Split-Segments([string]$text) {
        $text = $text -replace '\d*>&\d+', ' ' -replace '(?<=\s)\d*>{1,2}\s*(?:"[^"]*"|''[^'']*''|[^\s;|&]+)', ' '
        $segs = New-Object System.Collections.Generic.List[string]
        $sb = New-Object System.Text.StringBuilder
        $q = [char]0
        foreach ($ch in $text.ToCharArray()) {
            if ($q -ne [char]0) { [void]$sb.Append($ch); if ($ch -eq $q) { $q = [char]0 }; continue }
            if ($ch -eq [char]34 -or $ch -eq [char]39) { $q = $ch; [void]$sb.Append($ch); continue }
            if ($ch -eq ';' -or $ch -eq '|' -or $ch -eq '&' -or $ch -eq "`n" -or $ch -eq "`r") { $segs.Add($sb.ToString()); [void]$sb.Clear(); continue }
            [void]$sb.Append($ch)
        }
        $segs.Add($sb.ToString())
        return $segs
    }
    $wrapRx = '^(?:[A-Za-z_]\w*=(?:"[^"]*"|''[^'']*''|\S*)\s+|(?:time|nohup|sudo|call|command|exec|nice|cross-env|dotenv)\s+(?:--\s+)?|(?:npx|bunx|pnpx)\s+(?:-{1,2}[\w-]+(?:=\S+)?\s+)*|(?:pnpm|yarn)\s+(?:exec|dlx)\s+|npm\s+exec\s+(?:--\s+)?|(?:uv|poetry|pipenv)\s+run\s+)'
    function Normalize([string]$seg) {
        $s = $seg.Trim().TrimStart('(', '{', '&', ' ').TrimEnd(')', '}', ' ')
        for ($i = 0; $i -lt 8; $i++) {
            $n = [regex]::Replace($s, $wrapRx, '', 'IgnoreCase')
            if ($n -eq $s) { break }
            $s = $n.TrimStart()
        }
        if (-not $s) { return '' }
        # first token: strip quotes, directory and executable extension
        $m = [regex]::Match($s, '^(?:"([^"]*)"|''([^'']*)''|(\S+))(.*)$', 'Singleline')
        $tok = $m.Groups[1].Value + $m.Groups[2].Value + $m.Groups[3].Value
        $rest = $m.Groups[4].Value
        $leaf = ($tok -split '[\\/]')[-1] -replace '(?i)\.(exe|cmd|bat|ps1|sh)$', ''
        return ($leaf + $rest).Trim()
    }
    function Find-Classes([string]$text, [int]$depth) {
        $found = @()
        foreach ($seg in (Split-Segments $text)) {
            $n = Normalize $seg
            if (-not $n) { continue }
            $w = [regex]::Match($n, '^(?:bash|sh|zsh|cmd|powershell|pwsh)\s+(?:-\S+\s+)*?(?:-c|/c|/k|-command)\s+(.+)$', 'IgnoreCase,Singleline')
            if ($w.Success -and $depth -lt 2) {
                $inner = $w.Groups[1].Value.Trim()
                if ($inner.Length -ge 2 -and ($inner[0] -eq [char]34 -or $inner[0] -eq [char]39) -and $inner[$inner.Length - 1] -eq $inner[0]) { $inner = $inner.Substring(1, $inner.Length - 2) }
                $found += @(Find-Classes $inner ($depth + 1))
                continue
            }
            $skip = $false
            foreach ($a in $allow) { try { if ($n -match "(?i)$a") { $skip = $true; break } } catch { } }
            if ($skip) { continue }
            foreach ($p in $patterns) {
                $hit = $false
                try { $hit = ($n -match "(?i)$($p.pattern)") } catch { }
                if ($hit) { $found += [pscustomobject]@{ Class = ([string]$p.class).ToLower(); Seg = $n }; break }
            }
        }
        return $found
    }

    $hits = @(Find-Classes $cmd 0)
    if (-not $hits.Count) { exit 0 }
    $classes = @($hits | ForEach-Object { $_.Class } | Select-Object -Unique)

    # ---- gate ----
    $gate = Join-Path $stateDir 'integration-gate'
    $open = @(); $why = 'the gate is closed'
    if (Test-Path -LiteralPath $gate) {
        $age = (Get-Date) - (Get-Item -LiteralPath $gate).LastWriteTime
        if ($age.TotalHours -gt $ttl) {
            $why = "the gate file is stale (older than $ttl h; the coordinator must rewrite it to keep it open)"
        } else {
            $gtext = [IO.File]::ReadAllText($gate)
            if ($gtext -notmatch '(?im)^[ \t]*owner-approved:[ \t]*\d{4}-\d{2}-\d{2}[ \t]+"[^"\r\n]+"[ \t]*\r?$') {
                $why = 'the gate file has no valid owner-approved line (gate without owner approval)'
            } else {
                # classes come only from the lines other than owner-approved / open-tasks-reported (the owner's quote must not open classes)
                $ctext = ($gtext -split '\r?\n' | Where-Object { $_ -notmatch '(?i)^\s*(owner-approved|open-tasks-reported)\s*:' }) -join ' '
                $open = @([regex]::Split($ctext.ToLower(), '[^a-z0-9_*-]+') | Where-Object { $_ })
                $why = "the gate is open only for: $(($open | Where-Object { $_ -notmatch '^\d' -and $_ -ne 'classes' }) -join ', ')"
            }
        }
    }
    $missing = @($classes | Where-Object { -not ($open -contains $_ -or $open -contains '*' -or $open -contains 'all') })

    $agent = if ($in.agent_type) { [string]$in.agent_type } else { 'main' }
    $decision = if ($missing.Count) { 'DENY' } else { 'allow' }
    try {
        New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
        $sample = ($hits[0].Seg -replace '\s+', ' '); if ($sample.Length -gt 160) { $sample = $sample.Substring(0, 160) }
        $line = "{0}`t{1}`t{2}`t{3}`t{4}`t{5}" -f (Get-Date -Format 's'), $decision, ($classes -join ','), $agent, $sample, $(if ($missing.Count) { $why } else { '-' })
        [IO.File]::AppendAllText((Join-Path $stateDir 'integration-guard.log'), $line + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
    } catch { }

    if ($missing.Count) {
        Deny ("Karkas integration-guard: integration action ($($missing -join ', ')) is deferred: $why. Report 'integration deferred to coordinator' instead and run only the narrowest check proving your own change (typecheck without emit, one test file), or ask the coordinator to get the owner's approval and open the gate (.claude/team/state/integration-gate). Blocked: $($hits[0].Seg)")
    }
    exit 0
} catch {
    exit 0   # fail open
}

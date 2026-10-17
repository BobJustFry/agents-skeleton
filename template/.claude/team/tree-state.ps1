# Karkas: prints the "tree state" key for the runs ledger (.claude/team/state/runs.md):  <HEAD short>+<8 hex of the working-tree hash>
# Usage: powershell -NoProfile -File .claude/team/tree-state.ps1      (from anywhere inside the repo)
# The hash covers: git status --porcelain, git diff HEAD (tracked edits) and name+size+mtime of untracked files.
# Everything under .claude/team/state/ is excluded: the ledger and the briefs change all the time and must not change the key.
# Not a git repo / no commits -> prints "nogit+unknown" / "nohead+<hash>"; an "unknown" key never proves that the tree is unchanged.
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
function Invoke-Git {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $out = & git @args 2>$null; $code = $LASTEXITCODE } catch { $out = $null; $code = 1 } finally { $ErrorActionPreference = $old }
    return [pscustomobject]@{ Out = (@($out) -join "`n"); Code = $code }
}
try {
    $top = Invoke-Git rev-parse --show-toplevel
    if ($top.Code -ne 0 -or -not $top.Out) { 'nogit+unknown'; exit 0 }
    $t = $top.Out.Trim()
    $x = ':(exclude).claude/team/state'
    $head = Invoke-Git -C $t rev-parse --short HEAD
    $h = if ($head.Code -eq 0) { $head.Out.Trim() } else { 'nohead' }
    $status = Invoke-Git -C $t -c core.quotepath=off status --porcelain --untracked-files=all -- . $x
    $diff = if ($head.Code -eq 0) { Invoke-Git -C $t diff HEAD --no-color --no-ext-diff -- . $x } else { Invoke-Git -C $t diff --no-color --no-ext-diff -- . $x }
    $un = Invoke-Git -C $t -c core.quotepath=off ls-files --others --exclude-standard -- . $x
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append($status.Out).Append("`n--`n").Append($diff.Out).Append("`n--`n")
    $n = 0
    foreach ($f in ($un.Out -split "`n" | Where-Object { $_ })) {
        if (++$n -gt 20000) { break }
        $fi = Get-Item -LiteralPath (Join-Path $t $f) -ErrorAction SilentlyContinue
        if ($fi) { [void]$sb.Append($f).Append('|').Append($fi.Length).Append('|').Append($fi.LastWriteTimeUtc.Ticks).Append("`n") }
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($sb.ToString()))
    $hex = (($bytes | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 8)
    "$h+$hex"
} catch {
    'nogit+unknown'
}

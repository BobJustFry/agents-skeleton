<#
.SYNOPSIS
  Устанавливает AI-команду «Каркас» в новую или существующую папку проекта.

.DESCRIPTION
  Сначала анализ, потом изменения:
  1. Анализирует папку: git-состояние, существующие CLAUDE.md, .claude/agents, .claude/settings.json, .gitignore.
  2. Показывает план (что добавится, что объединится, где конфликты) и спрашивает подтверждение.
  3. Применяет план без потерь:
     - ваши файлы с такими же именами не перезаписываются — версия каркаса кладётся в .claude/team/incoming/;
     - CLAUDE.md, settings.json, .gitignore только дополняются (копии — в .claude/team/backup/<дата>/);
     - установленные файлы записываются в .claude/team/kit-manifest.json, чтобы при -Update
       обновлять только то, что поставил каркас и что вы не меняли.
  4. Пишет отчёт .claude/team/install-report.md. Дальше в Claude Code: «Проведи онбординг Каркаса».

.PARAMETER Analyze  Только анализ и план, ничего не менять (то же, что -WhatIf).
.PARAMETER Update   Обновить файлы каркаса до текущей версии (только неизменённые вами).
.PARAMETER Yes      Не спрашивать подтверждение.
.PARAMETER Force    Разрешить установку при незакоммиченных изменениях в git.

.EXAMPLE
  .\install.ps1 -Target "P:\Projects\МойПроект" -Analyze
  .\install.ps1 -Target "P:\Projects\МойПроект"
  .\install.ps1 -Target "P:\Projects\МойПроект" -Update
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Target,
    [switch]$Update,
    [switch]$Analyze,
    [switch]$Yes,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
$analyzeOnly = $Analyze -or $WhatIfPreference
$WhatIfPreference = $false
$templateRoot = Join-Path $PSScriptRoot 'template'
$srcClaude = Join-Path $templateRoot '.claude'
$srcSettings = Join-Path $srcClaude 'settings.json'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$importLine = '@.claude/team/ORCHESTRATOR.md'
$compactMarker = '# Karkas: compaction instructions'
$gitignoreMarker = '# Karkas (AI team): local artifacts'
$gitignoreLines = @(
    '.claude/team/backup/',
    '.claude/team/incoming/',
    '.claude/team/kit-source.txt',
    '.claude/team/state/update-check.json',
    '.claude/team/state/paid-calls.log',
    '.claude/team/state/integration-guard.log',
    '.claude/team/state/integration-gate',
    '.claude/team/state/integration-guard-off',
    '.claude/team/state/runs.md',
    '.claude/team/state/screenshots/',
    '.claude/team/state/compactions/',
    '.claude/agent-memory-local/'
)

function Invoke-GitQuiet {
    # git writes errors to stderr; with ErrorActionPreference=Stop PowerShell 5.1 would turn that into a terminating error
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $out = & git @args 2>$null; $code = $LASTEXITCODE } catch { $out = $null; $code = 1 } finally { $ErrorActionPreference = $old }
    return [pscustomobject]@{ Out = $out; Code = $code }
}
function Get-Hash([string]$path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }

# ---------- 0. Папка ----------
if (-not $Target) { $Target = Read-Host 'Путь к папке проекта (новой или существующей)' }
$Target = $Target.Trim().Trim('"')
if (-not $Target) { throw 'Путь к папке не указан.' }
$kitRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path.TrimEnd('\')
$isNew = -not (Test-Path -LiteralPath $Target)
if (-not $isNew) {
    $Target = (Resolve-Path -LiteralPath $Target).Path.TrimEnd('\')
    if ($Target -eq $kitRoot -or $Target.StartsWith($kitRoot + '\')) { throw 'Нельзя ставить каркас внутрь самого каркаса. Укажите папку проекта.' }
} else {
    $Target = [IO.Path]::GetFullPath($Target).TrimEnd('\')
}

# ---------- 1. Анализ ----------
$isGit = $false; $dirty = @()
if (-not $isNew) {
    if ((Invoke-GitQuiet -C $Target rev-parse --is-inside-work-tree).Code -eq 0) {
        $isGit = $true
        $dirty = @((Invoke-GitQuiet -C $Target status --porcelain).Out | Where-Object { $_ })
    }
}
$dstSettings = Join-Path $Target '.claude\settings.json'
if (Test-Path -LiteralPath $dstSettings) {
    try { $null = [IO.File]::ReadAllText($dstSettings) | ConvertFrom-Json }
    catch { throw "Не удалось прочитать $dstSettings (неверный JSON). Исправьте файл и запустите снова. Ничего не изменено." }
}
$manifestPath = Join-Path $Target '.claude\team\kit-manifest.json'
$manifest = @{}
if (Test-Path -LiteralPath $manifestPath) {
    $m = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
    foreach ($p in $m.files.PSObject.Properties) { $manifest[$p.Name] = $p.Value }
}
$legacy = ($manifest.Count -eq 0) -and (Test-Path -LiteralPath (Join-Path $Target '.claude\team\kit-source.txt'))

# Файлы каркаса
$plan = @()
Get-ChildItem -LiteralPath $srcClaude -Recurse -File | Where-Object { $_.FullName -ne $srcSettings } | ForEach-Object {
    $rel = '.claude\' + $_.FullName.Substring($srcClaude.Length).TrimStart('\')
    $key = $rel.Replace('\', '/')
    $dst = Join-Path $Target $rel
    $hs = Get-Hash $_.FullName
    $action = 'add'
    if (Test-Path -LiteralPath $dst) {
        $hd = Get-Hash $dst
        if ($hd -eq $hs) { $action = 'same' }
        elseif (($manifest.ContainsKey($key) -and $manifest[$key] -eq $hd) -or $legacy) { $action = if ($Update) { 'update' } else { 'outdated' } }
        else { $action = 'conflict' }
    }
    $plan += [pscustomobject]@{ Rel = $rel; Key = $key; Src = $_.FullName; Dst = $dst; Hash = $hs; Action = $action }
}

# settings.json
$settingsPlan = 'add'; $addedEvents = @(); $addedKeys = @(); $keptValues = @(); $newSettingsJson = $null
if (Test-Path -LiteralPath $dstSettings) {
    $dstText = [IO.File]::ReadAllText($dstSettings)
    $dst = $dstText | ConvertFrom-Json
    $src = [IO.File]::ReadAllText($srcSettings) | ConvertFrom-Json
    if (-not ($dst.PSObject.Properties.Name -contains 'hooks')) { $dst | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) }
    $ourMark = '.claude/team/hooks/'
    foreach ($ev in $src.hooks.PSObject.Properties.Name) {
        $ours = @($src.hooks.$ev)
        if ($dst.hooks.PSObject.Properties.Name -contains $ev) {
            $existing = @($dst.hooks.$ev)
            $existingJson = ConvertTo-Json -InputObject $existing -Depth 16 -Compress
            $others = @($existing | Where-Object { -not (ConvertTo-Json -InputObject $_ -Depth 16 -Compress).Contains($ourMark) })
            $ourScripts = @([regex]::Matches((ConvertTo-Json -InputObject $ours -Depth 16 -Compress), '[\w-]+\.ps1') | ForEach-Object { $_.Value } | Sort-Object -Unique)
            $missing = @($ourScripts | Where-Object { -not $existingJson.Contains($_) })
            if (-not $Update -and $missing.Count -eq 0) { continue }
            $newEv = @($others + $ours)
            if ((ConvertTo-Json -InputObject $newEv -Depth 16 -Compress) -eq $existingJson) { continue }
            $dst.hooks.$ev = $newEv
        } else {
            $dst.hooks | Add-Member -NotePropertyName $ev -NotePropertyValue $ours
        }
        $addedEvents += $ev
    }
    # Top-level defaults (model, env entries): add only what is missing, never overwrite the project's own values
    if ($src.PSObject.Properties.Name -contains 'model') {
        if ($dst.PSObject.Properties.Name -contains 'model') { if ([string]$dst.model -ne [string]$src.model) { $keptValues += "model=$($dst.model)" } }
        else { $dst | Add-Member -NotePropertyName model -NotePropertyValue $src.model; $addedKeys += 'model' }
    }
    if ($src.PSObject.Properties.Name -contains 'env') {
        if (-not ($dst.PSObject.Properties.Name -contains 'env') -or $null -eq $dst.env) { $dst | Add-Member -Force -NotePropertyName env -NotePropertyValue ([pscustomobject]@{}) }
        foreach ($p in $src.env.PSObject.Properties) {
            if ($dst.env.PSObject.Properties.Name -contains $p.Name) { if ([string]$dst.env.($p.Name) -ne [string]$p.Value) { $keptValues += "env.$($p.Name)=$($dst.env.($p.Name))" } }
            else { $dst.env | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value; $addedKeys += "env.$($p.Name)" }
        }
    }
    if ($addedEvents.Count -eq 0 -and $addedKeys.Count -eq 0) { $settingsPlan = 'same' } else { $settingsPlan = 'merge'; $newSettingsJson = $dst | ConvertTo-Json -Depth 32 }
    $foreignHooks = @($dst.hooks.PSObject.Properties | ForEach-Object { $ev = $_.Name; @($_.Value) | Where-Object { -not ((ConvertTo-Json -InputObject $_ -Depth 16 -Compress).Contains('.claude/team/hooks/')) } | ForEach-Object { $ev } })
} else { $foreignHooks = @() }

# CLAUDE.md (в корне или в .claude/)
$claudeRoot = Join-Path $Target 'CLAUDE.md'
$claudeDot = Join-Path $Target '.claude\CLAUDE.md'
$tplText = [IO.File]::ReadAllText((Join-Path $templateRoot 'CLAUDE.md'))
$compactBlock = $tplText.Substring($tplText.IndexOf($compactMarker)).Trim()
if (Test-Path -LiteralPath $claudeRoot) { $claudeMd = $claudeRoot } elseif (Test-Path -LiteralPath $claudeDot) { $claudeMd = $claudeDot } else { $claudeMd = $null }
$claudeAppend = ''; $claudeWhat = @()
if ($claudeMd) {
    $existing = [IO.File]::ReadAllText($claudeMd)
    $imp = if ($claudeMd -eq $claudeDot) { '@team/ORCHESTRATOR.md' } else { $importLine }
    if (-not ($existing.Contains($importLine) -or $existing.Contains('@team/ORCHESTRATOR.md'))) { $claudeAppend += "`r`n`r`n# AI-команда (Каркас)`r`n$imp"; $claudeWhat += 'подключение координатора' }
    if (-not $existing.Contains($compactMarker)) { $claudeAppend += "`r`n`r`n" + ($compactBlock -replace "`r?`n", "`r`n"); $claudeWhat += 'указания для сжатия контекста' }
    $claudePlan = if ($claudeAppend) { 'append' } else { 'same' }
} else { $claudePlan = 'create' }

# .gitignore
$giPath = Join-Path $Target '.gitignore'
$giPlan = 'skip'; $giMissing = @()
if ($isGit -or $isNew -or (Test-Path -LiteralPath $giPath)) {
    $gi = if (Test-Path -LiteralPath $giPath) { [IO.File]::ReadAllText($giPath) } else { '' }
    if ($gi.Contains($gitignoreMarker)) {
        # block written by an older kit version: add only the lines it lacks (e.g. the integration gate must never be committed)
        $giMissing = @($gitignoreLines | Where-Object { $gi -notmatch ('(?m)^' + [regex]::Escape($_) + '\s*$') })
        $giPlan = if ($giMissing.Count) { 'extend' } else { 'same' }
    } elseif ($gi) { $giPlan = 'append' } else { $giPlan = 'create' }
}

# Другие инструкции для AI в проекте (для онбординга)
$otherRules = @('AGENTS.md', 'GEMINI.md', '.cursorrules', '.cursor\rules', '.github\copilot-instructions.md', '.windsurfrules') | Where-Object { Test-Path -LiteralPath (Join-Path $Target $_) }
$foreignAgents = @()
if (Test-Path -LiteralPath (Join-Path $Target '.claude\agents')) {
    $kitAgents = @($plan | Where-Object { $_.Rel -like '.claude\agents\*' } | ForEach-Object { Split-Path -Leaf $_.Rel })
    $foreignAgents = @(Get-ChildItem -LiteralPath (Join-Path $Target '.claude\agents') -Filter *.md -File | Where-Object { $kitAgents -notcontains $_.Name } | ForEach-Object { $_.Name })
}

# ---------- 2. План ----------
$c = @{}; foreach ($a in 'add','update','outdated','same','conflict') { $c[$a] = @($plan | Where-Object { $_.Action -eq $a }) }
Write-Host ''
Write-Host "Каркас -> $Target"
Write-Host ("Тип: " + $(if ($isNew) { 'новая папка' } elseif ($legacy) { 'проект с прежней установкой Каркаса' } elseif ($manifest.Count) { 'проект с установленным Каркасом' } else { 'существующий проект' }))
if ($isGit) { Write-Host ("Git: да; незакоммиченных изменений: " + $dirty.Count) } elseif (-not $isNew) { Write-Host 'Git: нет (откат — только по резервным копиям)' }
Write-Host ''
Write-Host 'ПЛАН:'
Write-Host ("  добавить файлов:            " + $c.add.Count)
Write-Host ("  обновить (не менялись вами): " + $c.update.Count)
if ($c.outdated.Count) { Write-Host ("  устаревших (нужен -Update):  " + $c.outdated.Count) }
Write-Host ("  без изменений:              " + $c.same.Count)
Write-Host ("  КОНФЛИКТОВ:                 " + $c.conflict.Count + $(if ($c.conflict.Count) { '  (ваш файл не трогаем; версия каркаса -> .claude\team\incoming\)' } else { '' }))
foreach ($x in $c.conflict) { Write-Host ("     ! " + $x.Rel) }
Write-Host ("  .claude\settings.json:      " + @{ add = 'создать (хуки и настройки каркаса)'; merge = 'дополнить: ' + (@($addedEvents) + @($addedKeys) -join ', ') + ' (ваши настройки сохраняются)'; same = 'без изменений' }[$settingsPlan])
if ($keptValues.Count) { Write-Host ("     оставляем ваши значения: " + ($keptValues -join ', ') + ' (каркас их не меняет)') }
if ($foreignHooks.Count) { Write-Host ("     в проекте есть свои хуки: " + (($foreignHooks | Sort-Object -Unique) -join ', ') + ' — останутся, проверим на онбординге') }
$claudeLabel = if ($claudeMd) { $claudeMd.Substring($Target.Length + 1) } else { 'CLAUDE.md' }
Write-Host ("  " + $claudeLabel + ": " + @{ create = 'создать из шаблона'; append = 'дописать в конец: ' + ($claudeWhat -join ', '); same = 'всё уже подключено' }[$claudePlan])
Write-Host ("  .gitignore:                 " + @{ skip = 'не трогаем (нет git)'; create = 'создать с локальными файлами каркаса'; append = 'дописать локальные файлы каркаса'; extend = 'дописать новые локальные файлы каркаса (' + $giMissing.Count + ')'; same = 'без изменений' }[$giPlan])
if ($foreignAgents.Count) { Write-Host ("  ваши агенты (останутся):    " + ($foreignAgents -join ', ')) }
if ($otherRules.Count) { Write-Host ("  другие правила для AI:      " + ($otherRules -join ', ') + ' — сверим на онбординге') }

if ($isGit -and $dirty.Count -and -not $Force -and -not $analyzeOnly) {
    Write-Host ''
    Write-Host 'СТОП: в проекте есть незакоммиченные изменения. Сделайте коммит (чтобы любую установку можно было откатить через git) и запустите снова, либо добавьте -Force. Ничего не изменено.'
    exit 2
}
if ($analyzeOnly) { Write-Host ''; Write-Host 'Это только анализ. Ничего не изменено.'; exit 0 }
if (-not $Yes) {
    $ans = Read-Host 'Применить план? (да/нет)'
    if (@('да', 'д', 'yes', 'y') -notcontains $ans.Trim().ToLower()) { Write-Host 'Отменено. Ничего не изменено.'; exit 1 }
}

# ---------- 3. Применение ----------
$backupDir = Join-Path $Target (".claude\team\backup\" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
function Backup-File([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return }
    $bak = Join-Path $backupDir $path.Substring($Target.Length + 1)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $bak) | Out-Null
    Copy-Item -LiteralPath $path -Destination $bak -Force
}
if ($isNew) { New-Item -ItemType Directory -Force -Path $Target | Out-Null }

$newManifest = @{}
foreach ($k in $manifest.Keys) { $newManifest[$k] = $manifest[$k] }
foreach ($x in $plan) {
    switch ($x.Action) {
        'add'      { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $x.Dst) | Out-Null; Copy-Item -LiteralPath $x.Src -Destination $x.Dst; $newManifest[$x.Key] = $x.Hash }
        'update'   { Backup-File $x.Dst; Copy-Item -LiteralPath $x.Src -Destination $x.Dst -Force; $newManifest[$x.Key] = $x.Hash }
        'same'     { $newManifest[$x.Key] = $x.Hash }
        'conflict' { $inc = Join-Path $Target ('.claude\team\incoming\' + $x.Rel.Substring(8)); New-Item -ItemType Directory -Force -Path (Split-Path -Parent $inc) | Out-Null; Copy-Item -LiteralPath $x.Src -Destination $inc -Force }
    }
}
switch ($settingsPlan) {
    'add'   { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dstSettings) | Out-Null; Copy-Item -LiteralPath $srcSettings -Destination $dstSettings }
    'merge' { Backup-File $dstSettings; [IO.File]::WriteAllText($dstSettings, $newSettingsJson, $utf8NoBom) }
}
switch ($claudePlan) {
    'create' { Copy-Item -LiteralPath (Join-Path $templateRoot 'CLAUDE.md') -Destination $claudeRoot }
    'append' { Backup-File $claudeMd; [IO.File]::WriteAllText($claudeMd, ([IO.File]::ReadAllText($claudeMd)).TrimEnd() + $claudeAppend + "`r`n", $utf8NoBom) }
}
if ($giPlan -eq 'extend') {
    Backup-File $giPath
    [IO.File]::WriteAllText($giPath, ([IO.File]::ReadAllText($giPath)).TrimEnd() + "`r`n" + ($giMissing -join "`r`n") + "`r`n", $utf8NoBom)
}
if ($giPlan -in @('create', 'append')) {
    Backup-File $giPath
    $gi = if (Test-Path -LiteralPath $giPath) { ([IO.File]::ReadAllText($giPath)).TrimEnd() + "`r`n`r`n" } else { '' }
    [IO.File]::WriteAllText($giPath, $gi + $gitignoreMarker + "`r`n" + ($gitignoreLines -join "`r`n") + "`r`n", $utf8NoBom)
}
[IO.File]::WriteAllText((Join-Path $Target '.claude\team\kit-source.txt'), (Join-Path $templateRoot '.claude\team\ORCHESTRATOR.md') + "`r`n", $utf8NoBom)
$sorted = [ordered]@{}; foreach ($k in ($newManifest.Keys | Sort-Object)) { $sorted[$k] = $newManifest[$k] }
$kitVersion = if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'VERSION')) { ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'VERSION'))).Trim() } else { '' }
$kitRepo = ''
$origin = Invoke-GitQuiet -C $PSScriptRoot remote get-url origin
$originUrl = [string]$origin.Out
if ($origin.Code -eq 0 -and $originUrl -match 'github\.com[/:]([^/]+)/([^/.]+?)(\.git)?$') { $kitRepo = "https://github.com/$($Matches[1])/$($Matches[2])" }
[IO.File]::WriteAllText($manifestPath, ([ordered]@{ version = $kitVersion; repo = $kitRepo; installed = (Get-Date -Format 's'); files = $sorted } | ConvertTo-Json -Depth 4), $utf8NoBom)

# ---------- 4. Отчёт ----------
$r = @()
$r += '# Отчёт об установке Каркаса'
$r += ''
$r += "Дата: $(Get-Date -Format 'yyyy-MM-dd HH:mm'). Папка: $Target. Git: $(if ($isGit) { 'да' } else { 'нет' })."
$r += ''
$r += "- Добавлено файлов: $($c.add.Count); обновлено: $($c.update.Count); без изменений: $($c.same.Count); устаревших (нужен -Update): $($c.outdated.Count)."
$r += "- settings.json: $settingsPlan $(if ($addedEvents.Count -or $addedKeys.Count) { '(' + (@($addedEvents) + @($addedKeys) -join ', ') + ')' })."
if ($keptValues.Count) { $r += "- settings.json: оставлены значения проекта (каркас предлагает иные): $($keptValues -join ', ')." }
$r += "- $claudeLabel`: $claudePlan $(if ($claudeWhat.Count) { '(' + ($claudeWhat -join ', ') + ')' })."
$r += "- .gitignore: $giPlan."
if (Test-Path -LiteralPath $backupDir) { $r += "- Резервные копии изменённых файлов: $($backupDir.Substring($Target.Length + 1))." }
$r += ''
$r += '## Требует онбординга'
if ($c.conflict.Count) { $r += '- Конфликты файлов (ваш файл сохранён, версия Каркаса лежит в `.claude/team/incoming/`):'; foreach ($x in $c.conflict) { $r += "  - $($x.Key)" } }
if ($foreignAgents.Count) { $r += "- Собственные агенты проекта: $($foreignAgents -join ', ')." }
if ($foreignHooks.Count) { $r += "- Собственные хуки проекта: $((($foreignHooks | Sort-Object -Unique) -join ', '))." }
if ($otherRules.Count) { $r += "- Другие правила для AI: $($otherRules -join ', ')." }
if (-not ($c.conflict.Count -or $foreignAgents.Count -or $foreignHooks.Count -or $otherRules.Count)) { $r += '- Конфликтов не найдено.' }
$r += ''
$r += 'Следующий шаг: открыть проект в Claude Code и написать «Проведи онбординг Каркаса».'
[IO.File]::WriteAllText((Join-Path $Target '.claude\team\install-report.md'), ($r -join "`r`n") + "`r`n", $utf8NoBom)

Write-Host ''
Write-Host 'Готово. Отчёт: .claude\team\install-report.md'
if ($c.outdated.Count) { Write-Host 'Часть файлов каркаса устарела — чтобы обновить их, запустите с ключом -Update.' }
if ($c.conflict.Count) { Write-Host 'Есть конфликты: ваши файлы сохранены, версии Каркаса лежат в .claude\team\incoming\ — разберём на онбординге.' }
Write-Host 'Дальше: откройте папку в Claude Code и напишите: «Проведи онбординг Каркаса».'

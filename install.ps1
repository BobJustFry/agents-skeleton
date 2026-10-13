<#
.SYNOPSIS
  Устанавливает AI-команду «Каркас» в новую или существующую папку проекта.

.DESCRIPTION
  - Новая папка: создаётся и получает готовую команду (CLAUDE.md + .claude/).
  - Существующий проект: файлы команды добавляются, ничего не удаляется и не перезаписывается.
    Если CLAUDE.md уже есть, в его конец дописывается одна строка импорта координатора.
  - -Update: обновляет файлы команды из каркаса; старые версии сохраняются в .claude/team/backup/<дата>/.

.EXAMPLE
  .\install.ps1 -Target "P:\Projects\НовыйСайт"
  .\install.ps1 -Target "P:\Projects\СтарыйПроект" -Update
  .\install.ps1 -Target "P:\Projects\СтарыйПроект" -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Target,
    [switch]$Update
)

$ErrorActionPreference = 'Stop'
$templateRoot = Join-Path $PSScriptRoot 'template'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$importLine = '@.claude/team/ORCHESTRATOR.md'

if (-not $Target) {
    $Target = Read-Host 'Путь к папке проекта (новой или существующей)'
}
$Target = $Target.Trim().Trim('"')
if (-not $Target) { throw 'Путь к папке не указан.' }

$kitRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
if (Test-Path -LiteralPath $Target) {
    $Target = (Resolve-Path -LiteralPath $Target).Path
    if ($Target.TrimEnd('\') -eq $kitRoot.TrimEnd('\') -or $Target.StartsWith($kitRoot.TrimEnd('\') + '\')) {
        throw 'Нельзя ставить каркас внутрь самого каркаса. Укажите папку проекта.'
    }
    $mode = 'существующий проект'
} else {
    if ($PSCmdlet.ShouldProcess($Target, 'Создать папку проекта')) {
        New-Item -ItemType Directory -Force -Path $Target | Out-Null
        $Target = (Resolve-Path -LiteralPath $Target).Path
    }
    $mode = 'новая папка'
}

$existingSettings = Join-Path $Target '.claude\settings.json'
if (Test-Path -LiteralPath $existingSettings) {
    try { $null = [IO.File]::ReadAllText($existingSettings) | ConvertFrom-Json }
    catch { throw "Не удалось прочитать $existingSettings (неверный JSON). Исправьте файл и запустите снова. Ничего не изменено." }
}

Write-Host "Каркас -> $Target ($mode)"
$stats = @{ added = 0; updated = 0; kept = 0 }
$backupDir = Join-Path $Target (".claude\team\backup\" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))

function Copy-KitFile([string]$src, [string]$dst, [string]$rel) {
    $dir = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $dir) -and $PSCmdlet.ShouldProcess($dir, 'Создать папку')) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    if (Test-Path -LiteralPath $dst) {
        $same = (Get-FileHash -LiteralPath $src).Hash -eq (Get-FileHash -LiteralPath $dst).Hash
        if ($same -or -not $Update) { $script:stats.kept++; return }
        if ($PSCmdlet.ShouldProcess($dst, 'Обновить (старая версия -> backup)')) {
            $bak = Join-Path $backupDir $rel
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $bak) | Out-Null
            Copy-Item -LiteralPath $dst -Destination $bak -Force
            Copy-Item -LiteralPath $src -Destination $dst -Force
        }
        $script:stats.updated++
        Write-Host "  обновлён:  $rel"
    } else {
        if ($PSCmdlet.ShouldProcess($dst, 'Добавить')) {
            Copy-Item -LiteralPath $src -Destination $dst
        }
        $script:stats.added++
        Write-Host "  добавлен:  $rel"
    }
}

# 1. Файлы команды: .claude/agents, .claude/team
$srcClaude = Join-Path $templateRoot '.claude'
$srcSettings = Join-Path $srcClaude 'settings.json'
Get-ChildItem -LiteralPath $srcClaude -Recurse -File | Where-Object { $_.FullName -ne $srcSettings } | ForEach-Object {
    $rel = '.claude\' + $_.FullName.Substring($srcClaude.Length).TrimStart('\')
    Copy-KitFile $_.FullName (Join-Path $Target $rel) $rel
}

# 1b. .claude/settings.json: хуки непрерывной работы. Чужие настройки не трогаем, только добавляем наши хуки.
$dstSettings = Join-Path $Target '.claude\settings.json'
if (-not (Test-Path -LiteralPath $dstSettings)) {
    if ($PSCmdlet.ShouldProcess($dstSettings, 'Добавить')) { Copy-Item -LiteralPath $srcSettings -Destination $dstSettings }
    $stats.added++
    Write-Host '  добавлен:  .claude\settings.json (хуки непрерывной работы)'
} else {
    $dstText = [IO.File]::ReadAllText($dstSettings)
    if ($dstText.Contains('stop-guard.ps1') -and $dstText.Contains('session-start.ps1')) {
        $stats.kept++
    } else {
        try { $dst = $dstText | ConvertFrom-Json } catch { throw "Не удалось прочитать $dstSettings (неверный JSON). Исправьте файл и запустите снова." }
        $src = [IO.File]::ReadAllText($srcSettings) | ConvertFrom-Json
        if (-not ($dst.PSObject.Properties.Name -contains 'hooks')) {
            $dst | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{})
        }
        foreach ($ev in @('SessionStart', 'Stop')) {
            $ours = @($src.hooks.$ev)
            if ($dst.hooks.PSObject.Properties.Name -contains $ev) {
                $dst.hooks.$ev = @(@($dst.hooks.$ev) + $ours)
            } else {
                $dst.hooks | Add-Member -NotePropertyName $ev -NotePropertyValue $ours
            }
        }
        if ($PSCmdlet.ShouldProcess($dstSettings, 'Добавить хуки (старая версия -> backup)')) {
            $bak = Join-Path $backupDir '.claude\settings.json'
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $bak) | Out-Null
            Copy-Item -LiteralPath $dstSettings -Destination $bak -Force
            [IO.File]::WriteAllText($dstSettings, ($dst | ConvertTo-Json -Depth 32), $utf8NoBom)
        }
        $stats.updated++
        Write-Host '  обновлён:  .claude\settings.json: добавлены хуки непрерывной работы (ваши настройки сохранены, копия в backup)'
    }
}

# 2. Путь к исходному каркасу — чтобы координатор видел, что политика моделей обновилась
$sourceFile = Join-Path $Target '.claude\team\kit-source.txt'
$sourceOrch = Join-Path $templateRoot '.claude\team\ORCHESTRATOR.md'
if ($PSCmdlet.ShouldProcess($sourceFile, 'Записать путь к каркасу')) {
    [IO.File]::WriteAllText($sourceFile, "$sourceOrch`r`n", $utf8NoBom)
}

# 3. CLAUDE.md: новый — из шаблона; существующий — только дописать импорт
$claudeMd = Join-Path $Target 'CLAUDE.md'
if (-not (Test-Path -LiteralPath $claudeMd)) {
    if ($PSCmdlet.ShouldProcess($claudeMd, 'Создать из шаблона')) {
        Copy-Item -LiteralPath (Join-Path $templateRoot 'CLAUDE.md') -Destination $claudeMd
    }
    Write-Host '  CLAUDE.md: создан из шаблона'
} else {
    $existing = [IO.File]::ReadAllText($claudeMd)
    if ($existing -match [regex]::Escape($importLine)) {
        Write-Host '  CLAUDE.md: координатор уже подключён'
    } elseif ($PSCmdlet.ShouldProcess($claudeMd, 'Дописать импорт координатора')) {
        $block = "`r`n`r`n# AI-команда (Каркас)`r`n$importLine`r`n"
        [IO.File]::WriteAllText($claudeMd, $existing.TrimEnd() + $block, $utf8NoBom)
        Write-Host '  CLAUDE.md: дописан импорт координатора (остальное содержимое не тронуто)'
    }
}

Write-Host ("Готово. Добавлено: {0}, обновлено: {1}, без изменений: {2}" -f $stats.added, $stats.updated, $stats.kept)
if (-not $Update -and $stats.kept -gt 0) {
    Write-Host 'Часть файлов уже была в проекте и оставлена как есть. Чтобы обновить их из каркаса, запустите с ключом -Update.'
}
Write-Host 'Откройте папку проекта в Claude Code (новая сессия) — команда готова к работе.'

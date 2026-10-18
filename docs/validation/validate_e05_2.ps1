param(
    [string]$ProjectPath = 'C:\Projects\ProcessGarden-CV23A-Validation',
    [string]$GodotPath = 'C:\tools\Godot\Godot_v4.7.2-stable_win64_console.exe',
    [switch]$RunBenchmarks
)

$ErrorActionPreference = 'Stop'

$gardenSource = '\\wsl.localhost\Ubuntu\home\sathler\projects\process-garden\garden'
$docsSource = '\\wsl.localhost\Ubuntu\home\sathler\projects\process-garden\docs'
$backupRoot = "${ProjectPath}-backups\E05.2-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$logRoot = Join-Path $ProjectPath 'validation-logs\E05.2'

if (-not (Test-Path -LiteralPath $ProjectPath -PathType Container)) {
    throw "Validation project directory does not exist: $ProjectPath"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot executable does not exist: $GodotPath"
}

$syncItems = @(
    @{ Root = $gardenSource; Relative = 'project.godot'; Destination = 'project.godot' },
    @{ Root = $gardenSource; Relative = 'export_presets.cfg'; Destination = 'export_presets.cfg' },
    @{ Root = $gardenSource; Relative = 'scripts\process_selector.gd'; Destination = 'scripts\process_selector.gd' },
    @{ Root = $gardenSource; Relative = 'scripts\habitat_layout.gd'; Destination = 'scripts\habitat_layout.gd' },
    @{ Root = $gardenSource; Relative = 'scripts\habitat_layout.gd.uid'; Destination = 'scripts\habitat_layout.gd.uid' },
    @{ Root = $gardenSource; Relative = 'scripts\environment.gd'; Destination = 'scripts\environment.gd' },
    @{ Root = $gardenSource; Relative = 'scripts\garden_controller.gd'; Destination = 'scripts\garden_controller.gd' },
    @{ Root = $gardenSource; Relative = 'scripts\creature.gd'; Destination = 'scripts\creature.gd' },
    @{ Root = $gardenSource; Relative = 'scripts\main.gd'; Destination = 'scripts\main.gd' },
    @{ Root = $gardenSource; Relative = 'scripts\cozy_mystic_sprite_library.gd'; Destination = 'scripts\cozy_mystic_sprite_library.gd' },
    @{ Root = $gardenSource; Relative = 'scripts\cozy_mystic_sprite_library.gd.uid'; Destination = 'scripts\cozy_mystic_sprite_library.gd.uid' },
    @{ Root = $gardenSource; Relative = 'scripts\cozy_mystic_visual.gd'; Destination = 'scripts\cozy_mystic_visual.gd' },
    @{ Root = $gardenSource; Relative = 'scripts\cozy_mystic_visual.gd.uid'; Destination = 'scripts\cozy_mystic_visual.gd.uid' },
    @{ Root = $gardenSource; Relative = 'scripts\synthetic_wisp.gd'; Destination = 'scripts\synthetic_wisp.gd' },
    @{ Root = $gardenSource; Relative = 'scripts\collector_process_manager.gd'; Destination = 'scripts\collector_process_manager.gd' },
    @{ Root = $gardenSource; Relative = 'scripts\collector_process_manager.gd.uid'; Destination = 'scripts\collector_process_manager.gd.uid' },
    @{ Root = $gardenSource; Relative = 'scripts\snapshot_client.gd'; Destination = 'scripts\snapshot_client.gd' },
    @{ Root = $gardenSource; Relative = 'scripts\synthetic_life_visual.gd'; Destination = 'scripts\synthetic_life_visual.gd' },
    @{ Root = $gardenSource; Relative = 'scripts\synthetic_life_visual.gd.uid'; Destination = 'scripts\synthetic_life_visual.gd.uid' },
    @{ Root = $gardenSource; Relative = 'scripts\synthetic_life_lab.gd'; Destination = 'scripts\synthetic_life_lab.gd' },
    @{ Root = $gardenSource; Relative = 'scripts\synthetic_life_lab.gd.uid'; Destination = 'scripts\synthetic_life_lab.gd.uid' },
    @{ Root = $gardenSource; Relative = 'scenes\previews\synthetic_life_lab.tscn'; Destination = 'scenes\previews\synthetic_life_lab.tscn' },
    @{ Root = $gardenSource; Relative = 'tests\run_tests.gd'; Destination = 'tests\run_tests.gd' },
    @{ Root = $gardenSource; Relative = 'tests\run_benchmark.gd'; Destination = 'tests\run_benchmark.gd' },
    @{ Root = $gardenSource; Relative = 'tests\run_sprite_prototype_tests.gd'; Destination = 'tests\run_sprite_prototype_tests.gd' },
    @{ Root = $gardenSource; Relative = 'tests\run_sprite_resolution_tests.gd'; Destination = 'tests\run_sprite_resolution_tests.gd' },
    @{ Root = $gardenSource; Relative = 'tests\run_sprite_resolution_tests.gd.uid'; Destination = 'tests\run_sprite_resolution_tests.gd.uid' },
    @{ Root = $gardenSource; Relative = 'tests\run_animation_poc_tests.gd'; Destination = 'tests\run_animation_poc_tests.gd' },
    @{ Root = $gardenSource; Relative = 'tests\run_synthetic_wisp_tests.gd'; Destination = 'tests\run_synthetic_wisp_tests.gd' },
    @{ Root = $gardenSource; Relative = 'tests\run_synthetic_wisp_tests.gd.uid'; Destination = 'tests\run_synthetic_wisp_tests.gd.uid' },
    @{ Root = $gardenSource; Relative = 'tests\capture_synthetic_garden_preview.gd'; Destination = 'tests\capture_synthetic_garden_preview.gd' },
    @{ Root = $gardenSource; Relative = 'tests\capture_synthetic_garden_preview.gd.uid'; Destination = 'tests\capture_synthetic_garden_preview.gd.uid' },
    @{ Root = $docsSource; Relative = 'habitat-layout.md'; Destination = 'docs\habitat-layout.md' },
    @{ Root = $docsSource; Relative = 'creature-sprite-pipeline.md'; Destination = 'docs\creature-sprite-pipeline.md' },
    @{ Root = $docsSource; Relative = 'validation\E05.2.md'; Destination = 'docs\validation\E05.2.md' },
    @{ Root = $docsSource; Relative = 'validation\validate_e05_2.ps1'; Destination = 'docs\validation\validate_e05_2.ps1' },
    @{ Root = '\\wsl.localhost\Ubuntu\home\sathler\projects\process-garden'; Relative = 'README.md'; Destination = 'README.md' },
    @{ Root = '\\wsl.localhost\Ubuntu\home\sathler\projects\process-garden'; Relative = 'DESIGN.md'; Destination = 'DESIGN.md' }
)

foreach ($item in $syncItems) {
    $source = Join-Path $item.Root $item.Relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Required source file is missing; no files have been synchronized: $source"
    }
}

foreach ($item in $syncItems) {
    $source = Join-Path $item.Root $item.Relative
    $destination = Join-Path $ProjectPath $item.Destination
    $sourceHash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    $destinationExists = Test-Path -LiteralPath $destination -PathType Leaf
    $destinationHash = if ($destinationExists) {
        (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
    } else { '' }
    if ($destinationExists -and $sourceHash -eq $destinationHash) {
        continue
    }

    if ($destinationExists) {
        $backup = Join-Path $backupRoot $item.Destination
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backup) | Out-Null
        Copy-Item -LiteralPath $destination -Destination $backup
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination
    $copiedHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
    if ($copiedHash -ne $sourceHash) {
        throw "Hash mismatch after sync: $destination"
    }
}

New-Item -ItemType Directory -Force -Path $logRoot | Out-Null

function Invoke-GodotCheck {
    param(
        [string]$Name,
        [string[]]$Arguments,
        [string]$RequiredSummary = ''
    )

    $logPath = Join-Path $logRoot "$Name.log"
    $output = & $GodotPath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $text = $output -join "`n"
    $output | Set-Content -LiteralPath $logPath
    if ($exitCode -ne 0) {
        throw "$Name failed with exit code $exitCode. See $logPath"
    }
    if ($text -match '(?m)ERROR:|SCRIPT ERROR:') {
        throw "$Name logged ERROR or SCRIPT ERROR. See $logPath"
    }
    if ($RequiredSummary -and $text -notmatch $RequiredSummary) {
        throw "$Name did not report its required zero-failure summary. See $logPath"
    }
    Write-Host "$Name passed; log: $logPath"
}

Invoke-GodotCheck -Name 'import' -Arguments @('--headless', '--editor', '--path', $ProjectPath, '--quit')
$suites = @(
    @{ Name = 'godot-main'; Runner = 'res://tests/run_tests.gd'; Summary = 'Godot tests: \d+ passed, 0 failed' },
    @{ Name = 'sprite-prototypes'; Runner = 'res://tests/run_sprite_prototype_tests.gd'; Summary = 'Sprite prototype tests: \d+ passed, 0 failed' },
    @{ Name = 'sprite-resolution'; Runner = 'res://tests/run_sprite_resolution_tests.gd'; Summary = 'Sprite resolution tests: \d+ passed, 0 failed' },
    @{ Name = 'animation-poc'; Runner = 'res://tests/run_animation_poc_tests.gd'; Summary = 'Animation proof tests: \d+ passed, 0 failed' },
    @{ Name = 'synthetic-wisp'; Runner = 'res://tests/run_synthetic_wisp_tests.gd'; Summary = 'Synthetic Wisp tests: \d+ passed, 0 failed' }
)
foreach ($suite in $suites) {
    Invoke-GodotCheck -Name $suite.Name -Arguments @('--headless', '--path', $ProjectPath, '--script', $suite.Runner) -RequiredSummary $suite.Summary
}

if ($RunBenchmarks) {
    foreach ($renderer in @('legacy', 'cozy_mystic', 'synthetic_life')) {
        foreach ($population in @(50, 150, 300, 500)) {
            $name = "benchmark-$renderer-$population"
            Invoke-GodotCheck -Name $name -Arguments @(
                '--path', $ProjectPath,
                '--script', 'res://tests/run_benchmark.gd', '--',
                "--renderer=$renderer", "--scenario=$population",
                '--duration-seconds=30', '--warmup-seconds=5', '--seed=2025'
            )
        }
    }
}

Write-Host "Validation completed. Logs: $logRoot"
Write-Host "For graphical REAL/DEMO, renderer, click/details, and reconnect checks, launch:"
Write-Host "Start-Process -FilePath '$GodotPath' -ArgumentList @('--path', '$ProjectPath')"

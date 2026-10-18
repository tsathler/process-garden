param(
    [string]$GodotPath = 'C:\tools\Godot\Godot_v4.7.2-stable_win64_console.exe',
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$gardenPath = Join-Path $repoRoot 'garden'
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repoRoot 'build\windows-candidate'
}
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$collectorOutput = Join-Path $OutputPath 'collector'
$collectorDist = Join-Path $repoRoot "build\collector-dist-$PID"
$godotOutput = Join-Path $OutputPath 'ProcessGarden.exe'

if ($env:OS -ne 'Windows_NT') {
    throw 'The Windows MVP build must run in native Windows PowerShell.'
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot 4.7.2 executable not found: $GodotPath"
}
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    throw 'uv is required; no Python installation is bundled into the output.'
}
if (Test-Path -LiteralPath $OutputPath) {
    throw "Output path already exists; move or rename it before building: $OutputPath"
}
if ($repoRoot.StartsWith('\\wsl.localhost\', [System.StringComparison]::OrdinalIgnoreCase) -and
    [string]::IsNullOrWhiteSpace($env:UV_PROJECT_ENVIRONMENT)) {
    $env:UV_PROJECT_ENVIRONMENT = Join-Path $env:TEMP 'ProcessGarden-WindowsBuildEnv'
}

Push-Location $repoRoot
try {
    uv sync --locked
    if ($LASTEXITCODE -ne 0) { throw "uv sync failed: $LASTEXITCODE" }
    uv run --locked ruff check .
    if ($LASTEXITCODE -ne 0) { throw "Ruff check failed: $LASTEXITCODE" }
    uv run --locked ruff format --check .
    if ($LASTEXITCODE -ne 0) { throw "Ruff format check failed: $LASTEXITCODE" }
    uv run --locked pytest
    if ($LASTEXITCODE -ne 0) { throw "pytest failed: $LASTEXITCODE" }

    & $GodotPath --headless --editor --path $gardenPath --quit
    if ($LASTEXITCODE -ne 0) { throw "Godot import failed: $LASTEXITCODE" }
    foreach ($runner in @(
        'res://tests/run_tests.gd',
        'res://tests/run_sprite_prototype_tests.gd',
        'res://tests/run_sprite_resolution_tests.gd',
        'res://tests/run_animation_poc_tests.gd',
        'res://tests/run_synthetic_wisp_tests.gd'
    )) {
        & $GodotPath --headless --path $gardenPath --script $runner
        if ($LASTEXITCODE -ne 0) { throw "Godot test suite failed ($runner): $LASTEXITCODE" }
    }

    New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
    uv run --locked pyinstaller --noconfirm --clean --onedir --windowed `
        --name ProcessGardenCollector `
        --distpath $collectorDist `
        --workpath (Join-Path $repoRoot 'build\pyinstaller-work') `
        --specpath (Join-Path $repoRoot 'build\pyinstaller-spec') `
        (Join-Path $repoRoot 'collector\entry.py')
    if ($LASTEXITCODE -ne 0) { throw "PyInstaller failed: $LASTEXITCODE" }
    New-Item -ItemType Directory -Force -Path $collectorOutput | Out-Null
    Move-Item -Path (Join-Path $collectorDist 'ProcessGardenCollector\*') -Destination $collectorOutput
    Remove-Item -LiteralPath $collectorDist -Recurse -Force

    & $GodotPath --headless --path $gardenPath --export-release 'Windows Desktop' $godotOutput
    if ($LASTEXITCODE -ne 0) { throw "Godot Windows export failed: $LASTEXITCODE" }
    if (-not (Test-Path -LiteralPath $godotOutput -PathType Leaf)) {
        throw "Godot export did not create $godotOutput"
    }
    Copy-Item -LiteralPath (Join-Path $repoRoot 'LICENSE') -Destination (Join-Path $OutputPath 'LICENSE.txt')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.txt') -Destination (Join-Path $OutputPath 'README.txt')
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'THIRD-PARTY-NOTICES.txt') -Destination (Join-Path $OutputPath 'THIRD-PARTY-NOTICES.txt')
    $licensesOutput = Join-Path $OutputPath 'licenses'
    New-Item -ItemType Directory -Force -Path $licensesOutput | Out-Null
    Copy-Item -Path (Join-Path $PSScriptRoot 'licenses\*') -Destination $licensesOutput
    Compress-Archive -Path (Join-Path $OutputPath '*') -DestinationPath "$OutputPath.zip" -CompressionLevel Optimal
    Write-Host "Windows MVP candidate built at $OutputPath"
    Write-Host "ZIP package: $OutputPath.zip"
} finally {
    Pop-Location
}

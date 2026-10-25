param(
    [Parameter(Mandatory = $true)]
    [string]$PackagePath,
    [int]$StartupTimeoutSeconds = 30
)

$ErrorActionPreference = 'Stop'
$PackagePath = [System.IO.Path]::GetFullPath($PackagePath)
$AppPath = Join-Path $PackagePath 'ProcessGarden.exe'
$CollectorPath = Join-Path $PackagePath 'collector\ProcessGardenCollector.exe'
if (-not (Test-Path -LiteralPath $AppPath -PathType Leaf)) {
    throw "ProcessGarden.exe not found in package: $PackagePath"
}
if (-not (Test-Path -LiteralPath $CollectorPath -PathType Leaf)) {
    throw "Bundled collector not found in package: $CollectorPath"
}
if (-not (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)) {
    throw 'Get-NetTCPConnection is required to verify the dynamic loopback endpoint.'
}

if (-not ('ProcessGardenLifecycleWindow' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ProcessGardenLifecycleWindow {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
}
'@
}

$RunRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("ProcessGarden-Lifecycle-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $RunRoot | Out-Null
$Apps = @()
$Collectors = @()

function Start-TestApp {
    param(
        [string]$Name,
        [string]$TestPackagePath = $PackagePath
    )

    $TempPath = Join-Path $RunRoot $Name
    $AppDataPath = Join-Path $TempPath 'appdata'
    $LocalAppDataPath = Join-Path $TempPath 'local-appdata'
    New-Item -ItemType Directory -Force -Path $TempPath, $AppDataPath, $LocalAppDataPath | Out-Null
    $StartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $StartInfo.FileName = Join-Path $TestPackagePath 'ProcessGarden.exe'
    $StartInfo.WorkingDirectory = $TestPackagePath
    $StartInfo.UseShellExecute = $false
    $StartInfo.EnvironmentVariables['TEMP'] = $TempPath
    $StartInfo.EnvironmentVariables['TMP'] = $TempPath
    $StartInfo.EnvironmentVariables['APPDATA'] = $AppDataPath
    $StartInfo.EnvironmentVariables['LOCALAPPDATA'] = $LocalAppDataPath
    $App = [System.Diagnostics.Process]::Start($StartInfo)
    if ($null -eq $App) { throw "Could not start test app: $Name" }
    $script:Apps += $App
    return $App
}

function Get-OwnedCollectors {
    param([int]$OwnerPid)

    $Children = @(Get-CimInstance -ClassName Win32_Process -Filter "ParentProcessId = $OwnerPid" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'ProcessGardenCollector.exe' })
    $Processes = @()
    foreach ($Child in $Children) {
        try {
            $Process = [System.Diagnostics.Process]::GetProcessById([int]$Child.ProcessId)
            $Process.Refresh()
            if (-not $Process.HasExited) { $Processes += $Process }
        } catch [System.ArgumentException] {
            # The child exited between the CIM query and opening its process handle.
        }
    }
    return $Processes
}

function Wait-OwnedCollector {
    param(
        [System.Diagnostics.Process]$App,
        [int]$TimeoutSeconds = $StartupTimeoutSeconds,
        [datetime]$StartedAfter = [datetime]::MinValue
    )

    $Deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([datetime]::UtcNow -lt $Deadline) {
        $App.Refresh()
        if ($App.HasExited) { throw 'The Process Garden app exited before its collector became ready.' }
        foreach ($Collector in @(Get-OwnedCollectors -OwnerPid $App.Id)) {
            if ($Collector.StartTime.ToUniversalTime() -gt $StartedAfter) {
                $script:Collectors += $Collector
                return $Collector
            }
        }
        Start-Sleep -Milliseconds 200
    }
    throw "The app did not start its collector within $TimeoutSeconds seconds."
}

function Assert-CollectorEndpoint {
    param([System.Diagnostics.Process]$Collector)

    $Deadline = [datetime]::UtcNow.AddSeconds(15)
    while ([datetime]::UtcNow -lt $Deadline) {
        $Connections = @(Get-NetTCPConnection -State Listen -OwningProcess $Collector.Id -ErrorAction SilentlyContinue |
            Where-Object { $_.LocalAddress -eq '127.0.0.1' })
        foreach ($Connection in $Connections) {
            try {
                $Snapshot = Invoke-RestMethod -Uri "http://127.0.0.1:$($Connection.LocalPort)/v1/snapshot" -TimeoutSec 2
                if ($Snapshot.schema_version -eq 1 -and $Snapshot.status -in @('ok', 'partial') -and $null -ne $Snapshot.processes) {
                    return
                }
            } catch {
                # The listener may appear before the HTTP server begins serving.
            }
        }
        Start-Sleep -Milliseconds 250
    }
    throw 'The owned collector did not serve a valid loopback snapshot.'
}

function Close-TestAppNormally {
    param([System.Diagnostics.Process]$App)

    $Deadline = [datetime]::UtcNow.AddSeconds(10)
    while ([datetime]::UtcNow -lt $Deadline) {
        $App.Refresh()
        if ($App.HasExited) { return }
        if ($App.MainWindowHandle -ne [IntPtr]::Zero) {
            [void][ProcessGardenLifecycleWindow]::PostMessage($App.MainWindowHandle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
            if ($App.WaitForExit(15000)) { return }
            throw 'The app did not close after receiving WM_CLOSE.'
        }
        Start-Sleep -Milliseconds 200
    }
    throw 'The app did not expose a main window for normal-close validation.'
}

function Assert-CollectorExited {
    param([System.Diagnostics.Process]$Collector)

    if (-not $Collector.WaitForExit(10000)) {
        throw "Owned collector PID $($Collector.Id) did not exit within ten seconds."
    }
}

function Assert-NoLifecycleFiles {
    param([string]$TempPath)

    $Files = @(Get-ChildItem -LiteralPath $TempPath -Filter 'process-garden-*' -File -ErrorAction SilentlyContinue)
    if ($Files.Count -gt 0) {
        throw "Collector lifecycle files remain in the isolated TEMP directory: $TempPath"
    }
}

try {
    $MissingPackage = Join-Path $RunRoot 'missing-collector-package'
    New-Item -ItemType Directory -Path $MissingPackage | Out-Null
    Copy-Item -Path (Join-Path $PackagePath '*') -Destination $MissingPackage -Recurse -Force
    $MissingCollector = Join-Path $MissingPackage 'collector\ProcessGardenCollector.exe'
    Move-Item -LiteralPath $MissingCollector -Destination "$MissingCollector.disabled"
    $MissingApp = Start-TestApp -Name 'missing-collector' -TestPackagePath $MissingPackage
    Start-Sleep -Seconds 3
    $MissingApp.Refresh()
    if ($MissingApp.HasExited) { throw 'The app exited when its bundled collector was absent.' }
    if (@(Get-OwnedCollectors -OwnerPid $MissingApp.Id).Count -gt 0) {
        throw 'The app started a collector despite the helper executable being absent.'
    }
    Close-TestAppNormally -App $MissingApp
    Assert-NoLifecycleFiles -TempPath (Join-Path $RunRoot 'missing-collector')
    Write-Host 'PASS: missing helper leaves the app running without a collector or stale handshake files.'

    $NormalApp = Start-TestApp -Name 'normal-close'
    $NormalCollector = Wait-OwnedCollector -App $NormalApp
    Assert-CollectorEndpoint -Collector $NormalCollector
    Close-TestAppNormally -App $NormalApp
    Assert-CollectorExited -Collector $NormalCollector
    Assert-NoLifecycleFiles -TempPath (Join-Path $RunRoot 'normal-close')
    Write-Host 'PASS: dynamic loopback startup and normal close clean up the owned collector.'

    $AbruptApp = Start-TestApp -Name 'abrupt-close'
    $AbruptCollector = Wait-OwnedCollector -App $AbruptApp
    Assert-CollectorEndpoint -Collector $AbruptCollector
    $AbruptApp.Kill()
    if (-not $AbruptApp.WaitForExit(10000)) { throw 'The test app did not exit abruptly.' }
    Assert-CollectorExited -Collector $AbruptCollector
    Assert-NoLifecycleFiles -TempPath (Join-Path $RunRoot 'abrupt-close')
    Write-Host 'PASS: abrupt app exit stops its exact collector and cleans lifecycle files.'

    $RecoveryApp = Start-TestApp -Name 'collector-recovery'
    $FirstCollector = Wait-OwnedCollector -App $RecoveryApp
    Assert-CollectorEndpoint -Collector $FirstCollector
    $FirstStartTime = $FirstCollector.StartTime.ToUniversalTime()
    $FirstCollector.Kill()
    if (-not $FirstCollector.WaitForExit(10000)) { throw 'The test collector did not exit after termination.' }
    $RecoveredCollector = Wait-OwnedCollector -App $RecoveryApp -TimeoutSeconds 45 -StartedAfter $FirstStartTime
    Assert-CollectorEndpoint -Collector $RecoveredCollector
    Close-TestAppNormally -App $RecoveryApp
    Assert-CollectorExited -Collector $RecoveredCollector
    Assert-NoLifecycleFiles -TempPath (Join-Path $RunRoot 'collector-recovery')
    Write-Host 'PASS: an unexpected owned-collector exit recovers and the replacement stops normally.'
} finally {
    foreach ($App in $Apps) {
        $App.Refresh()
        if (-not $App.HasExited) {
            $App.Kill()
            [void]$App.WaitForExit(10000)
        }
    }
    foreach ($Collector in $Collectors) {
        $Collector.Refresh()
        if (-not $Collector.HasExited) {
            $Collector.Kill()
            [void]$Collector.WaitForExit(10000)
        }
    }
    Remove-Item -LiteralPath $RunRoot -Recurse -Force -ErrorAction SilentlyContinue
}

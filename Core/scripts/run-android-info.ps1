$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$remotePath = '/data/local/tmp/hyperusbd-vscode'
$binaryPath = Join-Path $repoRoot 'target\aarch64-linux-android\debug\hyperusbd'

$adbCandidates = @(
    (Get-Command adb -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
    (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe')
)
if ($env:ANDROID_HOME) {
    $adbCandidates += Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe'
}
if ($env:ANDROID_SDK_ROOT) {
    $adbCandidates += Join-Path $env:ANDROID_SDK_ROOT 'platform-tools\adb.exe'
}
$adbCandidates = $adbCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

$adbPath = $adbCandidates | Select-Object -First 1
if (-not $adbPath) {
    throw 'adb.exe was not found. Add Android SDK platform-tools to PATH or set ANDROID_HOME.'
}

Push-Location $repoRoot
try {
    Write-Host 'Building the Android ARM64 binary...'
    cargo build --workspace
    if ($LASTEXITCODE -ne 0) {
        throw 'cargo build failed.'
    }

    if (-not (Test-Path -LiteralPath $binaryPath)) {
        throw "Build output was not found: $binaryPath"
    }

    & $adbPath get-state *> $null
    if ($LASTEXITCODE -ne 0) {
        throw 'No ADB device is available. Connect and authorize a device first.'
    }

    Write-Host 'Pushing the binary and running --info...'
    & $adbPath push $binaryPath $remotePath
    if ($LASTEXITCODE -ne 0) {
        throw 'adb push failed.'
    }

    & $adbPath shell chmod 755 $remotePath
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to make the remote binary executable.'
    }

    & $adbPath shell $remotePath --info
    if ($LASTEXITCODE -ne 0) {
        throw 'The binary failed to run on the device.'
    }
}
finally {
    try {
        & $adbPath shell rm -f $remotePath 2>$null
    }
    catch {
        Write-Verbose 'Unable to remove the temporary device binary.'
    }
    Pop-Location
}

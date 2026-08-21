[CmdletBinding()]
param(
    [string]$AvdName = 'HyperUSB_API_35',
    [string]$PackageName = 'org.orynnx.hyperusb',
    [string]$SystemImage = 'system-images;android-35;google_apis;x86_64',
    [switch]$CreateAvd,
    [switch]$SkipChecks
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$sdkRoot = if ($env:ANDROID_SDK_ROOT) {
    $env:ANDROID_SDK_ROOT
} elseif ($env:ANDROID_HOME) {
    $env:ANDROID_HOME
} else {
    Join-Path $env:LOCALAPPDATA 'Android\Sdk'
}

$adb = Join-Path $sdkRoot 'platform-tools\adb.exe'
$emulator = Join-Path $sdkRoot 'emulator\emulator.exe'
$avdManager = Join-Path $sdkRoot 'cmdline-tools\latest\bin\avdmanager.bat'
$flutter = Get-Command flutter -ErrorAction Stop
$apk = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-debug.apk'

foreach ($tool in @($adb, $emulator)) {
    if (-not (Test-Path -LiteralPath $tool)) {
        throw "缺少 Android SDK 工具：$tool"
    }
}

$existingAvds = & $emulator -list-avds
if ($existingAvds -notcontains $AvdName) {
    if (-not $CreateAvd) {
        throw "未找到 AVD '$AvdName'。安装 '$SystemImage' 后，使用 -CreateAvd 再次运行。"
    }
    if (-not (Test-Path -LiteralPath $avdManager)) {
        throw "缺少 avdmanager：$avdManager"
    }
    # 'no' keeps the default hardware profile when avdmanager asks about a custom profile.
    cmd.exe /c "echo no| `"$avdManager`" create avd --force --name $AvdName --package `"$SystemImage`""
    if ($LASTEXITCODE -ne 0) { throw "创建 AVD '$AvdName' 失败。" }
}

$device = (& $adb devices | Select-String '^emulator-.*\s+device$' | Select-Object -First 1).ToString().Split()[0]
if (-not $device) {
    Start-Process -FilePath $emulator -ArgumentList @('-avd', $AvdName, '-no-snapshot-save')
    $deadline = (Get-Date).AddMinutes(4)
    do {
        Start-Sleep -Seconds 3
        $device = (& $adb devices | Select-String '^emulator-.*\s+device$' | Select-Object -First 1).ToString().Split()[0]
    } until ($device -or (Get-Date) -ge $deadline)
    if (-not $device) { throw "模拟器 '$AvdName' 未在 4 分钟内连接 ADB。" }
}

& $adb -s $device wait-for-device
do {
    Start-Sleep -Seconds 2
    $bootComplete = (& $adb -s $device shell getprop sys.boot_completed).Trim()
} until ($bootComplete -eq '1')

Push-Location $projectRoot
try {
    & $flutter.Source pub get
    if (-not $SkipChecks) {
        & $flutter.Source analyze
        if ($LASTEXITCODE -ne 0) { throw 'flutter analyze 失败。' }
        & $flutter.Source test
        if ($LASTEXITCODE -ne 0) { throw 'flutter test 失败。' }
    }
    & $flutter.Source build apk --debug
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $apk)) { throw 'APK 构建失败。' }
} finally {
    Pop-Location
}

& $adb -s $device install -r $apk
if ($LASTEXITCODE -ne 0) { throw 'APK 安装失败。' }
& $adb -s $device shell monkey -p $PackageName 1 | Out-Host
if ($LASTEXITCODE -ne 0) { throw "无法启动 $PackageName。" }

$focusedWindow = (& $adb -s $device shell dumpsys window windows | Select-String 'mCurrentFocus' | Select-Object -First 1).ToString()
if ($focusedWindow -notmatch [regex]::Escape($PackageName)) {
    throw "应用未进入前台：$focusedWindow"
}

Write-Output "验证通过：$PackageName 已安装并在 $device 前台运行。"

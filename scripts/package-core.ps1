$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$core = Join-Path $projectRoot 'Core'
$asset = Join-Path $projectRoot 'UI\assets\core\arm64-v8a\hyperusbd'
$ndk = 'C:\Users\Orynnx\AppData\Local\Android\Sdk\ndk\28.2.13676358'
$linker = Join-Path $ndk 'toolchains\llvm\prebuilt\windows-x86_64\bin\aarch64-linux-android35-clang.cmd'
if (-not (Test-Path -LiteralPath $linker)) { throw "Android NDK linker not found: $linker" }
$env:CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER = $linker
Push-Location $core
try {
  cargo build --release --target aarch64-linux-android
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $asset) | Out-Null
  Copy-Item -LiteralPath (Join-Path $core 'target\aarch64-linux-android\release\hyperusbd') -Destination $asset -Force
} finally {
  Pop-Location
}

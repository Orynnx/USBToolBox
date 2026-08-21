# HyperUSB UI

HyperUSB 的 Flutter 用户界面，当前提供 Android 与 Windows 平台工程壳。

在本目录中执行：

```powershell
flutter analyze
flutter test
flutter run
```

Core 的 USB Gadget 控制逻辑位于仓库同级的 `../Core/`，UI 后续仅通过明确的应用层接口与其交互。

## Android 模拟器本地链路

首次准备好 Android SDK 的 `emulator`、`platform-tools`、`cmdline-tools` 与
`system-images;android-35;google_apis;x86_64` 后，在 `UI` 目录执行：

```powershell
.\tooling\deploy-android-emulator.ps1 -CreateAvd
```

脚本会创建或复用 `HyperUSB_API_35`，等待模拟器完全启动，依次执行依赖解析、
静态检查、测试、Debug APK 构建、ADB 安装和前台启动验证。日常复用时省略
`-CreateAvd`；`-SkipChecks` 只适合已经通过检查后的快速安装调试。

脚本只识别 `emulator-*` ADB 设备，因而不会把 APK 安装到连接的真机。

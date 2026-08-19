# HyperUSB UI

HyperUSB 的 Flutter 用户界面，当前提供 Android 与 Windows 平台工程壳。

在本目录中执行：

```powershell
flutter analyze
flutter test
flutter run
```

Core 的 USB Gadget 控制逻辑位于仓库同级的 `../Core/`，UI 后续仅通过明确的应用层接口与其交互。

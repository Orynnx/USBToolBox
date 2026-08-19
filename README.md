# HyperUSB

这个仓库由两个独立工程组成：

- `Core/`：Android ARM64 Rust USB Gadget 核心与 ADB 测试脚本。
- `UI/`：HyperUSB 的 Flutter 用户界面。

请分别在各自目录中执行构建、测试和平台相关命令。

在仓库根目录打开 VS Code 后，可使用下列共享运行配置：

- `Android: 构建并运行 --info（输出在终端）`：构建并运行 `Core` 的 Android 命令行程序。
- `Flutter: 运行 HyperUSB UI`：启动 `UI` 的 Flutter 应用。

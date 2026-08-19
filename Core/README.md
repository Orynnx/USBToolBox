# hyperusbd — Android ARM64 USB Gadget 核心

`hyperusbd` 是运行在 Android userspace 的 AArch64 native 程序。它通过 root 权限管理
ConfigFS USB Gadget，不是 APK、JNI、内核模块或 Android Service。

CLI 是开发者使用的单进程 Root shell，不启动 daemon、不提供 IPC。一个 shell 进程持有
一个 `UsbSession`，从 `start` 到 `stop` 期间可以连续发送 HID 报告、切换存储介质；进程
退出时也会尽力恢复 Android USB。`panic = "abort"` 或进程被杀时则使用持久恢复状态救援。

## 构建

工程默认目标是 `aarch64-linux-android`，链接器配置位于 `.cargo/config.toml`：

```powershell
rustup target add aarch64-linux-android
cargo build
cargo build --release
```

产物分别位于：

```text
target/aarch64-linux-android/debug/hyperusbd
target/aarch64-linux-android/release/hyperusbd
```

## CLI

```text
hyperusbd [shell]
hyperusbd info
hyperusbd --info
hyperusbd restore
```

不带参数时进入 shell。`info` 和兼容别名 `--info` 动态读取程序版本、Android 内核和 SDK、
Root、SELinux、ConfigFS、Gadget、UDC 及可写状态。缺少接口或权限时显示 `Unavailable`。

```text
hyperusb> start --hid --nkro --storage /data/media/0/HyperUSB/disk.img
hyperusb> hid type "diskpart"
hyperusb> hid key ENTER
hyperusb> hid release
hyperusb> hid chord ALT F4
hyperusb> hid chord CTRL SHIFT ESC
hyperusb> hid chord GUI R
hyperusb> storage eject 0
hyperusb> storage attach 0 /data/media/0/HyperUSB/other.img
hyperusb> stop
```

`start` 至少需要 `--hid`、`--nkro`、`--storage <image>` 或 `--cdrom <iso>` 之一。`--hid`
创建兼容 BIOS/PE 的 Boot Keyboard；`--nkro` 额外创建一个独立的 NKRO Keyboard interface，
它可用位图同时保持最多 224 个普通 Usage。两者同时启用时，shell 的 `hid` 命令只写 NKRO，
不会向 Host 重复输入。存储镜像必须是普通文件；不允许直接暴露块设备。`hid key <name>` 保持按下状态，需配对 `hid release`；
`hid chord <modifier/key>...` 发送组合键后自动释放，例如 `ALT F4`、`CTRL C`、
`CTRL SHIFT ESC`、`GUI R`。它支持左右 Ctrl/Shift/Alt/GUI 修饰键、方向键、导航键、
`F1..F12`、`A..Z` 和 `0..9`。完整用法可在 shell 内输入 `help` 查看。

### 崩溃恢复

接管 UDC 前，程序会原子写入 `/data/adb/hyperusb/usb_state.json`，其中保存原始
`sys.usb.config` 与两个 ADB 禁用属性。读取 `sys.usb.config` 或写入状态失败时，程序会
拒绝接管，绝不猜测默认配置。

正常 `stop` 先解绑 HyperUSB、恢复 Android 并确认 `g1` 稳定绑定 UDC，最后才删除状态
文件。如果 `panic = "abort"`、进程被杀或设备端操作中断，重新以 root 执行：

```bash
su -c hyperusbd restore
```

它会先解除 HyperUSB 的绑定，再用状态文件恢复 Android USB；成功后删除状态文件。若状态
文件不存在，`restore` 会报错而不会猜测或改写当前 USB 配置。

## USB 核心设计

HyperUSB 使用自己拥有的持久 Gadget，默认名称为 `hyperusb`。正常停用时不会删除 Gadget
根目录，避免部分 Android 厂商内核在删除 Gadget 后无法于同一次开机内重新创建。

一次会话由 `UsbSession` 完整管理：

1. 校验 HID 和全部存储 LUN 配置。
2. 从 `sys.usb.controller` 或 `/sys/class/udc` 解析 UDC。
3. 严格读取并原子保存当前 USB/ADB 属性；临时禁止厂商 Gadget HAL 抢回 ADB Function，
   再切换到 `none` 并释放 Android 的 `g1`。
4. 创建或复用持久 `hyperusb` Gadget。
5. 解绑、调整 HID 与 Mass Storage Function，再替换 configuration 链接。
6. 执行系统同步并绑定 UDC。
7. 停用或异常析构时解绑 HyperUSB、清空 backing file，恢复原 USB/ADB 属性，并等待
   Android `g1` 稳定重新绑定后才返回。

存储设备统一位于 `mass_storage.hyperusb`：每个 `lun.N` 是一个独立的磁盘或光驱，因此可
一次创建多个存储设备。重新配置时严格按照“清空 `file` → 设置
`ro/removable/cdrom/nofua` → 写入镜像路径”的顺序执行。

backing file 的 SELinux 标签必须允许内核 `file-storage` 线程访问。实机验证中，
`/data/local/tmp` 的 `shell_data_file` 会被 `u:r:kernel:s0` 拒绝；应使用参考脚本所在的
`/data/media/0` 路径及其 `media_rw_data_file` 标签。普通 Unix 权限或 `ro=0` 不能替代
SELinux 访问权限。

ConfigFS 的“清空”会写入换行符，等价于 shell 的 `echo "" > file`。零字节 write 不会
触发内核属性的 store 回调，不能用于 UDC 解绑或 LUN 弹出。

键盘同时支持标准 8 字节 Boot Keyboard Report 与 30 字节 NKRO 位图 Report。`Key`、
`Modifiers`、`KeyChord` 提供语义层，`KeyboardState` 与 `NkroKeyboardState` 可让 UI
保持 Ctrl 等按键状态；HID 端点根据 ConfigFS Function 与
`/sys/class/hidg` 的设备号匹配，不假设端点一定是 `/dev/hidg0`；端点保持打开，写入具备
Host 状态检查、限时重试、部分写检测和退出时全零释放。

## 验证

```powershell
cargo fmt --all -- --check
cargo test --target x86_64-pc-windows-msvc
cargo clippy --all-targets -- -D warnings
cargo build --release
```

## VS Code 一键运行 `--info`

在“运行和调试”中选择 `Android: 构建并运行 --info（输出在终端）` 后按 F5。脚本会从
Android Studio SDK 查找 `adb.exe`，构建、推送并运行程序，最后清理设备端临时文件。
输出显示在“终端”面板。

## 日志

Android 日志写入 logcat，tag 为 `HyperUSBCore`：

```bash
adb logcat -s HyperUSBCore
```

Debug 构建默认记录 `Debug` 及以上级别，Release 构建默认记录 `Info` 及以上级别。

## 实机验证结果

在 Android 17 / SDK 37 设备与 Windows Host 上已验证：Boot Keyboard 能发送实际文本；
256 MiB 可写 LUN 能由 Windows 创建 MBR、FAT32 分区并写入文件；断开并重新连接同一
backing image 后，文件内容与 SHA-256 保持一致。

## 工程结构

```text
src/main.rs                       进程 bootstrap
src/app.rs                        CLI 参数分发
src/info.rs                       --info 动态环境信息
src/logging.rs                    logcat 与本机日志初始化
src/usb_sub/usb_model.rs          唯一的目标配置和运行状态
src/usb_sub/usb_gadget.rs         ConfigFS、UDC 与 Android USB 所有权
src/usb_sub/usb_composite.rs      持久 Gadget 和完整会话生命周期
src/usb_sub/usb_recovery.rs       异常退出后的原子恢复状态
src/usb_sub/usb_hid.rs            Boot Keyboard 配置、编码与端点写入
src/usb_sub/usb_nkro.rs           独立 NKRO 键盘、位图状态与端点写入
src/usb_sub/usb_storage.rs        多 LUN Mass Storage 配置与介质管理
src/usb_sub/usb_serial.rs         CDC-ACM 参数占位
src/usb_sub/usb_uvc.rs            UVC 参数占位
src/usb_sub/usb_ncm.rs            CDC-NCM 参数占位
scripts/run-android-info.ps1      VS Code/ADB 的 --info 运行脚本
```

不要从 `/sdcard` 直接执行二进制，该路径通常带有 `noexec`。USB 切换必须以 root 身份运行。

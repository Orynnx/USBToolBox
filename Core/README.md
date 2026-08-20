# hyperusbd — Android ARM64 USB Gadget Daemon

> **UNTESTED — CDC ACM / UVC**
>
> 本版本只完成代码、编译和静态验证，尚未在真实 Android 设备或 USB Host 上验证 CDC ACM
> 串口通信、UVC 摄像头画面或 Android Camera2 Producer。不要将当前版本标记为硬件验收通过。

`hyperusbd` 是运行在 Android userspace 的 Root AArch64 程序。它通过 ConfigFS 管理一个
Boot Keyboard + CDC ACM Serial + UVC + Mass Storage Composite Gadget，并在停止或异常恢复时
还原 Android USB。

Core 不提供 NKRO、持续按键状态或 NCM；上层只需声明目标配置。Boot Keyboard 仍只提供一次性
chord，CDC ACM Serial 和 UVC 使用 Linux Gadget 的运行时机制。

## 构建

```powershell
cargo build --release
cargo test --target x86_64-pc-windows-msvc
cargo clippy --all-targets -- -D warnings
```

Android产物：

```text
target/aarch64-linux-android/release/hyperusbd
```

## 命令

```text
hyperusbd [daemon]
hyperusbd info
hyperusbd --info
hyperusbd restore
hyperusbd help
```

无参数和 `daemon` 都以前台方式启动常驻服务。进程由 KernelSU/Magisk 等外部服务管理，
Core 自己不 fork。

Socket：

```text
/data/adb/usb_sub/usb.sock
```

拥有 Socket文件访问权限的客户端可以使用设备自带的 netcat：

```sh
printf 'SET /data/adb/usb_sub/config.json\n' | su -c 'toybox nc -U -q 1 /data/adb/usb_sub/usb.sock'
printf 'BOOT_KEY CTRL SHIFT ESC\n' | su -c 'toybox nc -U -q 1 /data/adb/usb_sub/usb.sock'
```

完整协议和 JSON字段见 [USB 子设备上层接口](src/usb_sub/docs/API.md)。

## 生命周期与恢复

Daemon 严格执行：

1. 创建并保护 `/data/adb/usb_sub`。
2. 取得单实例 `flock`。
3. 检查并恢复 canonical/legacy状态。
4. 安全清理陈旧 Unix Socket。
5. 创建 `0600` Socket；部署方通过文件 owner/group和权限控制客户端访问。
6. 由唯一控制线程串行执行 USB操作。

接管 UDC 前，Core 会先用临时文件、`fsync`、原子 rename和父目录同步写入：

```text
/data/adb/usb_sub/usb_state.json
```

旧版本路径 `/data/adb/hyperusb/usb_state.json` 仍可用于一次恢复；两个状态同时存在时优先使用
canonical并记录 warning，恢复成功后尽力删除 stale legacy。Daemon退出只有在确认 Android USB
恢复后才删除当前恢复状态。`hyperusbd restore`没有待恢复状态时也成功返回 `OK`。

`SIGINT/SIGTERM` 通过安全唤醒通道通知控制线程，由控制线程完成 Boot释放、停止 USB、恢复
Android及删除 Socket。`SIGKILL` 后再次启动 Daemon会先恢复 Android USB，再开放 Socket。

## USB 核心

- `UsbTargetState` 表示恢复 Android USB或应用活动 HyperUSB配置。
- `UsbConfiguration` 只表示活动目标，由 `GadgetIdentity + UsbProfile`组成。
- `UsbProfile` 包含 `keyboard_enabled`、`serial_enabled`、可选的 UVC 能力描述和
  `storage_luns`。
- 相同 `SET` 是无操作；差异 `SET` 失败时先恢复旧配置。
- 空配置或最终 Function为零的配置会停止 HyperUSB并恢复 Android USB。
- Core不创建 Placeholder HID；只有显式启用 `keyboard.boot`时才暴露 Boot Keyboard接口。
- 只有显式启用 `serial.enabled`时才创建 `acm.hyperusb` CDC ACM Function；内核分配的
  `port_num`对应设备侧 `/dev/ttyGS<n>`。
- CDC ACM 的波特率、数据位、校验位和停止位由 Host 在打开串口时运行时发送，Core 不把它们
  作为 Gadget 静态配置。
- 只有显式启用 `uvc.enabled`时才创建 `uvc.hyperusb`；UVC 只根据 `formats[].frames[]`
  声明 MJPEG/YUYV 的分辨率与帧率，不暴露 ConfigFS 带宽参数或视频来源。
- Boot Keyboard只提供 Chord Tap：Press → 5 ms → Release。
- Mass Storage使用持久 `mass_storage.hyperusb` Function；重新配置严格按清空 backing file、
  设置属性、重新挂载的顺序执行。
- 旧 `hid.nkro` Function目录可以存在，但新版本始终解除其 configuration链接。

镜像必须是普通文件。实际设备上应使用能被 `u:r:kernel:s0` 访问的路径，例如
`/data/media/0/HyperUSB`；`/data/local/tmp` 的 SELinux标签通常会导致 Host读写失败。

## 日志与验证

日志写入 logcat，tag 为 `HyperUSBCore`：

```sh
adb logcat -s HyperUSBCore
```

硬件验收步骤见 [硬件测试](src/usb_sub/docs/HARDWARE_TEST.md)。

主要源码：

```text
src/app.rs                       Daemon/info/restore入口
src/usb_sub/usb_daemon.rs        Unix Socket、权限、背压与控制线程
src/usb_sub/usb_protocol.rs      SET/BOOT_KEY协议
src/usb_sub/usb_config.rs        JSON快照与语义校验
src/usb_sub/usb_model.rs         UsbConfiguration/UsbProfile
src/usb_sub/usb_composite.rs     USB会话、回滚与Android恢复
src/usb_sub/usb_gadget.rs        ConfigFS与UDC所有权
src/usb_sub/usb_hid.rs           Boot HID Chord Tap
src/usb_sub/usb_serial.rs        CDC ACM Function与 /dev/ttyGS<n>解析
src/usb_sub/usb_uvc.rs           UVC格式/帧描述与ConfigFS链接
src/usb_sub/uvc_runtime.rs       Producer Socket、UVC状态和2帧背压
src/usb_sub/uvc_v4l2.rs          Linux/Android UVC事件、Probe/Commit和V4L2输出
src/usb_sub/usb_storage.rs       Mass Storage LUN
src/usb_sub/usb_recovery.rs      崩溃一致恢复状态
```

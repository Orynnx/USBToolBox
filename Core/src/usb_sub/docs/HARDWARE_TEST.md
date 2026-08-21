# HyperUSB Core 硬件测试

> **UNTESTED — 本文是验收清单，不是当前版本的通过报告。**
>
> 当前 Core 版本尚未完成真实 Android 设备/USB Host 的 CDC ACM、CDC-NCM、UVC 画面和 Camera2 Producer
> 验证。文末已有的历史记录只覆盖当时版本的 Boot/Storage/Daemon 项目，不能证明本版本的
> ACM/UVC 已通过实机测试。

## 1. 前置条件

- Android设备已 Root并支持 ConfigFS USB Gadget。
- 接管有线 USB 后 ADB会断开，因此先启用无线 ADB。
- Windows Host直接连接 Android设备。
- Release二进制位于 `/data/local/tmp/hyperusbd`。
- 所有 Socket命令均在 Root shell中执行。

```powershell
cargo fmt --all -- --check
cargo test --target x86_64-pc-windows-msvc
cargo clippy --all-targets -- -D warnings
cargo build --release
adb push target/aarch64-linux-android/release/hyperusbd /data/local/tmp/hyperusbd
adb shell su -c "chmod 0755 /data/local/tmp/hyperusbd"
```

Daemon以前台语义运行，测试时可由 Root shell放到后台：

```sh
su -c 'nohup /data/local/tmp/hyperusbd daemon >/data/local/tmp/hyperusbd-daemon.log 2>&1 &'
```

确认 Socket和权限：

```sh
su -c 'ls -ldZ /data/adb/usb_sub; ls -lZ /data/adb/usb_sub/usb.sock'
```

发送命令（命令名和键名大小写不敏感）：

```sh
printf 'set /data/adb/usb_sub/empty.json\n' | su -c 'toybox nc -U -q 1 /data/adb/usb_sub/usb.sock'
```

## 2. Boot Keyboard

配置 `/data/adb/usb_sub/boot.json`：

```json
{
  "device": {
    "manufacturer": "HyperUSB",
    "product": "HyperUSB Boot Keyboard",
    "serialNumber": "HYPERUSB-BOOT-0001"
  },
  "keyboard": {
    "boot": true
  }
}
```

在 Windows打开文本框后执行：

```sh
printf 'SET /data/adb/usb_sub/boot.json\n' | su -c 'toybox nc -U -q 1 /data/adb/usb_sub/usb.sock'
printf 'BOOT_KEY SHIFT B\n' | su -c 'toybox nc -U -q 1 /data/adb/usb_sub/usb.sock'
printf 'BOOT_KEY O\n' | su -c 'toybox nc -U -q 1 /data/adb/usb_sub/usb.sock'
printf 'BOOT_KEY O\n' | su -c 'toybox nc -U -q 1 /data/adb/usb_sub/usb.sock'
printf 'BOOT_KEY T\n' | su -c 'toybox nc -U -q 1 /data/adb/usb_sub/usb.sock'
```

验收：

- Windows设备管理器显示一个可用的 HID Keyboard Device。
- 文本框得到 `BOOT`，没有重复字符或粘住的 modifier。
- `BOOT_KEY CTRL SHIFT ESC` 能打开 Windows任务管理器。
- 相同配置再次 `SET` 返回 `OK`，Host不重新枚举。

## 3. CDC ACM 串口

配置 `/data/adb/usb_sub/serial.json`：

```json
{
  "device": {
    "manufacturer": "HyperUSB",
    "product": "HyperUSB Serial",
    "serialNumber": "HYPERUSB-SERIAL-0001"
  },
  "serial": {
    "enabled": true
  }
}
```

应用配置：

```sh
printf 'SET /data/adb/usb_sub/serial.json\n' | su -c 'toybox nc -U -q 1 /data/adb/usb_sub/usb.sock'
```

设备侧读取 ACM Function 的端口编号：

```sh
cat /config/usb_gadget/hyperusb/functions/acm.hyperusb/port_num
```

如果读到 `0`，设备侧端点就是 `/dev/ttyGS0`。Host 侧应枚举出 CDC ACM COM 口；打开
COM 口时可使用任意常见的 `8N1`、`115200` 等参数，但这些是 Host 运行时参数，不是
HyperUSB 的静态 Gadget 配置。

验收：

- `acm.hyperusb` 已链接到 `configs/c.1`。
- Host 设备管理器出现 CDC ACM 串口。
- 读取 `port_num` 得到合法的非负整数，并映射到 `/dev/ttyGS<n>`。
- 将 `serial.enabled` 改为 `false` 后重新 `SET`，串口 Function 链接被移除，Android USB恢复。

## 4. CDC-NCM 网络

配置 `/data/adb/usb_sub/ncm.json`：

```json
{
  "device": {
    "manufacturer": "HyperUSB",
    "product": "HyperUSB NCM",
    "serialNumber": "HYPERUSB-NCM-0001"
  },
  "ncm": {
    "enabled": true,
    "deviceMac": "02:48:59:50:45:01",
    "hostMac": "02:48:59:50:45:02",
    "qmult": 5,
    "ifname": "hyperusb%d"
  }
}
```

应用并检查 ConfigFS 属性：

```sh
printf 'SET /data/adb/usb_sub/ncm.json\n' | su -c 'toybox nc -U -q 1 /data/adb/usb_sub/usb.sock'
printf 'NET_STATUS\n' | su -c 'toybox nc -U -q 1 /data/adb/usb_sub/usb.sock'
su -c 'cat /config/usb_gadget/hyperusb/functions/ncm.hyperusb/dev_addr'
su -c 'cat /config/usb_gadget/hyperusb/functions/ncm.hyperusb/host_addr'
su -c 'cat /config/usb_gadget/hyperusb/functions/ncm.hyperusb/qmult'
su -c 'cat /config/usb_gadget/hyperusb/functions/ncm.hyperusb/ifname'
su -c 'ip link'
```

验收：

- `ncm.hyperusb` 已链接到 `configs/c.1`，`dev_addr`、`host_addr` 和显式 `qmult` 与配置一致。
- `NET_STATUS` 返回 `enabled=true`，实际 `ifname` 是按 `deviceMac` 从 `/sys/class/net` 找到的网卡名，
  不应返回 `hyperusb%d` 模板；`deviceMac`/`hostMac` 与 ConfigFS、Android/Windows 实际值一致；
  `NET_STATUS abc` 返回 `ERR invalid_command`。
- `ifname` 在 UDC bind 后通过 MAC 匹配实际 Android netdev，并出现在 `ip link` 中。
- Windows 设备管理器显示 CDC-NCM/USB Ethernet 适配器且设备状态正常。
- Core 不配置 DHCP、IP、NAT 或路由；手工给 Android/Windows 设置同一网段地址后，分别验证双向
  `ping`、TCP 连接和（若环境具备）双向 `iperf3`。
- `SET empty.json` 后 NCM Function 链接移除、Android USB恢复，Host 网卡消失；再次 `SET ncm.json`
  时同一 serial 派生的 MAC 保持稳定。
- `SET empty.json` 后 `NET_STATUS` 返回 `OK {"enabled":false}`；未启动 Session 时查询也应返回同样结果。
- 先完成 NCM-only，再依次验证 NCM+Boot、NCM+Storage、NCM+UVC 和全组合；确认相同配置不重新枚举。

## 5. UVC 摄像头

配置 `/data/adb/usb_sub/uvc.json`：

```json
{
  "device": {
    "manufacturer": "HyperUSB",
    "product": "HyperUSB Camera",
    "serialNumber": "HYPERUSB-UVC-0001"
  },
  "uvc": {
    "enabled": true,
    "formats": [
      {
        "format": "mjpeg",
        "frames": [
          {"width": 1280, "height": 720, "fps": [30, 60]},
          {"width": 1920, "height": 1080, "fps": [30]}
        ]
      },
      {
        "format": "yuyv",
        "frames": [
          {"width": 640, "height": 480, "fps": [30]}
        ]
      }
    ]
  }
}
```

应用配置：

```sh
printf 'SET /data/adb/usb_sub/uvc.json\n' | su -c 'toybox nc -U -q 1 /data/adb/usb_sub/usb.sock'
```

验收：

- `uvc.hyperusb` 已链接到 `configs/c.1`。
- Host 识别出 USB Camera/UVC 摄像头。
- Host 能枚举 MJPEG 的 1280x720@30/60、1920x1080@30，以及 YUYV 640x480@30。
- `hyperusbd` 启动时能找到 `g_uvc` 的 `/dev/videoX` output 节点，并创建：
  `/data/adb/usb_sub/uvc.sock`。
- Producer 连接 `uvc.sock` 后先发送 `HELLO`，收到 Core 的 `FORMAT` 和 `STREAM_ON` 后，
  发送完整 MJPEG/YUYV `FRAME`；Host Camera 应能显示动态画面。
- Host 切换分辨率/FPS 时，Producer 应收到新的 `FORMAT`；Host 关闭摄像头时应收到
  `STREAM_OFF`。Producer 崩溃后 USB 不应重新枚举，重新连接应恢复当前状态。
- 本配置不指定摄像头来源，来源仍由 Producer 决定。
- 将 `uvc.enabled` 改为 `false` 后重新 `SET`，UVC Function 链接被移除，Android USB恢复。

## 6. 普通磁盘

创建测试镜像：

```sh
su -c 'mkdir -p /data/media/0/HyperUSB && dd if=/dev/zero of=/data/media/0/HyperUSB/disk-256m.img bs=1M count=256 conv=fsync'
```

配置 `/data/adb/usb_sub/disk.json`：

```json
{
  "device": {
    "manufacturer": "HyperUSB",
    "product": "HyperUSB Storage",
    "serialNumber": "HYPERUSB-DISK-0001"
  },
  "disk": {
    "enabled": true,
    "imagePath": "/data/media/0/HyperUSB/disk-256m.img",
    "readOnly": false,
    "removable": true,
    "cdrom": false
  }
}
```

```sh
printf 'SET /data/adb/usb_sub/disk.json\n' | su -c 'toybox nc -U -q 1 /data/adb/usb_sub/usb.sock'
```

Windows验收：

1. 只操作新出现的 `Linux File-Stor Gadget`，严禁选择系统盘。
2. 空白 removable镜像可能表现为 offset 0 的 whole-disk volume；确认物理扇区后再格式化。
3. 格式化为 FAT32并写入测试文件，记录 SHA-256。
4. 安全刷新并卸载，其中 `E:` 替换为实际盘符：

```powershell
fsutil volume flush E:
fsutil volume dismount E:
```

5. `SET empty.json`恢复 Android USB后重新 `SET`同一镜像，确认文件内容和 SHA-256不变。

## 7. CD-ROM

配置中设置 `cdrom=true` 并省略 `readOnly`，`SET` 应返回 `OK`，Windows应枚举只读光驱。

```json
"disk": {
  "enabled": true,
  "imagePath": "/data/media/0/HyperUSB/test.iso",
  "cdrom": true
}
```

将 `readOnly` 显式设为 `false` 后，`SET` 必须返回：

```text
ERR invalid_config
```

当前活动 USB不能断开或重新枚举。

## 8. 校验失败、恢复与安全退出

- 对活动会话发送不存在、超大或非法 JSON配置，确认返回稳定错误码且 Host设备保持不变。
- 在活动状态向 Daemon发送 `SIGTERM`，确认先恢复 Android USB，再删除 `usb.sock`。
- 在活动状态执行 `SIGKILL`，确认 recovery state仍存在。
- 重启 Daemon，确认它先恢复 Android USB并删除 recovery state，之后才创建 `usb.sock`。
- 在 Socket路径放置普通文件或 symlink时启动 Daemon，应自动删除并重新创建 Socket。
- 在 Socket路径放置目录时启动 Daemon，必须报错退出且不能删除该目录。
- 第二个 Daemon实例必须因 `flock` 失败而退出。
- `hyperusbd restore`在没有 recovery state时输出 `OK`并以成功状态退出。
- canonical和 legacy state同时存在时使用 canonical、记录 warning，并在成功后尽力删除 legacy。

## 9. 空配置与宽容协议

准备内容为 `{}` 的 `/data/adb/usb_sub/empty.json`，执行 `SET`：

- 当前 HyperUSB Session停止并恢复 Android USB。
- HyperUSB Gadget解除 UDC绑定，不保留 Boot HID Placeholder。
- recovery state在确认 Android USB恢复后删除。
- 再次 `SET empty.json`仍返回 `OK`。
- `BOOT_KEY A`返回 `ERR not_started`。
- 启用任意 Function但缺少或传入空 `serialNumber`时返回 `ERR invalid_config`，当前 USB保持不变。
- `boot_key ctrl LCTRL shift a`可以执行，重复 modifier自动去重。
- `BOOT_KEY NONE A`、缺少普通键、多个普通键和未知键仍返回 `ERR invalid_command`。

## 10. Daemon协议实测记录

2026-08-20，Android 17 / SDK 37 Root设备与 Windows Host完成本版 Daemon复测：

- Windows Host测试 35项全部通过，Clippy `-D warnings`通过，Android ARM64 Release构建通过。
- 工作目录为 `0700`、Socket为 `0600`；第二实例被 `flock`拒绝。
- 空配置会恢复 Android USB，不创建 HID Placeholder；启用实际 Function时必须提供非空 serial。
- 缺失或空 `serialNumber`的 Boot配置均返回 `ERR invalid_config`；活动配置仍保持
  `HYPERUSB-FINAL-BOOT-0001`且 UDC继续绑定。
- 有效 Boot配置在 Windows枚举为状态 `OK`的 USB输入设备和 HID Keyboard；宽容解析的
  `boot_key ctrl LCTRL shift Shift a`返回 `OK`。
- 活动 Boot会话执行 `SET {}`后 Android恢复为 `adb`，HyperUSB UDC和 Function链接清空，
  recovery state删除；重复空 `SET`返回 `OK`，随后 `BOOT_KEY A`返回 `ERR not_started`。
- `STOP`返回 `ERR invalid_command`。
- 普通文件和 symlink均被安全替换为 Socket，symlink目标内容保持不变；目录会阻止启动且目录保留。
- canonical和 legacy同时存在时 logcat记录选择 canonical的 warning，成功后两个状态文件都被清理。
- 连续两次在无状态时执行 `hyperusbd restore`均输出 `OK`。
- Boot配置枚举为 `USB\\VID_1D6B&PID_0104\\HYPERUSB-DAEMON-BOOT-0001`，HID Keyboard状态为 `OK`。
- `BOOT_KEY`在 Windows记事本实际输入 `Boot`；`CTRL A`、`CTRL C`返回 `OK`且剪贴板内容为 `Boot`。
- 活动 Boot会话收到 `cdrom=true, readOnly=false`配置时返回 `ERR invalid_config`，UDC保持连接。
- 256 MiB FAT32镜像枚举为 `Linux File-Stor Gadget`，序列号为 `HYPERUSB-DAEMON-DISK-0001`。
- 镜像中的测试文件内容为 `HyperUSB daemon SET persistence test 2026-08-20`；安全卸载、恢复 Android和再次
  `SET`后 SHA-256均为
  `EE485CE0A48A4B73EFBD631DC12EF8D46BC7061B63B60DF716EEC902E2DEEE40`。
- `cdrom=true`且省略 `readOnly`时枚举为 `Linux File-CD Gadget USB Device`。
- `SIGTERM`可恢复 Android USB并删除 Socket和 recovery state。
- 活动状态 `SIGKILL`后保留 canonical state；重启 Daemon先恢复 Android USB，再删除 state并创建 Socket。
- 单独存在 legacy state时可恢复并删除 legacy文件；canonical与 legacy后续均为空。
- 活动 Daemon期间执行 `restore`会被同一 `flock`拒绝。

经 ADB shell发起会改变 `sys.usb.config`的首个 `SET`时，adbd可能在响应返回前重启，导致该次
测试命令看不到响应文本；配置实际已应用，同配置再次 `SET`返回 `OK`。独立 Root上层进程不依赖
adbd，因此不受此测试传输链路影响。

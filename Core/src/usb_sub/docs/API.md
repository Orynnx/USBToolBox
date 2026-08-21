# HyperUSB Core API 契约

HyperUSB Core 是常驻 Root Daemon。上层通过 Unix Domain Socket **声明目标 USB 状态**，Daemon 自行处理首次创建、重新配置或恢复 Android USB。

```text
/data/adb/usb_sub/usb.sock
```

工作目录权限 `0700`，Socket 权限 `0600`。Core 不额外硬编码客户端 UID；部署方可以通过目录、Socket owner/group 和权限决定授权边界。

## 1. 协议

公开命令只有：

```text
SET <absolute-config-path>
BOOT_KEY <modifier>... <key>
NET_STATUS
```

响应：

```text
OK
ERR <code>
```

每条命令以 `\n` 或 `\r\n` 结束，最大 8 KiB。一个连接可以连续执行多条命令。命令名和按键名大小写不敏感，参数使用一个或多个 ASCII 空白分隔。

`NET_STATUS` 不接受参数；带参数时返回 `ERR invalid_command`。它是只读查询，即使当前没有活动 HyperUSB 会话也返回成功。

---

## 2. SET

```text
SET /data/adb/usb_sub/config.json
SET /data/My USB/config.json
```

`SET` 表示：

> 将当前 USB 状态设置为配置文件描述的目标状态。

上层不需要判断当前 USB 是否已经启动。

### 路径

命令与路径之间允许一个或多个 ASCII 空白。解析时移除整行首尾 ASCII 空白，路径内部保持不变：

* 必须是绝对路径。
* 可以包含空格。
* 不执行 shell quote、escape 或变量替换。
* 路径内部的空格不会被折叠。

### 行为

Daemon 一次打开配置文件，最多读取 64 KiB，关闭文件后解析内存快照。

配置有效后：

* 当前未运行 HyperUSB：按配置创建。
* 当前配置相同：直接返回 `OK`，不重新枚举。
* 当前配置不同：重新配置。
* 配置没有启用实际 Function：停止 HyperUSB并恢复 Android USB。

因此：

```json
{}
```

也是合法配置，表示：

```text
Android USB
```

空目标会尽力释放 Boot Keyboard、停用 HyperUSB、解绑 UDC并恢复 Android USB。
Core不创建 Placeholder HID；没有实际 Function时 Host不会看到一把虚拟键盘。

### 失败处理

配置读取或校验失败：

```text
当前 USB 状态保持不变
```

新配置应用失败：

```text
尝试恢复旧配置
```

恢复成功：

```text
ERR apply_failed
```

旧配置也恢复失败：

```text
恢复 Android USB
ERR restore_failed
```

---

## 3. JSON 配置

示例：

```json
{
  "device": {
    "manufacturer": "KeyBridge",
    "product": "USB Composite Device",
    "serialNumber": "KB202608200001",
    "vid": "0x1234",
    "pid": "0x5678",
    "deviceVersion": "1.20"
  },

  "disk": {
    "enabled": true,
    "imagePath": "/data/media/0/HyperUSB/disk.img",
    "readOnly": false,
    "removable": true,
    "cdrom": false
  },

  "keyboard": {
    "boot": true
  },

  "serial": {
    "enabled": true
  },

  "ncm": {
    "enabled": true,
    "deviceMac": "02:48:59:50:45:01",
    "hostMac": "02:48:59:50:45:02",
    "qmult": 5,
    "ifname": "hyperusb%d"
  },

  "uvc": {
    "enabled": true,
    "formats": [
      {
        "format": "mjpeg",
        "frames": [
          {
            "width": 1280,
            "height": 720,
            "fps": [30, 60]
          }
        ]
      }
    ]
  }
}
```

### 通用规则

未知字段忽略。

已知字段类型错误：

```text
ERR invalid_config
```

最终没有启用实际 Function时，不要求 `device`或 `serialNumber`，也不校验 VID/PID和其他 identity字段。

启用 Boot Keyboard、Serial、UVC、NCM 或 Disk时，`device`必须存在，`serialNumber`必须由调用方提供且非空。

所有显式提供的 USB 字符串不能包含 NUL、CR或 LF，最长 126个 UTF-16 code unit。

---

## 4. device

| 字段              | 类型     | 必填 | 默认值                    |
| --------------- | ------ | -- | ---------------------- |
| `manufacturer`  | string | 否  | `USB Device`           |
| `product`       | string | 否  | `Composite USB Device` |
| `serialNumber`  | string | 是  | 无                      |
| `vid`           | string | 否  | `0x1D6B`               |
| `pid`           | string | 否  | `0x0104`               |
| `deviceVersion` | string | 否  | `1.0`                  |

VID/PID 格式：

```text
0x1234
0xABCD
```

即 `0x` 加四位十六进制数字。

默认 VID/PID 仅用于开发测试，正式分发应显式配置合法取得的 VID/PID。

`deviceVersion` 使用 `major.minor`：

```text
"1.2"   -> 0x0102
"1.20"  -> 0x0120
"12.34" -> 0x1234
```

major 和 minor 范围均为 `0..99`。

---

## 5. disk

| 字段          | 类型      | 必填  | 默认值                        |
| ----------- | ------- | --- | -------------------------- |
| `enabled`   | boolean | 否   | `false`                    |
| `imagePath` | string  | 启用时 | 无                          |
| `readOnly`  | boolean | 否   | 普通磁盘 `false`，CD-ROM `true` |
| `removable` | boolean | 否   | `true`                     |
| `cdrom`     | boolean | 否   | `false`                    |

普通磁盘：

```json
{
  "disk": {
    "enabled": true,
    "imagePath": "/data/usb/disk.img"
  }
}
```

CD-ROM：

```json
{
  "disk": {
    "enabled": true,
    "imagePath": "/data/usb/boot.iso",
    "cdrom": true
  }
}
```

规则：

* `imagePath` 必须是绝对路径。
* 最终目标必须是普通文件。
* 不支持目录和块设备。
* 允许符号链接。
* `enabled=false` 时其他字段不参与语义校验，但类型仍必须正确。
* `cdrom=true` 且未指定 `readOnly` 时自动使用 `true`。
* `cdrom=true` 且显式指定 `readOnly=false` 时返回 `invalid_config`。

---

## 6. keyboard

```json
{
  "keyboard": {
    "boot": true
  }
}
```

Core 只提供标准 Boot Keyboard Chord Tap。

不提供：

```text
NKRO
KEY_DOWN
KEY_UP
持续按键状态
```

---

## 7. serial

```json
{
  "serial": {
    "enabled": true
  }
}
```

启用后，Core 创建并链接 ConfigFS Function：

```text
functions/acm.hyperusb
```

Linux Gadget 会在 Function 创建后分配只读的 `port_num`。读取该值 `n` 后，设备侧端点为：

```text
/dev/ttyGS<n>
```

第一版不暴露 `baudRate`、`dataBits`、`parity`、`stopBits` 或 `protocol` 配置。Host 仍可
发送 CDC ACM 的 `SET_LINE_CODING`、`SET_CONTROL_LINE_STATE` 和 `BREAK` 请求；这些参数
属于 Host 运行时状态，不改变 USB Bulk 传输本身的速率。

## 8. ncm

```json
{
  "device": {
    "serialNumber": "HYPERUSB-NCM-001"
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

`ncm.enabled=false`（默认值）时不创建 NCM Function。启用 NCM 时，调用方必须提供非空
`device.serialNumber`；未提供 `deviceMac` 或 `hostMac` 时，Core 根据 serial 稳定派生本地管理的
单播 MAC，且同一 serial 每次保持一致。显式 MAC 必须是六组十六进制字节、不能是 multicast，
且 `deviceMac` 与 `hostMac` 不能相同；大小写会规范化为小写 ConfigFS 值。

`qmult` 可省略。省略时 Core 不写 `functions/ncm.hyperusb/qmult`，使用内核默认值；显式提供时
必须是 `1..65535` 并写入 ConfigFS。`ifname` 可省略，默认写入 `hyperusb%d`；显式值必须非空、
不超过 15 个 UTF-8 字节且只包含字母、数字、`_`、`-` 或 `%`。这里的值是 ConfigFS 提供给
内核的命名模板，不一定是最终网卡名。UDC bind 后 Core 根据 `deviceMac` 枚举
`/sys/class/net/*/address`，记录匹配到的实际 netdev 名称；找不到匹配项则视为激活失败。

NCM Function 固定为 `ncm.hyperusb`。Core 只负责建立 USB Ethernet link，不配置 DHCP、静态 IP、
NAT、DNS、IP forwarding、路由或网络共享；IP 连通性由上层或测试脚本自行配置。

### NET_STATUS

`NET_STATUS` 返回当前实际运行状态，而不是原始配置内容：

```text
NET_STATUS
```

NCM 活动时，`ifname` 是 UDC bind 后根据设备 MAC 从 `/sys/class/net` 找到的实际 netdev 名称，
不是 `hyperusb%d` 这样的 ConfigFS 命名模板：

```text
OK {"enabled":true,"ifname":"hyperusb0","deviceMac":"02:48:59:50:45:01","hostMac":"02:48:59:50:45:02"}
```

NCM 未启用、HyperUSB 未启动或 `SET {}` 后：

```text
OK {"enabled":false}
```

返回值不包含 `qmult`、IP 地址、路由、Gateway、DNS、DHCP、NAT 或防火墙信息。配置变更失败并成功回滚时，查询仍返回旧的实际 NCM 状态。

## 9. UVC Runtime 契约（v1）

独立于 `usb.sock` 的运行时数据通道（仅 Producer 与 Core 通讯）：

```text
/data/adb/usb_sub/uvc.sock
```

固定头：

```c
struct UvcMessageHeader {
    char     magic[4];    // "HUVC"
    uint16_t version;     // 1
    uint16_t type;
    uint32_t payloadSize;
};
```

消息类型：

- `HELLO`：Producer 首次连接后发送。
- `FORMAT`：Core → Producer，通知 `format / width / height / fps`。
- `STREAM_ON` / `STREAM_OFF`：Core → Producer。
- `FRAME`：Producer → Core，携带完整一帧。

`FORMAT` 载荷：

```c
struct UvcFormat {
    uint32_t fourcc;   // "MJPG" / "YUYV"
    uint32_t width;
    uint32_t height;
    uint32_t fps;
};
```

`FRAME` 载荷：

```c
struct UvcFrameHeader {
    uint64_t sequence;
    uint64_t timestampNs;
    uint32_t dataSize;
    uint32_t flags;
};
```

核心规则：

- 同一时刻只允许一个 Producer 连接；
- Producer 需要先 HELLO，Core 才接受 FRAME；
- 只缓存完整帧，默认最多 2 帧，满时丢弃最旧；
- Producer 不需要使用 `/dev/videoX`、V4L2 ioctl、Probe/Commit 或 UVC payload 细节；这些由 Core
  内部 V4L2 backend 处理；
- `YUYV` 载荷必须正好是 `width*height*2` 字节，`MJPEG` 载荷必须非空。

`uvc` JSON 只声明能力，Frame source 由 Producer 决定（摄像头、屏幕、文件、图片等都可实现为 Producer）。

Core 内部数据面：

```text
Host Probe/Commit
        │
        ▼
UVC V4L2 event backend
        │ FORMAT / STREAM_ON/OFF
        ▼
uvc.sock Producer
        │ FRAME
        ▼
2-frame queue → MMAP V4L2 output → UVC Gadget → Host
```

Linux/Android 上，UVC Function 绑定后 Core 会定位 `g_uvc` 的 V4L2 output 节点，订阅
`UVC_EVENT_SETUP`、`UVC_EVENT_DATA`、`UVC_EVENT_STREAMON` 和 `UVC_EVENT_STREAMOFF`。
Host 的 Probe/Commit 会归一化到 JSON 中声明的 format/frame/fps，并通过 `FORMAT` 通知
Producer；`STREAM_ON` 后 Core 才接受并提交 `FRAME`。UVC Function 或 V4L2 output 节点
启动失败会作为 UVC Runtime 启动失败返回，不会报告一个实际不可用的 UVC 会话。

## 10. uvc

```json
{
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

`enabled=false` 时不创建 UVC Function，`formats` 不参与语义校验。`enabled=true` 时：

- `formats` 至少一个；每个格式至少一个 `frame`。
- `format` 大小写和首尾空白会归一化；第一版只支持 `mjpeg` 和 `yuyv`。
- `width`、`height` 和每个 `fps` 必须大于零；重复的格式、分辨率和 FPS 会合并去重。
- UVC Function 为 `uvc.hyperusb`，视频能力写入 ConfigFS 的 MJPEG/YUYV descriptors，并
  链接到 `fs/hs/ss` 中可用的 streaming class。
- `streaming_interval`、`streaming_maxpacket`、`streaming_maxburst`、
  `maxPayloadTransferSize`、`frameBufferSize`、`/dev/videoX` 和视频来源不属于配置契约。

Core 负责声明 UVC 能力、响应 Host 协商并把 Producer 帧写入 Gadget 的 V4L2 output；视频
来源仍由 Producer 决定，不由本配置决定。

## 11. BOOT_KEY

`BOOT_KEY` 执行一次完整的按键组合：

```text
Press Report
→ 保持 5 ms
→ Release Report
```

示例：

```text
BOOT_KEY ENTER
BOOT_KEY ALT F4
BOOT_KEY CTRL SHIFT ESC
BOOT_KEY RCTRL RALT DELETE
```

### modifier

通用名称固定映射到左侧：

```text
CTRL  = LCTRL
SHIFT = LSHIFT
ALT   = LALT
GUI   = LGUI
```

右侧 modifier：

```text
RCTRL
RSHIFT
RALT
RGUI
```

### 参数规则

必须包含：

```text
0 个或多个 modifier
+
恰好 1 个普通键
```

支持：

```text
A..Z
0..9
F1..F12
导航键
编辑键
```

命令、modifier和普通键名大小写不敏感；多余的首尾空白、连续空白以及重复 modifier会被归一化。

以下情况返回：

```text
ERR invalid_command
```

包括：

* 缺少普通键。
* 出现多个普通键。
* 未知键名。

如果 HyperUSB 当前未运行：

```text
ERR not_started
```

当前配置没有启用 Boot Keyboard：

```text
ERR boot_disabled
```

Press 和首次 Release 均成功后才返回：

```text
OK
```

Release 失败时 Daemon 会再次尽力发送全零 Report，并返回：

```text
ERR internal_error
```

---

## 12. 空配置与 Daemon退出

没有单独的 `STOP` 命令。

没有启用实际 Function的配置是一种合法目标状态：

例如：

```json
{}
```

执行：

```text
SET /data/adb/usb_sub/empty.json
```

Daemon 会：

```text
尽力释放 Boot Keyboard
→ 停用 HyperUSB Gadget
→ 解绑 UDC
→ 恢复 Android USB
→ OK
```

此后执行 `BOOT_KEY`返回 `ERR not_started`。

Daemon退出不属于配置协议。收到 `SIGINT`或 `SIGTERM`时才会停用 HyperUSB并恢复 Android USB。
异常退出后的离线恢复使用幂等命令 `hyperusbd restore`；没有待恢复状态时同样输出 `OK`。

因此上层始终遵循同一个原则：

```text
配置变化
   ↓
SET
```

无需判断应该执行 Start、Update 还是 Stop。

---

## 13. 错误码

```text
invalid_command
invalid_config_path
config_not_found
invalid_config
invalid_vid
invalid_pid
invalid_device_version
image_not_found
image_not_file
not_started
boot_disabled
apply_failed
restore_failed
internal_error
```

协议只返回稳定错误码。

详细错误记录到 logcat：

```text
HyperUSBCore
```

## 14. 上层调用模型

最终 API 可以概括为：

```text
SET <config>
    = 声明 USB 应该处于什么状态

BOOT_KEY <chord>
    = 执行一次 Boot Keyboard 组合键
```

除此之外，上层无需了解 ConfigFS、UDC、Mass Storage Gadget、HID Gadget 或 Android USB 恢复实现。

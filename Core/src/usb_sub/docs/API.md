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
```

响应：

```text
OK
ERR <code>
```

每条命令以 `\n` 或 `\r\n` 结束，最大 8 KiB。一个连接可以连续执行多条命令。命令名和按键名大小写不敏感，参数使用一个或多个 ASCII 空白分隔。

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

启用 Boot Keyboard或 Disk时，`device`必须存在，`serialNumber`必须由调用方提供且非空。

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

## 7. BOOT_KEY

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

## 8. 空配置与 Daemon退出

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

## 9. 错误码

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

## 10. 上层调用模型

最终 API 可以概括为：

```text
SET <config>
    = 声明 USB 应该处于什么状态

BOOT_KEY <chord>
    = 执行一次 Boot Keyboard 组合键
```

除此之外，上层无需了解 ConfigFS、UDC、Mass Storage Gadget、HID Gadget 或 Android USB 恢复实现。

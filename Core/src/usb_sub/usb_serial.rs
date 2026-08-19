//! CDC-ACM 串口配置占位。
//!
//! 开关状态统一保存在 `UsbProfile::serial_enabled`；本结构只描述未来 Function 所需参数。

#[derive(Debug, Clone, Default)]
pub struct UsbSerialConfig {
    pub port_name: Option<String>,
}

//! CDC-NCM 网络配置占位。
//!
//! 开关状态统一保存在 `UsbProfile::ncm_enabled`；本结构只描述未来网络接口参数。

#[derive(Debug, Clone, Default)]
pub struct UsbNcmConfig {
    pub interface_name: Option<String>,
}

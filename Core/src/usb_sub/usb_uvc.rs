//! UVC 摄像头配置占位。
//!
//! 开关状态统一保存在 `UsbProfile::uvc_enabled`；本结构不保存运行状态。

use std::path::PathBuf;

#[derive(Debug, Clone, Default)]
pub struct UsbUvcConfig {
    pub video_device: Option<PathBuf>,
}

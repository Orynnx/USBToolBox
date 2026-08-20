//! 非 Unix 平台的 UVC ConfigFS 空实现。
//!
//! UVC ConfigFS 和 Linux V4L2 只存在于 Unix/Android 设备侧。Host 编译仍需要
//! 保留相同的类型和方法签名，让配置、状态机和单元测试不被平台实现污染。

use std::path::Path;

use crate::usb_sub::{UsbError, UsbResult, UvcConfig};

#[derive(Debug, Default)]
pub struct UsbUvc;

impl UsbUvc {
    pub fn configure_function(
        &self,
        _function_path: impl AsRef<Path>,
        _config: &UvcConfig,
    ) -> UsbResult<()> {
        Err(UsbError::Unsupported("UVC ConfigFS 仅支持 Unix 设备侧"))
    }
}

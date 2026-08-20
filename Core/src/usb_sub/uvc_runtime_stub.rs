//! 仅用于非 Unix 平台的 UVC Runtime 空实现。

use crate::usb_sub::{UsbResult, UvcConfig, UvcFormatKind};

/// 与 Unix 平台一致的 Runtime 句柄（空实现）。
#[derive(Debug, Default)]
pub struct UsbUvcRuntime {
    active: bool,
}

/// UVC Runtime 的 Unix Socket 路径（非 Unix 平台为标识性常量）。
pub const UVC_SOCKET_PATH: &str = "/data/adb/usb_sub/uvc.sock";

impl UsbUvcRuntime {
    pub fn start(config: Option<&UvcConfig>) -> UsbResult<Self> {
        Ok(Self {
            active: config.is_some(),
        })
    }

    pub fn is_active(&self) -> bool {
        self.active
    }

    pub fn reconfigure(&self, _config: &UvcConfig) -> UsbResult<()> {
        Ok(())
    }

    pub fn set_streaming(&self, _enabled: bool) -> UsbResult<()> {
        Ok(())
    }

    pub fn notify_format(
        &self,
        _format: UvcFormatKind,
        _width: u32,
        _height: u32,
        _fps: u32,
    ) -> UsbResult<()> {
        Ok(())
    }

    pub fn stop(&mut self) -> UsbResult<()> {
        self.active = false;
        Ok(())
    }

    pub fn pending_queue_len(&self) -> usize {
        0
    }
}

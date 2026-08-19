//! USB 目标配置与运行状态。
//!
//! 这是 USB 开关状态的唯一来源。Mass Storage 通过 LUN 列表表达多个设备；Boot HID、
//! NKRO HID、串口、UVC 和 NCM 都是单实例开关，不再由各 Function 自己保存重复字段。

use std::path::PathBuf;
use std::time::Duration;

use crate::usb_sub::usb_gadget::GadgetIdentity;
use crate::usb_sub::usb_recovery::DEFAULT_USB_STATE_PATH;
use crate::usb_sub::usb_storage::StorageLun;
use crate::usb_sub::{UsbError, UsbResult};

/// 用户希望激活的 USB 组合。
#[derive(Debug, Clone, Default)]
pub struct UsbProfile {
    /// 是否向 Host 暴露一个 Boot Keyboard。
    pub keyboard_enabled: bool,
    /// 是否额外向 Host 暴露一个 NKRO 键盘 interface。
    ///
    /// 它与 Boot Keyboard 独立；两者同时启用时，Boot 保持兼容性，NKRO 用于多键并发。
    pub nkro_keyboard_enabled: bool,
    /// 每一项对应一个 `lun.N`，因此可以一次暴露多个磁盘或光驱。
    pub storage_luns: Vec<StorageLun>,
    /// CDC-ACM 目前只保留开关语义，实际 Function 尚未接入。
    pub serial_enabled: bool,
    /// UVC 目前只保留开关语义，实际 Function 尚未接入。
    pub uvc_enabled: bool,
    /// CDC-NCM 目前只保留开关语义，实际 Function 尚未接入。
    pub ncm_enabled: bool,
}

impl UsbProfile {
    pub fn validate(&self) -> UsbResult<()> {
        if self.serial_enabled || self.uvc_enabled || self.ncm_enabled {
            return Err(UsbError::Unsupported(
                "当前仅实现 HID 键盘与 Mass Storage Function",
            ));
        }
        if !self.keyboard_enabled && !self.nkro_keyboard_enabled && self.storage_luns.is_empty() {
            return Err(UsbError::InvalidInput(
                "USB 组合至少需要启用 Boot/NKRO 键盘或添加一个存储 LUN".into(),
            ));
        }
        for lun in &self.storage_luns {
            lun.validate()?;
        }
        Ok(())
    }
}

/// 一次 HyperUSB 会话使用的固定运行参数。
#[derive(Debug, Clone)]
pub struct UsbRuntimeConfig {
    /// ConfigFS Gadget 根目录；`None` 时自动探测两个 Android 常见位置。
    pub gadget_root: Option<PathBuf>,
    /// HyperUSB 自己拥有并长期保留的 Gadget 名称。
    pub gadget_name: String,
    /// HyperUSB Gadget 内的 configuration 名称。
    pub configuration_name: String,
    /// Android 系统原有 Gadget 名称，通常为 `g1`。
    pub android_gadget_name: String,
    /// USB 描述符与可见字符串。
    pub identity: GadgetIdentity,
    /// `setprop sys.usb.config none` 后等待 Android Gadget HAL 释放 UDC 的时间。
    pub android_release_delay: Duration,
    /// 显式解绑 Android Gadget 后等待控制器完成异步收尾的时间。
    pub udc_settle_delay: Duration,
    /// 绑定 HyperUSB 时仅针对 `EBUSY` 重试的最长时间。
    pub udc_bind_timeout: Duration,
    /// 停用后等待 Android Gadget 重新绑定 UDC 的最长时间。
    pub android_restore_timeout: Duration,
    /// 接管 Android USB 前写入的崩溃恢复状态文件。
    pub recovery_state_path: PathBuf,
}

impl Default for UsbRuntimeConfig {
    fn default() -> Self {
        Self {
            gadget_root: None,
            gadget_name: "hyperusb".into(),
            configuration_name: "c.1".into(),
            android_gadget_name: "g1".into(),
            identity: GadgetIdentity::default(),
            android_release_delay: Duration::from_secs(2),
            udc_settle_delay: Duration::from_secs(1),
            udc_bind_timeout: Duration::from_secs(3),
            android_restore_timeout: Duration::from_secs(5),
            recovery_state_path: PathBuf::from(DEFAULT_USB_STATE_PATH),
        }
    }
}

/// 当前会话的运行状态。
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub enum UsbRuntimeState {
    #[default]
    Stopped,
    Active {
        gadget: String,
        udc: String,
        keyboard_enabled: bool,
        nkro_keyboard_enabled: bool,
        storage_count: usize,
    },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_profile_is_rejected() {
        assert!(UsbProfile::default().validate().is_err());
    }

    #[test]
    fn storage_count_is_the_lun_count() {
        let profile = UsbProfile {
            storage_luns: vec![StorageLun::ejected_disk(), StorageLun::ejected_cdrom()],
            ..UsbProfile::default()
        };
        assert_eq!(profile.storage_luns.len(), 2);
        profile.validate().unwrap();
    }
}

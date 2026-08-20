//! USB 目标配置与运行状态。

use std::path::PathBuf;
use std::time::Duration;

use crate::usb_sub::usb_gadget::GadgetIdentity;
use crate::usb_sub::usb_recovery::DEFAULT_USB_STATE_PATH;
use crate::usb_sub::usb_storage::StorageLun;
use crate::usb_sub::UsbResult;

/// 一个至少包含实际 Function 的活动 HyperUSB配置。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UsbConfiguration {
    pub identity: GadgetIdentity,
    pub profile: UsbProfile,
}

impl UsbConfiguration {
    pub fn validate(&self) -> UsbResult<()> {
        if !self.profile.has_functions() {
            return Err(crate::usb_sub::UsbError::InvalidInput(
                "活动 HyperUSB 配置至少需要一个实际 Function".into(),
            ));
        }
        self.profile.validate()
    }
}

/// `SET` 的声明式目标：活动 HyperUSB配置，或完全恢复 Android USB。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum UsbTargetState {
    AndroidUsb,
    HyperUsb(UsbConfiguration),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UvcFormatKind {
    Mjpeg,
    Yuyv,
}

impl UvcFormatKind {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Mjpeg => "mjpeg",
            Self::Yuyv => "yuyv",
        }
    }

    pub const fn configfs_group(self) -> &'static str {
        match self {
            Self::Mjpeg => "mjpeg",
            Self::Yuyv => "uncompressed",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UvcFrame {
    pub width: u32,
    pub height: u32,
    pub fps: Vec<u32>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UvcFormat {
    pub format: UvcFormatKind,
    pub frames: Vec<UvcFrame>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UvcConfig {
    pub formats: Vec<UvcFormat>,
}

impl UvcConfig {
    pub fn validate(&self) -> UsbResult<()> {
        if self.formats.is_empty() {
            return Err(crate::usb_sub::UsbError::InvalidInput(
                "UVC enabled=true 时 formats 至少需要一个格式".into(),
            ));
        }

        for format in &self.formats {
            if format.frames.is_empty() {
                return Err(crate::usb_sub::UsbError::InvalidInput(format!(
                    "UVC 格式 {} 至少需要一个 frame",
                    format.format.as_str()
                )));
            }
            for frame in &format.frames {
                if frame.width == 0 || frame.height == 0 {
                    return Err(crate::usb_sub::UsbError::InvalidInput(
                        "UVC frame 的 width 和 height 必须大于零".into(),
                    ));
                }
                if frame.width > u16::MAX as u32 || frame.height > u16::MAX as u32 {
                    return Err(crate::usb_sub::UsbError::InvalidInput(
                        "UVC frame 的 width 和 height 不能超过 65535".into(),
                    ));
                }
                let buffer_size = u64::from(frame.width) * u64::from(frame.height) * 2;
                if buffer_size > u64::from(u32::MAX) {
                    return Err(crate::usb_sub::UsbError::InvalidInput(
                        "UVC frame 的最大缓冲区大小超过 ConfigFS 支持范围".into(),
                    ));
                }
                if frame.fps.is_empty() || frame.fps.contains(&0) {
                    return Err(crate::usb_sub::UsbError::InvalidInput(
                        "UVC frame 的 fps 至少需要一个且全部大于零".into(),
                    ));
                }
                if frame.fps.iter().any(|fps| *fps > 10_000_000) {
                    return Err(crate::usb_sub::UsbError::InvalidInput(
                        "UVC frame 的 fps 不能超过 10000000".into(),
                    ));
                }
            }
        }
        Ok(())
    }
}

/// 当前真正支持的 USB Function 组合。
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct UsbProfile {
    pub keyboard_enabled: bool,
    pub serial_enabled: bool,
    pub uvc: Option<UvcConfig>,
    pub storage_luns: Vec<StorageLun>,
}

impl UsbProfile {
    pub fn has_functions(&self) -> bool {
        self.keyboard_enabled
            || self.serial_enabled
            || self.uvc.is_some()
            || !self.storage_luns.is_empty()
    }

    pub fn validate(&self) -> UsbResult<()> {
        if let Some(uvc) = &self.uvc {
            uvc.validate()?;
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
    pub gadget_root: Option<PathBuf>,
    pub gadget_name: String,
    pub configuration_name: String,
    pub android_gadget_name: String,
    pub android_release_delay: Duration,
    pub udc_settle_delay: Duration,
    pub udc_bind_timeout: Duration,
    pub android_restore_timeout: Duration,
    pub recovery_state_path: PathBuf,
}

impl Default for UsbRuntimeConfig {
    fn default() -> Self {
        Self {
            gadget_root: None,
            gadget_name: "hyperusb".into(),
            configuration_name: "c.1".into(),
            android_gadget_name: "g1".into(),
            android_release_delay: Duration::from_secs(2),
            udc_settle_delay: Duration::from_secs(1),
            udc_bind_timeout: Duration::from_secs(3),
            android_restore_timeout: Duration::from_secs(5),
            recovery_state_path: PathBuf::from(DEFAULT_USB_STATE_PATH),
        }
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub enum UsbRuntimeState {
    #[default]
    Stopped,
    Active {
        gadget: String,
        udc: String,
        keyboard_enabled: bool,
        serial_enabled: bool,
        uvc_enabled: bool,
        storage_count: usize,
    },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_profile_is_valid_android_target_but_not_active_configuration() {
        UsbProfile::default().validate().unwrap();
        let configuration = UsbConfiguration {
            identity: GadgetIdentity::default(),
            profile: UsbProfile::default(),
        };
        assert!(configuration.validate().is_err());
    }

    #[test]
    fn boot_or_storage_makes_profile_valid() {
        UsbProfile {
            keyboard_enabled: true,
            serial_enabled: false,
            uvc: None,
            storage_luns: Vec::new(),
        }
        .validate()
        .unwrap();

        UsbProfile {
            keyboard_enabled: false,
            serial_enabled: false,
            uvc: None,
            storage_luns: vec![StorageLun::ejected_disk()],
        }
        .validate()
        .unwrap();
    }
}

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

/// 当前真正支持的 USB Function 组合。
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct UsbProfile {
    pub keyboard_enabled: bool,
    pub storage_luns: Vec<StorageLun>,
}

impl UsbProfile {
    pub fn has_functions(&self) -> bool {
        self.keyboard_enabled || !self.storage_luns.is_empty()
    }

    pub fn validate(&self) -> UsbResult<()> {
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
            storage_luns: Vec::new(),
        }
        .validate()
        .unwrap();

        UsbProfile {
            keyboard_enabled: false,
            storage_luns: vec![StorageLun::ejected_disk()],
        }
        .validate()
        .unwrap();
    }
}

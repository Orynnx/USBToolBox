//! 持久 Composite Gadget 与完整 USB 会话。
//!
//! [`UsbComposite`] 只管理 HyperUSB 自己的 Gadget；[`UsbSession`] 再把 Android 系统 USB
//! 所有权、UDC 绑定和失败恢复组合成一个不可拆开的生命周期。调用方无需手工拼接
//! `setprop`、ConfigFS 与清理步骤。

use std::path::PathBuf;
use std::time::Duration;

use log::{debug, info, warn};

use crate::usb_sub::usb_gadget::{
    discover_udc, restore_android_usb_from_state, AndroidUsbLease, UsbGadgetController,
};
use crate::usb_sub::usb_hid::{resolve_hid_endpoint, HidKeyboardWriter, UsbHid};
use crate::usb_sub::usb_model::{UsbProfile, UsbRuntimeConfig, UsbRuntimeState};
use crate::usb_sub::usb_nkro::{nkro_hid, NkroKeyboardWriter};
use crate::usb_sub::usb_recovery::UsbRecoveryState;
use crate::usb_sub::usb_storage::UsbStorage;
use crate::usb_sub::{UsbError, UsbResult};

const HID_INSTANCE: &str = "hid.hyperusb";
const NKRO_INSTANCE: &str = "hid.nkro";
const STORAGE_INSTANCE: &str = "mass_storage.hyperusb";

/// 一个持久的 HyperUSB Composite Gadget。
#[derive(Debug)]
pub struct UsbComposite {
    controller: UsbGadgetController,
}

impl UsbComposite {
    pub fn new(controller: UsbGadgetController) -> Self {
        Self { controller }
    }

    pub fn controller(&self) -> &UsbGadgetController {
        &self.controller
    }

    /// 将未绑定的持久 Gadget 调整到目标配置并绑定 UDC。
    pub fn activate(
        &self,
        profile: &UsbProfile,
        identity: &crate::usb_sub::GadgetIdentity,
        udc: &str,
        bind_timeout: Duration,
    ) -> UsbResult<()> {
        profile.validate()?;
        info!(
            "Activating HyperUSB: boot_keyboard={}, nkro_keyboard={}, storage_luns={}, udc={udc}",
            profile.keyboard_enabled,
            profile.nkro_keyboard_enabled,
            profile.storage_luns.len()
        );
        self.controller.unbind()?;

        let result = (|| {
            self.controller.ensure_base(identity)?;
            self.controller.unlink_function(HID_INSTANCE)?;
            self.controller.unlink_function(NKRO_INSTANCE)?;
            self.controller.unlink_function(STORAGE_INSTANCE)?;

            if profile.keyboard_enabled {
                let path = self.controller.function_path(HID_INSTANCE)?;
                UsbHid::default().configure_function(path)?;
                self.controller.replace_function_link(HID_INSTANCE)?;
            }

            if profile.nkro_keyboard_enabled {
                let path = self.controller.function_path(NKRO_INSTANCE)?;
                nkro_hid().configure_function(path)?;
                self.controller.replace_function_link(NKRO_INSTANCE)?;
            }

            let storage_path = self.controller.function_path(STORAGE_INSTANCE)?;
            if profile.storage_luns.is_empty() {
                UsbStorage::detach_all(storage_path)?;
            } else {
                UsbStorage::new(profile.storage_luns.clone()).reconcile_function(&storage_path)?;
                self.controller.replace_function_link(STORAGE_INSTANCE)?;
            }

            self.controller.sync_and_bind(udc, bind_timeout)
        })();

        if let Err(error) = result {
            warn!("HyperUSB activation failed; rolling back: {error}");
            let rollback = self.deactivate();
            return match rollback {
                Ok(()) => Err(error),
                Err(rollback_error) => Err(UsbError::Unavailable(format!(
                    "激活 USB 失败：{error}；回滚也失败：{rollback_error}"
                ))),
            };
        }
        Ok(())
    }

    /// 解绑并卸载 HyperUSB 自己的 Function，但保留 Gadget 与 Function 目录。
    pub fn deactivate(&self) -> UsbResult<()> {
        debug!("Deactivating HyperUSB functions while preserving Gadget structure");
        let mut errors = Vec::new();
        if let Err(error) = self.controller.unbind() {
            errors.push(error.to_string());
        }
        for instance in [HID_INSTANCE, NKRO_INSTANCE, STORAGE_INSTANCE] {
            if let Err(error) = self.controller.unlink_function(instance) {
                errors.push(error.to_string());
            }
        }
        match self.controller.function_path(STORAGE_INSTANCE) {
            Ok(path) => {
                if let Err(error) = UsbStorage::detach_all(path) {
                    errors.push(error.to_string());
                }
            }
            Err(error) => errors.push(error.to_string()),
        }

        if errors.is_empty() {
            Ok(())
        } else {
            Err(UsbError::Unavailable(format!(
                "停用 USB 时发生错误：{}",
                errors.join("；")
            )))
        }
    }

    pub fn hid_endpoint(&self) -> UsbResult<PathBuf> {
        resolve_hid_endpoint(self.controller.function_path(HID_INSTANCE)?)
    }

    pub fn nkro_hid_endpoint(&self) -> UsbResult<PathBuf> {
        resolve_hid_endpoint(self.controller.function_path(NKRO_INSTANCE)?)
    }
}

/// 一次从 Android USB 切换到 HyperUSB、再安全恢复的完整会话。
pub struct UsbSession {
    composite: UsbComposite,
    android_lease: Option<AndroidUsbLease>,
    config: UsbRuntimeConfig,
    profile: UsbProfile,
    udc: String,
    state: UsbRuntimeState,
}

impl UsbSession {
    pub fn start(config: UsbRuntimeConfig, profile: UsbProfile) -> UsbResult<Self> {
        profile.validate()?;
        if UsbRecoveryState::load(&config.recovery_state_path)?.is_some() {
            return Err(UsbError::Unavailable(format!(
                "发现未恢复的 USB 状态：{}；请先运行 `hyperusbd restore`",
                config.recovery_state_path.display()
            )));
        }
        let controller = match config.gadget_root.as_ref() {
            Some(root) => {
                UsbGadgetController::new(root, &config.gadget_name, &config.configuration_name)?
            }
            None => UsbGadgetController::discover(&config.gadget_name, &config.configuration_name)?,
        };
        let udc = discover_udc()?;
        info!("Starting HyperUSB session on UDC {udc}");
        let mut android_lease = AndroidUsbLease::acquire(
            controller.root(),
            &config.android_gadget_name,
            config.android_release_delay,
            config.udc_settle_delay,
            config.android_restore_timeout,
            config.recovery_state_path.clone(),
        )?;
        let composite = UsbComposite::new(controller);

        if let Err(error) =
            composite.activate(&profile, &config.identity, &udc, config.udc_bind_timeout)
        {
            let restore = android_lease.restore();
            return match restore {
                Ok(()) => Err(error),
                Err(restore_error) => Err(UsbError::Unavailable(format!(
                    "启动 HyperUSB 失败：{error}；恢复 Android USB 也失败：{restore_error}"
                ))),
            };
        }

        let state = UsbRuntimeState::Active {
            gadget: config.gadget_name.clone(),
            udc: udc.clone(),
            keyboard_enabled: profile.keyboard_enabled,
            nkro_keyboard_enabled: profile.nkro_keyboard_enabled,
            storage_count: profile.storage_luns.len(),
        };
        Ok(Self {
            composite,
            android_lease: Some(android_lease),
            config,
            profile,
            udc,
            state,
        })
    }

    pub fn state(&self) -> &UsbRuntimeState {
        &self.state
    }

    pub fn udc(&self) -> &str {
        &self.udc
    }

    /// 当前会话实际启用的组合。调用方如需变更，必须通过 [`Self::reconfigure`]，不能
    /// 直接修改这个值后继续向已绑定 Gadget 写入。
    pub fn profile(&self) -> &UsbProfile {
        &self.profile
    }

    pub fn udc_state_path(&self) -> PathBuf {
        PathBuf::from(format!("/sys/class/udc/{}/state", self.udc))
    }

    pub fn open_keyboard(&self) -> UsbResult<HidKeyboardWriter> {
        if !self.profile.keyboard_enabled {
            return Err(UsbError::Unavailable("当前 USB 组合未启用键盘".into()));
        }
        HidKeyboardWriter::open(self.composite.hid_endpoint()?, self.udc_state_path())
    }

    /// 打开 NKRO 键盘端点。它是独立 Function，因此不会与 Boot 键盘共用 `/dev/hidg*`。
    pub fn open_nkro_keyboard(&self) -> UsbResult<NkroKeyboardWriter> {
        if !self.profile.nkro_keyboard_enabled {
            return Err(UsbError::Unavailable(
                "当前 USB 组合未启用 NKRO 键盘".into(),
            ));
        }
        NkroKeyboardWriter::open(self.composite.nkro_hid_endpoint()?, self.udc_state_path())
    }

    /// 在同一个 root CLI 会话中替换已启用的 Function 组合。
    ///
    /// ConfigFS 只能在 UDC 未绑定时调整 Function；`activate` 已负责解绑、重建链接并
    /// 重新绑定。若重配失败，本会话立即停止并尝试恢复 Android，避免半配置 Gadget
    /// 持续占用 UDC。
    pub fn reconfigure(&mut self, profile: UsbProfile) -> UsbResult<()> {
        if matches!(self.state, UsbRuntimeState::Stopped) || self.android_lease.is_none() {
            return Err(UsbError::Unavailable("当前没有活动的 HyperUSB 会话".into()));
        }
        profile.validate()?;
        if let Err(error) = self.composite.activate(
            &profile,
            &self.config.identity,
            &self.udc,
            self.config.udc_bind_timeout,
        ) {
            let stop_error = self.stop_inner().err();
            return match stop_error {
                Some(stop_error) => Err(UsbError::Unavailable(format!(
                    "重新配置 HyperUSB 失败：{error}；恢复 Android USB 也失败：{stop_error}"
                ))),
                None => Err(error),
            };
        }

        self.profile = profile;
        self.state = UsbRuntimeState::Active {
            gadget: self.config.gadget_name.clone(),
            udc: self.udc.clone(),
            keyboard_enabled: self.profile.keyboard_enabled,
            nkro_keyboard_enabled: self.profile.nkro_keyboard_enabled,
            storage_count: self.profile.storage_luns.len(),
        };
        Ok(())
    }

    /// 恢复异常退出时遗留的 Android USB 状态。
    ///
    /// 必须先解除 HyperUSB 自己的 UDC 绑定，再把 Android 原始属性写回；否则 Android
    /// Gadget 很可能因 UDC 仍被占用而无法重新出现。
    pub fn restore_persisted(config: UsbRuntimeConfig) -> UsbResult<()> {
        let controller = match config.gadget_root.as_ref() {
            Some(root) => {
                UsbGadgetController::new(root, &config.gadget_name, &config.configuration_name)?
            }
            None => UsbGadgetController::discover(&config.gadget_name, &config.configuration_name)?,
        };
        let composite = UsbComposite::new(controller);
        let deactivate = composite.deactivate();
        let restore = restore_android_usb_from_state(
            composite.controller().root(),
            &config.android_gadget_name,
            config.android_restore_timeout,
            &config.recovery_state_path,
        );
        match (deactivate, restore) {
            (Ok(()), Ok(())) => Ok(()),
            (Err(error), Ok(())) | (Ok(()), Err(error)) => Err(error),
            (Err(deactivate_error), Err(restore_error)) => Err(UsbError::Unavailable(format!(
                "解除 HyperUSB 绑定失败：{deactivate_error}；恢复 Android USB 也失败：{restore_error}"
            ))),
        }
    }

    pub fn stop(mut self) -> UsbResult<()> {
        self.stop_inner()
    }

    fn stop_inner(&mut self) -> UsbResult<()> {
        if matches!(self.state, UsbRuntimeState::Stopped) {
            return Ok(());
        }

        let deactivate = self.composite.deactivate();
        let restore = match self.android_lease.as_mut() {
            Some(lease) => lease.restore(),
            None => Ok(()),
        };
        self.android_lease = None;
        self.state = UsbRuntimeState::Stopped;

        info!("HyperUSB session stopped");

        match (deactivate, restore) {
            (Ok(()), Ok(())) => Ok(()),
            (Err(error), Ok(())) | (Ok(()), Err(error)) => Err(error),
            (Err(deactivate_error), Err(restore_error)) => Err(UsbError::Unavailable(format!(
                "停用 HyperUSB 失败：{deactivate_error}；恢复 Android USB 也失败：{restore_error}"
            ))),
        }
    }
}

impl Drop for UsbSession {
    fn drop(&mut self) {
        let _ = self.stop_inner();
    }
}

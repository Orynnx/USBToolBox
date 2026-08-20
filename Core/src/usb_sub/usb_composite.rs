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
use crate::usb_sub::usb_model::{UsbConfiguration, UsbProfile, UsbRuntimeConfig, UsbRuntimeState};
use crate::usb_sub::usb_recovery::UsbRecoveryState;
use crate::usb_sub::usb_serial::UsbSerial;
use crate::usb_sub::usb_storage::UsbStorage;
use crate::usb_sub::{UsbError, UsbResult, UsbUvc, UsbUvcRuntime, UvcConfig, UvcFormatKind};

const HID_INSTANCE: &str = "hid.hyperusb";
/// 旧版本可能在持久 Gadget 中留下这个链接；新版本只负责解除，不再创建 NKRO。
const LEGACY_NKRO_INSTANCE: &str = "hid.nkro";
const SERIAL_INSTANCE: &str = "acm.hyperusb";
const UVC_INSTANCE: &str = "uvc.hyperusb";
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
            "Activating HyperUSB: boot_keyboard={}, serial={}, uvc_formats={}, storage_luns={}, udc={udc}",
            profile.keyboard_enabled,
            profile.serial_enabled,
            profile.uvc.as_ref().map_or(0, |uvc| uvc.formats.len()),
            profile.storage_luns.len()
        );
        self.controller.unbind()?;

        let result = (|| {
            self.controller.ensure_base(identity)?;
            self.controller.unlink_function(HID_INSTANCE)?;
            self.controller.unlink_function(LEGACY_NKRO_INSTANCE)?;
            self.controller.unlink_function(SERIAL_INSTANCE)?;
            self.controller.unlink_function(UVC_INSTANCE)?;
            self.controller.unlink_function(STORAGE_INSTANCE)?;

            if profile.keyboard_enabled {
                let path = self.controller.function_path(HID_INSTANCE)?;
                UsbHid::default().configure_function(path)?;
                self.controller.replace_function_link(HID_INSTANCE)?;
            }

            if profile.serial_enabled {
                let path = self.controller.function_path(SERIAL_INSTANCE)?;
                UsbSerial.configure_function(path)?;
                self.controller.replace_function_link(SERIAL_INSTANCE)?;
            }

            if let Some(uvc) = &profile.uvc {
                let path = self.controller.function_path(UVC_INSTANCE)?;
                UsbUvc.configure_function(path, uvc)?;
                self.controller.replace_function_link(UVC_INSTANCE)?;
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
        for instance in [
            HID_INSTANCE,
            LEGACY_NKRO_INSTANCE,
            SERIAL_INSTANCE,
            UVC_INSTANCE,
            STORAGE_INSTANCE,
        ] {
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

    pub fn serial_endpoint(&self) -> UsbResult<PathBuf> {
        UsbSerial::endpoint_path(self.controller.function_path(SERIAL_INSTANCE)?)
    }
}

/// 一次从 Android USB 切换到 HyperUSB、再安全恢复的完整会话。
pub struct UsbSession {
    composite: UsbComposite,
    android_lease: Option<AndroidUsbLease>,
    config: UsbRuntimeConfig,
    configuration: UsbConfiguration,
    udc: String,
    uvc_runtime: UsbUvcRuntime,
    state: UsbRuntimeState,
}

impl UsbSession {
    pub fn start(config: UsbRuntimeConfig, configuration: UsbConfiguration) -> UsbResult<Self> {
        configuration.validate()?;
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

        if let Err(error) = composite.activate(
            &configuration.profile,
            &configuration.identity,
            &udc,
            config.udc_bind_timeout,
        ) {
            let restore = android_lease.restore();
            return match restore {
                Ok(()) => Err(error),
                Err(restore_error) => Err(UsbError::RestoreFailed(format!(
                    "启动 HyperUSB 失败：{error}；恢复 Android USB 也失败：{restore_error}"
                ))),
            };
        }

        let uvc_runtime = match UsbUvcRuntime::start(configuration.profile.uvc.as_ref()) {
            Ok(runtime) => runtime,
            Err(error) => {
                // Runtime startup happens after ConfigFS activation. Always unbind the
                // composite gadget before restoring Android's USB state.
                let deactivate = composite.deactivate();
                let restore = android_lease.restore();
                match (deactivate, restore) {
                    (Ok(()), Ok(())) => return Err(error),
                    (Err(deactivate_error), Ok(())) => {
                        return Err(UsbError::RestoreFailed(format!(
                            "启动 UVC Runtime 失败：{error}；停用 HyperUSB 失败：{deactivate_error}"
                        )));
                    }
                    (Ok(()), Err(restore_error)) => {
                        return Err(UsbError::RestoreFailed(format!(
                            "启动 UVC Runtime 失败：{error}；恢复 Android USB 也失败：{restore_error}"
                        )));
                    }
                    (Err(deactivate_error), Err(restore_error)) => {
                        return Err(UsbError::RestoreFailed(format!(
                            "启动 UVC Runtime 失败：{error}；停用 HyperUSB 失败：{deactivate_error}；恢复 Android USB 也失败：{restore_error}"
                        )));
                    }
                }
            }
        };

        let state = UsbRuntimeState::Active {
            gadget: config.gadget_name.clone(),
            udc: udc.clone(),
            keyboard_enabled: configuration.profile.keyboard_enabled,
            serial_enabled: configuration.profile.serial_enabled,
            uvc_enabled: configuration.profile.uvc.is_some(),
            storage_count: configuration.profile.storage_luns.len(),
        };
        Ok(Self {
            composite,
            android_lease: Some(android_lease),
            config,
            configuration,
            udc,
            uvc_runtime,
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
        &self.configuration.profile
    }

    pub fn configuration(&self) -> &UsbConfiguration {
        &self.configuration
    }

    pub fn udc_state_path(&self) -> PathBuf {
        PathBuf::from(format!("/sys/class/udc/{}/state", self.udc))
    }

    pub fn open_keyboard(&self) -> UsbResult<HidKeyboardWriter> {
        if !self.configuration.profile.keyboard_enabled {
            return Err(UsbError::Unavailable("当前 USB 组合未启用键盘".into()));
        }
        HidKeyboardWriter::open(self.composite.hid_endpoint()?, self.udc_state_path())
    }

    pub fn serial_endpoint(&self) -> UsbResult<PathBuf> {
        if !self.configuration.profile.serial_enabled {
            return Err(UsbError::Unavailable(
                "当前 USB 组合未启用 CDC ACM 串口".into(),
            ));
        }
        self.composite.serial_endpoint()
    }

    /// 在同一个 Daemon 会话中替换完整 USB 目标配置。
    ///
    /// ConfigFS 只能在 UDC 未绑定时调整 Function；`activate` 已负责解绑、重建链接并
    /// 重新绑定。新配置失败时先恢复旧配置；只有旧配置也失败时才恢复 Android USB。
    pub fn reconfigure(&mut self, configuration: UsbConfiguration) -> UsbResult<()> {
        if matches!(self.state, UsbRuntimeState::Stopped) || self.android_lease.is_none() {
            return Err(UsbError::Unavailable("当前没有活动的 HyperUSB 会话".into()));
        }
        configuration.validate()?;
        let previous = self.configuration.clone();
        if let Err(error) = self.composite.activate(
            &configuration.profile,
            &configuration.identity,
            &self.udc,
            self.config.udc_bind_timeout,
        ) {
            match self.composite.activate(
                &previous.profile,
                &previous.identity,
                &self.udc,
                self.config.udc_bind_timeout,
            ) {
                Ok(()) => return Err(error),
                Err(rollback_error) => {
                    let stop_error = self.stop_inner().err();
                    return Err(UsbError::RestoreFailed(format!(
                        "新配置应用失败：{error}；旧配置恢复失败：{rollback_error}{}",
                        stop_error
                            .map(|value| format!("；Android USB 恢复也失败：{value}"))
                            .unwrap_or_default()
                    )));
                }
            }
        }
        if let Err(error) = self.sync_uvc_runtime(configuration.profile.uvc.as_ref()) {
            let rollback = self.composite.activate(
                &previous.profile,
                &previous.identity,
                &self.udc,
                self.config.udc_bind_timeout,
            );
            if rollback.is_ok() {
                let _ = self.sync_uvc_runtime(previous.profile.uvc.as_ref());
                return Err(error);
            }
            let stop_error = self.stop_inner().err();
            return Err(UsbError::RestoreFailed(format!(
                "应用新 UVC Runtime 失败：{error}；恢复 HyperUSB 也失败：{rollback:?}{}",
                stop_error
                    .map(|value| format!("；停止会话也失败：{value}"))
                    .unwrap_or_default()
            )));
        }

        self.configuration = configuration;
        self.refresh_state();
        Ok(())
    }

    pub fn set_uvc_streaming(&self, enabled: bool) -> UsbResult<()> {
        self.uvc_runtime.set_streaming(enabled)
    }

    pub fn notify_uvc_format(
        &self,
        format: UvcFormatKind,
        width: u32,
        height: u32,
        fps: u32,
    ) -> UsbResult<()> {
        self.uvc_runtime.notify_format(format, width, height, fps)
    }

    fn refresh_state(&mut self) {
        self.state = UsbRuntimeState::Active {
            gadget: self.config.gadget_name.clone(),
            udc: self.udc.clone(),
            keyboard_enabled: self.configuration.profile.keyboard_enabled,
            serial_enabled: self.configuration.profile.serial_enabled,
            uvc_enabled: self.configuration.profile.uvc.is_some(),
            storage_count: self.configuration.profile.storage_luns.len(),
        };
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
        let stop_uvc = self.uvc_runtime.stop();
        let restore = match self.android_lease.as_mut() {
            Some(lease) => lease.restore(),
            None => Ok(()),
        };
        self.android_lease = None;
        self.state = UsbRuntimeState::Stopped;

        info!("HyperUSB session stopped");

        match (deactivate, restore, stop_uvc) {
            (Ok(()), Ok(()), Ok(())) => Ok(()),
            (Err(error), Ok(()), Ok(())) => Err(error),
            (Ok(()), Ok(()), Err(uvc_error)) => {
                Err(UsbError::Unavailable(format!("停止 UVC Runtime 失败：{uvc_error}")))
            }
            (Ok(()), Err(restore_error), Ok(())) => Err(UsbError::RestoreFailed(format!(
                "恢复 Android USB 失败：{restore_error}"
            ))),
            (Ok(()), Err(restore_error), Err(uvc_error)) => {
                Err(UsbError::RestoreFailed(format!(
                    "恢复 Android USB 失败：{restore_error}；停止 UVC Runtime 失败：{uvc_error}"
                )))
            }
            (Err(deactivate_error), Ok(()), Err(uvc_error)) => Err(
                UsbError::RestoreFailed(format!(
                    "停用 HyperUSB 失败：{deactivate_error}；停止 UVC Runtime 失败：{uvc_error}"
                )),
            ),
            (Err(deactivate_error), Err(restore_error), Ok(())) => Err(
                UsbError::RestoreFailed(format!(
                    "停用 HyperUSB 失败：{deactivate_error}；恢复 Android USB 也失败：{restore_error}"
                )),
            ),
            (Err(deactivate_error), Err(restore_error), Err(uvc_error)) => Err(
                UsbError::RestoreFailed(format!(
                    "停用 HyperUSB 失败：{deactivate_error}；恢复 Android USB 也失败：{restore_error}；停止 UVC Runtime 失败：{uvc_error}"
                )),
            ),
        }
    }

    fn sync_uvc_runtime(&mut self, config: Option<&UvcConfig>) -> UsbResult<()> {
        match (self.uvc_runtime.is_active(), config) {
            (true, Some(config)) => self.uvc_runtime.reconfigure(config),
            (true, None) => self.uvc_runtime.stop(),
            (false, Some(config)) => {
                self.uvc_runtime = UsbUvcRuntime::start(Some(config))?;
                Ok(())
            }
            (false, None) => Ok(()),
        }
    }
}

impl Drop for UsbSession {
    fn drop(&mut self) {
        let _ = self.stop_inner();
    }
}

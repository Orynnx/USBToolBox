#![allow(dead_code)]

//! HyperUSB 的 USB Gadget 核心。
//!
//! 模块按职责分为三层：
//! - [`usb_model`] 描述用户希望得到的 USB 组合及当前运行状态；
//! - [`usb_composite`] 负责一次完整的启停会话和失败回滚；
//! - 其余模块只负责 ConfigFS、HID 或具体 Function 的底层操作。

pub mod usb_composite;
pub mod usb_config;
pub mod usb_daemon;
pub mod usb_gadget;
pub mod usb_hid;
pub mod usb_model;
pub mod usb_protocol;
pub mod usb_recovery;
pub mod usb_storage;

use std::fmt;

#[allow(unused_imports)]
pub use usb_composite::{UsbComposite, UsbSession};
#[allow(unused_imports)]
pub use usb_gadget::{
    configfs_status, gadget_status, udc_connection_status, udc_enumeration_state, udc_status,
    udc_writable, AndroidUsbLease, GadgetIdentity, UsbGadgetController,
};
#[allow(unused_imports)]
pub use usb_hid::{
    resolve_hid_endpoint, HidKeyboardWriter, Key, KeyChord, KeyboardReport, Modifiers, UsbHid,
    BOOT_KEYBOARD_DESCRIPTOR, KEYBOARD_REPORT_LENGTH,
};
#[allow(unused_imports)]
pub use usb_model::{
    UsbConfiguration, UsbProfile, UsbRuntimeConfig, UsbRuntimeState, UsbTargetState,
};
#[allow(unused_imports)]
pub use usb_recovery::{UsbRecoveryState, DEFAULT_USB_STATE_PATH, LEGACY_USB_STATE_PATH};
#[allow(unused_imports)]
pub use usb_storage::{StorageLun, UsbStorage};

/// USB 核心的统一错误类型。
#[derive(Debug)]
pub enum UsbError {
    /// 当前设备或当前版本尚不支持该能力。
    Unsupported(&'static str),
    /// 调用方提供的配置、描述符或路径无效。
    InvalidInput(String),
    /// UDC、Host 或 Android USB 状态不允许继续执行。
    Unavailable(String),
    /// 外部 Android 命令执行失败。
    CommandFailed {
        program: String,
        status: Option<i32>,
        stderr: String,
    },
    /// 等待端点或状态转换时超时。
    TimedOut(&'static str),
    /// HID Report 必须原子写入，但内核只接收了部分内容。
    PartialWrite { expected: usize, actual: usize },
    /// HyperUSB 和旧配置均无法恢复，Android USB 恢复结果不可信。
    RestoreFailed(String),
    /// 文件系统或设备节点 I/O 错误。
    Io(std::io::Error),
}

impl fmt::Display for UsbError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Unsupported(message) => formatter.write_str(message),
            Self::InvalidInput(message)
            | Self::Unavailable(message)
            | Self::RestoreFailed(message) => formatter.write_str(message),
            Self::CommandFailed {
                program,
                status,
                stderr,
            } => write!(
                formatter,
                "命令 {program} 执行失败（status={status:?}）：{}",
                stderr.trim()
            ),
            Self::TimedOut(message) => formatter.write_str(message),
            Self::PartialWrite { expected, actual } => {
                write!(formatter, "HID Report 仅写入 {actual}/{expected} 字节")
            }
            Self::Io(error) => error.fmt(formatter),
        }
    }
}

impl std::error::Error for UsbError {}

impl From<std::io::Error> for UsbError {
    fn from(error: std::io::Error) -> Self {
        Self::Io(error)
    }
}

pub type UsbResult<T> = Result<T, UsbError>;

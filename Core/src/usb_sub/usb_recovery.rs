//! 异常退出后的 Android USB 恢复状态。
//!
//! 这是开发者 CLI 的最小安全网：在接管 UDC 之前原子写入一份状态，只有 Android USB
//! 已确认恢复后才删除。它不承担 daemon、IPC 或跨进程锁职责。

use std::fs::{self, File, OpenOptions};
use std::io::{ErrorKind, Write};
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::usb_sub::{UsbError, UsbResult};

/// Android 设备上默认的持久恢复状态位置。
pub const DEFAULT_USB_STATE_PATH: &str = "/data/adb/hyperusb/usb_state.json";

/// 接管前读取到的 Android USB 属性。
///
/// `None` 表示该 ADB 开关属性在接管前不存在或为空；恢复时会将它清为空字符串，避免把
/// HyperUSB 写入的 `1` 留在系统中。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UsbRecoveryState {
    pub original_usb_config: String,
    pub sys_adb_disabled: Option<String>,
    pub vendor_adb_disabled: Option<String>,
}

impl UsbRecoveryState {
    /// 在重命名前同步临时文件，使掉电或 `panic = abort` 时不会留下半截 JSON。
    pub fn persist_atomically(&self, path: impl AsRef<Path>) -> UsbResult<()> {
        let path = path.as_ref();
        let parent = path.parent().ok_or_else(|| {
            UsbError::InvalidInput(format!("恢复状态路径没有父目录：{}", path.display()))
        })?;
        fs::create_dir_all(parent)?;

        let temporary = temporary_path(path);
        let write_result = (|| -> UsbResult<()> {
            let mut file = OpenOptions::new()
                .create(true)
                .write(true)
                .truncate(true)
                .open(&temporary)?;
            serde_json::to_writer_pretty(&mut file, self)
                .map_err(|error| UsbError::InvalidInput(format!("序列化恢复状态失败：{error}")))?;
            file.write_all(b"\n")?;
            file.sync_all()?;
            fs::rename(&temporary, path)?;
            sync_directory(parent)?;
            Ok(())
        })();

        if write_result.is_err() {
            let _ = fs::remove_file(&temporary);
        }
        write_result
    }

    /// 读取现有状态；不存在时返回 `Ok(None)`，格式损坏则拒绝继续猜测。
    pub fn load(path: impl AsRef<Path>) -> UsbResult<Option<Self>> {
        let path = path.as_ref();
        let file = match File::open(path) {
            Ok(file) => file,
            Err(error) if error.kind() == ErrorKind::NotFound => return Ok(None),
            Err(error) => return Err(error.into()),
        };
        let state = serde_json::from_reader(file)
            .map_err(|error| UsbError::InvalidInput(format!("恢复状态 JSON 无效：{error}")))?;
        Ok(Some(state))
    }

    /// 仅在 Android USB 已恢复后删除状态文件。
    pub fn clear(path: impl AsRef<Path>) -> UsbResult<()> {
        let path = path.as_ref();
        match fs::remove_file(path) {
            Ok(()) => {
                if let Some(parent) = path.parent() {
                    sync_directory(parent)?;
                }
                Ok(())
            }
            Err(error) if error.kind() == ErrorKind::NotFound => Ok(()),
            Err(error) => Err(error.into()),
        }
    }
}

fn temporary_path(path: &Path) -> PathBuf {
    let mut temporary = path.as_os_str().to_owned();
    temporary.push(".tmp");
    PathBuf::from(temporary)
}

fn sync_directory(path: &Path) -> UsbResult<()> {
    #[cfg(unix)]
    {
        File::open(path)?.sync_all()?;
    }
    #[cfg(not(unix))]
    {
        let _ = path;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_path(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!(
            "hyperusb-recovery-{name}-{}-{:?}.json",
            std::process::id(),
            std::thread::current().id()
        ))
    }

    #[test]
    fn state_round_trips_and_clears() {
        let path = test_path("round-trip");
        let state = UsbRecoveryState {
            original_usb_config: "mtp,adb".into(),
            sys_adb_disabled: Some("0".into()),
            vendor_adb_disabled: None,
        };

        state.persist_atomically(&path).unwrap();
        assert_eq!(UsbRecoveryState::load(&path).unwrap(), Some(state));
        UsbRecoveryState::clear(&path).unwrap();
        assert_eq!(UsbRecoveryState::load(&path).unwrap(), None);
    }
}

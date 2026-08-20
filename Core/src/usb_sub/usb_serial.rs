//! CDC ACM Serial Gadget Function。
//!
//! CDC ACM 的波特率、数据位、校验位和停止位属于 Host 打开串口时发送的
//! 运行时请求，不是 ConfigFS 的静态 Gadget 配置。HyperUSB 只负责创建
//! `acm.hyperusb` Function；Linux Gadget 默认使用 protocol 1，并把端点
//! 暴露为 `/dev/ttyGS<n>`。

use std::fs;
use std::path::{Path, PathBuf};

use crate::usb_sub::{UsbError, UsbResult};

/// Linux CDC ACM Function 的最小配置器。
#[derive(Debug, Default)]
pub struct UsbSerial;

impl UsbSerial {
    /// 创建一个未链接、未绑定的 CDC ACM Function。
    ///
    /// ConfigFS 会在创建目录时建立 ACM 的默认属性。这里不写 `protocol`，
    /// 也不尝试伪造 baud rate 等 Host 运行时参数。
    pub fn configure_function(&self, function_path: impl AsRef<Path>) -> UsbResult<()> {
        let function_path = function_path.as_ref();
        ensure_function_directory(function_path)?;
        Ok(())
    }

    /// 读取 ConfigFS 的 `port_num` 并解析对应的设备节点。
    pub fn endpoint_path(function_path: impl AsRef<Path>) -> UsbResult<PathBuf> {
        let function_path = function_path.as_ref();
        let port_num = fs::read_to_string(function_path.join("port_num"))?;
        let port_num = port_num.trim();
        if port_num.is_empty() || !port_num.bytes().all(|byte| byte.is_ascii_digit()) {
            return Err(UsbError::InvalidInput(format!(
                "CDC ACM port_num 无效：{port_num:?}"
            )));
        }
        Ok(PathBuf::from(format!("/dev/ttyGS{port_num}")))
    }
}

fn ensure_function_directory(path: &Path) -> UsbResult<()> {
    if !path.exists() {
        fs::create_dir(path)?;
    }
    if path.is_dir() {
        Ok(())
    } else {
        Err(UsbError::InvalidInput(format!(
            "CDC ACM Function 路径不是目录：{}",
            path.display()
        )))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_directory(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!(
            "hyperusb-serial-{name}-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        ))
    }

    #[test]
    fn creates_acm_function_without_host_line_coding_attributes() {
        let root = test_directory("create");
        let function = root.join("functions/acm.hyperusb");
        fs::create_dir_all(function.parent().unwrap()).unwrap();

        UsbSerial.configure_function(&function).unwrap();
        assert!(function.is_dir());

        // `protocol` 和 baud/data/parity/stop bits 都不是第一版的静态配置项。
        assert!(!function.join("baudRate").exists());
        assert!(!function.join("dataBits").exists());
        assert!(!function.join("parity").exists());
        assert!(!function.join("stopBits").exists());

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn resolves_ttygs_endpoint_from_port_num() {
        let root = test_directory("endpoint");
        fs::create_dir_all(&root).unwrap();
        fs::write(root.join("port_num"), "0\n").unwrap();

        assert_eq!(
            UsbSerial::endpoint_path(&root).unwrap(),
            PathBuf::from("/dev/ttyGS0")
        );

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn rejects_invalid_port_num() {
        let root = test_directory("invalid-port");
        fs::create_dir_all(&root).unwrap();
        fs::write(root.join("port_num"), "ttyGS0\n").unwrap();

        assert!(UsbSerial::endpoint_path(&root).is_err());

        fs::remove_dir_all(root).unwrap();
    }
}

//! CDC-NCM ConfigFS Function 配置。
//!
//! 本模块只负责 NCM Function 与其 ConfigFS 属性，不配置 IP、DHCP、NAT 或路由。

use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::path::Path;

use serde::Serialize;

use crate::usb_sub::{UsbError, UsbResult};

pub const NCM_INSTANCE: &str = "ncm.hyperusb";
pub const DEFAULT_IFNAME: &str = "hyperusb%d";
pub const SYS_NET_PATH: &str = "/sys/class/net";

/// NCM 当前实际运行状态，字段来自成功激活后的运行时回读，而不是原始 JSON。
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NetStatus {
    pub enabled: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ifname: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub device_mac: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub host_mac: Option<String>,
}

impl NetStatus {
    pub const fn disabled() -> Self {
        Self {
            enabled: false,
            ifname: None,
            device_mac: None,
            host_mac: None,
        }
    }

    pub fn active(ncm: &UsbNcm, ifname: String) -> Self {
        Self {
            enabled: true,
            ifname: Some(ifname),
            device_mac: Some(ncm.device_mac.as_configfs()),
            host_mac: Some(ncm.host_mac.as_configfs()),
        }
    }

    pub fn to_json(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string(self)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MacAddress(pub [u8; 6]);

impl MacAddress {
    pub fn parse(value: &str) -> UsbResult<Self> {
        let parts = value.split(':').collect::<Vec<_>>();
        if parts.len() != 6 || parts.iter().any(|part| part.len() != 2) {
            return Err(UsbError::InvalidInput(format!("NCM MAC 格式无效：{value}")));
        }
        let mut bytes = [0u8; 6];
        for (index, part) in parts.iter().enumerate() {
            bytes[index] = u8::from_str_radix(part, 16)
                .map_err(|_| UsbError::InvalidInput(format!("NCM MAC 格式无效：{value}")))?;
        }
        if bytes[0] & 1 != 0 {
            return Err(UsbError::InvalidInput(format!(
                "NCM MAC 不能是 multicast 地址：{value}"
            )));
        }
        Ok(Self(bytes))
    }

    pub fn derive(serial: &str, salt: u8) -> Self {
        let mut hash = 0xcbf29ce484222325u64 ^ u64::from(salt);
        for byte in serial.as_bytes() {
            hash ^= u64::from(*byte);
            hash = hash.wrapping_mul(0x100000001b3);
        }
        let mut bytes = [0u8; 6];
        bytes[0] = 0x02;
        bytes[1..].copy_from_slice(&hash.to_be_bytes()[3..]);
        Self(bytes)
    }

    pub fn as_configfs(&self) -> String {
        self.0
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<Vec<_>>()
            .join(":")
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UsbNcm {
    pub device_mac: MacAddress,
    pub host_mac: MacAddress,
    pub qmult: Option<u32>,
    pub ifname: Option<String>,
}

impl UsbNcm {
    pub fn validate(&self) -> UsbResult<()> {
        if self.device_mac.0[0] & 1 != 0 || self.host_mac.0[0] & 1 != 0 {
            return Err(UsbError::InvalidInput(
                "NCM MAC 不能是 multicast 地址".into(),
            ));
        }
        if self.device_mac == self.host_mac {
            return Err(UsbError::InvalidInput(
                "NCM deviceMac 和 hostMac 不能相同".into(),
            ));
        }
        if let Some(qmult) = self.qmult {
            if qmult == 0 || qmult > 65_535 {
                return Err(UsbError::InvalidInput("NCM qmult 必须是 1..65535".into()));
            }
        }
        if let Some(ifname) = &self.ifname {
            validate_ifname(ifname)?;
        }
        Ok(())
    }

    pub fn configure_function(&self, function_path: impl AsRef<Path>) -> UsbResult<()> {
        self.validate()?;
        let function_path = function_path.as_ref();
        ensure_directory(function_path)?;
        write_attr(
            &function_path.join("dev_addr"),
            &self.device_mac.as_configfs(),
            "write_dev_addr",
        )?;
        write_attr(
            &function_path.join("host_addr"),
            &self.host_mac.as_configfs(),
            "write_host_addr",
        )?;
        if let Some(qmult) = self.qmult {
            write_attr(
                &function_path.join("qmult"),
                &qmult.to_string(),
                "write_qmult",
            )?;
        }
        write_attr(
            &function_path.join("ifname"),
            self.ifname.as_deref().unwrap_or(DEFAULT_IFNAME),
            "write_ifname",
        )?;
        Ok(())
    }

    /// 读取 ConfigFS 中的命名模板，仅用于诊断；不能作为运行时 netdev 名称。
    pub fn read_ifname(&self, function_path: impl AsRef<Path>) -> UsbResult<String> {
        let path = function_path.as_ref().join("ifname");
        let value = fs::read_to_string(&path)
            .map_err(|error| stage_error("read_ifname", &path, error))?
            .trim()
            .to_owned();
        if value.is_empty() {
            return Err(UsbError::Unavailable(format!(
                "NCM stage=read_ifname path={} returned empty value",
                path.display()
            )));
        }
        Ok(value)
    }

    /// 根据 NCM 的实际 device MAC，从 sysfs 找到内核最终注册的 netdev 名称。
    ///
    /// ConfigFS 的 `ifname` 是 `hyperusb%d` 这样的命名模板，不能直接作为运行时接口名。
    pub fn find_interface(&self, net_root: impl AsRef<Path>) -> UsbResult<String> {
        let net_root = net_root.as_ref();
        let expected = self.device_mac.as_configfs();
        let mut names = Vec::new();
        let entries = fs::read_dir(net_root)
            .map_err(|error| stage_error("find_interface", net_root, error))?;
        for entry in entries {
            let entry = entry.map_err(|error| stage_error("find_interface", net_root, error))?;
            let name = entry.file_name().to_string_lossy().into_owned();
            let address_path = entry.path().join("address");
            let address = match fs::read_to_string(&address_path) {
                Ok(address) => address,
                Err(error) if error.kind() == io::ErrorKind::NotFound => continue,
                Err(error) => {
                    return Err(stage_error("find_interface", &address_path, error));
                }
            };
            if address.trim().eq_ignore_ascii_case(&expected) {
                names.push(name);
            }
        }
        names.sort();
        names.into_iter().next().ok_or_else(|| {
            UsbError::Unavailable(format!(
                "NCM stage=find_interface path={} device_mac={} 未找到匹配 netdev",
                net_root.display(),
                expected
            ))
        })
    }
}

fn validate_ifname(value: &str) -> UsbResult<()> {
    if value.is_empty()
        || value.len() > 15
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-' | b'%'))
    {
        return Err(UsbError::InvalidInput(format!(
            "NCM ifname 无效：{value:?}"
        )));
    }
    Ok(())
}

fn ensure_directory(path: &Path) -> UsbResult<()> {
    if !path.exists() {
        fs::create_dir(path).map_err(|error| stage_error("create_function", path, error))?;
    }
    if path.is_dir() {
        Ok(())
    } else {
        Err(UsbError::InvalidInput(format!(
            "NCM stage=create_function path={} 不是目录",
            path.display()
        )))
    }
}

fn write_attr(path: &Path, value: &str, stage: &str) -> UsbResult<()> {
    let mut file = OpenOptions::new()
        .write(true)
        .truncate(true)
        .open(path)
        .map_err(|error| stage_error(stage, path, error))?;
    file.write_all(value.as_bytes())
        .map_err(|error| stage_error(stage, path, error))?;
    Ok(())
}

fn stage_error(stage: &str, path: &Path, error: io::Error) -> UsbError {
    UsbError::Unavailable(format!(
        "NCM stage={stage} path={} error={error}",
        path.display()
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn derived_macs_are_stable_distinct_and_local_unicast() {
        let device = MacAddress::derive("NCM-1", 0);
        let host = MacAddress::derive("NCM-1", 1);
        assert_eq!(device, MacAddress::derive("NCM-1", 0));
        assert_ne!(device, host);
        assert_eq!(device.0[0] & 3, 2);
    }

    #[test]
    fn parses_and_rejects_mac_addresses() {
        assert_eq!(
            MacAddress::parse("02:48:59:50:45:01")
                .unwrap()
                .as_configfs(),
            "02:48:59:50:45:01"
        );
        assert!(MacAddress::parse("01:48:59:50:45:01").is_err());
        assert!(MacAddress::parse("bad").is_err());
    }

    #[test]
    fn configures_attributes_and_leaves_optional_qmult_untouched() {
        let root = std::env::temp_dir().join(format!(
            "hyperusb-ncm-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        ));
        std::fs::create_dir_all(&root).unwrap();
        for name in ["dev_addr", "host_addr", "ifname", "qmult"] {
            std::fs::write(root.join(name), if name == "qmult" { "99" } else { "" }).unwrap();
        }
        let ncm = UsbNcm {
            device_mac: MacAddress::parse("02:48:59:50:45:01").unwrap(),
            host_mac: MacAddress::parse("02:48:59:50:45:02").unwrap(),
            qmult: None,
            ifname: None,
        };
        ncm.configure_function(&root).unwrap();
        assert_eq!(
            std::fs::read_to_string(root.join("dev_addr")).unwrap(),
            "02:48:59:50:45:01"
        );
        assert_eq!(
            std::fs::read_to_string(root.join("host_addr")).unwrap(),
            "02:48:59:50:45:02"
        );
        assert_eq!(
            std::fs::read_to_string(root.join("ifname")).unwrap(),
            DEFAULT_IFNAME
        );
        assert_eq!(std::fs::read_to_string(root.join("qmult")).unwrap(), "99");
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn runtime_status_serializes_only_network_runtime_fields() {
        let ncm = UsbNcm {
            device_mac: MacAddress::parse("02:48:59:50:45:01").unwrap(),
            host_mac: MacAddress::parse("02:48:59:50:45:02").unwrap(),
            qmult: Some(5),
            ifname: Some(DEFAULT_IFNAME.into()),
        };
        assert_eq!(
            NetStatus::active(&ncm, "hyperusb0".into())
                .to_json()
                .unwrap(),
            r#"{"enabled":true,"ifname":"hyperusb0","deviceMac":"02:48:59:50:45:01","hostMac":"02:48:59:50:45:02"}"#
        );
        assert_eq!(
            NetStatus::disabled().to_json().unwrap(),
            r#"{"enabled":false}"#
        );
    }

    #[test]
    fn resolves_actual_interface_name_by_device_mac() {
        let root = std::env::temp_dir().join(format!(
            "hyperusb-net-status-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        ));
        std::fs::create_dir_all(root.join("hyperusb0")).unwrap();
        std::fs::create_dir_all(root.join("wlan0")).unwrap();
        std::fs::write(root.join("hyperusb0/address"), "02:48:59:50:45:01\n").unwrap();
        std::fs::write(root.join("wlan0/address"), "20:bd:1d:37:e5:92\n").unwrap();

        let ncm = UsbNcm {
            device_mac: MacAddress::parse("02:48:59:50:45:01").unwrap(),
            host_mac: MacAddress::parse("02:48:59:50:45:02").unwrap(),
            qmult: None,
            ifname: Some(DEFAULT_IFNAME.into()),
        };
        assert_eq!(ncm.find_interface(&root).unwrap(), "hyperusb0");
        assert!(!NetStatus::active(&ncm, ncm.find_interface(&root).unwrap())
            .to_json()
            .unwrap()
            .contains("hyperusb%d"));
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn missing_device_mac_interface_is_an_error() {
        let root = std::env::temp_dir().join(format!(
            "hyperusb-net-status-missing-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        ));
        std::fs::create_dir_all(root.join("wlan0")).unwrap();
        std::fs::write(root.join("wlan0/address"), "20:bd:1d:37:e5:92\n").unwrap();

        let ncm = UsbNcm {
            device_mac: MacAddress::parse("02:48:59:50:45:01").unwrap(),
            host_mac: MacAddress::parse("02:48:59:50:45:02").unwrap(),
            qmult: None,
            ifname: None,
        };
        assert!(ncm.find_interface(&root).is_err());
        let _ = std::fs::remove_dir_all(root);
    }
}

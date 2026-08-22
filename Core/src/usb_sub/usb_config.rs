//! `SET` 使用的 JSON 配置快照与严格语义校验。

use std::fs::File;
use std::io::{ErrorKind, Read};
use std::path::{Path, PathBuf};

use serde::Deserialize;

use crate::usb_sub::usb_protocol::{ApiError, ApiErrorCode, ApiResult};
use crate::usb_sub::{
    GadgetIdentity, MacAddress, StorageLun, UsbConfiguration, UsbNcm, UsbProfile, UsbTargetState,
    UvcConfig, UvcFormat, UvcFormatKind, UvcFrame,
};

pub const MAX_CONFIG_BYTES: u64 = 64 * 1024;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ConfigFile {
    #[serde(default)]
    device: Option<DeviceConfig>,
    #[serde(default)]
    disk: DiskConfig,
    #[serde(default)]
    storage: StorageConfig,
    #[serde(default)]
    keyboard: KeyboardConfig,
    #[serde(default)]
    serial: SerialConfig,
    #[serde(default)]
    uvc: UvcFileConfig,
    #[serde(default)]
    ncm: NcmFileConfig,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DeviceConfig {
    #[serde(default = "default_manufacturer")]
    manufacturer: String,
    #[serde(default = "default_product")]
    product: String,
    serial_number: Option<String>,
    #[serde(default = "default_vid")]
    vid: String,
    #[serde(default = "default_pid")]
    pid: String,
    #[serde(default = "default_device_version")]
    device_version: String,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DiskConfig {
    #[serde(default)]
    enabled: bool,
    image_path: Option<PathBuf>,
    read_only: Option<bool>,
    #[serde(default = "default_removable")]
    removable: bool,
    #[serde(default)]
    cdrom: bool,
    no_fua: Option<bool>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct StorageConfig {
    #[serde(default)]
    luns: Vec<StorageLunConfig>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct StorageLunConfig {
    image_path: PathBuf,
    #[serde(default)]
    read_only: bool,
    #[serde(default = "default_removable")]
    removable: bool,
    #[serde(default)]
    cdrom: bool,
    #[serde(default)]
    no_fua: bool,
}

#[derive(Debug, Default, Deserialize)]
struct KeyboardConfig {
    #[serde(default)]
    boot: bool,
}

#[derive(Debug, Default, Deserialize)]
struct SerialConfig {
    #[serde(default)]
    enabled: bool,
}

#[derive(Debug, Default, Deserialize)]
struct UvcFileConfig {
    #[serde(default)]
    enabled: bool,
    #[serde(default)]
    formats: Vec<UvcFormatFile>,
}

#[derive(Debug, Deserialize)]
struct UvcFormatFile {
    format: String,
    #[serde(default)]
    frames: Vec<UvcFrameFile>,
}

#[derive(Debug, Deserialize)]
struct UvcFrameFile {
    width: u32,
    height: u32,
    #[serde(default)]
    fps: Vec<u32>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct NcmFileConfig {
    #[serde(default)]
    enabled: bool,
    device_mac: Option<String>,
    host_mac: Option<String>,
    qmult: Option<u32>,
    ifname: Option<String>,
}

pub fn load_configuration(path: &Path) -> ApiResult<UsbTargetState> {
    if !path.is_absolute() {
        return Err(ApiError::new(
            ApiErrorCode::InvalidConfigPath,
            "配置文件路径必须是绝对路径",
        ));
    }
    let mut file = File::open(path).map_err(|error| {
        let code = if error.kind() == ErrorKind::NotFound {
            ApiErrorCode::ConfigNotFound
        } else {
            ApiErrorCode::InvalidConfig
        };
        ApiError::new(
            code,
            format!("无法打开配置文件 {}：{error}", path.display()),
        )
    })?;
    let metadata = file.metadata().map_err(|error| {
        ApiError::new(
            ApiErrorCode::InvalidConfig,
            format!("无法读取配置文件属性 {}：{error}", path.display()),
        )
    })?;
    if !metadata.is_file() {
        return Err(ApiError::new(
            ApiErrorCode::InvalidConfig,
            format!("配置路径最终目标不是普通文件：{}", path.display()),
        ));
    }

    let mut snapshot = Vec::with_capacity((MAX_CONFIG_BYTES + 1) as usize);
    file.by_ref()
        .take(MAX_CONFIG_BYTES + 1)
        .read_to_end(&mut snapshot)
        .map_err(|error| {
            ApiError::new(
                ApiErrorCode::InvalidConfig,
                format!("读取配置文件失败 {}：{error}", path.display()),
            )
        })?;
    drop(file);
    if snapshot.len() as u64 > MAX_CONFIG_BYTES {
        return Err(ApiError::new(
            ApiErrorCode::InvalidConfig,
            "配置文件超过 64 KiB",
        ));
    }

    parse_configuration(&snapshot)
}

pub fn parse_configuration(snapshot: &[u8]) -> ApiResult<UsbTargetState> {
    let config: ConfigFile = serde_json::from_slice(snapshot).map_err(|error| {
        ApiError::new(
            ApiErrorCode::InvalidConfig,
            format!("配置 JSON 无效：{error}"),
        )
    })?;
    if config.disk.enabled && !config.storage.luns.is_empty() {
        return Err(ApiError::new(
            ApiErrorCode::InvalidConfig,
            "legacy disk 与 storage.luns 不能同时启用",
        ));
    }
    let mut storage_luns = Vec::new();
    if config.disk.enabled {
        let image = config.disk.image_path.ok_or_else(|| {
            ApiError::new(
                ApiErrorCode::InvalidConfig,
                "disk.enabled=true 时必须指定 imagePath",
            )
        })?;
        validate_image_path(&image)?;
        let read_only = if config.disk.cdrom {
            match config.disk.read_only {
                None | Some(true) => true,
                Some(false) => {
                    return Err(ApiError::new(
                        ApiErrorCode::InvalidConfig,
                        "cdrom=true 时 readOnly 不能为 false",
                    ))
                }
            }
        } else {
            config.disk.read_only.unwrap_or(false)
        };
        storage_luns.push(StorageLun {
            image: Some(image),
            read_only,
            removable: config.disk.removable,
            cdrom: config.disk.cdrom,
            no_fua: config.disk.no_fua.unwrap_or(config.disk.cdrom),
            ejected: false,
        });
    } else {
        for lun in config.storage.luns {
            storage_luns.push(parse_storage_lun(lun)?);
        }
    }
    reject_duplicate_backing_files(&storage_luns)?;

    let mut profile = UsbProfile {
        keyboard_enabled: config.keyboard.boot,
        serial_enabled: config.serial.enabled,
        uvc: parse_uvc_config(config.uvc)?,
        ncm: None,
        storage_luns,
    };
    if !profile.has_functions() && !config.ncm.enabled {
        return Ok(UsbTargetState::AndroidUsb);
    }

    let device = config.device.ok_or_else(|| {
        ApiError::new(
            ApiErrorCode::InvalidConfig,
            "启用 HyperUSB Function 时必须提供 device",
        )
    })?;
    let serial_number = device.serial_number.ok_or_else(|| {
        ApiError::new(
            ApiErrorCode::InvalidConfig,
            "启用 HyperUSB Function 时必须提供 serialNumber",
        )
    })?;
    let serial_number = validate_usb_string("serialNumber", serial_number)?;
    profile.ncm = parse_ncm_config(config.ncm, &serial_number)?;
    let manufacturer = validate_usb_string("manufacturer", device.manufacturer)?;
    let product = validate_usb_string("product", device.product)?;
    let identity = GadgetIdentity {
        vendor_id: parse_hex_id(&device.vid, ApiErrorCode::InvalidVid, "VID")?,
        product_id: parse_hex_id(&device.pid, ApiErrorCode::InvalidPid, "PID")?,
        usb_version: 0x0200,
        device_version: parse_device_version(&device.device_version)?,
        serial_number,
        manufacturer,
        product,
        configuration: "HyperUSB Configuration".into(),
    };

    let configuration = UsbConfiguration { identity, profile };
    configuration
        .validate()
        .map_err(|error| ApiError::new(ApiErrorCode::InvalidConfig, error.to_string()))?;
    Ok(UsbTargetState::HyperUsb(configuration))
}

fn parse_storage_lun(lun: StorageLunConfig) -> ApiResult<StorageLun> {
    validate_image_path(&lun.image_path)?;
    if lun.cdrom && !lun.read_only {
        return Err(ApiError::new(
            ApiErrorCode::InvalidConfig,
            "cdrom=true 时 readOnly 必须为 true",
        ));
    }
    Ok(StorageLun {
        image: Some(lun.image_path),
        read_only: lun.read_only,
        removable: lun.removable,
        cdrom: lun.cdrom,
        no_fua: lun.no_fua,
        ejected: false,
    })
}

fn reject_duplicate_backing_files(luns: &[StorageLun]) -> ApiResult<()> {
    let mut seen = std::collections::HashSet::new();
    for lun in luns {
        let image = lun.image.as_ref().expect("parsed storage LUN has an image");
        let canonical = std::fs::canonicalize(image).map_err(|error| {
            ApiError::new(
                ApiErrorCode::InvalidConfig,
                format!("无法规范化镜像 {}：{error}", image.display()),
            )
        })?;
        if !seen.insert(canonical) {
            return Err(ApiError::new(
                ApiErrorCode::DuplicateBackingFile,
                "同一 backing file 不能被多个活动 LUN 同时使用",
            ));
        }
    }
    Ok(())
}

fn parse_ncm_config(config: NcmFileConfig, serial_number: &str) -> ApiResult<Option<UsbNcm>> {
    if !config.enabled {
        return Ok(None);
    }

    let device_explicit = config.device_mac.is_some();
    let host_explicit = config.host_mac.is_some();
    let device_mac = match config.device_mac {
        Some(value) => MacAddress::parse(&value).map_err(invalid_ncm)?,
        None => MacAddress::derive(serial_number, 0),
    };
    let mut host_mac = match config.host_mac {
        Some(value) => MacAddress::parse(&value).map_err(invalid_ncm)?,
        None => MacAddress::derive(serial_number, 1),
    };
    if device_mac == host_mac {
        if host_explicit || device_explicit {
            return Err(invalid_ncm("deviceMac 和 hostMac 不能相同"));
        }
        host_mac = MacAddress::derive(serial_number, 2);
    }
    let ncm = UsbNcm {
        device_mac,
        host_mac,
        qmult: config.qmult,
        ifname: config.ifname,
    };
    ncm.validate().map_err(invalid_ncm)?;
    Ok(Some(ncm))
}

fn invalid_ncm(error: impl std::fmt::Display) -> ApiError {
    ApiError::new(
        ApiErrorCode::InvalidConfig,
        format!("NCM 配置无效：{error}"),
    )
}

fn parse_uvc_config(config: UvcFileConfig) -> ApiResult<Option<UvcConfig>> {
    if !config.enabled {
        return Ok(None);
    }

    let mut formats: Vec<UvcFormat> = Vec::new();
    for raw_format in config.formats {
        let format = match raw_format.format.trim().to_ascii_lowercase().as_str() {
            "mjpeg" => UvcFormatKind::Mjpeg,
            "yuyv" => UvcFormatKind::Yuyv,
            other => {
                return Err(invalid_uvc(format!(
                    "不支持的 format：{other}，第一版只支持 mjpeg 和 yuyv"
                )))
            }
        };
        let target = if let Some(existing) = formats.iter_mut().find(|item| item.format == format) {
            existing
        } else {
            formats.push(UvcFormat {
                format,
                frames: Vec::new(),
            });
            formats.last_mut().expect("format was just pushed")
        };

        for raw_frame in raw_format.frames {
            let frame = UvcFrame {
                width: raw_frame.width,
                height: raw_frame.height,
                fps: deduplicate(raw_frame.fps),
            };
            if let Some(existing) = target
                .frames
                .iter_mut()
                .find(|item| item.width == frame.width && item.height == frame.height)
            {
                for fps in frame.fps {
                    if !existing.fps.contains(&fps) {
                        existing.fps.push(fps);
                    }
                }
            } else {
                target.frames.push(frame);
            }
        }
    }

    let config = UvcConfig { formats };
    config
        .validate()
        .map_err(|error| invalid_uvc(error.to_string()))?;
    Ok(Some(config))
}

fn deduplicate(values: Vec<u32>) -> Vec<u32> {
    let mut unique = Vec::with_capacity(values.len());
    for value in values {
        if !unique.contains(&value) {
            unique.push(value);
        }
    }
    unique
}

fn invalid_uvc(message: impl Into<String>) -> ApiError {
    ApiError::new(
        ApiErrorCode::InvalidConfig,
        format!("UVC 配置无效：{}", message.into()),
    )
}

fn parse_hex_id(value: &str, code: ApiErrorCode, label: &str) -> ApiResult<u16> {
    let digits = value.strip_prefix("0x");
    let Some(digits) = digits else {
        return Err(ApiError::new(code, format!("{label} 缺少 0x 前缀")));
    };
    if digits.len() != 4 || !digits.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err(ApiError::new(
            code,
            format!("{label} 必须是 0x 加四位十六进制数字"),
        ));
    }
    u16::from_str_radix(digits, 16)
        .map_err(|error| ApiError::new(code, format!("{label} 无效：{error}")))
}

fn parse_device_version(value: &str) -> ApiResult<u16> {
    let Some((major, minor)) = value.split_once('.') else {
        return Err(invalid_version(value));
    };
    if major.is_empty()
        || minor.is_empty()
        || minor.contains('.')
        || !major.bytes().all(|byte| byte.is_ascii_digit())
        || !minor.bytes().all(|byte| byte.is_ascii_digit())
    {
        return Err(invalid_version(value));
    }
    let major = major.parse::<u8>().map_err(|_| invalid_version(value))?;
    let minor = minor.parse::<u8>().map_err(|_| invalid_version(value))?;
    if major > 99 || minor > 99 {
        return Err(invalid_version(value));
    }
    Ok(((bcd_component(major) as u16) << 8) | bcd_component(minor) as u16)
}

fn invalid_version(value: &str) -> ApiError {
    ApiError::new(
        ApiErrorCode::InvalidDeviceVersion,
        format!("deviceVersion 必须是 0..99.0..99：{value}"),
    )
}

const fn bcd_component(value: u8) -> u8 {
    ((value / 10) << 4) | (value % 10)
}

fn validate_usb_string(label: &str, value: String) -> ApiResult<String> {
    if value.is_empty() || value.contains(['\0', '\r', '\n']) || value.encode_utf16().count() > 126
    {
        return Err(ApiError::new(
            ApiErrorCode::InvalidConfig,
            format!("{label} 为空、包含非法控制字符或超过 126 个 UTF-16 code unit"),
        ));
    }
    Ok(value)
}

fn validate_image_path(path: &Path) -> ApiResult<()> {
    if !path.is_absolute() {
        return Err(ApiError::new(
            ApiErrorCode::InvalidConfig,
            "imagePath 必须是绝对路径",
        ));
    }
    let metadata = std::fs::metadata(path).map_err(|error| {
        let code = if error.kind() == ErrorKind::NotFound {
            ApiErrorCode::ImageNotFound
        } else {
            ApiErrorCode::InvalidConfig
        };
        ApiError::new(code, format!("无法访问镜像 {}：{error}", path.display()))
    })?;
    if !metadata.is_file() {
        return Err(ApiError::new(
            ApiErrorCode::ImageNotFile,
            format!("镜像最终目标不是普通文件：{}", path.display()),
        ));
    }
    Ok(())
}

fn default_manufacturer() -> String {
    "USB Device".into()
}

fn default_product() -> String {
    "Composite USB Device".into()
}

fn default_vid() -> String {
    "0x1D6B".into()
}

fn default_pid() -> String {
    "0x0104".into()
}

fn default_device_version() -> String {
    "1.0".into()
}

const fn default_removable() -> bool {
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_path(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!(
            "hyperusb-config-{name}-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        ))
    }

    fn base_json(extra: &str) -> Vec<u8> {
        format!(r#"{{"device":{{"serialNumber":"TEST-1"}},"keyboard":{{"boot":true}}{extra}}}"#)
            .into_bytes()
    }

    fn active(target: UsbTargetState) -> UsbConfiguration {
        match target {
            UsbTargetState::HyperUsb(configuration) => configuration,
            UsbTargetState::AndroidUsb => panic!("expected active HyperUSB configuration"),
        }
    }

    #[test]
    fn applies_defaults_and_ignores_unknown_fields() {
        let config = active(parse_configuration(&base_json(",\"unknown\":123")).unwrap());
        assert_eq!(config.identity.vendor_id, 0x1d6b);
        assert_eq!(config.identity.product_id, 0x0104);
        assert_eq!(config.identity.device_version, 0x0100);
        assert_eq!(config.identity.serial_number, "TEST-1");
    }

    #[test]
    fn empty_function_configs_target_android_without_identity_validation() {
        for json in [
            br#"{}"#.as_slice(),
            br#"{"keyboard":{"boot":false},"disk":{"enabled":false}}"#,
            br#"{"uvc":{"enabled":false,"formats":[{"format":"not-supported","frames":[]}]}}"#,
            br#"{"device":{"serialNumber":"","vid":"invalid"}}"#,
        ] {
            assert_eq!(
                parse_configuration(json).unwrap(),
                UsbTargetState::AndroidUsb
            );
        }
    }

    #[test]
    fn active_functions_require_non_empty_serial() {
        for json in [
            br#"{"keyboard":{"boot":true}}"#.as_slice(),
            br#"{"serial":{"enabled":true}}"#.as_slice(),
            br#"{"uvc":{"enabled":true,"formats":[]}}"#.as_slice(),
            br#"{"device":{},"keyboard":{"boot":true}}"#,
            br#"{"device":{"serialNumber":""},"keyboard":{"boot":true}}"#,
        ] {
            assert_eq!(
                parse_configuration(json).unwrap_err().code,
                ApiErrorCode::InvalidConfig
            );
        }
    }

    #[test]
    fn encodes_two_digit_bcd_components() {
        assert_eq!(parse_device_version("1.2").unwrap(), 0x0102);
        assert_eq!(parse_device_version("1.20").unwrap(), 0x0120);
        assert_eq!(parse_device_version("12.34").unwrap(), 0x1234);
    }

    #[test]
    fn validates_hex_ids_strictly() {
        for value in ["1234", "0X1234", "0x123", "0x12345", "0x12G4"] {
            assert!(parse_hex_id(value, ApiErrorCode::InvalidVid, "VID").is_err());
        }
        assert_eq!(
            parse_hex_id("0xABCD", ApiErrorCode::InvalidPid, "PID").unwrap(),
            0xabcd
        );
    }

    #[test]
    fn rejects_wrong_types_for_known_fields() {
        for json in [
            br#"{"device":{"serialNumber":123},"keyboard":{"boot":true}}"#.as_slice(),
            br#"{"device":{"serialNumber":"TEST"},"keyboard":{"boot":"yes"}}"#,
            br#"{"device":{"serialNumber":"TEST"},"serial":{"enabled":"yes"}}"#,
            br#"{"device":{"serialNumber":"TEST"},"uvc":{"enabled":"yes"}}"#,
            br#"{"device":{"serialNumber":"TEST"},"ncm":{"enabled":"yes"}}"#,
            br#"{"device":{"serialNumber":"TEST"},"uvc":{"enabled":true,"formats":[{"format":"mjpeg","frames":[{"width":"1280","height":720,"fps":[30]}]}]}}"#,
            br#"{"device":{"serialNumber":"TEST"},"disk":{"enabled":false,"cdrom":1},"keyboard":{"boot":true}}"#,
        ] {
            assert_eq!(
                parse_configuration(json).unwrap_err().code,
                ApiErrorCode::InvalidConfig
            );
        }
    }

    #[test]
    fn parses_serial_only_profile_without_line_coding_options() {
        let config = active(
            parse_configuration(
                br#"{
                    "device":{"serialNumber":"SERIAL-1"},
                    "serial":{"enabled":true}
                }"#,
            )
            .unwrap(),
        );
        assert!(config.profile.serial_enabled);
        assert!(!config.profile.keyboard_enabled);
        assert!(config.profile.storage_luns.is_empty());
    }

    #[test]
    fn parses_ncm_defaults_from_serial() {
        let config = active(
            parse_configuration(
                br#"{
                    "device":{"serialNumber":"NCM-001"},
                    "ncm":{"enabled":true}
                }"#,
            )
            .unwrap(),
        );
        let ncm = config.profile.ncm.as_ref().unwrap();
        assert_eq!(ncm.device_mac, MacAddress::derive("NCM-001", 0));
        assert_eq!(ncm.host_mac, MacAddress::derive("NCM-001", 1));
        assert_ne!(ncm.device_mac, ncm.host_mac);
        assert_eq!(ncm.qmult, None);
        assert_eq!(ncm.ifname, None);
    }

    #[test]
    fn parses_and_validates_explicit_ncm_attributes() {
        let json = serde_json::json!({
            "device": {"serialNumber": "NCM-002"},
            "ncm": {
                "enabled": true,
                "deviceMac": "0A:48:59:50:45:01",
                "hostMac": "0a:48:59:50:45:02",
                "qmult": 5,
                "ifname": "hyperusb%d"
            }
        });
        let config = active(parse_configuration(&serde_json::to_vec(&json).unwrap()).unwrap());
        let ncm = config.profile.ncm.unwrap();
        assert_eq!(ncm.device_mac.as_configfs(), "0a:48:59:50:45:01");
        assert_eq!(ncm.host_mac.as_configfs(), "0a:48:59:50:45:02");
        assert_eq!(ncm.qmult, Some(5));
        assert_eq!(ncm.ifname.as_deref(), Some("hyperusb%d"));

        for invalid in [
            serde_json::json!({
                "device": {"serialNumber": "NCM-002"},
                "ncm": {"enabled": true, "deviceMac": "01:48:59:50:45:01"}
            }),
            serde_json::json!({
                "device": {"serialNumber": "NCM-002"},
                "ncm": {
                    "enabled": true,
                    "deviceMac": "02:48:59:50:45:01",
                    "hostMac": "02:48:59:50:45:01"
                }
            }),
            serde_json::json!({
                "device": {"serialNumber": "NCM-002"},
                "ncm": {"enabled": true, "qmult": 0}
            }),
            serde_json::json!({
                "device": {"serialNumber": "NCM-002"},
                "ncm": {"enabled": true, "ifname": "name with spaces"}
            }),
        ] {
            assert_eq!(
                parse_configuration(&serde_json::to_vec(&invalid).unwrap())
                    .unwrap_err()
                    .code,
                ApiErrorCode::InvalidConfig
            );
        }
    }

    #[test]
    fn normalizes_uvc_formats_frames_and_fps() {
        let json = serde_json::json!({
            "device": {"serialNumber": "UVC-1"},
            "uvc": {
                "enabled": true,
                "formats": [
                    {
                        "format": " MJPEG ",
                        "frames": [
                            {"width": 1280, "height": 720, "fps": [30, 60, 30]},
                            {"width": 1280, "height": 720, "fps": [60, 24]}
                        ]
                    },
                    {
                        "format": "mjpeg",
                        "frames": [
                            {"width": 1920, "height": 1080, "fps": [30]}
                        ]
                    },
                    {
                        "format": "YUYV",
                        "frames": [
                            {"width": 640, "height": 480, "fps": [30]}
                        ]
                    }
                ]
            }
        });
        let config = active(parse_configuration(&serde_json::to_vec(&json).unwrap()).unwrap());

        assert_eq!(config.profile.uvc.as_ref().unwrap().formats.len(), 2);
        let mjpeg = &config.profile.uvc.as_ref().unwrap().formats[0];
        assert_eq!(mjpeg.format, UvcFormatKind::Mjpeg);
        assert_eq!(mjpeg.frames.len(), 2);
        assert_eq!(mjpeg.frames[0].fps, vec![30, 60, 24]);
        assert_eq!(mjpeg.frames[1].fps, vec![30]);
        assert_eq!(
            config.profile.uvc.as_ref().unwrap().formats[1].format,
            UvcFormatKind::Yuyv
        );
    }

    #[test]
    fn rejects_invalid_enabled_uvc_semantics() {
        let invalid_configs = [
            serde_json::json!({
                "device": {"serialNumber": "UVC-1"},
                "uvc": {"enabled": true, "formats": [{"format": "h264", "frames": []}]}
            }),
            serde_json::json!({
                "device": {"serialNumber": "UVC-1"},
                "uvc": {"enabled": true, "formats": [{"format": "mjpeg", "frames": [{"width": 0, "height": 720, "fps": [30]}]}]}
            }),
            serde_json::json!({
                "device": {"serialNumber": "UVC-1"},
                "uvc": {"enabled": true, "formats": [{"format": "yuyv", "frames": [{"width": 640, "height": 480, "fps": []}]}]}
            }),
        ];

        for json in invalid_configs {
            assert_eq!(
                parse_configuration(&serde_json::to_vec(&json).unwrap())
                    .unwrap_err()
                    .code,
                ApiErrorCode::InvalidConfig
            );
        }
    }

    #[test]
    fn disabled_disk_does_not_require_image_or_read_only_semantics() {
        let json = br#"{
            "device":{"serialNumber":"TEST"},
            "disk":{"enabled":false,"cdrom":true,"readOnly":false},
            "keyboard":{"boot":true}
        }"#;
        parse_configuration(json).unwrap();
    }

    #[test]
    fn cdrom_defaults_read_only_and_rejects_false() {
        let image = test_path("cdrom.iso");
        std::fs::write(&image, b"iso").unwrap();
        let base = serde_json::json!({
            "device": {"serialNumber": "TEST"},
            "disk": {
                "enabled": true,
                "imagePath": image,
                "cdrom": true
            }
        });
        let config = active(parse_configuration(&serde_json::to_vec(&base).unwrap()).unwrap());
        assert!(config.profile.storage_luns[0].read_only);
        assert!(config.profile.storage_luns[0].no_fua);

        let mut invalid = base;
        invalid["disk"]["readOnly"] = serde_json::Value::Bool(false);
        assert_eq!(
            parse_configuration(&serde_json::to_vec(&invalid).unwrap())
                .unwrap_err()
                .code,
            ApiErrorCode::InvalidConfig
        );
        let _ = std::fs::remove_file(image);
    }

    #[test]
    fn legacy_disk_becomes_one_lun() {
        let image = test_path("legacy.img");
        std::fs::write(&image, b"disk").unwrap();
        let json = serde_json::json!({
            "device": {"serialNumber": "TEST"},
            "disk": {"enabled": true, "imagePath": image, "noFua": true}
        });
        let profile =
            active(parse_configuration(&serde_json::to_vec(&json).unwrap()).unwrap()).profile;
        assert_eq!(profile.storage_luns.len(), 1);
        assert!(profile.storage_luns[0].no_fua);
        let _ = std::fs::remove_file(image);
    }

    #[test]
    fn storage_luns_support_multiple_images_and_empty_target() {
        let first = test_path("first.img");
        let second = test_path("second.img");
        std::fs::write(&first, b"first").unwrap();
        std::fs::write(&second, b"second").unwrap();
        let json = serde_json::json!({
            "device": {"serialNumber": "TEST"},
            "storage": {"luns": [
                {"imagePath": first, "readOnly": false, "noFua": false},
                {"imagePath": second, "readOnly": true, "removable": true, "noFua": true}
            ]}
        });
        let profile =
            active(parse_configuration(&serde_json::to_vec(&json).unwrap()).unwrap()).profile;
        assert_eq!(profile.storage_luns.len(), 2);
        assert!(!profile.storage_luns[0].no_fua);
        assert!(profile.storage_luns[1].no_fua);
        assert_eq!(
            parse_configuration(br#"{"storage":{"luns":[]}}"#).unwrap(),
            UsbTargetState::AndroidUsb
        );
        let _ = std::fs::remove_file(first);
        let _ = std::fs::remove_file(second);
    }

    #[test]
    fn storage_luns_reject_duplicate_and_legacy_conflict() {
        let image = test_path("duplicate.img");
        let link = test_path("duplicate-link.img");
        std::fs::write(&image, b"disk").unwrap();
        #[cfg(unix)]
        std::os::unix::fs::symlink(&image, &link).unwrap();
        #[cfg(not(unix))]
        std::fs::copy(&image, &link).unwrap();
        #[cfg(unix)]
        {
            let duplicate = serde_json::json!({
                "device": {"serialNumber": "TEST"},
                "storage": {"luns": [{"imagePath": image}, {"imagePath": link}]}
            });
            assert_eq!(
                parse_configuration(&serde_json::to_vec(&duplicate).unwrap())
                    .unwrap_err()
                    .code,
                ApiErrorCode::DuplicateBackingFile
            );
        }
        let conflict = serde_json::json!({
            "device": {"serialNumber": "TEST"},
            "disk": {"enabled": true, "imagePath": image},
            "storage": {"luns": [{"imagePath": link}]}
        });
        assert_eq!(
            parse_configuration(&serde_json::to_vec(&conflict).unwrap())
                .unwrap_err()
                .code,
            ApiErrorCode::InvalidConfig
        );
        let _ = std::fs::remove_file(link);
        let _ = std::fs::remove_file(image);
    }

    #[test]
    fn rejects_directory_as_image() {
        let directory = test_path("directory");
        std::fs::create_dir_all(&directory).unwrap();
        let json = serde_json::json!({
            "device": {"serialNumber": "TEST"},
            "disk": {"enabled": true, "imagePath": directory}
        });
        assert_eq!(
            parse_configuration(&serde_json::to_vec(&json).unwrap())
                .unwrap_err()
                .code,
            ApiErrorCode::ImageNotFile
        );
        let _ = std::fs::remove_dir(directory);
    }

    #[test]
    fn rejects_config_larger_than_64_kib() {
        let path = test_path("oversized.json");
        std::fs::write(&path, vec![b' '; MAX_CONFIG_BYTES as usize + 1]).unwrap();
        assert_eq!(
            load_configuration(&path).unwrap_err().code,
            ApiErrorCode::InvalidConfig
        );
        let _ = std::fs::remove_file(path);
    }
}

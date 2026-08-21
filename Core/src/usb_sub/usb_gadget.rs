//! ConfigFS Gadget 与 Android USB 所有权管理。
//!
//! HyperUSB 使用自己拥有的持久 Gadget。正常停用只解绑 UDC、断开 Function 链接并清空
//! backing file，不删除 Gadget 根目录；这既符合参考脚本的生命周期，也绕开部分厂商内核
//! 删除 Gadget 后无法在同一次开机内重新创建的问题。

use std::fs::{self, OpenOptions};
use std::io::{ErrorKind, Write};
use std::path::{Component, Path, PathBuf};
use std::process::Command;
use std::sync::Mutex;
use std::thread;
use std::time::{Duration, Instant};

use log::{debug, info, warn};

use crate::usb_sub::usb_recovery::UsbRecoveryState;
use crate::usb_sub::{UsbError, UsbResult};

const CONFIGFS_ROOTS: [&str; 2] = ["/config/usb_gadget", "/sys/kernel/config/usb_gadget"];
static USB_OWNERSHIP_LOCK: Mutex<()> = Mutex::new(());

/// Host 可见的 USB 设备描述信息。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GadgetIdentity {
    pub vendor_id: u16,
    pub product_id: u16,
    pub usb_version: u16,
    pub device_version: u16,
    pub serial_number: String,
    pub manufacturer: String,
    pub product: String,
    pub configuration: String,
}

impl Default for GadgetIdentity {
    fn default() -> Self {
        Self {
            vendor_id: 0x1d6b,
            product_id: 0x0104,
            usb_version: 0x0200,
            device_version: 0x0100,
            serial_number: "HYPERUSB-0001".into(),
            manufacturer: "HyperUSB".into(),
            product: "HyperUSB Composite Device".into(),
            configuration: "Keyboard + Storage".into(),
        }
    }
}

/// 一个由 HyperUSB 长期拥有的 ConfigFS Gadget。
#[derive(Debug, Clone)]
pub struct UsbGadgetController {
    root: PathBuf,
    gadget_name: String,
    configuration_name: String,
}

impl UsbGadgetController {
    pub fn discover(
        gadget_name: impl Into<String>,
        configuration_name: impl Into<String>,
    ) -> UsbResult<Self> {
        Self::new(discover_gadget_root()?, gadget_name, configuration_name)
    }

    pub fn new(
        root: impl Into<PathBuf>,
        gadget_name: impl Into<String>,
        configuration_name: impl Into<String>,
    ) -> UsbResult<Self> {
        let root = root.into();
        let gadget_name = gadget_name.into();
        let configuration_name = configuration_name.into();
        validate_component(&gadget_name, "Gadget")?;
        validate_component(&configuration_name, "Configuration")?;
        if !root.is_dir() {
            return Err(UsbError::Unavailable(format!(
                "USB Gadget 根目录不可用：{}",
                root.display()
            )));
        }
        Ok(Self {
            root,
            gadget_name,
            configuration_name,
        })
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn gadget_name(&self) -> &str {
        &self.gadget_name
    }

    pub fn gadget_path(&self) -> PathBuf {
        self.root.join(&self.gadget_name)
    }

    pub fn config_path(&self) -> PathBuf {
        self.gadget_path()
            .join("configs")
            .join(&self.configuration_name)
    }

    pub fn function_path(&self, instance: &str) -> UsbResult<PathBuf> {
        validate_component(instance, "Function")?;
        Ok(self.gadget_path().join("functions").join(instance))
    }

    /// 创建或刷新持久 Gadget 的基础描述信息。
    ///
    /// 本方法不会创建 Function、不会绑定 UDC，也不会删除已有 Gadget。调用方必须保证
    /// Gadget 当前处于未绑定状态。
    pub fn ensure_base(&self, identity: &GadgetIdentity) -> UsbResult<()> {
        let gadget = self.gadget_path();
        if !gadget.exists() {
            info!("Creating persistent USB Gadget at {}", gadget.display());
            fs::create_dir(&gadget)?;
        } else {
            debug!("Reusing persistent USB Gadget at {}", gadget.display());
        }

        write_text(
            &gadget.join("idVendor"),
            &format!("0x{:04x}", identity.vendor_id),
        )?;
        write_text(
            &gadget.join("idProduct"),
            &format!("0x{:04x}", identity.product_id),
        )?;
        write_text(
            &gadget.join("bcdUSB"),
            &format!("0x{:04x}", identity.usb_version),
        )?;
        write_text(
            &gadget.join("bcdDevice"),
            &format!("0x{:04x}", identity.device_version),
        )?;
        for attribute in ["bDeviceClass", "bDeviceSubClass", "bDeviceProtocol"] {
            write_text(&gadget.join(attribute), "0")?;
        }

        let strings = gadget.join("strings/0x409");
        ensure_directory(&strings)?;
        write_text(&strings.join("serialnumber"), &identity.serial_number)?;
        write_text(&strings.join("manufacturer"), &identity.manufacturer)?;
        write_text(&strings.join("product"), &identity.product)?;

        let config = self.config_path();
        ensure_directory(&config)?;
        let config_strings = config.join("strings/0x409");
        ensure_directory(&config_strings)?;
        write_text(
            &config_strings.join("configuration"),
            &identity.configuration,
        )?;
        let attributes = config.join("bmAttributes");
        if attributes.exists() {
            write_text(&attributes, "0x80")?;
        }
        Ok(())
    }

    pub fn bound_udc(&self) -> UsbResult<String> {
        Ok(fs::read_to_string(self.gadget_path().join("UDC"))?
            .trim()
            .to_owned())
    }

    pub fn unbind(&self) -> UsbResult<()> {
        let udc = self.gadget_path().join("UDC");
        if udc.exists() && !fs::read_to_string(&udc)?.trim().is_empty() {
            write_text(&udc, "")?;
        }
        Ok(())
    }

    pub fn bind(&self, udc: &str) -> UsbResult<()> {
        validate_component(udc, "UDC")?;
        let udc_path = self.gadget_path().join("UDC");
        debug!(
            "sync_and_bind stage=udc_write path={} value={udc}",
            udc_path.display()
        );
        write_text(&udc_path, udc)
            .map_err(|error| contextual_error("udc_write", &udc_path, error))?;
        debug!(
            "sync_and_bind stage=udc_readback path={}",
            udc_path.display()
        );
        let actual = fs::read_to_string(&udc_path)
            .map_err(|error| contextual_error("udc_readback", &udc_path, UsbError::Io(error)))?
            .trim()
            .to_owned();
        if actual == udc {
            Ok(())
        } else {
            Err(UsbError::Unavailable(format!(
                "Gadget 未能绑定 UDC：期望 {udc}，实际 {actual}"
            )))
        }
    }

    /// 用指定 Function 替换同名 configuration 链接。
    ///
    /// 这对应参考脚本中的 `rm -f` + `ln -s`，因此重复激活不会堆积旧链接。
    pub fn replace_function_link(&self, instance: &str) -> UsbResult<PathBuf> {
        let function = self.function_path(instance)?;
        if !function.is_dir() {
            return Err(UsbError::Unavailable(format!(
                "Function 不存在：{}",
                function.display()
            )));
        }
        let link = self.config_path().join(instance);
        self.unlink_function(instance).map_err(|error| {
            UsbError::Unavailable(format!(
                "replace_function_link stage=unlink source={} target={} error={error}",
                function.display(),
                link.display()
            ))
        })?;

        #[cfg(unix)]
        {
            std::os::unix::fs::symlink(&function, &link).map_err(|error| {
                UsbError::Unavailable(format!(
                    "replace_function_link stage=symlink source={} target={} error={error}",
                    function.display(),
                    link.display()
                ))
            })?;
            Ok(link)
        }
        #[cfg(not(unix))]
        {
            let _ = link;
            Err(UsbError::Unsupported("ConfigFS Function 链接仅支持 Unix"))
        }
    }

    /// 如果链接存在则删除；不存在视为已经达到目标状态。
    pub fn unlink_function(&self, instance: &str) -> UsbResult<()> {
        validate_component(instance, "Function")?;
        let link = self.config_path().join(instance);
        match fs::symlink_metadata(&link) {
            Ok(metadata) if metadata.file_type().is_symlink() => {
                fs::remove_file(link)?;
                Ok(())
            }
            Ok(_) => Err(UsbError::InvalidInput(format!(
                "Function 链接位置被非符号链接占用：{}",
                link.display()
            ))),
            Err(error) if error.kind() == ErrorKind::NotFound => Ok(()),
            Err(error) => Err(error.into()),
        }
    }

    /// 将文件系统缓冲刷新到 backing file，再绑定 UDC。
    pub fn sync_and_bind(&self, udc: &str, timeout: Duration) -> UsbResult<()> {
        let gadget = self.gadget_path();
        let udc_path = gadget.join("UDC");
        info!(
            "sync_and_bind stage=sync gadget={} udc_path={}",
            gadget.display(),
            udc_path.display()
        );
        #[cfg(unix)]
        unsafe {
            debug!("sync_and_bind stage=sync");
            libc::sync();
        }
        let deadline = Instant::now() + timeout;
        loop {
            match self.bind(udc) {
                Ok(()) => return Ok(()),
                Err(UsbError::Io(error)) if error.raw_os_error() == Some(libc::EBUSY) => {
                    if Instant::now() >= deadline {
                        return Err(UsbError::TimedOut(
                            "UDC 在 Android USB 解绑后持续处于忙碌状态",
                        ));
                    }
                    thread::sleep(Duration::from_millis(50));
                }
                Err(error) => return Err(error),
            }
        }
    }

    /// 记录 UDC bind 前 UVC Function 与 configuration 的 ConfigFS 树。
    ///
    /// 诊断失败不得影响正常 USB 状态转换，因此所有读取错误只写日志。
    pub fn log_uvc_bind_snapshot(&self) {
        for root in [
            self.gadget_path().join("functions").join("uvc.hyperusb"),
            self.config_path(),
        ] {
            info!("UDC bind pre-snapshot root={}", root.display());
            log_tree(&root, 0);
        }
    }
}

/// 暂时接管 Android 系统 USB 的所有权。
///
/// 创建时保存 `sys.usb.config`，切换到 `none` 并确保系统 Gadget 已解绑；显式恢复或 Drop
/// 时写回原配置。此对象必须比 HyperUSB Gadget 的绑定存活得更久。
pub struct AndroidUsbLease {
    recovery_state: UsbRecoveryState,
    recovery_state_path: PathBuf,
    android_udc_path: PathBuf,
    restore_timeout: Duration,
    restored: bool,
    _lock: std::sync::MutexGuard<'static, ()>,
}

impl AndroidUsbLease {
    pub fn acquire(
        gadget_root: &Path,
        android_gadget_name: &str,
        release_delay: Duration,
        settle_delay: Duration,
        restore_timeout: Duration,
        recovery_state_path: impl Into<PathBuf>,
    ) -> UsbResult<Self> {
        validate_component(android_gadget_name, "Android Gadget")?;
        if !is_root() {
            return Err(UsbError::Unavailable(
                "切换 USB Gadget 需要以 root 身份运行".into(),
            ));
        }

        let lock = USB_OWNERSHIP_LOCK
            .lock()
            .map_err(|_| UsbError::Unavailable("USB 所有权锁已损坏".into()))?;
        let original_config = read_android_property("sys.usb.config")?
            .filter(|value| !value.is_empty())
            .ok_or_else(|| {
                UsbError::Unavailable(
                    "无法确定当前 Android USB 配置；为避免无法安全恢复，拒绝接管 UDC".into(),
                )
            })?;
        let recovery_state = UsbRecoveryState {
            original_usb_config: original_config,
            sys_adb_disabled: read_android_property("sys.usb.adb.disabled")?,
            vendor_adb_disabled: read_android_property("vendor.sys.usb.adb.disabled")?,
        };
        let recovery_state_path = recovery_state_path.into();
        // 一切会改变 Android USB 的命令之前，必须先落盘恢复信息。`panic = abort` 时 Drop
        // 不会执行，开发者仍可运行 `hyperusbd restore` 救回设备。
        recovery_state.persist_atomically(&recovery_state_path)?;
        let android_udc_path = gadget_root.join(android_gadget_name).join("UDC");
        let mut lease = Self {
            recovery_state,
            recovery_state_path,
            android_udc_path,
            restore_timeout,
            restored: false,
            _lock: lock,
        };

        let takeover = (|| {
            info!(
                "Taking Android USB ownership; previous config={}",
                lease.recovery_state.original_usb_config
            );
            // 小米 Gadget HAL 会在 ADB 未被禁用时重新绑定 g1，即使 sys.usb.config 已经
            // 临时切换为 none。两个属性都必须保存并置位，避免 HAL 与 HyperUSB 争抢 UDC。
            set_android_property("sys.usb.adb.disabled", "1")?;
            set_android_property("vendor.sys.usb.adb.disabled", "1")?;
            set_android_property("sys.usb.config", "none")?;
            thread::sleep(release_delay);
            if lease.android_udc_path.exists() {
                write_text(&lease.android_udc_path, "")?;
            }
            // ConfigFS 的 UDC 属性已清空，并不代表 DWC3 驱动已经完成端点和中断收尾。
            // 参考脚本在此显式等待；否则紧接着绑定另一个 Gadget 会收到 EBUSY。
            thread::sleep(settle_delay);
            Ok(())
        })();
        if let Err(error) = takeover {
            let _ = lease.restore();
            return Err(error);
        }
        Ok(lease)
    }

    pub fn restore(&mut self) -> UsbResult<()> {
        if self.restored {
            return Ok(());
        }
        restore_android_usb_state(
            &self.recovery_state,
            &self.android_udc_path,
            self.restore_timeout,
        )?;
        UsbRecoveryState::clear(&self.recovery_state_path)?;
        self.restored = true;
        Ok(())
    }

    pub fn original_config(&self) -> &str {
        &self.recovery_state.original_usb_config
    }
}

impl Drop for AndroidUsbLease {
    fn drop(&mut self) {
        let _ = self.restore();
    }
}

/// 读取持久恢复状态并恢复 Android USB；用于崩溃后的独立 `restore` 命令。
pub fn restore_android_usb_from_state(
    gadget_root: &Path,
    android_gadget_name: &str,
    restore_timeout: Duration,
    recovery_state_path: impl AsRef<Path>,
) -> UsbResult<()> {
    validate_component(android_gadget_name, "Android Gadget")?;
    if !is_root() {
        return Err(UsbError::Unavailable(
            "恢复 Android USB 需要以 root 身份运行".into(),
        ));
    }
    let _lock = USB_OWNERSHIP_LOCK
        .lock()
        .map_err(|_| UsbError::Unavailable("USB 所有权锁已损坏".into()))?;
    let recovery_state_path = recovery_state_path.as_ref();
    let state = UsbRecoveryState::load(recovery_state_path)?.ok_or_else(|| {
        UsbError::Unavailable(format!(
            "未找到待恢复的 USB 状态：{}",
            recovery_state_path.display()
        ))
    })?;
    let android_udc_path = gadget_root.join(android_gadget_name).join("UDC");
    restore_android_usb_state(&state, &android_udc_path, restore_timeout)?;
    UsbRecoveryState::clear(recovery_state_path)
}

fn restore_android_usb_state(
    state: &UsbRecoveryState,
    android_udc_path: &Path,
    restore_timeout: Duration,
) -> UsbResult<()> {
    info!("Restoring Android USB config={}", state.original_usb_config);
    let mut errors = Vec::new();
    for (name, value) in [
        ("sys.usb.adb.disabled", state.sys_adb_disabled.as_deref()),
        (
            "vendor.sys.usb.adb.disabled",
            state.vendor_adb_disabled.as_deref(),
        ),
        ("sys.usb.config", Some(state.original_usb_config.as_str())),
    ] {
        // Android property service 没有删除属性的接口；对原先不存在/为空的开关写入空字符串，
        // 恢复 getprop 可见值与 ADB 禁用语义，而不是遗留 HyperUSB 写入的 `1`。
        if let Err(error) = set_android_property(name, value.unwrap_or("")) {
            errors.push(error.to_string());
        }
    }
    if !errors.is_empty() {
        return Err(UsbError::Unavailable(format!(
            "恢复 Android USB 属性失败：{}",
            errors.join("；")
        )));
    }

    if state.original_usb_config == "none" {
        return Ok(());
    }
    let deadline = Instant::now() + restore_timeout;
    let stable_duration = Duration::from_millis(500);
    let mut stable_since = None;
    loop {
        let bound = fs::read_to_string(android_udc_path)
            .map(|value| !value.trim().is_empty())
            .unwrap_or(false);
        if bound {
            let since = stable_since.get_or_insert_with(Instant::now);
            if since.elapsed() >= stable_duration {
                return Ok(());
            }
        } else {
            stable_since = None;
        }
        if Instant::now() >= deadline {
            return Err(UsbError::TimedOut(
                "Android USB 属性已恢复，但系统 Gadget 未在期限内稳定绑定 UDC",
            ));
        }
        thread::sleep(Duration::from_millis(50));
    }
}

pub fn discover_gadget_root() -> UsbResult<PathBuf> {
    CONFIGFS_ROOTS
        .iter()
        .map(PathBuf::from)
        .find(|path| path.is_dir())
        .ok_or_else(|| UsbError::Unavailable("未找到 ConfigFS USB Gadget 根目录".into()))
}

/// 优先读取 Android 公布的 UDC，再回退到 `/sys/class/udc` 枚举。
pub fn discover_udc() -> UsbResult<String> {
    if let Some(controller) = android_property("sys.usb.controller") {
        if !controller.is_empty() && Path::new("/sys/class/udc").join(&controller).exists() {
            return Ok(controller);
        }
    }
    let mut udcs = fs::read_dir("/sys/class/udc")?
        .filter_map(Result::ok)
        .filter_map(|entry| entry.file_name().into_string().ok())
        .collect::<Vec<_>>();
    udcs.sort();
    udcs.into_iter()
        .next()
        .ok_or_else(|| UsbError::Unavailable("设备没有可用的 UDC".into()))
}

pub fn configfs_status() -> &'static str {
    if Path::new("/sys/kernel/config").is_dir() {
        "Available"
    } else {
        "Unavailable"
    }
}

pub fn gadget_status() -> &'static str {
    if CONFIGFS_ROOTS.iter().any(|path| Path::new(path).is_dir()) {
        "Available"
    } else {
        "Unavailable"
    }
}

pub fn udc_status() -> String {
    discover_udc().unwrap_or_else(|_| "Unavailable".into())
}

/// 返回当前 USB Device Controller 是否已被 USB Host 连接并枚举。
pub fn udc_connection_status() -> String {
    let Ok(udc) = discover_udc() else {
        return "Unavailable".into();
    };
    let state_path = Path::new("/sys/class/udc").join(udc).join("state");
    match fs::read_to_string(state_path) {
        Ok(state) => match state.trim() {
            "configured" | "suspended" => "Yes".into(),
            "attached" => "Connecting".into(),
            "not attached" => "No".into(),
            other if !other.is_empty() => format!("Unknown ({other})"),
            _ => "Unavailable".into(),
        },
        Err(_) => "Unavailable".into(),
    }
}

pub fn udc_enumeration_state() -> String {
    let Ok(udc) = discover_udc() else {
        return "Unavailable".into();
    };
    match fs::read_to_string(Path::new("/sys/class/udc").join(udc).join("state")) {
        Ok(state) if !state.trim().is_empty() => state.trim().to_owned(),
        _ => "Unavailable".into(),
    }
}

pub fn udc_writable() -> &'static str {
    let Ok(root) = discover_gadget_root() else {
        return "Unavailable";
    };
    let Ok(gadgets) = fs::read_dir(root) else {
        return "Unavailable";
    };
    let mut found = false;
    for gadget in gadgets.filter_map(Result::ok) {
        let udc = gadget.path().join("UDC");
        if !udc.is_file() {
            continue;
        }
        found = true;
        if OpenOptions::new().write(true).open(udc).is_ok() {
            return "Yes";
        }
    }
    if found {
        "No"
    } else {
        "Unavailable"
    }
}

fn validate_component(value: &str, label: &str) -> UsbResult<()> {
    let mut components = Path::new(value).components();
    if value.is_empty()
        || !matches!(components.next(), Some(Component::Normal(_)))
        || components.next().is_some()
    {
        return Err(UsbError::InvalidInput(format!(
            "{label} 名称必须是单个安全路径组件：{value:?}"
        )));
    }
    Ok(())
}

fn ensure_directory(path: &Path) -> UsbResult<()> {
    if !path.exists() {
        if let Some(parent) = path.parent() {
            ensure_directory(parent)?;
        }
        fs::create_dir(path)?;
    }
    if path.is_dir() {
        Ok(())
    } else {
        Err(UsbError::InvalidInput(format!(
            "ConfigFS 路径不是目录：{}",
            path.display()
        )))
    }
}

fn contextual_error(stage: &str, path: &Path, error: UsbError) -> UsbError {
    match error {
        UsbError::Io(io_error) if io_error.raw_os_error() == Some(libc::EBUSY) => {
            UsbError::Io(io_error)
        }
        other => UsbError::Unavailable(format!(
            "sync_and_bind stage={stage} path={} error={other}",
            path.display()
        )),
    }
}

fn log_tree(path: &Path, depth: usize) {
    let indent = "  ".repeat(depth);
    match fs::symlink_metadata(path) {
        Ok(metadata) => {
            let target = if metadata.file_type().is_symlink() {
                fs::read_link(path)
                    .map(|value| format!(" -> {}", value.display()))
                    .unwrap_or_else(|error| format!(" -> <readlink error: {error}>"))
            } else {
                String::new()
            };
            info!("UDC bind pre-snapshot {indent}{}{}", path.display(), target);
            if metadata.is_dir() {
                match fs::read_dir(path) {
                    Ok(entries) => {
                        for entry in entries {
                            match entry {
                                Ok(entry) => log_tree(&entry.path(), depth + 1),
                                Err(error) => warn!(
                                    "UDC bind pre-snapshot stage=read_dir path={} error={error}",
                                    path.display()
                                ),
                            }
                        }
                    }
                    Err(error) => warn!(
                        "UDC bind pre-snapshot stage=read_dir path={} error={error}",
                        path.display()
                    ),
                }
            }
        }
        Err(error) => warn!(
            "UDC bind pre-snapshot stage=symlink_metadata path={} error={error}",
            path.display()
        ),
    }
}

fn write_text(path: &Path, value: &str) -> UsbResult<()> {
    let mut file = OpenOptions::new().write(true).truncate(true).open(path)?;
    if value.is_empty() {
        // Shell 的 `echo "" > UDC` 会写入一个换行符；零字节 write 不会触发 ConfigFS
        // 属性的 store 回调，因此不能用于解绑。
        file.write_all(b"\n")?;
    } else {
        file.write_all(value.as_bytes())?;
    }
    Ok(())
}

fn android_property(name: &str) -> Option<String> {
    read_android_property(name).ok().flatten()
}

/// 严格读取 Android 属性。
///
/// 空值或未定义属性是正常状态，表示为 `Ok(None)`；但 `getprop` 本身无法执行或返回失败
/// 绝不能伪装成默认值。接管前必须能准确保存 `sys.usb.config`，否则没有可靠恢复路径。
fn read_android_property(name: &str) -> UsbResult<Option<String>> {
    let output = Command::new("getprop").arg(name).output()?;
    if !output.status.success() {
        return Err(UsbError::CommandFailed {
            program: format!("getprop {name}"),
            status: output.status.code(),
            stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
        });
    }
    let value = String::from_utf8_lossy(&output.stdout).trim().to_owned();
    Ok((!value.is_empty()).then_some(value))
}

fn set_android_property(name: &str, value: &str) -> UsbResult<()> {
    let output = Command::new("setprop").args([name, value]).output()?;
    if output.status.success() {
        Ok(())
    } else {
        Err(UsbError::CommandFailed {
            program: format!("setprop {name}"),
            status: output.status.code(),
            stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
        })
    }
}

#[cfg(unix)]
fn is_root() -> bool {
    unsafe { libc::geteuid() == 0 }
}

#[cfg(not(unix))]
fn is_root() -> bool {
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_nested_configfs_names() {
        assert!(validate_component("../g1", "Gadget").is_err());
        assert!(validate_component("a/b", "Gadget").is_err());
        assert!(validate_component("hyperusb", "Gadget").is_ok());
    }

    #[test]
    fn empty_control_value_writes_a_newline() {
        let path = std::env::temp_dir().join(format!(
            "hyperusb-control-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        ));
        fs::write(&path, "occupied").unwrap();
        write_text(&path, "").unwrap();
        assert_eq!(fs::read(&path).unwrap(), b"\n");
        fs::remove_file(path).unwrap();
    }
}

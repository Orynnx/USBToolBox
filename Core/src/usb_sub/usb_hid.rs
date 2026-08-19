//! USB Boot Keyboard 核心。
//!
//! 包含标准 8 字节键盘 Report、ASCII 按键编码、HID 描述符校验、ConfigFS Function
//! 配置，以及 `/dev/hidg*` 的顺序写入。所有会修改设备状态的操作都必须由调用方显式
//! 调用；创建结构体本身不会触碰 ConfigFS。

use std::fs::{self, File, OpenOptions};
use std::io::{ErrorKind, Write};
use std::path::{Path, PathBuf};
use std::thread;
use std::time::{Duration, Instant};

use crate::usb_sub::{UsbError, UsbResult};

/// Linux HID Gadget 使用的标准 Boot Keyboard Report 长度。
pub const KEYBOARD_REPORT_LENGTH: usize = 8;

/// NKRO 键盘的位图 Report 长度：修饰键 1 字节、保留字节 1 个、224 个普通 Usage 位。
pub const NKRO_KEYBOARD_REPORT_LENGTH: usize = 30;

/// Boot Keyboard Report Descriptor，支持 8 个修饰键、5 个 LED 和 6 个普通按键槽位。
pub const BOOT_KEYBOARD_DESCRIPTOR: [u8; 63] = [
    0x05, 0x01, 0x09, 0x06, 0xa1, 0x01, 0x05, 0x07, 0x19, 0xe0, 0x29, 0xe7, 0x15, 0x00, 0x25, 0x01,
    0x75, 0x01, 0x95, 0x08, 0x81, 0x02, 0x95, 0x01, 0x75, 0x08, 0x81, 0x03, 0x95, 0x05, 0x75, 0x01,
    0x05, 0x08, 0x19, 0x01, 0x29, 0x05, 0x91, 0x02, 0x95, 0x01, 0x75, 0x03, 0x91, 0x03, 0x95, 0x06,
    0x75, 0x08, 0x15, 0x00, 0x25, 0x73, 0x05, 0x07, 0x19, 0x00, 0x29, 0x73, 0x81, 0x00, 0xc0,
];

const ERROR_ROLLOVER: u8 = 0x01;
const DEFAULT_KEY_HOLD: Duration = Duration::from_millis(5);

/// Boot Keyboard Report 第一个字节中的修饰键位图。
///
/// 修饰键不占用普通按键的六个槽位，可通过 `|` 组合，例如
/// `Modifiers::LEFT_CTRL | Modifiers::LEFT_SHIFT`。
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash)]
pub struct Modifiers(u8);

impl Modifiers {
    pub const NONE: Self = Self(0x00);
    pub const LEFT_CTRL: Self = Self(0x01);
    pub const LEFT_SHIFT: Self = Self(0x02);
    pub const LEFT_ALT: Self = Self(0x04);
    pub const LEFT_GUI: Self = Self(0x08);
    pub const RIGHT_CTRL: Self = Self(0x10);
    pub const RIGHT_SHIFT: Self = Self(0x20);
    pub const RIGHT_ALT: Self = Self(0x40);
    pub const RIGHT_GUI: Self = Self(0x80);

    /// 返回可直接放入 Boot Keyboard Report 的位图。
    pub const fn bits(self) -> u8 {
        self.0
    }
}

impl std::ops::BitOr for Modifiers {
    type Output = Self;

    fn bitor(self, right: Self) -> Self::Output {
        Self(self.0 | right.0)
    }
}

impl std::ops::BitOrAssign for Modifiers {
    fn bitor_assign(&mut self, right: Self) {
        self.0 |= right.0;
    }
}

/// 上层可见的标准 USB Boot Keyboard 按键。
///
/// 具体 Usage ID 保留在此处，调用 CLI、Flutter 或其他上层时无需接触裸字节。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Key {
    A,
    B,
    C,
    D,
    E,
    F,
    G,
    H,
    I,
    J,
    K,
    L,
    M,
    N,
    O,
    P,
    Q,
    R,
    S,
    T,
    U,
    V,
    W,
    X,
    Y,
    Z,
    Digit1,
    Digit2,
    Digit3,
    Digit4,
    Digit5,
    Digit6,
    Digit7,
    Digit8,
    Digit9,
    Digit0,
    Enter,
    Escape,
    Backspace,
    Tab,
    Space,
    Insert,
    Home,
    PageUp,
    Delete,
    End,
    PageDown,
    ArrowRight,
    ArrowLeft,
    ArrowDown,
    ArrowUp,
    F1,
    F2,
    F3,
    F4,
    F5,
    F6,
    F7,
    F8,
    F9,
    F10,
    F11,
    F12,
}

impl Key {
    /// 标准 USB HID Usage ID。
    pub const fn usage(self) -> u8 {
        match self {
            Self::A => 0x04,
            Self::B => 0x05,
            Self::C => 0x06,
            Self::D => 0x07,
            Self::E => 0x08,
            Self::F => 0x09,
            Self::G => 0x0a,
            Self::H => 0x0b,
            Self::I => 0x0c,
            Self::J => 0x0d,
            Self::K => 0x0e,
            Self::L => 0x0f,
            Self::M => 0x10,
            Self::N => 0x11,
            Self::O => 0x12,
            Self::P => 0x13,
            Self::Q => 0x14,
            Self::R => 0x15,
            Self::S => 0x16,
            Self::T => 0x17,
            Self::U => 0x18,
            Self::V => 0x19,
            Self::W => 0x1a,
            Self::X => 0x1b,
            Self::Y => 0x1c,
            Self::Z => 0x1d,
            Self::Digit1 => 0x1e,
            Self::Digit2 => 0x1f,
            Self::Digit3 => 0x20,
            Self::Digit4 => 0x21,
            Self::Digit5 => 0x22,
            Self::Digit6 => 0x23,
            Self::Digit7 => 0x24,
            Self::Digit8 => 0x25,
            Self::Digit9 => 0x26,
            Self::Digit0 => 0x27,
            Self::Enter => 0x28,
            Self::Escape => 0x29,
            Self::Backspace => 0x2a,
            Self::Tab => 0x2b,
            Self::Space => 0x2c,
            Self::F1 => 0x3a,
            Self::F2 => 0x3b,
            Self::F3 => 0x3c,
            Self::F4 => 0x3d,
            Self::F5 => 0x3e,
            Self::F6 => 0x3f,
            Self::F7 => 0x40,
            Self::F8 => 0x41,
            Self::F9 => 0x42,
            Self::F10 => 0x43,
            Self::F11 => 0x44,
            Self::F12 => 0x45,
            Self::Insert => 0x49,
            Self::Home => 0x4a,
            Self::PageUp => 0x4b,
            Self::Delete => 0x4c,
            Self::End => 0x4d,
            Self::PageDown => 0x4e,
            Self::ArrowRight => 0x4f,
            Self::ArrowLeft => 0x50,
            Self::ArrowDown => 0x51,
            Self::ArrowUp => 0x52,
        }
    }
}

/// 一次需要同时按下的修饰键与普通键。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct KeyChord {
    pub modifiers: Modifiers,
    pub keys: Vec<Key>,
}

impl KeyChord {
    pub fn new(modifiers: Modifiers, keys: impl IntoIterator<Item = Key>) -> UsbResult<Self> {
        let chord = Self {
            modifiers,
            keys: keys.into_iter().collect(),
        };
        chord.validate()?;
        Ok(chord)
    }

    pub fn validate(&self) -> UsbResult<()> {
        if self.keys.len() > 6 {
            return Err(UsbError::InvalidInput(
                "一个 Boot Keyboard 组合键最多包含六个普通按键".into(),
            ));
        }
        if self
            .keys
            .iter()
            .enumerate()
            .any(|(index, key)| self.keys[..index].contains(key))
        {
            return Err(UsbError::InvalidInput("组合键中不能重复普通按键".into()));
        }
        Ok(())
    }

    pub fn report(&self) -> UsbResult<KeyboardReport> {
        self.validate()?;
        Ok(KeyboardReport::new(
            self.modifiers.bits(),
            self.keys.iter().copied().map(Key::usage),
        ))
    }
}

/// 可用于虚拟键盘的当前按键状态。
///
/// 它是纯内存模型；UI 可在按下/松开时更新它，并调用 [`HidKeyboardWriter::write_state`]
/// 输出完整 Report，从而让 Ctrl 等修饰键在普通键释放后继续保持按下。
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct KeyboardState {
    modifiers: Modifiers,
    keys: Vec<Key>,
}

impl KeyboardState {
    pub fn modifiers(&self) -> Modifiers {
        self.modifiers
    }

    pub fn keys(&self) -> &[Key] {
        &self.keys
    }

    pub fn set_modifiers(&mut self, modifiers: Modifiers) {
        self.modifiers = modifiers;
    }

    pub fn press(&mut self, key: Key) -> UsbResult<()> {
        if self.keys.contains(&key) {
            return Ok(());
        }
        if self.keys.len() == 6 {
            return Err(UsbError::InvalidInput(
                "Boot Keyboard 同时最多保持六个普通按键".into(),
            ));
        }
        self.keys.push(key);
        Ok(())
    }

    pub fn release(&mut self, key: Key) -> bool {
        let Some(index) = self.keys.iter().position(|held| *held == key) else {
            return false;
        };
        self.keys.remove(index);
        true
    }

    pub fn release_all(&mut self) {
        self.modifiers = Modifiers::NONE;
        self.keys.clear();
    }

    pub fn report(&self) -> KeyboardReport {
        KeyboardReport::new(
            self.modifiers.bits(),
            self.keys.iter().copied().map(Key::usage),
        )
    }
}

/// 一个完整的 Boot Keyboard 实时状态。
///
/// 字节 0 为修饰键位图，字节 1 保留，后 6 字节为普通按键 Usage。按键会保持按下，
/// 直到显式发送 [`KeyboardReport::released`]。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct KeyboardReport([u8; KEYBOARD_REPORT_LENGTH]);

impl KeyboardReport {
    /// 根据修饰键位图和普通按键 Usage 构造 Report。
    ///
    /// 重复 Usage 会被去重；超过 6 个普通按键时，按 HID Boot Protocol 要求在全部按键
    /// 槽位中写入 `ErrorRollOver`。
    pub fn new(modifier: u8, usages: impl IntoIterator<Item = u8>) -> Self {
        let mut keys = [0_u8; 6];
        let mut count = 0;

        for usage in usages {
            if usage == 0 || keys[..count].contains(&usage) {
                continue;
            }
            if count == keys.len() {
                keys.fill(ERROR_ROLLOVER);
                break;
            }
            keys[count] = usage;
            count += 1;
        }

        let mut report = [0_u8; KEYBOARD_REPORT_LENGTH];
        report[0] = modifier;
        report[2..].copy_from_slice(&keys);
        Self(report)
    }

    /// 返回“全部按键已释放”的全零 Report。
    pub const fn released() -> Self {
        Self([0; KEYBOARD_REPORT_LENGTH])
    }

    /// 返回可直接写入 `/dev/hidg*` 的 8 字节内容。
    pub const fn as_bytes(&self) -> &[u8; KEYBOARD_REPORT_LENGTH] {
        &self.0
    }
}

/// 将标准 US 键盘布局可表示的文本编码为“按下、释放”Report 序列。
///
/// 每个字符固定生成两个 Report，确保前一个按键不会在主机端保持按下。无法表示的 Unicode
/// 字符会返回包含字符位置和码点的错误。
pub fn encode_text(text: &str) -> UsbResult<Vec<KeyboardReport>> {
    let mut reports = Vec::with_capacity(text.chars().count() * 2);
    for (index, character) in text.chars().enumerate() {
        let (modifier, usage) = key_for_character(character).ok_or_else(|| {
            UsbError::InvalidInput(format!(
                "第 {} 个字符无法用标准 USB 键盘发送：U+{:04X}",
                index + 1,
                character as u32
            ))
        })?;
        reports.push(KeyboardReport::new(modifier, [usage]));
        reports.push(KeyboardReport::released());
    }
    Ok(reports)
}

/// HID Function 的配置模型。
#[derive(Debug)]
pub struct UsbHid {
    /// 写入 ConfigFS `report_desc` 的 HID Report Descriptor。
    pub descriptor: Vec<u8>,
    /// 写入 ConfigFS `report_length` 的单个 Report 字节数。
    pub report_length: u16,
    /// USB HID interface protocol；键盘为 `1`。
    pub protocol: u8,
    /// `1` 表示 Boot 子类，`0` 表示普通 HID 子类。
    pub subclass: u8,
}

impl Default for UsbHid {
    fn default() -> Self {
        Self {
            descriptor: BOOT_KEYBOARD_DESCRIPTOR.to_vec(),
            report_length: KEYBOARD_REPORT_LENGTH as u16,
            protocol: 1,
            subclass: 1,
        }
    }
}

impl UsbHid {
    /// 校验 Report 长度及 HID Descriptor 的结构完整性。
    pub fn validate(&self) -> UsbResult<()> {
        if self.report_length == 0 {
            return Err(UsbError::InvalidInput(format!(
                "HID report_length 必须大于零，实际为 {}",
                self.report_length
            )));
        }
        validate_descriptor(&self.descriptor)
    }

    /// 创建并配置一个未链接、未绑定的 ConfigFS HID Function。
    ///
    /// 调用方必须先解绑 Gadget 的 UDC，并在成功后自行把 Function 链接到 configuration。
    pub fn configure_function(&self, function_path: impl AsRef<Path>) -> UsbResult<()> {
        self.validate()?;
        let function_path = function_path.as_ref();
        ensure_function_directory(function_path)?;

        write_attribute(
            &function_path.join("protocol"),
            self.protocol.to_string().as_bytes(),
        )?;
        write_attribute(
            &function_path.join("subclass"),
            self.subclass.to_string().as_bytes(),
        )?;
        write_attribute(
            &function_path.join("report_length"),
            self.report_length.to_string().as_bytes(),
        )?;
        let no_out_endpoint = function_path.join("no_out_endpoint");
        if no_out_endpoint.exists() {
            write_attribute(&no_out_endpoint, b"1")?;
        }
        write_attribute(&function_path.join("report_desc"), &self.descriptor)
    }
}

/// 供各类 HID 键盘共享的端点写入器。
///
/// 统一处理 Host 就绪检查、非阻塞重试、完整写入校验与 Drop 时的全零释放，Boot/NKRO
/// 不会各自复制一套容易漂移的 I/O 逻辑。
pub(crate) struct HidReportWriter {
    endpoint_path: PathBuf,
    udc_state_path: PathBuf,
    endpoint: File,
    retry_timeout: Duration,
    report_length: usize,
}

impl HidReportWriter {
    pub(crate) fn open(
        endpoint_path: impl Into<PathBuf>,
        udc_state_path: impl Into<PathBuf>,
        report_length: usize,
    ) -> UsbResult<Self> {
        if report_length == 0 {
            return Err(UsbError::InvalidInput("HID Report 长度必须大于零".into()));
        }
        let endpoint_path = endpoint_path.into();
        let endpoint = open_nonblocking(&endpoint_path)?;
        Ok(Self {
            endpoint_path,
            udc_state_path: udc_state_path.into(),
            endpoint,
            retry_timeout: Duration::from_secs(2),
            report_length,
        })
    }

    pub(crate) fn set_retry_timeout(&mut self, timeout: Duration) {
        self.retry_timeout = timeout;
    }

    pub(crate) fn write_report(&mut self, report: &[u8]) -> UsbResult<()> {
        if report.len() != self.report_length {
            return Err(UsbError::InvalidInput(format!(
                "HID Report 长度不匹配：期望 {}，实际 {}",
                self.report_length,
                report.len()
            )));
        }
        let deadline = Instant::now() + self.retry_timeout;

        loop {
            // 每次重试前重新检查 UDC，避免 Host 在端点忙碌期间断开后继续写入。
            self.ensure_host_ready()?;
            match self.endpoint.write(report) {
                Ok(actual) if actual == self.report_length => return Ok(()),
                Ok(actual) => {
                    return Err(UsbError::PartialWrite {
                        expected: self.report_length,
                        actual,
                    });
                }
                Err(error)
                    if matches!(error.kind(), ErrorKind::WouldBlock | ErrorKind::Interrupted) =>
                {
                    if Instant::now() >= deadline {
                        return Err(UsbError::TimedOut("HID 端点持续忙碌超过重试期限"));
                    }
                    thread::sleep(Duration::from_millis(2));
                }
                Err(error) => return Err(error.into()),
            }
        }
    }

    pub(crate) fn endpoint_path(&self) -> &Path {
        &self.endpoint_path
    }

    fn ensure_host_ready(&self) -> UsbResult<()> {
        let state = fs::read_to_string(&self.udc_state_path)
            .map(|state| state.trim().to_owned())
            .unwrap_or_else(|_| "unavailable".into());
        if matches!(state.as_str(), "configured" | "suspended") {
            Ok(())
        } else {
            Err(UsbError::Unavailable(format!(
                "USB Host 未就绪（UDC state={state}）"
            )))
        }
    }
}

impl Drop for HidReportWriter {
    fn drop(&mut self) {
        let _ = self.endpoint.write(&vec![0; self.report_length]);
        let _ = self.endpoint.flush();
    }
}

/// 一个持久打开的 Boot Keyboard Gadget 端点。
pub struct HidKeyboardWriter {
    inner: HidReportWriter,
}

impl HidKeyboardWriter {
    pub fn open(
        endpoint_path: impl Into<PathBuf>,
        udc_state_path: impl Into<PathBuf>,
    ) -> UsbResult<Self> {
        Ok(Self {
            inner: HidReportWriter::open(endpoint_path, udc_state_path, KEYBOARD_REPORT_LENGTH)?,
        })
    }

    /// 修改端点忙碌时的最大重试时间。
    pub fn set_retry_timeout(&mut self, timeout: Duration) {
        self.inner.set_retry_timeout(timeout);
    }

    /// 原子写入一个 8 字节键盘状态。
    pub fn write_report(&mut self, report: KeyboardReport) -> UsbResult<()> {
        self.inner.write_report(report.as_bytes())
    }

    /// 按顺序发送多个 Report，并在 Report 之间等待指定时间。
    pub fn write_reports(
        &mut self,
        reports: &[KeyboardReport],
        interval: Duration,
    ) -> UsbResult<()> {
        for (index, report) in reports.iter().copied().enumerate() {
            self.write_report(report)?;
            if index + 1 < reports.len() && !interval.is_zero() {
                thread::sleep(interval);
            }
        }
        Ok(())
    }

    /// 编码并发送文本。
    pub fn write_text(&mut self, text: &str, interval: Duration) -> UsbResult<()> {
        let reports = encode_text(text)?;
        self.write_reports(&reports, interval)
    }

    /// 按下一个普通键与指定修饰键，并保持该状态直到调用 [`Self::key_up_all`]。
    pub fn key_down(&mut self, key: Key, modifiers: Modifiers) -> UsbResult<()> {
        self.write_report(KeyboardReport::new(modifiers.bits(), [key.usage()]))
    }

    /// 释放全部修饰键和普通键。
    pub fn key_up_all(&mut self) -> UsbResult<()> {
        self.write_report(KeyboardReport::released())
    }

    /// 点按一个普通键：按下后短暂保持，再释放全部按键。
    pub fn tap(&mut self, key: Key, modifiers: Modifiers) -> UsbResult<()> {
        self.key_down(key, modifiers)?;
        thread::sleep(DEFAULT_KEY_HOLD);
        self.key_up_all()
    }

    /// 发送组合键：同时按下所有键，短暂保持，再释放。
    ///
    /// `Alt+F4` 可表示为 `KeyChord::new(Modifiers::LEFT_ALT, [Key::F4])`。Windows 对
    /// `Ctrl+Alt+Delete` 等安全注意序列的处理由 Host 决定，但 HID 物理键序列可以表达。
    pub fn send_chord(&mut self, chord: &KeyChord) -> UsbResult<()> {
        self.write_report(chord.report()?)?;
        thread::sleep(DEFAULT_KEY_HOLD);
        self.key_up_all()
    }

    /// 发送由 UI 或其他上层维护的完整按键状态。
    pub fn write_state(&mut self, state: &KeyboardState) -> UsbResult<()> {
        self.write_report(state.report())
    }

    pub fn endpoint_path(&self) -> &Path {
        self.inner.endpoint_path()
    }
}

/// 根据 ConfigFS HID Function 的 `dev` 设备号解析对应的 `/dev/hidg*` 端点。
///
/// 不能假设新 Function 一定对应 `hidg0`；设备上可能已存在其他 HID Function，因此必须
/// 比较 `/sys/class/hidg/hidg*/dev` 的 `major:minor`。
pub fn resolve_hid_endpoint(function_path: impl AsRef<Path>) -> UsbResult<PathBuf> {
    resolve_hid_endpoint_in(
        function_path.as_ref(),
        Path::new("/sys/class/hidg"),
        Path::new("/dev"),
    )
}

fn key_for_character(character: char) -> Option<(u8, u8)> {
    let key = match character {
        'a'..='z' => (0, 0x04 + (character as u8 - b'a')),
        'A'..='Z' => (
            Modifiers::LEFT_SHIFT.bits(),
            0x04 + (character as u8 - b'A'),
        ),
        '1'..='9' => (0, 0x1e + (character as u8 - b'1')),
        '0' => (0, 0x27),
        '\n' | '\r' => (0, 0x28),
        '\t' => (0, 0x2b),
        ' ' => (0, 0x2c),
        '-' => (0, 0x2d),
        '_' => (Modifiers::LEFT_SHIFT.bits(), 0x2d),
        '=' => (0, 0x2e),
        '+' => (Modifiers::LEFT_SHIFT.bits(), 0x2e),
        '[' => (0, 0x2f),
        '{' => (Modifiers::LEFT_SHIFT.bits(), 0x2f),
        ']' => (0, 0x30),
        '}' => (Modifiers::LEFT_SHIFT.bits(), 0x30),
        '\\' => (0, 0x31),
        '|' => (Modifiers::LEFT_SHIFT.bits(), 0x31),
        ';' => (0, 0x33),
        ':' => (Modifiers::LEFT_SHIFT.bits(), 0x33),
        '\'' => (0, 0x34),
        '"' => (Modifiers::LEFT_SHIFT.bits(), 0x34),
        '`' => (0, 0x35),
        '~' => (Modifiers::LEFT_SHIFT.bits(), 0x35),
        ',' => (0, 0x36),
        '<' => (Modifiers::LEFT_SHIFT.bits(), 0x36),
        '.' => (0, 0x37),
        '>' => (Modifiers::LEFT_SHIFT.bits(), 0x37),
        '/' => (0, 0x38),
        '?' => (Modifiers::LEFT_SHIFT.bits(), 0x38),
        '!' => (Modifiers::LEFT_SHIFT.bits(), 0x1e),
        '@' => (Modifiers::LEFT_SHIFT.bits(), 0x1f),
        '#' => (Modifiers::LEFT_SHIFT.bits(), 0x20),
        '$' => (Modifiers::LEFT_SHIFT.bits(), 0x21),
        '%' => (Modifiers::LEFT_SHIFT.bits(), 0x22),
        '^' => (Modifiers::LEFT_SHIFT.bits(), 0x23),
        '&' => (Modifiers::LEFT_SHIFT.bits(), 0x24),
        '*' => (Modifiers::LEFT_SHIFT.bits(), 0x25),
        '(' => (Modifiers::LEFT_SHIFT.bits(), 0x26),
        ')' => (Modifiers::LEFT_SHIFT.bits(), 0x27),
        _ => return None,
    };
    Some(key)
}

fn validate_descriptor(descriptor: &[u8]) -> UsbResult<()> {
    if descriptor.is_empty() {
        return Err(UsbError::InvalidInput("HID Descriptor 不能为空".into()));
    }

    let mut offset = 0;
    let mut collection_depth = 0_usize;
    let mut saw_application_collection = false;

    while offset < descriptor.len() {
        let prefix = descriptor[offset];
        if prefix == 0xfe {
            if offset + 2 >= descriptor.len() {
                return descriptor_error(offset, "长项目头不完整");
            }
            let length = descriptor[offset + 1] as usize;
            if offset + 3 + length > descriptor.len() {
                return descriptor_error(offset, "长项目越界");
            }
            offset += 3 + length;
            continue;
        }

        let size = match prefix & 0x03 {
            3 => 4,
            value => value as usize,
        };
        if offset + 1 + size > descriptor.len() {
            return descriptor_error(offset, "项目数据不完整");
        }

        let item_type = (prefix >> 2) & 0x03;
        let tag = (prefix >> 4) & 0x0f;
        if item_type == 0 {
            match tag {
                0x0a => {
                    if size != 1 {
                        return descriptor_error(offset, "Collection 项目长度错误");
                    }
                    if collection_depth == 0 && descriptor[offset + 1] == 1 {
                        saw_application_collection = true;
                    }
                    collection_depth += 1;
                }
                0x0c => {
                    if collection_depth == 0 {
                        return descriptor_error(offset, "存在多余的 End Collection");
                    }
                    collection_depth -= 1;
                }
                0x08 | 0x09 | 0x0b if collection_depth == 0 => {
                    return descriptor_error(offset, "主项目位于顶层集合之外");
                }
                _ => {}
            }
        }
        offset += 1 + size;
    }

    if !saw_application_collection {
        return Err(UsbError::InvalidInput(
            "HID Descriptor 缺少顶层 Application Collection".into(),
        ));
    }
    if collection_depth != 0 {
        return Err(UsbError::InvalidInput(format!(
            "HID Descriptor Collection 未闭合，剩余层级 {collection_depth}"
        )));
    }
    Ok(())
}

fn descriptor_error<T>(offset: usize, message: &str) -> UsbResult<T> {
    Err(UsbError::InvalidInput(format!(
        "HID Descriptor 偏移 {offset}：{message}"
    )))
}

fn ensure_function_directory(path: &Path) -> UsbResult<()> {
    if !path.exists() {
        fs::create_dir(path)?;
    }
    if path.is_dir() {
        Ok(())
    } else {
        Err(UsbError::InvalidInput(format!(
            "HID Function 路径不是目录：{}",
            path.display()
        )))
    }
}

fn write_attribute(path: &Path, value: &[u8]) -> UsbResult<()> {
    let mut file = OpenOptions::new().write(true).truncate(true).open(path)?;
    file.write_all(value)?;
    Ok(())
}

fn open_nonblocking(path: &Path) -> UsbResult<File> {
    let mut options = OpenOptions::new();
    options.write(true);

    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.custom_flags(libc::O_NONBLOCK);
    }

    Ok(options.open(path)?)
}

fn resolve_hid_endpoint_in(
    function_path: &Path,
    hid_class_root: &Path,
    device_root: &Path,
) -> UsbResult<PathBuf> {
    let function_device =
        fs::read_to_string(function_path.join("dev")).map(|value| value.trim().to_owned())?;
    if function_device.is_empty() {
        return Err(UsbError::Unavailable("HID Function 尚未获得设备号".into()));
    }

    for entry in fs::read_dir(hid_class_root)? {
        let entry = entry?;
        let class_device = fs::read_to_string(entry.path().join("dev"))
            .map(|value| value.trim().to_owned())
            .unwrap_or_default();
        if class_device != function_device {
            continue;
        }
        let endpoint = device_root.join(entry.file_name());
        if endpoint.exists() {
            return Ok(endpoint);
        }
    }

    Err(UsbError::Unavailable(format!(
        "未找到设备号 {function_device} 对应的 HID Gadget 端点"
    )))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_directory(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!(
            "hyperusb-hid-{name}-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        ))
    }

    #[test]
    fn report_keeps_key_pressed_until_release() {
        assert_eq!(
            KeyboardReport::new(0, [0x04]).as_bytes(),
            &[0, 0, 0x04, 0, 0, 0, 0, 0]
        );
        assert_eq!(KeyboardReport::released().as_bytes(), &[0; 8]);
    }

    #[test]
    fn report_preserves_modifier_bits() {
        assert_eq!(
            KeyboardReport::new(0x11, []).as_bytes(),
            &[0x11, 0, 0, 0, 0, 0, 0, 0]
        );
    }

    #[test]
    fn seventh_key_emits_error_rollover() {
        assert_eq!(
            KeyboardReport::new(0, [4, 5, 6, 7, 8, 9, 10]).as_bytes(),
            &[0, 0, 1, 1, 1, 1, 1, 1]
        );
    }

    #[test]
    fn text_encoding_emits_press_and_release() {
        let reports = encode_text("A").unwrap();
        assert_eq!(reports.len(), 2);
        assert_eq!(
            reports[0].as_bytes(),
            &[Modifiers::LEFT_SHIFT.bits(), 0, 4, 0, 0, 0, 0, 0]
        );
        assert_eq!(reports[1], KeyboardReport::released());
    }

    #[test]
    fn chord_encodes_alt_f4_as_a_single_report() {
        let chord = KeyChord::new(Modifiers::LEFT_ALT, [Key::F4]).unwrap();
        assert_eq!(
            chord.report().unwrap().as_bytes(),
            &[0x04, 0, 0x3d, 0, 0, 0, 0, 0]
        );
    }

    #[test]
    fn chord_combines_modifiers_without_using_key_slots() {
        let chord =
            KeyChord::new(Modifiers::LEFT_CTRL | Modifiers::LEFT_SHIFT, [Key::Escape]).unwrap();
        assert_eq!(
            chord.report().unwrap().as_bytes(),
            &[0x03, 0, 0x29, 0, 0, 0, 0, 0]
        );
    }

    #[test]
    fn keyboard_state_keeps_modifier_after_releasing_normal_key() {
        let mut state = KeyboardState::default();
        state.set_modifiers(Modifiers::LEFT_CTRL);
        state.press(Key::C).unwrap();
        assert_eq!(state.report().as_bytes(), &[0x01, 0, 0x06, 0, 0, 0, 0, 0]);
        assert!(state.release(Key::C));
        assert_eq!(state.report().as_bytes(), &[0x01, 0, 0, 0, 0, 0, 0, 0]);
    }

    #[test]
    fn chord_rejects_more_than_six_normal_keys() {
        assert!(KeyChord::new(
            Modifiers::NONE,
            [Key::A, Key::B, Key::C, Key::D, Key::E, Key::F, Key::G]
        )
        .is_err());
    }

    #[test]
    fn built_in_descriptor_is_valid() {
        UsbHid::default().validate().unwrap();
    }

    #[test]
    fn resolves_endpoint_by_device_number() {
        let root = test_directory("resolve");
        let function = root.join("function");
        let class = root.join("class/hidg0");
        let devices = root.join("dev");
        fs::create_dir_all(&function).unwrap();
        fs::create_dir_all(&class).unwrap();
        fs::create_dir_all(&devices).unwrap();
        fs::write(function.join("dev"), "240:0\n").unwrap();
        fs::write(class.join("dev"), "240:0\n").unwrap();
        fs::write(devices.join("hidg0"), []).unwrap();

        let endpoint = resolve_hid_endpoint_in(&function, &root.join("class"), &devices).unwrap();
        assert_eq!(endpoint, devices.join("hidg0"));
        fs::remove_dir_all(root).unwrap();
    }
}

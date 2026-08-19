//! NKRO（N-Key Rollover）键盘 Function。
//!
//! 它与现有 Boot Keyboard 使用两个独立的 HID interface：Boot 键盘保留 BIOS/PE 兼容性，
//! NKRO 键盘使用 Usage 位图表达同时按下的普通键，不受 6KRO 槽位限制。

use std::path::Path;
use std::thread;
use std::time::Duration;

use crate::usb_sub::usb_hid::{
    encode_text, HidReportWriter, Key, KeyChord, KeyboardReport, KeyboardState, Modifiers, UsbHid,
    NKRO_KEYBOARD_REPORT_LENGTH,
};
use crate::usb_sub::{UsbError, UsbResult};

const NKRO_MAX_USAGE: u8 = 0xdf;
const DEFAULT_KEY_HOLD: Duration = Duration::from_millis(5);

/// 普通键 Usage `0x00..=0xdf` 的 224 位位图，加上 modifier 与保留字节。
pub const NKRO_KEYBOARD_DESCRIPTOR: [u8; 43] = [
    0x05, 0x01, // Usage Page (Generic Desktop)
    0x09, 0x06, // Usage (Keyboard)
    0xa1, 0x01, // Collection (Application)
    0x05, 0x07, //   Usage Page (Keyboard)
    0x19, 0xe0, //   Usage Minimum (Left Control)
    0x29, 0xe7, //   Usage Maximum (Right GUI)
    0x15, 0x00, //   Logical Minimum (0)
    0x25, 0x01, //   Logical Maximum (1)
    0x75, 0x01, //   Report Size (1)
    0x95, 0x08, //   Report Count (8): modifier bitmap
    0x81, 0x02, //   Input (Data, Variable, Absolute)
    0x95, 0x08, //   Report Count (8): reserved byte
    0x81, 0x03, //   Input (Constant, Variable, Absolute)
    0x19, 0x00, //   Usage Minimum (0)
    0x2a, 0xdf, 0x00, // Usage Maximum (223)
    0x15, 0x00, //   Logical Minimum (0)
    0x25, 0x01, //   Logical Maximum (1)
    0x75, 0x01, //   Report Size (1)
    0x96, 0xe0, 0x00, // Report Count (224): one bit per Usage
    0x81, 0x02, //   Input (Data, Variable, Absolute)
    0xc0, // End Collection
];

/// 返回 NKRO Function 的 ConfigFS 配置。
pub fn nkro_hid() -> UsbHid {
    UsbHid {
        descriptor: NKRO_KEYBOARD_DESCRIPTOR.to_vec(),
        report_length: NKRO_KEYBOARD_REPORT_LENGTH as u16,
        protocol: 1,
        // NKRO 不是 USB HID Boot Protocol；Host 应使用完整 Report Descriptor。
        subclass: 0,
    }
}

/// 一个完整的 NKRO 键盘 Report。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NkroKeyboardReport([u8; NKRO_KEYBOARD_REPORT_LENGTH]);

impl NkroKeyboardReport {
    pub fn new(modifiers: Modifiers, usages: impl IntoIterator<Item = u8>) -> UsbResult<Self> {
        let mut report = Self::released();
        report.0[0] = modifiers.bits();
        for usage in usages {
            report.press_usage(usage)?;
        }
        Ok(report)
    }

    /// 将已有 Boot Report 转为具有相同按键状态的 NKRO Report。
    pub fn from_boot_report(report: KeyboardReport) -> Self {
        let bytes = report.as_bytes();
        let mut nkro = Self::released();
        nkro.0[0] = bytes[0];
        for usage in bytes[2..].iter().copied().filter(|usage| *usage != 0) {
            // Boot usages 均在 NKRO 位图范围内。
            nkro.press_usage(usage)
                .expect("Boot Keyboard usage must fit NKRO bitmap");
        }
        nkro
    }

    pub const fn released() -> Self {
        Self([0; NKRO_KEYBOARD_REPORT_LENGTH])
    }

    pub const fn as_bytes(&self) -> &[u8; NKRO_KEYBOARD_REPORT_LENGTH] {
        &self.0
    }

    fn press_usage(&mut self, usage: u8) -> UsbResult<()> {
        let (byte, mask) = bit_position(usage)?;
        self.0[byte] |= mask;
        Ok(())
    }
}

/// 可保持任意数量（最多 224 个 Usage）的 NKRO 普通键状态。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NkroKeyboardState {
    modifiers: Modifiers,
    usages: [u8; NKRO_KEYBOARD_REPORT_LENGTH - 2],
}

impl Default for NkroKeyboardState {
    fn default() -> Self {
        Self {
            modifiers: Modifiers::NONE,
            usages: [0; NKRO_KEYBOARD_REPORT_LENGTH - 2],
        }
    }
}

impl NkroKeyboardState {
    pub fn modifiers(&self) -> Modifiers {
        self.modifiers
    }

    pub fn set_modifiers(&mut self, modifiers: Modifiers) {
        self.modifiers = modifiers;
    }

    pub fn press(&mut self, key: Key) -> UsbResult<()> {
        self.press_usage(key.usage())
    }

    pub fn press_usage(&mut self, usage: u8) -> UsbResult<()> {
        let (byte, mask) = bit_position(usage)?;
        self.usages[byte - 2] |= mask;
        Ok(())
    }

    pub fn release(&mut self, key: Key) -> UsbResult<()> {
        self.release_usage(key.usage())
    }

    pub fn release_usage(&mut self, usage: u8) -> UsbResult<()> {
        let (byte, mask) = bit_position(usage)?;
        self.usages[byte - 2] &= !mask;
        Ok(())
    }

    pub fn release_all(&mut self) {
        self.modifiers = Modifiers::NONE;
        self.usages.fill(0);
    }

    pub fn report(&self) -> NkroKeyboardReport {
        let mut report = NkroKeyboardReport::released();
        report.0[0] = self.modifiers.bits();
        report.0[2..].copy_from_slice(&self.usages);
        report
    }
}

/// NKRO 键盘的持久端点 writer。
pub struct NkroKeyboardWriter {
    inner: HidReportWriter,
}

impl NkroKeyboardWriter {
    pub fn open(
        endpoint_path: impl Into<std::path::PathBuf>,
        udc_state_path: impl Into<std::path::PathBuf>,
    ) -> UsbResult<Self> {
        Ok(Self {
            inner: HidReportWriter::open(
                endpoint_path,
                udc_state_path,
                NKRO_KEYBOARD_REPORT_LENGTH,
            )?,
        })
    }

    pub fn set_retry_timeout(&mut self, timeout: Duration) {
        self.inner.set_retry_timeout(timeout);
    }

    pub fn write_report(&mut self, report: NkroKeyboardReport) -> UsbResult<()> {
        self.inner.write_report(report.as_bytes())
    }

    pub fn write_text(&mut self, text: &str, interval: Duration) -> UsbResult<()> {
        let reports = encode_text(text)?;
        let report_count = reports.len();
        for (index, report) in reports.into_iter().enumerate() {
            self.write_report(NkroKeyboardReport::from_boot_report(report))?;
            if index + 1 < report_count && !interval.is_zero() {
                thread::sleep(interval);
            }
        }
        Ok(())
    }

    pub fn key_down(&mut self, key: Key, modifiers: Modifiers) -> UsbResult<()> {
        self.write_report(NkroKeyboardReport::new(modifiers, [key.usage()])?)
    }

    pub fn key_up_all(&mut self) -> UsbResult<()> {
        self.write_report(NkroKeyboardReport::released())
    }

    pub fn tap(&mut self, key: Key, modifiers: Modifiers) -> UsbResult<()> {
        self.key_down(key, modifiers)?;
        thread::sleep(DEFAULT_KEY_HOLD);
        self.key_up_all()
    }

    pub fn send_chord(&mut self, chord: &KeyChord) -> UsbResult<()> {
        chord.validate()?;
        self.write_report(NkroKeyboardReport::new(
            chord.modifiers,
            chord.keys.iter().copied().map(Key::usage),
        )?)?;
        thread::sleep(DEFAULT_KEY_HOLD);
        self.key_up_all()
    }

    pub fn write_state(&mut self, state: &NkroKeyboardState) -> UsbResult<()> {
        self.write_report(state.report())
    }

    /// 将 Boot 状态投影为 NKRO Report，便于上层逐步迁移。
    pub fn write_boot_state(&mut self, state: &KeyboardState) -> UsbResult<()> {
        self.write_report(NkroKeyboardReport::from_boot_report(state.report()))
    }

    pub fn endpoint_path(&self) -> &Path {
        self.inner.endpoint_path()
    }
}

fn bit_position(usage: u8) -> UsbResult<(usize, u8)> {
    if usage == 0 || usage > NKRO_MAX_USAGE {
        return Err(UsbError::InvalidInput(format!(
            "NKRO 仅支持普通 Usage 0x01..=0x{NKRO_MAX_USAGE:02x}，实际为 0x{usage:02x}"
        )));
    }
    Ok((2 + usize::from(usage / 8), 1 << (usage % 8)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn descriptor_and_report_length_are_valid() {
        nkro_hid().validate().unwrap();
        assert_eq!(NKRO_KEYBOARD_DESCRIPTOR.len(), 43);
    }

    #[test]
    fn nkro_state_supports_more_than_six_keys() {
        let mut state = NkroKeyboardState::default();
        for key in [Key::A, Key::B, Key::C, Key::D, Key::E, Key::F, Key::G] {
            state.press(key).unwrap();
        }
        let report = state.report();
        assert_eq!(report.as_bytes()[2], 0b1111_0000);
        assert_eq!(report.as_bytes()[3], 0b0000_0111);
    }

    #[test]
    fn nkro_report_preserves_modifier_and_usage() {
        let report = NkroKeyboardReport::new(Modifiers::LEFT_ALT, [Key::F4.usage()]).unwrap();
        assert_eq!(report.as_bytes()[0], 0x04);
        assert_eq!(report.as_bytes()[9], 0b0010_0000);
    }

    #[test]
    fn nkro_rejects_reserved_or_out_of_range_usage() {
        assert!(NkroKeyboardReport::new(Modifiers::NONE, [0]).is_err());
        assert!(NkroKeyboardReport::new(Modifiers::NONE, [0xe0]).is_err());
    }
}

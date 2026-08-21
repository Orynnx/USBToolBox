//! Unix Socket 的稳定文本协议。

use std::fmt;
use std::path::PathBuf;

use crate::usb_sub::{Key, KeyChord, Modifiers};

pub const MAX_COMMAND_BYTES: usize = 8 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ApiErrorCode {
    InvalidCommand,
    InvalidConfigPath,
    ConfigNotFound,
    InvalidConfig,
    InvalidVid,
    InvalidPid,
    InvalidDeviceVersion,
    ImageNotFound,
    ImageNotFile,
    DuplicateBackingFile,
    NotStarted,
    BootDisabled,
    ApplyFailed,
    RestoreFailed,
    InternalError,
}

impl ApiErrorCode {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::InvalidCommand => "invalid_command",
            Self::InvalidConfigPath => "invalid_config_path",
            Self::ConfigNotFound => "config_not_found",
            Self::InvalidConfig => "invalid_config",
            Self::InvalidVid => "invalid_vid",
            Self::InvalidPid => "invalid_pid",
            Self::InvalidDeviceVersion => "invalid_device_version",
            Self::ImageNotFound => "image_not_found",
            Self::ImageNotFile => "image_not_file",
            Self::DuplicateBackingFile => "duplicate_backing_file",
            Self::NotStarted => "not_started",
            Self::BootDisabled => "boot_disabled",
            Self::ApplyFailed => "apply_failed",
            Self::RestoreFailed => "restore_failed",
            Self::InternalError => "internal_error",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ApiError {
    pub code: ApiErrorCode,
    pub detail: String,
}

impl ApiError {
    pub fn new(code: ApiErrorCode, detail: impl Into<String>) -> Self {
        Self {
            code,
            detail: detail.into(),
        }
    }
}

impl fmt::Display for ApiError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{}: {}", self.code.as_str(), self.detail)
    }
}

impl std::error::Error for ApiError {}

pub type ApiResult<T> = Result<T, ApiError>;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ApiRequest {
    Set(PathBuf),
    Ping,
    Status,
    BootKey(KeyChord),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ApiResponse {
    Ok,
    Status(String),
    Error(ApiErrorCode),
}

impl ApiResponse {
    pub fn encode(self) -> String {
        match self {
            Self::Ok => "OK\n".into(),
            Self::Status(payload) => format!("OK {payload}\n"),
            Self::Error(code) => format!("ERR {}\n", code.as_str()),
        }
    }
}

pub fn parse_request(line: &str) -> ApiResult<ApiRequest> {
    let line = line.trim_matches(|character: char| character.is_ascii_whitespace());
    let command_end = line
        .bytes()
        .position(|byte| byte.is_ascii_whitespace())
        .unwrap_or(line.len());
    let command = &line[..command_end];
    let arguments =
        line[command_end..].trim_matches(|character: char| character.is_ascii_whitespace());

    if command.eq_ignore_ascii_case("SET") {
        let path = arguments;
        if path.is_empty() || !path.starts_with('/') {
            return Err(ApiError::new(
                ApiErrorCode::InvalidConfigPath,
                "SET 需要非空绝对配置路径",
            ));
        }
        return Ok(ApiRequest::Set(PathBuf::from(path)));
    }
    if command.eq_ignore_ascii_case("PING") && arguments.is_empty() {
        return Ok(ApiRequest::Ping);
    }
    if command.eq_ignore_ascii_case("STATUS") && arguments.is_empty() {
        return Ok(ApiRequest::Status);
    }
    if command.eq_ignore_ascii_case("BOOT_KEY") {
        return parse_boot_key(arguments).map(ApiRequest::BootKey);
    }
    Err(ApiError::new(ApiErrorCode::InvalidCommand, "未知命令"))
}

fn parse_boot_key(arguments: &str) -> ApiResult<KeyChord> {
    let tokens = arguments.split_ascii_whitespace().collect::<Vec<_>>();
    if tokens.is_empty() {
        return Err(ApiError::new(
            ApiErrorCode::InvalidCommand,
            "BOOT_KEY 不能为空",
        ));
    }
    let mut modifiers = Modifiers::NONE;
    let mut key = None;
    for name in tokens {
        if let Some(modifier) = parse_modifier(name) {
            modifiers |= modifier;
        } else if let Some(normal_key) = parse_key(name) {
            if key.replace(normal_key).is_some() {
                return Err(ApiError::new(
                    ApiErrorCode::InvalidCommand,
                    "BOOT_KEY 只能包含最多一个普通按键",
                ));
            }
        } else {
            return Err(ApiError::new(
                ApiErrorCode::InvalidCommand,
                format!("不支持的按键或修饰键：{name}"),
            ));
        }
    }
    if modifiers == Modifiers::NONE && key.is_none() {
        return Err(ApiError::new(
            ApiErrorCode::InvalidCommand,
            "BOOT_KEY 必须至少包含一个修饰键或普通按键",
        ));
    }
    let keys = key.into_iter().collect::<Vec<_>>();
    KeyChord::new(modifiers, keys)
        .map_err(|error| ApiError::new(ApiErrorCode::InvalidCommand, error.to_string()))
}

fn parse_modifier(name: &str) -> Option<Modifiers> {
    if name.eq_ignore_ascii_case("CTRL") || name.eq_ignore_ascii_case("LCTRL") {
        Some(Modifiers::LEFT_CTRL)
    } else if name.eq_ignore_ascii_case("SHIFT") || name.eq_ignore_ascii_case("LSHIFT") {
        Some(Modifiers::LEFT_SHIFT)
    } else if name.eq_ignore_ascii_case("ALT") || name.eq_ignore_ascii_case("LALT") {
        Some(Modifiers::LEFT_ALT)
    } else if name.eq_ignore_ascii_case("GUI") || name.eq_ignore_ascii_case("LGUI") {
        Some(Modifiers::LEFT_GUI)
    } else if name.eq_ignore_ascii_case("RCTRL") {
        Some(Modifiers::RIGHT_CTRL)
    } else if name.eq_ignore_ascii_case("RSHIFT") {
        Some(Modifiers::RIGHT_SHIFT)
    } else if name.eq_ignore_ascii_case("RALT") {
        Some(Modifiers::RIGHT_ALT)
    } else if name.eq_ignore_ascii_case("RGUI") {
        Some(Modifiers::RIGHT_GUI)
    } else {
        None
    }
}

fn parse_key(name: &str) -> Option<Key> {
    let name = name.to_ascii_uppercase();
    let key = match name.as_str() {
        "A" => Key::A,
        "B" => Key::B,
        "C" => Key::C,
        "D" => Key::D,
        "E" => Key::E,
        "F" => Key::F,
        "G" => Key::G,
        "H" => Key::H,
        "I" => Key::I,
        "J" => Key::J,
        "K" => Key::K,
        "L" => Key::L,
        "M" => Key::M,
        "N" => Key::N,
        "O" => Key::O,
        "P" => Key::P,
        "Q" => Key::Q,
        "R" => Key::R,
        "S" => Key::S,
        "T" => Key::T,
        "U" => Key::U,
        "V" => Key::V,
        "W" => Key::W,
        "X" => Key::X,
        "Y" => Key::Y,
        "Z" => Key::Z,
        "1" => Key::Digit1,
        "2" => Key::Digit2,
        "3" => Key::Digit3,
        "4" => Key::Digit4,
        "5" => Key::Digit5,
        "6" => Key::Digit6,
        "7" => Key::Digit7,
        "8" => Key::Digit8,
        "9" => Key::Digit9,
        "0" => Key::Digit0,
        "ENTER" => Key::Enter,
        "ESC" | "ESCAPE" => Key::Escape,
        "BACKSPACE" => Key::Backspace,
        "TAB" => Key::Tab,
        "SPACE" => Key::Space,
        "MINUS" | "-" => Key::Minus,
        "EQUAL" | "=" => Key::Equal,
        "LEFTBRACKET" | "[" => Key::LeftBracket,
        "RIGHTBRACKET" | "]" => Key::RightBracket,
        "BACKSLASH" | "\\" => Key::Backslash,
        "SEMICOLON" | ";" => Key::Semicolon,
        "QUOTE" | "'" => Key::Quote,
        "GRAVE" | "`" => Key::Grave,
        "COMMA" | "," => Key::Comma,
        "DOT" | "." => Key::Dot,
        "SLASH" | "/" => Key::Slash,
        "CAPSLOCK" | "CAPS" => Key::CapsLock,
        "PRINTSCREEN" | "PRTSC" => Key::PrintScreen,
        "SCROLLLOCK" | "SCRLK" => Key::ScrollLock,
        "PAUSE" => Key::Pause,
        "INSERT" | "INS" => Key::Insert,
        "HOME" => Key::Home,
        "PAGEUP" | "PGUP" => Key::PageUp,
        "DELETE" | "DEL" => Key::Delete,
        "END" => Key::End,
        "PAGEDOWN" | "PGDN" => Key::PageDown,
        "RIGHT" => Key::ArrowRight,
        "LEFT" => Key::ArrowLeft,
        "DOWN" => Key::ArrowDown,
        "UP" => Key::ArrowUp,
        "MENU" | "APPLICATION" | "APP" => Key::Menu,
        "F1" => Key::F1,
        "F2" => Key::F2,
        "F3" => Key::F3,
        "F4" => Key::F4,
        "F5" => Key::F5,
        "F6" => Key::F6,
        "F7" => Key::F7,
        "F8" => Key::F8,
        "F9" => Key::F9,
        "F10" => Key::F10,
        "F11" => Key::F11,
        "F12" => Key::F12,
        _ => return None,
    };
    Some(key)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn set_preserves_spaces_exactly() {
        assert_eq!(
            parse_request("SET /data/My USB/config.json").unwrap(),
            ApiRequest::Set(PathBuf::from("/data/My USB/config.json"))
        );
        assert_eq!(
            parse_request("  set\t /data/config.json  ").unwrap(),
            ApiRequest::Set(PathBuf::from("/data/config.json"))
        );
    }

    #[test]
    fn boot_key_maps_generic_modifiers_left() {
        let ApiRequest::BootKey(chord) = parse_request("BOOT_KEY CTRL SHIFT ESC").unwrap() else {
            panic!("expected boot key");
        };
        assert_eq!(
            chord.modifiers,
            Modifiers::LEFT_CTRL | Modifiers::LEFT_SHIFT
        );
        assert_eq!(chord.keys, vec![Key::Escape]);
    }

    #[test]
    fn boot_key_is_case_and_whitespace_insensitive_and_deduplicates_modifiers() {
        let ApiRequest::BootKey(chord) =
            parse_request("  boot_key\tctrl  LCTRL shift Shift a  ").unwrap()
        else {
            panic!("expected boot key");
        };
        assert_eq!(
            chord.modifiers,
            Modifiers::LEFT_CTRL | Modifiers::LEFT_SHIFT
        );
        assert_eq!(chord.keys, vec![Key::A]);
    }

    #[test]
    fn boot_key_parses_punctuation_and_function_keys() {
        let ApiRequest::BootKey(chord) = parse_request("BOOT_KEY SHIFT MINUS").unwrap() else {
            panic!("expected boot key");
        };
        assert_eq!(chord.modifiers, Modifiers::LEFT_SHIFT);
        assert_eq!(chord.keys, vec![Key::Minus]);

        let ApiRequest::BootKey(chord2) = parse_request("BOOT_KEY CTRL ALT DEL").unwrap() else {
            panic!("expected boot key");
        };
        assert_eq!(
            chord2.modifiers,
            Modifiers::LEFT_CTRL | Modifiers::LEFT_ALT
        );
        assert_eq!(chord2.keys, vec![Key::Delete]);
    }

    #[test]
    fn boot_key_supports_modifier_only_and_single_key() {
        for (cmd, expected_mods) in [
            ("BOOT_KEY SHIFT", Modifiers::LEFT_SHIFT),
            ("BOOT_KEY RSHIFT", Modifiers::RIGHT_SHIFT),
            ("BOOT_KEY CTRL", Modifiers::LEFT_CTRL),
            ("BOOT_KEY ALT", Modifiers::LEFT_ALT),
            ("BOOT_KEY GUI", Modifiers::LEFT_GUI),
            (
                "BOOT_KEY LCTRL RALT",
                Modifiers::LEFT_CTRL | Modifiers::RIGHT_ALT,
            ),
        ] {
            let ApiRequest::BootKey(chord) = parse_request(cmd).unwrap() else {
                panic!("expected boot key");
            };
            assert_eq!(chord.modifiers, expected_mods);
            assert!(chord.keys.is_empty());
        }

        let ApiRequest::BootKey(chord) = parse_request("BOOT_KEY A").unwrap() else {
            panic!("expected boot key");
        };
        assert_eq!(chord.modifiers, Modifiers::NONE);
        assert_eq!(chord.keys, vec![Key::A]);

        let ApiRequest::BootKey(chord) = parse_request("BOOT_KEY SHIFT A").unwrap() else {
            panic!("expected boot key");
        };
        assert_eq!(chord.modifiers, Modifiers::LEFT_SHIFT);
        assert_eq!(chord.keys, vec![Key::A]);
    }

    #[test]
    fn boot_key_rejects_empty_multiple_keys_or_unknown_names() {
        for command in [
            "BOOT_KEY",
            "BOOT_KEY    ",
            "BOOT_KEY A B",
            "BOOT_KEY NONE A",
        ] {
            assert_eq!(
                parse_request(command).unwrap_err().code,
                ApiErrorCode::InvalidCommand
            );
        }
    }

    #[test]
    fn stop_is_not_a_public_command() {
        assert_eq!(
            parse_request("STOP").unwrap_err().code,
            ApiErrorCode::InvalidCommand
        );
    }

    #[test]
    fn ping_and_status_have_no_arguments() {
        assert_eq!(parse_request("PING").unwrap(), ApiRequest::Ping);
        assert_eq!(parse_request("status").unwrap(), ApiRequest::Status);
        assert_eq!(
            parse_request("PING now").unwrap_err().code,
            ApiErrorCode::InvalidCommand
        );
    }

    #[test]
    fn right_modifiers_must_be_explicit() {
        let ApiRequest::BootKey(left) = parse_request("BOOT_KEY CTRL A").unwrap() else {
            panic!("expected boot key");
        };
        let ApiRequest::BootKey(right) = parse_request("BOOT_KEY RCTRL A").unwrap() else {
            panic!("expected boot key");
        };
        assert_eq!(left.modifiers, Modifiers::LEFT_CTRL);
        assert_eq!(right.modifiers, Modifiers::RIGHT_CTRL);
    }
}

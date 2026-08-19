//! 开发者交互式 Root CLI。
//!
//! HyperUSB 不启动 daemon：一次 shell 进程只持有一个 [`UsbSession`]，因此 HID 写入、
//! 存储介质切换和停止恢复都天然处在同一个对象生命周期中。

use std::env;
use std::io::{self, BufRead, Write};
use std::time::Duration;

use log::{debug, info};

use crate::info;
use crate::usb_sub::{
    HidKeyboardWriter, Key, KeyChord, Modifiers, NkroKeyboardWriter, StorageLun, UsbProfile,
    UsbRuntimeConfig, UsbRuntimeState, UsbSession,
};

const PROMPT: &str = "hyperusb> ";

pub fn run() -> Result<(), String> {
    let arguments = env::args().skip(1).collect::<Vec<_>>();
    debug!("Received command: {arguments:?}");
    match arguments.as_slice() {
        [] => run_shell(),
        [command] if command == "shell" => run_shell(),
        [command] if command == "info" || command == "--info" => info::print(),
        [command] if command == "restore" => restore_persisted(),
        [command] if matches!(command.as_str(), "help" | "--help" | "-h") => {
            print_usage();
            Ok(())
        }
        _ => {
            print_usage();
            Err(format!("不支持的命令：{}", arguments.join(" ")))
        }
    }
}

fn print_usage() {
    println!(
        "HyperUSB Core\n\n\
         用法:\n\
           hyperusbd [shell]             进入交互式 USB 会话（默认）\n\
           hyperusbd info | --info        查看设备与 Core 信息\n\
           hyperusbd restore              恢复异常退出前的 Android USB\n\n\
         在 shell 内输入 help 查看 start、hid、storage、stop 等命令。"
    );
}

fn restore_persisted() -> Result<(), String> {
    UsbSession::restore_persisted(UsbRuntimeConfig::default())
        .map_err(|error| error.to_string())?;
    println!("Android USB 已恢复，恢复状态文件已清除。");
    Ok(())
}

fn run_shell() -> Result<(), String> {
    info!("Starting interactive HyperUSB shell");
    println!("HyperUSB Core {}", env!("CARGO_PKG_VERSION"));
    println!("输入 help 查看命令。USB 会话仅在此进程存活期间保持。\n");

    let stdin = io::stdin();
    let mut output = io::stdout();
    let mut session = None;
    loop {
        write!(output, "{PROMPT}").map_err(|error| error.to_string())?;
        output.flush().map_err(|error| error.to_string())?;
        let mut line = String::new();
        if stdin
            .lock()
            .read_line(&mut line)
            .map_err(|error| error.to_string())?
            == 0
        {
            println!();
            return stop_active_session(&mut session);
        }
        let command = match parse_command_line(line.trim()) {
            Ok(command) => command,
            Err(error) => {
                eprintln!("错误：{error}");
                continue;
            }
        };
        if command.is_empty() {
            continue;
        }
        match execute_shell_command(&command, &mut session) {
            Ok(ShellControl::Continue) => {}
            Ok(ShellControl::Exit) => return stop_active_session(&mut session),
            Err(error) => eprintln!("错误：{error}"),
        }
    }
}

enum ShellControl {
    Continue,
    Exit,
}

struct InteractiveSession {
    usb: UsbSession,
    keyboard: Option<InteractiveKeyboardWriter>,
}

/// Shell 在一个会话中只向一把键盘写入，避免 Boot 与 NKRO 同时报出相同按键。
enum InteractiveKeyboardWriter {
    Boot(HidKeyboardWriter),
    Nkro(NkroKeyboardWriter),
}

impl InteractiveKeyboardWriter {
    fn write_text(&mut self, text: &str, interval: Duration) -> Result<(), String> {
        match self {
            Self::Boot(writer) => writer.write_text(text, interval),
            Self::Nkro(writer) => writer.write_text(text, interval),
        }
        .map_err(|error| error.to_string())
    }

    fn key_down(&mut self, key: Key, modifiers: Modifiers) -> Result<(), String> {
        match self {
            Self::Boot(writer) => writer.key_down(key, modifiers),
            Self::Nkro(writer) => writer.key_down(key, modifiers),
        }
        .map_err(|error| error.to_string())
    }

    fn key_up_all(&mut self) -> Result<(), String> {
        match self {
            Self::Boot(writer) => writer.key_up_all(),
            Self::Nkro(writer) => writer.key_up_all(),
        }
        .map_err(|error| error.to_string())
    }

    fn send_chord(&mut self, chord: &KeyChord) -> Result<(), String> {
        match self {
            Self::Boot(writer) => writer.send_chord(chord),
            Self::Nkro(writer) => writer.send_chord(chord),
        }
        .map_err(|error| error.to_string())
    }
}

impl InteractiveSession {
    fn new(usb: UsbSession) -> Self {
        Self {
            usb,
            keyboard: None,
        }
    }

    fn keyboard_mut(&mut self) -> Result<&mut InteractiveKeyboardWriter, String> {
        if self.keyboard.is_none() {
            self.keyboard = Some(if self.usb.profile().nkro_keyboard_enabled {
                InteractiveKeyboardWriter::Nkro(
                    self.usb
                        .open_nkro_keyboard()
                        .map_err(|error| error.to_string())?,
                )
            } else {
                InteractiveKeyboardWriter::Boot(
                    self.usb
                        .open_keyboard()
                        .map_err(|error| error.to_string())?,
                )
            });
        }
        Ok(self
            .keyboard
            .as_mut()
            .expect("keyboard writer was initialized"))
    }

    fn reconfigure(&mut self, profile: UsbProfile) -> Result<(), String> {
        // `/dev/hidg*` 属于旧 Function；重配前关闭 writer，Drop 会尽力发送 release。
        self.keyboard = None;
        self.usb
            .reconfigure(profile)
            .map_err(|error| error.to_string())
    }

    fn stop(mut self) -> Result<(), String> {
        self.keyboard = None;
        self.usb.stop().map_err(|error| error.to_string())
    }
}

fn execute_shell_command(
    command: &[String],
    session: &mut Option<InteractiveSession>,
) -> Result<ShellControl, String> {
    match command[0].as_str() {
        "help" => {
            print_shell_help();
            Ok(ShellControl::Continue)
        }
        "info" => {
            info::print()?;
            Ok(ShellControl::Continue)
        }
        "status" => {
            print_status(session.as_ref());
            Ok(ShellControl::Continue)
        }
        "start" => {
            if session.is_some() {
                return Err("已有活动 USB 会话；请先执行 stop。".into());
            }
            let profile = parse_profile(&command[1..])?;
            let usb = UsbSession::start(UsbRuntimeConfig::default(), profile)
                .map_err(|error| error.to_string())?;
            println!("UDC 已接管：{}", usb.udc());
            *session = Some(InteractiveSession::new(usb));
            print_status(session.as_ref());
            Ok(ShellControl::Continue)
        }
        "stop" => {
            stop_active_session(session)?;
            println!("Android USB 已恢复。");
            Ok(ShellControl::Continue)
        }
        "restore" => {
            if session.is_some() {
                return Err("请先 stop 当前会话；不能在活动会话中执行 restore。".into());
            }
            restore_persisted()?;
            Ok(ShellControl::Continue)
        }
        "hid" => execute_hid_command(&command[1..], session).map(|()| ShellControl::Continue),
        "storage" => {
            execute_storage_command(&command[1..], session).map(|()| ShellControl::Continue)
        }
        "exit" | "quit" => Ok(ShellControl::Exit),
        other => Err(format!("未知命令：{other}；输入 help 查看用法。")),
    }
}

fn print_shell_help() {
    println!(
        "命令:\n\
           start [--hid] [--nkro] [--storage <image>]... [--cdrom <iso>]...\n\
           status\n\
           hid type <ASCII text> | hid key <name> | hid chord <modifier/key>... | hid release\n\
           storage list | storage attach <lun> <image> | storage eject <lun>\n\
           stop\n\
           restore       # 仅在没有活动会话时，用于异常退出后的救援\n\
           exit\n\n\
         示例：hid chord ALT F4、hid chord CTRL SHIFT ESC、hid chord GUI R。\n\
         键名支持 ENTER、ESC、TAB、SPACE、BACKSPACE、DELETE、方向键、HOME、END、\n\
         PAGEUP、PAGEDOWN、INSERT、F1..F12、A..Z、0..9。--nkro 会额外创建 NKRO 键盘，\n\
         且 shell 的 hid 命令会优先写入它。路径或文本包含空格时请使用引号。"
    );
}

fn parse_profile(arguments: &[String]) -> Result<UsbProfile, String> {
    let mut profile = UsbProfile::default();
    let mut index = 0;
    while index < arguments.len() {
        match arguments[index].as_str() {
            "--hid" => profile.keyboard_enabled = true,
            "--nkro" => profile.nkro_keyboard_enabled = true,
            "--storage" => {
                index += 1;
                let path = arguments.get(index).ok_or("--storage 需要镜像路径")?;
                profile.storage_luns.push(StorageLun::disk(path));
            }
            "--cdrom" => {
                index += 1;
                let path = arguments.get(index).ok_or("--cdrom 需要 ISO 路径")?;
                profile.storage_luns.push(StorageLun::cdrom(path));
            }
            other => return Err(format!("start 不支持参数：{other}")),
        }
        index += 1;
    }
    profile.validate().map_err(|error| error.to_string())?;
    Ok(profile)
}

fn print_status(session: Option<&InteractiveSession>) {
    let Some(session) = session else {
        println!("状态：未启动");
        return;
    };
    match session.usb.state() {
        UsbRuntimeState::Active {
            gadget,
            udc,
            keyboard_enabled,
            nkro_keyboard_enabled,
            storage_count,
        } => println!(
            "状态：运行中\nGadget：{gadget}\nUDC：{udc}\nBoot 键盘：{}\nNKRO 键盘：{}\n存储 LUN：{storage_count}",
            if *keyboard_enabled {
                "启用"
            } else {
                "未启用"
            },
            if *nkro_keyboard_enabled {
                "启用"
            } else {
                "未启用"
            }
        ),
        UsbRuntimeState::Stopped => println!("状态：已停止"),
    }
}

fn stop_active_session(session: &mut Option<InteractiveSession>) -> Result<(), String> {
    match session.take() {
        Some(active) => active.stop(),
        None => Ok(()),
    }
}

fn active_session(
    session: &mut Option<InteractiveSession>,
) -> Result<&mut InteractiveSession, String> {
    session
        .as_mut()
        .ok_or_else(|| "没有活动 USB 会话；请先执行 start。".into())
}

fn execute_hid_command(
    arguments: &[String],
    session: &mut Option<InteractiveSession>,
) -> Result<(), String> {
    let (operation, rest) = arguments.split_first().ok_or(
        "用法：hid type <text> | hid key <name> | hid chord <modifier/key>... | hid release",
    )?;
    let keyboard = active_session(session)?.keyboard_mut()?;
    match operation.as_str() {
        "type" if !rest.is_empty() => keyboard
            .write_text(&rest.join(" "), Duration::from_millis(5))
            .map_err(|error| error.to_string()),
        "key" if rest.len() == 1 => keyboard
            .key_down(key_from_name(&rest[0])?, Modifiers::NONE)
            .map_err(|error| error.to_string()),
        "release" if rest.is_empty() => keyboard.key_up_all().map_err(|error| error.to_string()),
        "chord" if !rest.is_empty() => keyboard
            .send_chord(&chord_from_names(rest)?)
            .map_err(|error| error.to_string()),
        _ => Err(
            "用法：hid type <text> | hid key <name> | hid chord <modifier/key>... | hid release"
                .into(),
        ),
    }
}

fn execute_storage_command(
    arguments: &[String],
    session: &mut Option<InteractiveSession>,
) -> Result<(), String> {
    let (operation, rest) = arguments
        .split_first()
        .ok_or("用法：storage list | storage attach <lun> <image> | storage eject <lun>")?;
    match operation.as_str() {
        "list" if rest.is_empty() => {
            for (index, lun) in active_session(session)?
                .usb
                .profile()
                .storage_luns
                .iter()
                .enumerate()
            {
                let kind = if lun.cdrom { "CD-ROM" } else { "Disk" };
                let medium = if lun.ejected {
                    "已弹出".to_owned()
                } else {
                    lun.image
                        .as_ref()
                        .map(|path| path.display().to_string())
                        .unwrap_or_else(|| "无介质".into())
                };
                println!("LUN {index}: {kind}, {medium}");
            }
            Ok(())
        }
        "eject" if rest.len() == 1 => {
            let index = parse_lun_index(&rest[0])?;
            let mut profile = active_session(session)?.usb.profile().clone();
            profile
                .storage_luns
                .get_mut(index)
                .ok_or_else(|| format!("不存在 LUN {index}"))?
                .eject();
            reconfigure_session(session, profile)?;
            println!("LUN {index} 已弹出。");
            Ok(())
        }
        "attach" if rest.len() == 2 => {
            let index = parse_lun_index(&rest[0])?;
            let mut profile = active_session(session)?.usb.profile().clone();
            profile
                .storage_luns
                .get_mut(index)
                .ok_or_else(|| format!("不存在 LUN {index}"))?
                .mount(&rest[1]);
            reconfigure_session(session, profile)?;
            println!("镜像已挂载到 LUN {index}。");
            Ok(())
        }
        _ => Err("用法：storage list | storage attach <lun> <image> | storage eject <lun>".into()),
    }
}

fn reconfigure_session(
    session: &mut Option<InteractiveSession>,
    profile: UsbProfile,
) -> Result<(), String> {
    let result = active_session(session)?.reconfigure(profile);
    let stopped = session
        .as_ref()
        .is_some_and(|active| matches!(active.usb.state(), UsbRuntimeState::Stopped));
    if stopped {
        // 底层激活失败时 UsbSession 已 stop/restore；移除对象以免 shell 误判状态。输入
        // 参数校验失败不会改变状态，因此保留原会话供用户修正命令后继续使用。
        let _ = session.take();
    }
    result
}

fn parse_lun_index(value: &str) -> Result<usize, String> {
    value
        .parse::<usize>()
        .map_err(|_| format!("LUN 索引必须是非负整数：{value}"))
}

fn chord_from_names(values: &[String]) -> Result<KeyChord, String> {
    let mut modifiers = Modifiers::NONE;
    let mut keys = Vec::new();
    for value in values {
        if let Some(modifier) = modifier_from_name(value) {
            modifiers |= modifier;
        } else {
            keys.push(key_from_name(value)?);
        }
    }
    if keys.is_empty() {
        return Err("hid chord 至少需要一个普通按键，例如：hid chord ALT F4".into());
    }
    KeyChord::new(modifiers, keys).map_err(|error| error.to_string())
}

fn modifier_from_name(value: &str) -> Option<Modifiers> {
    match value.to_ascii_uppercase().as_str() {
        "CTRL" | "CONTROL" | "LCTRL" | "LEFTCTRL" => Some(Modifiers::LEFT_CTRL),
        "SHIFT" | "LSHIFT" | "LEFTSHIFT" => Some(Modifiers::LEFT_SHIFT),
        "ALT" | "LALT" | "LEFTALT" => Some(Modifiers::LEFT_ALT),
        "GUI" | "WIN" | "WINDOWS" | "LGUI" | "LEFTGUI" => Some(Modifiers::LEFT_GUI),
        "RCTRL" | "RIGHTCTRL" => Some(Modifiers::RIGHT_CTRL),
        "RSHIFT" | "RIGHTSHIFT" => Some(Modifiers::RIGHT_SHIFT),
        "RALT" | "RIGHTALT" | "ALTGR" => Some(Modifiers::RIGHT_ALT),
        "RGUI" | "RIGHTGUI" => Some(Modifiers::RIGHT_GUI),
        _ => None,
    }
}

fn key_from_name(value: &str) -> Result<Key, String> {
    let upper = value.to_ascii_uppercase();
    let key = match upper.as_str() {
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
        "ENTER" | "RETURN" => Key::Enter,
        "ESC" | "ESCAPE" => Key::Escape,
        "BACKSPACE" => Key::Backspace,
        "TAB" => Key::Tab,
        "SPACE" => Key::Space,
        "INSERT" | "INS" => Key::Insert,
        "HOME" => Key::Home,
        "PAGEUP" | "PGUP" => Key::PageUp,
        "DELETE" | "DEL" => Key::Delete,
        "END" => Key::End,
        "PAGEDOWN" | "PGDOWN" => Key::PageDown,
        "RIGHT" | "ARROWRIGHT" => Key::ArrowRight,
        "LEFT" | "ARROWLEFT" => Key::ArrowLeft,
        "DOWN" | "ARROWDOWN" => Key::ArrowDown,
        "UP" | "ARROWUP" => Key::ArrowUp,
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
        _ => return Err(format!("不支持的键名：{value}")),
    };
    Ok(key)
}

/// 将一行 shell 输入拆为参数，支持单/双引号及反斜杠转义。
fn parse_command_line(input: &str) -> Result<Vec<String>, String> {
    let mut parts = Vec::new();
    let mut current = String::new();
    let mut quote = None;
    let mut escaped = false;
    let mut started = false;
    for character in input.chars() {
        if escaped {
            current.push(character);
            escaped = false;
            started = true;
            continue;
        }
        if character == '\\' {
            escaped = true;
            started = true;
            continue;
        }
        if let Some(active_quote) = quote {
            if character == active_quote {
                quote = None;
            } else {
                current.push(character);
            }
            started = true;
        } else if matches!(character, '\'' | '"') {
            quote = Some(character);
            started = true;
        } else if character.is_whitespace() {
            if started {
                parts.push(std::mem::take(&mut current));
                started = false;
            }
        } else {
            current.push(character);
            started = true;
        }
    }
    if escaped {
        return Err("命令末尾不能是未转义的反斜杠。".into());
    }
    if quote.is_some() {
        return Err("引号没有闭合。".into());
    }
    if started {
        parts.push(current);
    }
    Ok(parts)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parser_keeps_quoted_paths_and_text() {
        assert_eq!(
            parse_command_line("start --storage '/sdcard/My Disk.img' --hid").unwrap(),
            ["start", "--storage", "/sdcard/My Disk.img", "--hid"]
        );
    }

    #[test]
    fn parser_rejects_unclosed_quote() {
        assert!(parse_command_line("hid type \"unfinished").is_err());
    }

    #[test]
    fn key_names_cover_common_control_keys() {
        assert_eq!(key_from_name("ENTER").unwrap(), Key::Enter);
        assert_eq!(key_from_name("F12").unwrap(), Key::F12);
        assert_eq!(key_from_name("a").unwrap(), Key::A);
    }

    #[test]
    fn chord_parser_maps_alt_f4_to_semantic_model() {
        let chord = chord_from_names(&["ALT".into(), "F4".into()]).unwrap();
        assert_eq!(chord.modifiers, Modifiers::LEFT_ALT);
        assert_eq!(chord.keys, [Key::F4]);
    }

    #[test]
    fn chord_parser_requires_a_normal_key() {
        assert!(chord_from_names(&["CTRL".into(), "ALT".into()]).is_err());
    }
}

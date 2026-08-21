//! HyperUSB Daemon 命令入口。

use std::env;

use crate::info;
use crate::usb_sub::usb_daemon;

pub fn run() -> Result<(), String> {
    let arguments = env::args().skip(1).collect::<Vec<_>>();
    match arguments.as_slice() {
        [] => usb_daemon::run(),
        [command] if command == "daemon" => usb_daemon::run(),
        [command] if command == "info" || command == "--info" => info::print(),
        [command] if command == "--version" || command == "version" => {
            println!("{}", env!("CARGO_PKG_VERSION"));
            Ok(())
        }
        [command] if command == "restore" => {
            usb_daemon::restore()?;
            println!("OK");
            Ok(())
        }
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
           hyperusbd [daemon]             启动常驻 USB Daemon（默认）\n\
           hyperusbd info | --info        查看设备与 Core 信息\n\
           hyperusbd version | --version  查看 Core 版本\n\
           hyperusbd restore              恢复异常退出前的 Android USB\n\
           hyperusbd help                 查看帮助"
    );
}

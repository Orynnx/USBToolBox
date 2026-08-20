use std::fs;
use std::process::Command;

use log::{debug, info};

use crate::usb_sub;

const VERSION: &str = env!("CARGO_PKG_VERSION");

pub fn print() -> Result<(), String> {
    debug!("Collecting runtime information");
    let executable_path = std::env::current_exe()
        .map(|path| path.display().to_string())
        .unwrap_or_else(|_| "Unavailable".into());

    println!("Here are some information you might need:");
    println!("HyperUSB Core Version: {VERSION}");
    println!("Android Kernel Version: {}", kernel_version());
    println!("Android SDK version: {}", sdk_version());
    println!("Running with root: {}", running_with_root());
    println!("Root manager: {}", root_manager());
    println!("SELinux enforcing: {}", selinux_enforcing());
    println!("ConfigFS: {}", usb_sub::configfs_status());
    println!("USB Gadget: {}", usb_sub::gadget_status());
    println!("UDC: {}", usb_sub::udc_status());
    println!("UDC writable: {}", usb_sub::udc_writable());
    println!("USB Host connected: {}", usb_sub::udc_connection_status());
    println!(
        "USB Enumeration state: {}",
        usb_sub::udc_enumeration_state()
    );
    println!("Executable file path: {executable_path}");

    info!("Runtime information report emitted");
    Ok(())
}

fn kernel_version() -> String {
    fs::read_to_string("/proc/sys/kernel/osrelease")
        .map(|version| version.trim().to_owned())
        .unwrap_or_else(|_| "Unavailable".into())
}

fn sdk_version() -> String {
    let sdk = system_property("ro.build.version.sdk");
    let release = system_property("ro.build.version.release");

    match (sdk, release) {
        (Some(sdk), Some(release)) => format!("SDK {sdk}, Android {release}"),
        _ => "Unavailable".into(),
    }
}

fn running_with_root() -> &'static str {
    let Some(status) = fs::read_to_string("/proc/self/status").ok() else {
        return "Unavailable";
    };
    let Some(uid_line) = status.lines().find(|line| line.starts_with("Uid:")) else {
        return "Unavailable";
    };

    match uid_line.split_whitespace().nth(1) {
        Some("0") => "Yes",
        Some(_) => "No",
        None => "Unavailable",
    }
}

fn root_manager() -> &'static str {
    if ["/data/adb/ksu/bin/ksud", "/data/adb/ksud", "/data/adb/ksu"]
        .iter()
        .any(|path| fs::metadata(path).is_ok())
    {
        "KernelSU"
    } else if ["/data/adb/magisk", "/data/adb/magisk.db"]
        .iter()
        .any(|path| fs::metadata(path).is_ok())
    {
        "Magisk"
    } else if ["/data/adb/ap", "/data/adb/apd"]
        .iter()
        .any(|path| fs::metadata(path).is_ok())
    {
        "APatch"
    } else {
        "Unavailable"
    }
}

fn selinux_enforcing() -> &'static str {
    match fs::read_to_string("/sys/fs/selinux/enforce") {
        Ok(value) if value.trim() == "1" => "Yes",
        Ok(value) if value.trim() == "0" => "No",
        _ => "Unavailable",
    }
}

fn system_property(name: &str) -> Option<String> {
    let output = Command::new("getprop")
        .arg(name)
        .output()
        .map_err(|error| {
            debug!("Unable to read Android property {name}: {error}");
            error
        })
        .ok()?;
    if !output.status.success() {
        debug!("Android property {name} returned a non-zero status");
        return None;
    }

    let value = String::from_utf8_lossy(&output.stdout).trim().to_owned();
    if value.is_empty() {
        debug!("Android property {name} is empty");
    }
    (!value.is_empty()).then_some(value)
}

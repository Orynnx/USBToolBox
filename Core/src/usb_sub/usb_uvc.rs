//! UVC Gadget Function 的 ConfigFS 描述符配置。
//!
//! UVC 的用户配置只描述格式、分辨率和帧率。Function 的传输带宽属性由内核和
//! Core 的后续运行时策略决定，不从 JSON 透传 `streaming_*` 参数。

use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};

use crate::usb_sub::{UsbError, UsbResult, UvcConfig};

const SPEEDS: [&str; 3] = ["fs", "hs", "ss"];

/// 配置一个未链接、未绑定的 UVC Function。
#[derive(Debug, Default)]
pub struct UsbUvc;

impl UsbUvc {
    pub fn configure_function(
        &self,
        function_path: impl AsRef<Path>,
        config: &UvcConfig,
    ) -> UsbResult<()> {
        config.validate()?;
        let function_path = function_path.as_ref();
        ensure_directory(function_path, "UVC Function")?;
        clear_function(function_path)?;
        configure_formats(function_path, config)?;
        configure_headers(function_path, config)
    }
}

fn configure_formats(function_path: &Path, config: &UvcConfig) -> UsbResult<()> {
    for format in &config.formats {
        let format_group = function_path
            .join("streaming")
            .join(format.format.configfs_group());
        ensure_directory(&format_group, "UVC format group")?;
        let format_path = format_group.join(format.format.as_str());
        create_configfs_item(&format_path, "UVC format")?;

        for frame in &format.frames {
            let frame_path = format_path.join(format!("{}x{}", frame.width, frame.height));
            create_configfs_item(&frame_path, "UVC frame")?;
            write_attribute(&frame_path.join("wWidth"), frame.width)?;
            write_attribute(&frame_path.join("wHeight"), frame.height)?;
            write_attribute(
                &frame_path.join("dwMaxVideoFrameBufferSize"),
                frame_buffer_size(frame.width, frame.height),
            )?;
            let intervals = frame
                .fps
                .iter()
                .map(|fps| frame_interval(*fps).map(|value| value.to_string()))
                .collect::<UsbResult<Vec<_>>>()?
                .join("\n");
            write_text(&frame_path.join("dwFrameInterval"), &intervals)?;
        }
    }
    Ok(())
}

fn configure_headers(function_path: &Path, config: &UvcConfig) -> UsbResult<()> {
    let streaming = function_path.join("streaming");
    let streaming_header_parent = streaming.join("header");
    ensure_directory(&streaming_header_parent, "UVC streaming header")?;
    let streaming_header = streaming_header_parent.join("h");
    create_configfs_item(&streaming_header, "UVC streaming header item")?;

    for format in &config.formats {
        let target = PathBuf::from("../..")
            .join(format.format.configfs_group())
            .join(format.format.as_str());
        create_relative_symlink(&target, &streaming_header.join(format.format.as_str()))?;
    }
    link_header_to_speeds(
        &streaming.join("class"),
        Path::new("../../header/h"),
        "streaming",
    )?;

    let control = function_path.join("control");
    let control_header_parent = control.join("header");
    ensure_directory(&control_header_parent, "UVC control header")?;
    let control_header = control_header_parent.join("h");
    create_configfs_item(&control_header, "UVC control header item")?;
    link_header_to_speeds(
        &control.join("class"),
        Path::new("../../header/h"),
        "control",
    )?;
    Ok(())
}

fn link_header_to_speeds(class_root: &Path, target: &Path, label: &str) -> UsbResult<()> {
    let mut linked = 0;
    for speed in SPEEDS {
        let class_path = class_root.join(speed);
        if class_path.is_dir() {
            create_relative_symlink(target, &class_path.join("h"))?;
            linked += 1;
        }
    }
    if linked == 0 {
        return Err(UsbError::Unavailable(format!(
            "UVC {label} class 没有可用的 USB speed 目录：{}",
            class_root.display()
        )));
    }
    Ok(())
}

fn clear_function(function_path: &Path) -> UsbResult<()> {
    let streaming = function_path.join("streaming");
    let control = function_path.join("control");

    for speed in SPEEDS {
        remove_class_link(&streaming.join("class").join(speed).join("h"))?;
        remove_class_link(&control.join("class").join(speed).join("h"))?;
    }
    remove_header_item(&streaming.join("header").join("h"))?;
    remove_header_item(&control.join("header").join("h"))?;
    remove_format_items(&streaming.join("mjpeg"))?;
    remove_format_items(&streaming.join("uncompressed"))?;
    Ok(())
}

fn ensure_directory(path: &Path, label: &str) -> UsbResult<()> {
    if !path.exists() {
        fs::create_dir(path)?;
    }
    if path.is_dir() {
        Ok(())
    } else {
        Err(UsbError::InvalidInput(format!(
            "{label} 路径不是目录：{}",
            path.display()
        )))
    }
}

fn create_configfs_item(path: &Path, label: &str) -> UsbResult<()> {
    if path.exists() {
        return Err(UsbError::Unavailable(format!(
            "{label} 已存在，无法安全重建：{}",
            path.display()
        )));
    }
    fs::create_dir(path)?;
    Ok(())
}

fn remove_class_link(path: &Path) -> UsbResult<()> {
    let metadata = match fs::symlink_metadata(path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error.into()),
    };
    if metadata.file_type().is_symlink() {
        fs::remove_file(path)?;
        return Ok(());
    }
    Err(UsbError::Unavailable(format!(
        "UVC class 链接不是 symlink，拒绝删除：{}",
        path.display()
    )))
}

fn remove_header_item(path: &Path) -> UsbResult<()> {
    let metadata = match fs::symlink_metadata(path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error.into()),
    };
    if !metadata.is_dir() {
        return Err(UsbError::Unavailable(format!(
            "UVC header item 不是目录，拒绝删除：{}",
            path.display()
        )));
    }
    for entry in fs::read_dir(path)? {
        let child = entry?.path();
        let metadata = fs::symlink_metadata(&child)?;
        if metadata.file_type().is_symlink() {
            fs::remove_file(child)?;
        }
        // ConfigFS attributes such as bcdUVC and dwClockFrequency are ordinary
        // kernel-created files. They are removed together with the item by rmdir.
    }
    // ConfigFS item attributes are kernel-created files. Removing the item with rmdir
    // removes those attributes; they must never be passed to remove_file().
    fs::remove_dir(path)?;
    Ok(())
}

fn remove_format_items(group_path: &Path) -> UsbResult<()> {
    if !group_path.is_dir() {
        return Ok(());
    }
    for format_entry in fs::read_dir(group_path)? {
        let format_path = format_entry?.path();
        if !format_path.is_dir() {
            return Err(UsbError::Unavailable(format!(
                "UVC format group 出现非目录子项，拒绝删除：{}",
                format_path.display()
            )));
        }
        for frame_entry in fs::read_dir(&format_path)? {
            let frame_path = frame_entry?.path();
            let metadata = fs::symlink_metadata(&frame_path)?;
            if metadata.is_dir() {
                // Do not enumerate or remove wWidth/dwFrameInterval and other attributes.
                fs::remove_dir(frame_path)?;
            } else if metadata.file_type().is_symlink() {
                // A format may also carry an optional ConfigFS descriptor link.
                fs::remove_file(frame_path)?;
            }
        }
        fs::remove_dir(format_path)?;
    }
    Ok(())
}

#[cfg(unix)]
fn create_relative_symlink(target: &Path, link: &Path) -> UsbResult<()> {
    std::os::unix::fs::symlink(target, link)?;
    Ok(())
}

#[cfg(not(unix))]
fn create_relative_symlink(_target: &Path, _link: &Path) -> UsbResult<()> {
    Err(UsbError::Unsupported("UVC ConfigFS 链接仅支持 Unix"))
}

fn write_attribute<T: std::fmt::Display>(path: &Path, value: T) -> UsbResult<()> {
    write_text(path, &value.to_string())
}

fn write_text(path: &Path, value: &str) -> UsbResult<()> {
    let mut file = OpenOptions::new().write(true).truncate(true).open(path)?;
    file.write_all(value.as_bytes())?;
    Ok(())
}

fn frame_buffer_size(width: u32, height: u32) -> u32 {
    width.saturating_mul(height).saturating_mul(2)
}

fn frame_interval(fps: u32) -> UsbResult<u32> {
    if fps == 0 {
        return Err(UsbError::InvalidInput(
            "UVC fps 必须大于零，无法生成 frame interval".into(),
        ));
    }
    let interval = 10_000_000 / u64::from(fps);
    u32::try_from(interval)
        .map_err(|_| UsbError::InvalidInput(format!("UVC fps 无法转换为 frame interval：{fps}")))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn converts_fps_to_100ns_frame_interval() {
        assert_eq!(frame_interval(30).unwrap(), 333_333);
        assert_eq!(frame_interval(60).unwrap(), 166_666);
    }

    #[test]
    fn calculates_safe_frame_buffer_size() {
        assert_eq!(frame_buffer_size(1280, 720), 1_843_200);
    }
}

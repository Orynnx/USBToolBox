//! USB Mass Storage 的多 LUN 核心。
//!
//! 一个持久 `mass_storage.hyperusb` Function 对应一个 USB Mass Storage 设备，其中
//! `lun.0`、`lun.1`……分别作为独立磁盘或光驱出现在 Host。重新配置时复用 Function，
//! 先卸载所有旧 backing file，再调整 LUN 数量并按参考脚本的属性顺序重新挂载。

use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};

use crate::usb_sub::{UsbError, UsbResult};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StorageLun {
    /// 普通镜像文件路径；不支持直接暴露块设备节点。`ejected=true` 时可以为空。
    ///
    /// Android SELinux 必须允许 `u:r:kernel:s0` 访问该文件。通常应使用
    /// `/data/media/0` 下的 `media_rw_data_file`，不要使用 `/data/local/tmp` 下的
    /// `shell_data_file`，否则 Host 会收到读写错误。
    pub image: Option<PathBuf>,
    pub read_only: bool,
    pub removable: bool,
    pub cdrom: bool,
    pub no_fua: bool,
    pub ejected: bool,
}

impl StorageLun {
    /// 可读写、可弹出的普通磁盘。
    pub fn disk(image: impl Into<PathBuf>) -> Self {
        Self {
            image: Some(image.into()),
            read_only: false,
            removable: true,
            cdrom: false,
            no_fua: false,
            ejected: false,
        }
    }

    /// 只读、可弹出的 CD-ROM/ISO。
    pub fn cdrom(image: impl Into<PathBuf>) -> Self {
        Self {
            image: Some(image.into()),
            read_only: true,
            removable: true,
            cdrom: true,
            no_fua: true,
            ejected: false,
        }
    }

    /// 暂无介质但保留盘符语义的普通磁盘。
    pub fn ejected_disk() -> Self {
        let mut lun = Self::disk(PathBuf::new());
        lun.image = None;
        lun.ejected = true;
        lun
    }

    /// 暂无介质但保留盘符语义的光驱。
    pub fn ejected_cdrom() -> Self {
        let mut lun = Self::cdrom(PathBuf::new());
        lun.image = None;
        lun.ejected = true;
        lun
    }

    pub fn mount(&mut self, image: impl Into<PathBuf>) {
        self.image = Some(image.into());
        self.ejected = false;
    }

    pub fn eject(&mut self) {
        self.ejected = true;
    }

    pub fn validate(&self) -> UsbResult<()> {
        if self.cdrom && !self.read_only {
            return Err(UsbError::InvalidInput("CD-ROM LUN 必须为只读".into()));
        }
        if self.ejected {
            return Ok(());
        }
        let image = self
            .image
            .as_ref()
            .ok_or_else(|| UsbError::InvalidInput("未弹出的 LUN 必须指定镜像路径".into()))?;
        if !image.is_file() {
            return Err(UsbError::InvalidInput(format!(
                "存储镜像不存在或不是普通文件：{}",
                image.display()
            )));
        }
        if image.to_str().is_none() {
            return Err(UsbError::InvalidInput("存储镜像路径不是有效 UTF-8".into()));
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Default)]
pub struct UsbStorage {
    luns: Vec<StorageLun>,
}

impl UsbStorage {
    pub fn new(luns: Vec<StorageLun>) -> Self {
        Self { luns }
    }

    pub fn luns(&self) -> &[StorageLun] {
        &self.luns
    }

    pub fn add_lun(&mut self, lun: StorageLun) -> usize {
        self.luns.push(lun);
        self.luns.len() - 1
    }

    pub fn remove_lun(&mut self, index: usize) -> Option<StorageLun> {
        (index < self.luns.len()).then(|| self.luns.remove(index))
    }

    pub fn validate(&self) -> UsbResult<()> {
        if self.luns.is_empty() {
            return Err(UsbError::InvalidInput(
                "Mass Storage 至少需要一个 LUN".into(),
            ));
        }
        for lun in &self.luns {
            lun.validate()?;
        }
        Ok(())
    }

    /// 将持久 Function 调整到目标 LUN 列表。
    ///
    /// 必须在 Gadget 未绑定且 Function 未链接时调用。每个 LUN 都严格执行：清空 `file`、
    /// 写入 `ro/removable/cdrom/nofua`、最后写入镜像路径。
    pub fn reconcile_function(&self, function_path: impl AsRef<Path>) -> UsbResult<()> {
        self.validate()?;
        let function_path = function_path.as_ref();
        ensure_function_directory(function_path)?;

        let mut existing = existing_lun_indexes(function_path)?;
        for index in &existing {
            clear_lun_file(function_path, *index)?;
        }

        // lun.0 由 ConfigFS 随 Function 自动创建；额外 LUN 由用户态按需创建和删除。
        for index in lun_indexes_to_remove(&existing, self.luns.len()) {
            fs::remove_dir(function_path.join(format!("lun.{index}")))?;
        }
        for index in 0..self.luns.len() {
            let lun_path = function_path.join(format!("lun.{index}"));
            if !lun_path.exists() {
                fs::create_dir(&lun_path)?;
            }
            configure_lun(&lun_path, &self.luns[index])?;
        }

        existing = existing_lun_indexes(function_path)?;
        if existing.len() != self.luns.len() {
            return Err(UsbError::Unavailable(format!(
                "Mass Storage LUN 数量不一致：期望 {}，实际 {}",
                self.luns.len(),
                existing.len()
            )));
        }
        Ok(())
    }

    /// 清空 Function 中所有 backing file，但保留 Function 和 LUN 目录供下次复用。
    pub fn detach_all(function_path: impl AsRef<Path>) -> UsbResult<()> {
        let function_path = function_path.as_ref();
        if !function_path.exists() {
            return Ok(());
        }
        for index in existing_lun_indexes(function_path)? {
            clear_lun_file(function_path, index)?;
        }
        Ok(())
    }

    pub fn eject_configured_lun(function_path: impl AsRef<Path>, index: usize) -> UsbResult<()> {
        clear_lun_file(function_path.as_ref(), index)
    }
}

fn configure_lun(lun_path: &Path, lun: &StorageLun) -> UsbResult<()> {
    clear_attribute(&lun_path.join("file"))?;
    write_bool(&lun_path.join("ro"), lun.read_only)?;
    write_bool(&lun_path.join("removable"), lun.removable)?;
    write_bool(&lun_path.join("cdrom"), lun.cdrom)?;
    let no_fua = lun_path.join("nofua");
    if no_fua.exists() {
        write_bool(&no_fua, lun.no_fua)?;
    }

    if !lun.ejected {
        let image = lun.image.as_ref().expect("validated LUN has an image");
        write_attribute(
            &lun_path.join("file"),
            image
                .to_str()
                .expect("validated image path is UTF-8")
                .as_bytes(),
        )?;
    }
    Ok(())
}

fn existing_lun_indexes(function_path: &Path) -> UsbResult<Vec<usize>> {
    let mut indexes = Vec::new();
    for entry in fs::read_dir(function_path)? {
        let entry = entry?;
        let Some(name) = entry.file_name().to_str().map(str::to_owned) else {
            continue;
        };
        let Some(index) = name
            .strip_prefix("lun.")
            .and_then(|value| value.parse().ok())
        else {
            continue;
        };
        if entry.path().is_dir() {
            indexes.push(index);
        }
    }
    indexes.sort_unstable();
    Ok(indexes)
}

fn lun_indexes_to_remove(existing: &[usize], desired_count: usize) -> Vec<usize> {
    existing
        .iter()
        .copied()
        .rev()
        .filter(|index| *index >= desired_count && *index != 0)
        .collect()
}

fn clear_lun_file(function_path: &Path, index: usize) -> UsbResult<()> {
    let file = function_path.join(format!("lun.{index}/file"));
    if file.exists() {
        clear_attribute(&file)?;
    }
    Ok(())
}

fn ensure_function_directory(path: &Path) -> UsbResult<()> {
    if !path.exists() {
        fs::create_dir(path)?;
    }
    if path.is_dir() {
        Ok(())
    } else {
        Err(UsbError::InvalidInput(format!(
            "Mass Storage Function 路径不是目录：{}",
            path.display()
        )))
    }
}

fn write_bool(path: &Path, value: bool) -> UsbResult<()> {
    write_attribute(path, if value { b"1" } else { b"0" })
}

fn clear_attribute(path: &Path) -> UsbResult<()> {
    // 对 ConfigFS 属性执行零字节 write 不会调用内核 store；换行符才等价于 shell 的
    // `echo "" > lun.N/file`，可真正卸载 backing file。
    write_attribute(path, b"\n")
}

fn write_attribute(path: &Path, value: &[u8]) -> UsbResult<()> {
    let mut file = OpenOptions::new().write(true).truncate(true).open(path)?;
    file.write_all(value)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_directory(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!(
            "hyperusb-storage-{name}-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        ))
    }

    fn create_fake_lun(function: &Path, index: usize) {
        let lun = function.join(format!("lun.{index}"));
        fs::create_dir_all(&lun).unwrap();
        for attribute in ["file", "ro", "removable", "cdrom", "nofua"] {
            fs::write(lun.join(attribute), []).unwrap();
        }
    }

    #[test]
    fn reconciles_and_reuses_multiple_luns() {
        let root = test_directory("reconcile");
        let function = root.join("mass_storage.hyperusb");
        let disk = root.join("disk.img");
        let iso = root.join("setup.iso");
        fs::create_dir_all(&function).unwrap();
        fs::write(&disk, [0_u8; 16]).unwrap();
        fs::write(&iso, [0_u8; 16]).unwrap();
        create_fake_lun(&function, 0);
        create_fake_lun(&function, 1);

        UsbStorage::new(vec![StorageLun::disk(&disk), StorageLun::cdrom(&iso)])
            .reconcile_function(&function)
            .unwrap();

        assert_eq!(
            fs::read_to_string(function.join("lun.0/file")).unwrap(),
            disk.to_str().unwrap()
        );
        assert_eq!(
            fs::read_to_string(function.join("lun.1/file")).unwrap(),
            iso.to_str().unwrap()
        );
        assert_eq!(fs::read_to_string(function.join("lun.1/ro")).unwrap(), "1");
        assert_eq!(
            fs::read_to_string(function.join("lun.1/cdrom")).unwrap(),
            "1"
        );

        UsbStorage::detach_all(&function).unwrap();
        assert_eq!(
            fs::read_to_string(function.join("lun.0/file")).unwrap(),
            "\n"
        );
        assert_eq!(
            fs::read_to_string(function.join("lun.1/file")).unwrap(),
            "\n"
        );
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn removes_surplus_luns_in_reverse_order_but_keeps_lun_zero() {
        assert_eq!(lun_indexes_to_remove(&[0, 1, 2, 3], 2), vec![3, 2]);
        assert!(lun_indexes_to_remove(&[0], 0).is_empty());
    }

    #[test]
    fn ejected_luns_are_valid_without_images() {
        UsbStorage::new(vec![
            StorageLun::ejected_disk(),
            StorageLun::ejected_cdrom(),
        ])
        .validate()
        .unwrap();
    }

    #[test]
    fn mounted_lun_rejects_non_file_path() {
        let directory = test_directory("non-file");
        fs::create_dir_all(&directory).unwrap();

        assert!(StorageLun::disk(&directory).validate().is_err());

        fs::remove_dir_all(directory).unwrap();
    }
}

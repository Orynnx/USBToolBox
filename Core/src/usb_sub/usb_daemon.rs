//! Root Unix Socket Daemon 与唯一 USB 控制线程。

use std::path::Path;

use log::{error, warn};

use crate::usb_sub::usb_config::load_configuration;
use crate::usb_sub::usb_protocol::{ApiError, ApiErrorCode, ApiRequest, ApiResponse};
use crate::usb_sub::{
    HidKeyboardWriter, UsbConfiguration, UsbError, UsbRuntimeConfig, UsbRuntimeState, UsbSession,
    UsbTargetState,
};

pub const WORK_DIRECTORY: &str = "/data/adb/usb_sub";
pub const SOCKET_PATH: &str = "/data/adb/usb_sub/usb.sock";
pub const LOCK_PATH: &str = "/data/adb/usb_sub/usb.lock";

pub fn run() -> Result<(), String> {
    platform::run()
}

pub fn restore() -> Result<(), String> {
    platform::restore()
}

struct UsbController {
    runtime: UsbRuntimeConfig,
    session: Option<UsbSession>,
    keyboard: Option<HidKeyboardWriter>,
}

impl UsbController {
    fn new(runtime: UsbRuntimeConfig) -> Self {
        Self {
            runtime,
            session: None,
            keyboard: None,
        }
    }

    fn execute(&mut self, request: ApiRequest) -> ApiResponse {
        if matches!(request, ApiRequest::Ping) { return ApiResponse::Ok; }
        if matches!(request, ApiRequest::Status) { return ApiResponse::Status(self.status_json()); }
        let result = match request {
            ApiRequest::Set(path) => self.set(&path),
            ApiRequest::BootKey(chord) => self.boot_key(&chord),
            ApiRequest::Ping | ApiRequest::Status => unreachable!("handled above"),
        };
        match result {
            Ok(()) => ApiResponse::Ok,
            Err(error) => {
                warn!("API command failed: {error}");
                ApiResponse::Error(error.code)
            }
        }
    }

    fn status_json(&self) -> String {
        let Some(session) = &self.session else {
            return r#"{"state":"android","storageLuns":[],"keyboard":false,"serial":false,"uvc":false}"#.into();
        };
        let profile = session.profile();
        let luns = profile.storage_luns.iter().map(|lun| serde_json::json!({
            "imagePath": lun.image.as_ref().map(|path| path.to_string_lossy().into_owned()),
            "readOnly": lun.read_only, "removable": lun.removable,
            "cdrom": lun.cdrom, "noFua": lun.no_fua,
        })).collect::<Vec<_>>();
        serde_json::json!({
            "state": "active", "storageLuns": luns,
            "keyboard": profile.keyboard_enabled, "serial": profile.serial_enabled,
            "uvc": profile.uvc.is_some(), "udc": session.udc(),
        }).to_string()
    }


    fn set(&mut self, path: &Path) -> Result<(), ApiError> {
        let target = load_configuration(path)?;
        self.apply(target)
    }

    fn apply(&mut self, target: UsbTargetState) -> Result<(), ApiError> {
        match target {
            UsbTargetState::AndroidUsb => self.stop(),
            UsbTargetState::HyperUsb(configuration) => self.apply_hyperusb(configuration),
        }
    }

    fn apply_hyperusb(&mut self, configuration: UsbConfiguration) -> Result<(), ApiError> {
        if self
            .session
            .as_ref()
            .is_some_and(|session| session.configuration() == &configuration)
        {
            return Ok(());
        }

        if self.session.is_none() {
            self.session = Some(
                UsbSession::start(self.runtime.clone(), configuration).map_err(map_start_error)?,
            );
            return Ok(());
        }

        if let Err(error) = self.release_keyboard() {
            warn!("Boot release before SET failed: {error}");
        }
        let result = self
            .session
            .as_mut()
            .expect("active session checked above")
            .reconfigure(configuration);
        match result {
            Ok(()) => Ok(()),
            Err(UsbError::RestoreFailed(detail)) => {
                self.session = None;
                Err(ApiError::new(ApiErrorCode::RestoreFailed, detail))
            }
            Err(error) => {
                let stopped = self
                    .session
                    .as_ref()
                    .is_some_and(|session| matches!(session.state(), UsbRuntimeState::Stopped));
                if stopped {
                    self.session = None;
                    Err(ApiError::new(
                        ApiErrorCode::RestoreFailed,
                        error.to_string(),
                    ))
                } else {
                    Err(ApiError::new(ApiErrorCode::ApplyFailed, error.to_string()))
                }
            }
        }
    }

    fn boot_key(&mut self, chord: &crate::usb_sub::KeyChord) -> Result<(), ApiError> {
        let session = self
            .session
            .as_ref()
            .ok_or_else(|| ApiError::new(ApiErrorCode::NotStarted, "当前没有活动 USB 会话"))?;
        if !session.profile().keyboard_enabled {
            return Err(ApiError::new(
                ApiErrorCode::BootDisabled,
                "当前配置未启用 Boot Keyboard",
            ));
        }
        if self.keyboard.is_none() {
            self.keyboard = Some(session.open_keyboard().map_err(internal_error)?);
        }
        self.keyboard
            .as_mut()
            .expect("keyboard writer initialized")
            .send_chord(chord)
            .map_err(internal_error)
    }

    fn stop(&mut self) -> Result<(), ApiError> {
        let release_error = self.release_keyboard().err();
        let stop_result = match self.session.take() {
            Some(session) => session.stop(),
            None => Ok(()),
        };
        match stop_result {
            Err(UsbError::RestoreFailed(detail)) => {
                Err(ApiError::new(ApiErrorCode::RestoreFailed, detail))
            }
            Err(error) => Err(internal_error(error)),
            Ok(()) => match release_error {
                Some(error) => Err(internal_error(error)),
                None => Ok(()),
            },
        }
    }

    fn release_keyboard(&mut self) -> Result<(), UsbError> {
        let Some(mut keyboard) = self.keyboard.take() else {
            return Ok(());
        };
        if let Err(error) = keyboard.key_up_all() {
            let _ = keyboard.key_up_all();
            return Err(error);
        }
        Ok(())
    }

    fn shutdown(&mut self) {
        if let Err(error) = self.stop() {
            error!("Daemon shutdown cleanup failed: {error}");
        }
    }
}

fn map_start_error(error: UsbError) -> ApiError {
    match error {
        UsbError::RestoreFailed(detail) => ApiError::new(ApiErrorCode::RestoreFailed, detail),
        other => ApiError::new(ApiErrorCode::ApplyFailed, other.to_string()),
    }
}

fn internal_error(error: UsbError) -> ApiError {
    ApiError::new(ApiErrorCode::InternalError, error.to_string())
}


#[cfg(unix)]
mod platform {
    use std::fs::{self, File, OpenOptions};
    use std::io::{self, BufRead, BufReader, ErrorKind, Write};
    use std::os::unix::fs::{FileTypeExt, OpenOptionsExt, PermissionsExt};
    use std::os::unix::io::AsRawFd;
    use std::os::unix::net::{UnixListener, UnixStream};
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::sync::Arc;
    use std::thread;
    use std::time::Duration;

    use crossbeam_channel::{bounded, select, Sender};
    use log::info;
    use signal_hook::consts::{SIGINT, SIGTERM};
    use signal_hook::iterator::Signals;

    use super::*;
    use crate::usb_sub::usb_protocol::{parse_request, MAX_COMMAND_BYTES};
    use crate::usb_sub::{UsbRecoveryState, DEFAULT_USB_STATE_PATH, LEGACY_USB_STATE_PATH};

    const COMMAND_QUEUE_CAPACITY: usize = 32;

    struct InstanceLock {
        file: File,
    }

    impl InstanceLock {
        fn acquire(path: &Path) -> Result<Self, String> {
            let file = OpenOptions::new()
                .create(true)
                .read(true)
                .write(true)
                .truncate(false)
                .mode(0o600)
                .open(path)
                .map_err(|error| format!("无法打开实例锁 {}：{error}", path.display()))?;
            let result = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
            if result != 0 {
                return Err(format!(
                    "另一个 HyperUSB Daemon 已持有实例锁 {}：{}",
                    path.display(),
                    io::Error::last_os_error()
                ));
            }
            Ok(Self { file })
        }
    }

    impl Drop for InstanceLock {
        fn drop(&mut self) {
            let _ = unsafe { libc::flock(self.file.as_raw_fd(), libc::LOCK_UN) };
        }
    }

    struct CommandEnvelope {
        request: ApiRequest,
        response: Sender<ApiResponse>,
    }

    pub(super) fn run() -> Result<(), String> {
        ensure_work_directory()?;
        let _lock = InstanceLock::acquire(Path::new(LOCK_PATH))?;
        recover_before_listen()?;
        prepare_socket_path()?;
        let listener = UnixListener::bind(SOCKET_PATH)
            .map_err(|error| format!("无法绑定 Unix Socket {SOCKET_PATH}：{error}"))?;
        fs::set_permissions(SOCKET_PATH, fs::Permissions::from_mode(0o600))
            .map_err(|error| format!("无法设置 Socket 权限：{error}"))?;
        sync_directory(Path::new(WORK_DIRECTORY))?;
        listener
            .set_nonblocking(true)
            .map_err(|error| format!("无法设置非阻塞 listener：{error}"))?;

        let (command_tx, command_rx) = bounded::<CommandEnvelope>(COMMAND_QUEUE_CAPACITY);
        let (shutdown_tx, shutdown_rx) = bounded::<()>(1);
        let shutdown = Arc::new(AtomicBool::new(false));

        let mut signals = Signals::new([SIGINT, SIGTERM])
            .map_err(|error| format!("无法注册退出信号：{error}"))?;
        let signal_handle = signals.handle();
        let signal_shutdown = shutdown_tx.clone();
        let signal_thread = thread::spawn(move || {
            if signals.forever().next().is_some() {
                let _ = signal_shutdown.try_send(());
            }
        });

        let listener_shutdown = Arc::clone(&shutdown);
        let listener_thread =
            thread::spawn(move || listener_loop(listener, command_tx, listener_shutdown));

        info!("HyperUSB Daemon listening at {SOCKET_PATH}");
        let mut controller = UsbController::new(UsbRuntimeConfig::default());
        loop {
            select! {
                recv(shutdown_rx) -> _ => break,
                recv(command_rx) -> message => match message {
                    Ok(envelope) => {
                        let response = controller.execute(envelope.request);
                        let _ = envelope.response.send(response);
                    }
                    Err(_) => break,
                }
            }
        }

        shutdown.store(true, Ordering::Release);
        controller.shutdown();
        signal_handle.close();
        let _ = signal_thread.join();
        let _ = listener_thread.join();
        remove_socket()?;
        info!("HyperUSB Daemon stopped");
        Ok(())
    }

    pub(super) fn restore() -> Result<(), String> {
        ensure_work_directory()?;
        let _lock = InstanceLock::acquire(Path::new(LOCK_PATH))?;
        restore_pending_state()?;
        Ok(())
    }

    fn listener_loop(
        listener: UnixListener,
        command_tx: Sender<CommandEnvelope>,
        shutdown: Arc<AtomicBool>,
    ) {
        while !shutdown.load(Ordering::Acquire) {
            match listener.accept() {
                Ok((stream, _)) => {
                    let client_tx = command_tx.clone();
                    let client_shutdown = Arc::clone(&shutdown);
                    thread::spawn(move || handle_client(stream, client_tx, client_shutdown));
                }
                Err(error) if error.kind() == ErrorKind::WouldBlock => {
                    thread::sleep(Duration::from_millis(20));
                }
                Err(error) => {
                    warn!("Unix accept failed: {error}");
                    thread::sleep(Duration::from_millis(50));
                }
            }
        }
    }

    fn handle_client(
        stream: UnixStream,
        command_tx: Sender<CommandEnvelope>,
        shutdown: Arc<AtomicBool>,
    ) {
        let read_stream = match stream.try_clone() {
            Ok(stream) => stream,
            Err(error) => {
                warn!("Unable to clone Unix client stream: {error}");
                return;
            }
        };
        let mut reader = BufReader::with_capacity(1024, read_stream);
        let mut writer = stream;
        while !shutdown.load(Ordering::Acquire) {
            let response = match read_bounded_line(&mut reader) {
                Ok(BoundedLine::Eof) => return,
                Ok(BoundedLine::TooLong) => ApiResponse::Error(ApiErrorCode::InvalidCommand),
                Ok(BoundedLine::Line(bytes)) => match std::str::from_utf8(&bytes) {
                    Ok(line) => match parse_request(line) {
                        Ok(request) => {
                            let (response_tx, response_rx) = bounded(1);
                            if command_tx
                                .send(CommandEnvelope {
                                    request,
                                    response: response_tx,
                                })
                                .is_err()
                            {
                                return;
                            }
                            match response_rx.recv() {
                                Ok(response) => response,
                                Err(_) => return,
                            }
                        }
                        Err(error) => {
                            warn!("Invalid API request: {error}");
                            ApiResponse::Error(error.code)
                        }
                    },
                    Err(error) => {
                        warn!("API request is not UTF-8: {error}");
                        ApiResponse::Error(ApiErrorCode::InvalidCommand)
                    }
                },
                Err(error) => {
                    warn!("Unix client read failed: {error}");
                    return;
                }
            };
            if writer.write_all(response.encode().as_bytes()).is_err() {
                return;
            }
        }
    }

    enum BoundedLine {
        Eof,
        Line(Vec<u8>),
        TooLong,
    }

    fn read_bounded_line(reader: &mut impl BufRead) -> io::Result<BoundedLine> {
        let mut line = Vec::with_capacity(256);
        let mut too_long = false;
        loop {
            let available = reader.fill_buf()?;
            if available.is_empty() {
                return if too_long {
                    Ok(BoundedLine::TooLong)
                } else if line.is_empty() {
                    Ok(BoundedLine::Eof)
                } else {
                    Ok(BoundedLine::Line(line))
                };
            }
            let newline = available.iter().position(|byte| *byte == b'\n');
            let content_length = newline.unwrap_or(available.len());
            if !too_long {
                if line.len() + content_length > MAX_COMMAND_BYTES {
                    too_long = true;
                    line.clear();
                } else {
                    line.extend_from_slice(&available[..content_length]);
                }
            }
            let consumed = content_length + usize::from(newline.is_some());
            reader.consume(consumed);
            if newline.is_some() {
                if too_long {
                    return Ok(BoundedLine::TooLong);
                }
                if line.last() == Some(&b'\r') {
                    line.pop();
                }
                return Ok(BoundedLine::Line(line));
            }
        }
    }

    fn ensure_work_directory() -> Result<(), String> {
        let path = Path::new(WORK_DIRECTORY);
        if !path.exists() {
            fs::create_dir_all(path)
                .map_err(|error| format!("无法创建工作目录 {}：{error}", path.display()))?;
        }
        if !path.is_dir() {
            return Err(format!("工作路径不是目录：{}", path.display()));
        }
        fs::set_permissions(path, fs::Permissions::from_mode(0o700))
            .map_err(|error| format!("无法设置工作目录权限：{error}"))?;
        Ok(())
    }

    fn recover_before_listen() -> Result<(), String> {
        restore_pending_state()?;
        Ok(())
    }

    #[derive(Debug, PartialEq, Eq)]
    struct RecoverySelection {
        path: PathBuf,
        stale_legacy: Option<PathBuf>,
    }

    fn restore_pending_state() -> Result<bool, String> {
        let Some(selection) = select_recovery_path()? else {
            info!("No pending USB recovery state");
            return Ok(false);
        };
        info!("Recovering Android USB from {}", selection.path.display());
        restore_from_path(&selection.path)?;
        if let Some(stale_legacy) = selection.stale_legacy {
            if let Err(error) = UsbRecoveryState::clear(&stale_legacy) {
                warn!(
                    "Unable to remove stale legacy recovery state {}: {error}",
                    stale_legacy.display()
                );
            }
        }
        Ok(true)
    }

    fn restore_from_path(path: &Path) -> Result<(), String> {
        let runtime = UsbRuntimeConfig {
            recovery_state_path: path.to_owned(),
            ..UsbRuntimeConfig::default()
        };
        UsbSession::restore_persisted(runtime).map_err(|error| error.to_string())
    }

    fn select_recovery_path() -> Result<Option<RecoverySelection>, String> {
        select_recovery_paths(
            Path::new(DEFAULT_USB_STATE_PATH),
            Path::new(LEGACY_USB_STATE_PATH),
        )
    }

    fn select_recovery_paths(
        canonical: &Path,
        legacy: &Path,
    ) -> Result<Option<RecoverySelection>, String> {
        let canonical_state = UsbRecoveryState::load(canonical)
            .map_err(|error| format!("无法读取 canonical recovery state：{error}"))?;
        if canonical_state.is_some() {
            let legacy_exists = match fs::symlink_metadata(legacy) {
                Ok(_) => true,
                Err(error) if error.kind() == ErrorKind::NotFound => false,
                Err(error) => return Err(format!("无法检查 legacy recovery state：{error}")),
            };
            if legacy_exists {
                warn!(
                    "Canonical and legacy recovery states both exist; using canonical: {}; stale legacy: {}",
                    canonical.display(),
                    legacy.display()
                );
            }
            return Ok(Some(RecoverySelection {
                path: canonical.to_owned(),
                stale_legacy: legacy_exists.then(|| legacy.to_owned()),
            }));
        }

        let legacy_state = UsbRecoveryState::load(legacy)
            .map_err(|error| format!("无法读取 legacy recovery state：{error}"))?;
        if legacy_state.is_some() {
            Ok(Some(RecoverySelection {
                path: legacy.to_owned(),
                stale_legacy: None,
            }))
        } else {
            Ok(None)
        }
    }

    fn prepare_socket_path() -> Result<(), String> {
        let path = Path::new(SOCKET_PATH);
        match fs::symlink_metadata(path) {
            Ok(metadata) if metadata.file_type().is_dir() => Err(format!(
                "Socket 路径被目录占用，拒绝删除：{}",
                path.display()
            )),
            Ok(_) => {
                fs::remove_file(path)
                    .map_err(|error| format!("无法删除陈旧 Socket 路径：{error}"))?;
                sync_directory(Path::new(WORK_DIRECTORY))
            }
            Err(error) if error.kind() == ErrorKind::NotFound => Ok(()),
            Err(error) => Err(format!("无法检查 Socket 路径：{error}")),
        }
    }

    fn remove_socket() -> Result<(), String> {
        match fs::symlink_metadata(SOCKET_PATH) {
            Ok(metadata) if metadata.file_type().is_socket() => {
                fs::remove_file(SOCKET_PATH)
                    .map_err(|error| format!("无法删除 Unix Socket：{error}"))?;
                sync_directory(Path::new(WORK_DIRECTORY))
            }
            Ok(_) => Err("退出时 Socket 路径已被替换，拒绝删除".into()),
            Err(error) if error.kind() == ErrorKind::NotFound => Ok(()),
            Err(error) => Err(format!("无法检查退出 Socket：{error}")),
        }
    }

    fn sync_directory(path: &Path) -> Result<(), String> {
        File::open(path)
            .and_then(|directory| directory.sync_all())
            .map_err(|error| format!("无法同步目录 {}：{error}", path.display()))
    }

    #[cfg(test)]
    mod tests {
        use super::*;
        use std::io::Cursor;

        #[test]
        fn bounded_reader_recovers_after_oversized_line() {
            let mut bytes = vec![b'A'; MAX_COMMAND_BYTES + 1];
            bytes.extend_from_slice(b"\nboot_key enter\r\n");
            let mut reader = BufReader::new(Cursor::new(bytes));
            assert!(matches!(
                read_bounded_line(&mut reader).unwrap(),
                BoundedLine::TooLong
            ));
            match read_bounded_line(&mut reader).unwrap() {
                BoundedLine::Line(line) => assert_eq!(line, b"boot_key enter"),
                _ => panic!("expected second line"),
            }
        }

        #[test]
        fn recovery_selection_prefers_canonical_and_marks_legacy_stale() {
            let root = std::env::temp_dir().join(format!(
                "hyperusb-recovery-selection-{}-{:?}",
                std::process::id(),
                std::thread::current().id()
            ));
            fs::create_dir_all(&root).unwrap();
            let canonical = root.join("canonical.json");
            let legacy = root.join("legacy.json");
            let state = UsbRecoveryState {
                original_usb_config: "adb".into(),
                sys_adb_disabled: None,
                vendor_adb_disabled: None,
            };
            state.persist_atomically(&canonical).unwrap();
            state.persist_atomically(&legacy).unwrap();
            assert_eq!(
                select_recovery_paths(&canonical, &legacy).unwrap(),
                Some(RecoverySelection {
                    path: canonical.clone(),
                    stale_legacy: Some(legacy.clone()),
                })
            );
            let _ = fs::remove_dir_all(root);
        }
    }
}

#[cfg(not(unix))]
mod platform {
    pub(super) fn run() -> Result<(), String> {
        Err("Unix Socket Daemon 仅支持 Android/Linux".into())
    }

    pub(super) fn restore() -> Result<(), String> {
        Err("USB restore 仅支持 Android/Linux".into())
    }
}

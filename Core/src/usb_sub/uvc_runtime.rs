//! UVC 视频 Runtime Unix Socket 层。
//!
//! 本文件提供“上层 Producer <-> Core Runtime”二进制协议通道，不直接处理 USB 控制协议。
//! Core 负责枚举和 V4L2 运行时配置；Producer 只负责交付完整帧。

use std::collections::VecDeque;
use std::fmt;
use std::io::{self, Read, Write};
use std::net::Shutdown;
use std::os::unix::fs::{FileTypeExt, PermissionsExt};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::Path;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use crossbeam_channel::{bounded, Receiver, Sender};
use log::{debug, error, info, warn};

use crate::usb_sub::{UsbError, UsbResult, UvcConfig, UvcFormat, UvcFormatKind};

#[cfg(any(target_os = "linux", target_os = "android"))]
#[path = "uvc_v4l2.rs"]
mod uvc_v4l2;

#[cfg(not(any(target_os = "linux", target_os = "android")))]
mod uvc_v4l2 {
    use super::{RuntimeState, UsbResult};
    use std::sync::{Arc, Mutex};

    pub(super) struct UvcV4l2Backend;

    impl UvcV4l2Backend {
        pub(super) fn start(_state: &Arc<Mutex<RuntimeState>>) -> UsbResult<Self> {
            Ok(Self)
        }

        pub(super) fn poll(&mut self, _state: &Arc<Mutex<RuntimeState>>) {}

        pub(super) fn reset(&mut self, _state: &Arc<Mutex<RuntimeState>>) {}

        pub(super) fn stop(&mut self, _state: &Arc<Mutex<RuntimeState>>) {}
    }
}

use uvc_v4l2::UvcV4l2Backend;

const WORKER_SLEEP_MS: u64 = 20;
// Keep enough producer frames to prime every V4L2 MMAP buffer before the
// kernel stream starts. Older frames are still discarded in favour of latency.
const FRAME_QUEUE_CAPACITY: usize = 4;
const MAX_FRAME_BYTES: usize = 64 * 1024 * 1024;
const MAX_MESSAGE_SIZE: usize = 128 * 1024 * 1024;

const UVC_MAGIC: &[u8; 4] = b"HUVC";
const UVC_PROTOCOL_VERSION: u16 = 1;

const MSG_HELLO: u16 = 1;
const MSG_FORMAT: u16 = 2;
const MSG_STREAM_ON: u16 = 3;
const MSG_STREAM_OFF: u16 = 4;
const MSG_FRAME: u16 = 5;

const HEADER_MAGIC_SIZE: usize = 4;
const HEADER_VERSION_SIZE: usize = 2;
const HEADER_TYPE_SIZE: usize = 2;
const HEADER_PAYLOAD_SIZE: usize = 4;
const MESSAGE_HEADER_SIZE: usize =
    HEADER_MAGIC_SIZE + HEADER_VERSION_SIZE + HEADER_TYPE_SIZE + HEADER_PAYLOAD_SIZE;

const FRAME_HEADER_SIZE: usize = 8 + 8 + 4 + 4;

/// UVC Runtime 统一监听的 Unix Socket。
pub const UVC_SOCKET_PATH: &str = "/data/adb/usb_sub/uvc.sock";

#[derive(Debug, Clone)]
struct ProducerConnection {
    writer: Arc<Mutex<UnixStream>>,
    socket: Arc<Mutex<UnixStream>>,
}

#[derive(Debug, Clone)]
struct UvcActiveFormat {
    kind: UvcFormatKind,
    width: u32,
    height: u32,
    fps: u32,
}

impl UvcActiveFormat {
    fn fourcc(&self) -> u32 {
        match self.kind {
            UvcFormatKind::Mjpeg => fourcc_from_bytes(*b"MJPG"),
            UvcFormatKind::Yuyv => fourcc_from_bytes(*b"YUYV"),
        }
    }

    fn expected_data_size(&self) -> Option<usize> {
        match self.kind {
            UvcFormatKind::Mjpeg => None,
            UvcFormatKind::Yuyv => Some(
                (self.width as usize)
                    .saturating_mul(self.height as usize)
                    .saturating_mul(2),
            ),
        }
    }
}

impl fmt::Display for UvcActiveFormat {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{} {}x{}@{}fps",
            self.kind.as_str(),
            self.width,
            self.height,
            self.fps
        )
    }
}

#[derive(Debug, Clone)]
struct QueuedFrame {
    sequence: u64,
    timestamp_ns: u64,
    data_size: u32,
    flags: u32,
    data: Arc<[u8]>,
}

#[derive(Debug)]
struct RuntimeState {
    supported_formats: Vec<UvcFormat>,
    negotiated_format: Option<UvcActiveFormat>,
    stream_on: bool,
    pending_frames: VecDeque<QueuedFrame>,
    producer: Option<ProducerConnection>,
}

impl RuntimeState {
    fn new(config: &UvcConfig) -> Self {
        let negotiated_format = default_negotiated_format(config);
        Self {
            supported_formats: config.formats.clone(),
            negotiated_format,
            stream_on: false,
            pending_frames: VecDeque::with_capacity(FRAME_QUEUE_CAPACITY),
            producer: None,
        }
    }

    fn apply_config(&mut self, config: UvcConfig) {
        self.supported_formats = config.formats.clone();
        let next = default_negotiated_format(&config);
        self.negotiated_format = if self
            .negotiated_format
            .as_ref()
            .is_some_and(|current| is_format_supported(current, &config.formats))
        {
            self.negotiated_format.clone()
        } else {
            next
        };
        self.stream_on = false;
        self.pending_frames.clear();
    }

    fn pending_count(&self) -> usize {
        self.pending_frames.len()
    }

    fn clear_producer(&mut self) {
        self.producer = None;
        self.pending_frames.clear();
        self.stream_on = false;
    }

    fn shutdown_producer(&mut self) {
        if let Some(producer) = &self.producer {
            if let Ok(socket) = producer.socket.lock() {
                let _ = socket.shutdown(Shutdown::Both);
            }
        }
        self.clear_producer();
    }

    fn queue_frame(&mut self, frame: QueuedFrame) {
        if self.pending_frames.len() >= FRAME_QUEUE_CAPACITY {
            let _ = self.pending_frames.pop_front();
            warn!("UVC runtime pending queue 满，丢弃最旧帧");
        }
        self.pending_frames.push_back(frame);
    }
}

struct UvcMessageHeader {
    message_type: u16,
    payload_size: u32,
}

#[derive(Debug, Clone)]
struct UvcFrameHeader {
    sequence: u64,
    timestamp_ns: u64,
    data_size: u32,
    flags: u32,
}

enum RuntimeCommand {
    Reconfigure(UvcConfig),
    SetStream(bool),
    SetFormat(UvcActiveFormat),
    Shutdown,
}

/// UVC Runtime 生命周期控制句柄。
#[derive(Debug)]
pub struct UsbUvcRuntime {
    command_tx: Option<Sender<RuntimeCommand>>,
    worker: Option<thread::JoinHandle<()>>,
    state: Option<Arc<Mutex<RuntimeState>>>,
}

impl UsbUvcRuntime {
    pub fn start(config: Option<&UvcConfig>) -> UsbResult<Self> {
        let Some(config) = config else {
            return Ok(Self::disabled());
        };
        prepare_socket(UVC_SOCKET_PATH)?;

        let state = Arc::new(Mutex::new(RuntimeState::new(config)));
        let (command_tx, command_rx) = bounded::<RuntimeCommand>(32);
        let (startup_tx, startup_rx) = bounded::<Result<(), String>>(1);
        let runtime_state = Arc::clone(&state);
        let socket_path = UVC_SOCKET_PATH.to_string();
        let handle = thread::Builder::new()
            .name("hyperusbd-uvc-runtime".into())
            .spawn(move || run_runtime(socket_path, runtime_state, command_rx, startup_tx))
            .map_err(|error| {
                UsbError::Unavailable(format!("启动 UVC Runtime 线程失败：{error}"))
            })?;
        match startup_rx.recv_timeout(Duration::from_secs(5)) {
            Ok(Ok(())) => {}
            Ok(Err(error)) => {
                let _ = command_tx.send(RuntimeCommand::Shutdown);
                let _ = handle.join();
                return Err(UsbError::Unavailable(error));
            }
            Err(error) => {
                let _ = command_tx.send(RuntimeCommand::Shutdown);
                let _ = handle.join();
                return Err(UsbError::Unavailable(format!(
                    "等待 UVC Runtime 启动确认超时：{error}"
                )));
            }
        }
        Ok(Self {
            command_tx: Some(command_tx),
            worker: Some(handle),
            state: Some(state),
        })
    }

    pub fn is_active(&self) -> bool {
        self.command_tx.is_some()
    }

    pub fn reconfigure(&self, config: &UvcConfig) -> UsbResult<()> {
        let command_tx = self
            .command_tx
            .as_ref()
            .ok_or_else(|| UsbError::Unavailable("UVC Runtime 当前未启用".into()))?;
        command_tx
            .send(RuntimeCommand::Reconfigure(config.clone()))
            .map_err(|_| UsbError::Unavailable("UVC Runtime 已退出".into()))?;
        Ok(())
    }

    pub fn set_streaming(&self, enabled: bool) -> UsbResult<()> {
        let command_tx = self
            .command_tx
            .as_ref()
            .ok_or_else(|| UsbError::Unavailable("UVC Runtime 当前未启用".into()))?;
        command_tx
            .send(RuntimeCommand::SetStream(enabled))
            .map_err(|_| UsbError::Unavailable("UVC Runtime 已退出".into()))?;
        Ok(())
    }

    pub fn notify_format(
        &self,
        format: UvcFormatKind,
        width: u32,
        height: u32,
        fps: u32,
    ) -> UsbResult<()> {
        let command_tx = self
            .command_tx
            .as_ref()
            .ok_or_else(|| UsbError::Unavailable("UVC Runtime 当前未启用".into()))?;
        command_tx
            .send(RuntimeCommand::SetFormat(UvcActiveFormat {
                kind: format,
                width,
                height,
                fps,
            }))
            .map_err(|_| UsbError::Unavailable("UVC Runtime 已退出".into()))?;
        Ok(())
    }

    pub fn stop(&mut self) -> UsbResult<()> {
        if let Some(tx) = self.command_tx.take() {
            let _ = tx.send(RuntimeCommand::Shutdown);
        }
        if let Some(handle) = self.worker.take() {
            handle
                .join()
                .map_err(|_| UsbError::Unavailable("UVC Runtime 线程退出异常".into()))?;
        }
        self.state = None;
        Ok(())
    }

    pub fn pending_queue_len(&self) -> usize {
        self.state
            .as_ref()
            .and_then(|state| state.lock().ok())
            .map_or(0, |state| state.pending_count())
    }

    fn disabled() -> Self {
        Self {
            command_tx: None,
            worker: None,
            state: None,
        }
    }
}

impl Drop for UsbUvcRuntime {
    fn drop(&mut self) {
        if self.state.is_some() {
            let _ = self.stop();
        }
    }
}

fn run_runtime(
    socket_path: String,
    state: Arc<Mutex<RuntimeState>>,
    command_rx: Receiver<RuntimeCommand>,
    startup_tx: Sender<Result<(), String>>,
) {
    let listener = match bind_socket(&socket_path) {
        Ok(listener) => listener,
        Err(error) => {
            error!("UVC Runtime 监听 Socket 失败：{error}");
            let _ = startup_tx.send(Err(format!("UVC Runtime 监听 Socket 失败：{error}")));
            let _ = cleanup_socket(&socket_path);
            return;
        }
    };

    let mut v4l2_backend = match UvcV4l2Backend::start(&state) {
        Ok(backend) => backend,
        Err(error) => {
            error!("UVC V4L2 backend 启动失败：{error}");
            let _ = startup_tx.send(Err(format!("UVC V4L2 backend 启动失败：{error}")));
            let _ = cleanup_socket(&socket_path);
            return;
        }
    };
    let _ = startup_tx.send(Ok(()));

    let mut shutting_down = false;
    let mut producer_thread: Option<thread::JoinHandle<()>> = None;
    while !shutting_down {
        loop {
            match command_rx.try_recv() {
                Ok(RuntimeCommand::Reconfigure(config)) => {
                    let mut runtime = state.lock().unwrap();
                    runtime.apply_config(config);
                    if let Some(writer) = &runtime.producer {
                        if let Some(format) = &runtime.negotiated_format {
                            let _ = send_format(writer, format.clone());
                        }
                        let _ = send_stream(writer, false);
                    }
                    drop(runtime);
                    v4l2_backend.reset(&state);
                }
                Ok(RuntimeCommand::SetStream(enabled)) => {
                    let mut runtime = state.lock().unwrap();
                    runtime.stream_on = enabled;
                    if let Some(writer) = &runtime.producer {
                        let _ = send_stream(writer, enabled);
                    }
                }
                Ok(RuntimeCommand::SetFormat(format)) => {
                    let mut runtime = state.lock().unwrap();
                    runtime.negotiated_format = Some(format.clone());
                    let _ = runtime
                        .producer
                        .as_ref()
                        .map(|writer| send_format(writer, format));
                }
                Ok(RuntimeCommand::Shutdown) => {
                    shutting_down = true;
                }
                Err(_) => break,
            }
        }
        if shutting_down {
            break;
        }

        v4l2_backend.poll(&state);

        match listener.accept() {
            Ok((stream, _)) => {
                let has_producer = state
                    .lock()
                    .map(|state| state.producer.is_some())
                    .unwrap_or(false);
                if has_producer {
                    info!("已有 UVC producer 连接中，拒绝额外连接");
                    drop(stream);
                    continue;
                }

                if let Some(handle) = producer_thread.take() {
                    join_producer_thread(handle);
                }
                match attach_producer(stream, &state) {
                    Ok(handle) => producer_thread = Some(handle),
                    Err(error) => warn!("接受 UVC producer 连接失败：{error}"),
                }
            }
            Err(error) if error.kind() == io::ErrorKind::WouldBlock => {
                thread::sleep(Duration::from_millis(WORKER_SLEEP_MS));
            }
            Err(error) => {
                warn!("UVC Runtime accept 出错：{error}");
                thread::sleep(Duration::from_millis(WORKER_SLEEP_MS));
            }
        }
    }

    stop_producer(&state, &mut producer_thread);
    v4l2_backend.stop(&state);
    state.lock().unwrap().clear_producer();
    info!("UVC Runtime 退出：{}", socket_path);
    let _ = cleanup_socket(&socket_path);
}

fn stop_producer(
    state: &Arc<Mutex<RuntimeState>>,
    producer_thread: &mut Option<thread::JoinHandle<()>>,
) {
    // shutdown(Both) is the stop signal for read_exact in the producer thread.
    state.lock().unwrap().shutdown_producer();
    if let Some(handle) = producer_thread.take() {
        join_producer_thread(handle);
    }
}

fn join_producer_thread(handle: thread::JoinHandle<()>) {
    if handle.join().is_err() {
        warn!("UVC producer 线程退出异常");
    }
}

fn bind_socket(path: &str) -> io::Result<UnixListener> {
    let socket = UnixListener::bind(path)?;
    socket.set_nonblocking(true)?;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600))
        .map_err(io::Error::other)?;
    Ok(socket)
}

fn attach_producer(
    stream: UnixStream,
    state: &Arc<Mutex<RuntimeState>>,
) -> io::Result<thread::JoinHandle<()>> {
    let mut read_stream = stream;
    let write_stream = read_stream.try_clone()?;
    let control_stream = read_stream.try_clone()?;
    let socket = Arc::new(Mutex::new(control_stream));
    let writer = ProducerConnection {
        writer: Arc::new(Mutex::new(write_stream)),
        socket: Arc::clone(&socket),
    };
    {
        let mut runtime = state.lock().unwrap();
        runtime.producer = Some(writer.clone());
    }

    let thread_state = Arc::clone(state);
    let connection_socket = Arc::clone(&socket);
    let handle = match thread::Builder::new()
        .name("hyperusbd-uvc-producer".into())
        .spawn(move || {
            if let Err(error) = run_producer_session(&mut read_stream, &thread_state) {
                if error.kind() == io::ErrorKind::UnexpectedEof {
                    debug!("UVC producer 正常断开");
                } else {
                    warn!("UVC producer 会话异常：{error}");
                }
            }
            let mut runtime = thread_state.lock().unwrap();
            let is_current = runtime
                .producer
                .as_ref()
                .map(|producer| Arc::ptr_eq(&producer.socket, &connection_socket))
                .unwrap_or(false);
            if is_current {
                runtime.clear_producer();
            }
            debug!("UVC producer 已断开，清空 pending frames");
        }) {
        Ok(handle) => handle,
        Err(error) => {
            state.lock().unwrap().clear_producer();
            return Err(error);
        }
    };

    Ok(handle)
}

fn run_producer_session(
    stream: &mut UnixStream,
    state: &Arc<Mutex<RuntimeState>>,
) -> io::Result<()> {
    let mut greeted = false;
    loop {
        let header = read_message_header(stream)?;
        let payload = read_payload(stream, header.payload_size)?;

        match header.message_type {
            MSG_HELLO => {
                if greeted {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "Producer HELLO 重复",
                    ));
                }
                greeted = true;
                send_hello_ack(state)?;
            }
            MSG_FRAME => {
                if !greeted {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "FRAME 之前缺少 HELLO",
                    ));
                }
                handle_frame_payload(state, &payload)?;
            }
            MSG_FORMAT | MSG_STREAM_ON | MSG_STREAM_OFF => {
                if !greeted {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "收到 Core→Producer 消息",
                    ));
                }
                warn!(
                    "收到 Producer 端不应发送的 UVC 消息：type={}",
                    header.message_type
                );
            }
            other => {
                warn!("未支持的 UVC 消息类型：{other}");
            }
        }
    }
}

fn send_hello_ack(state: &Arc<Mutex<RuntimeState>>) -> io::Result<()> {
    let runtime = state.lock().unwrap();
    let writer = runtime
        .producer
        .as_ref()
        .ok_or_else(|| io::Error::other("producer writer missing"))?;
    if let Some(format) = runtime.negotiated_format.clone() {
        send_format(writer, format)?;
    }
    send_stream(writer, runtime.stream_on)?;
    Ok(())
}

fn handle_frame_payload(state: &Arc<Mutex<RuntimeState>>, payload: &[u8]) -> io::Result<()> {
    if payload.len() < FRAME_HEADER_SIZE {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "FRAME payload 不足",
        ));
    }

    let frame = parse_frame_header(payload)?;
    let data = &payload[FRAME_HEADER_SIZE..];
    if data.len() != frame.data_size as usize {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "FRAME dataSize 与实际 payload 不匹配",
        ));
    }

    let mut runtime = state.lock().unwrap();
    let Some(expected_format) = &runtime.negotiated_format else {
        warn!("未协商 UVC format，丢弃完整帧");
        return Ok(());
    };
    if !runtime.stream_on {
        warn!("STREAM 未开启，丢弃完整帧 seq={}", frame.sequence);
        return Ok(());
    }
    if let Some(expected_bytes) = expected_format.expected_data_size() {
        if expected_bytes != data.len() {
            warn!(
                "YUYV 帧尺寸不匹配：expected={expected_bytes} actual={}",
                data.len()
            );
            return Ok(());
        }
    } else if data.is_empty() {
        warn!("MJPEG 帧为空，丢弃 seq={}", frame.sequence);
        return Ok(());
    }

    if data.len() > MAX_FRAME_BYTES {
        warn!("UVC 帧过大，丢弃 seq={}", frame.sequence);
        return Ok(());
    }

    runtime.queue_frame(QueuedFrame {
        sequence: frame.sequence,
        timestamp_ns: frame.timestamp_ns,
        data_size: frame.data_size,
        flags: frame.flags,
        data: Arc::from(data),
    });
    debug!(
        "UVC Runtime 缓存帧 seq={} timestamp={}ns flags=0x{:08x} size={}",
        frame.sequence, frame.timestamp_ns, frame.flags, frame.data_size
    );
    Ok(())
}

fn parse_frame_header(payload: &[u8]) -> io::Result<UvcFrameHeader> {
    if payload.len() < FRAME_HEADER_SIZE {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "frame header 不足 24 字节",
        ));
    }
    Ok(UvcFrameHeader {
        sequence: u64::from_le_bytes(
            payload[0..8]
                .try_into()
                .map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "sequence 无法解析"))?,
        ),
        timestamp_ns: u64::from_le_bytes(
            payload[8..16]
                .try_into()
                .map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "timestamp 无法解析"))?,
        ),
        data_size: u32::from_le_bytes(
            payload[16..20]
                .try_into()
                .map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "dataSize 无法解析"))?,
        ),
        flags: u32::from_le_bytes(
            payload[20..24]
                .try_into()
                .map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "flags 无法解析"))?,
        ),
    })
}

fn send_format(writer: &ProducerConnection, format: UvcActiveFormat) -> io::Result<()> {
    let payload = format_payload(&format);
    write_message(&writer.writer, MSG_FORMAT, &payload)
}

fn send_stream(writer: &ProducerConnection, enabled: bool) -> io::Result<()> {
    let message_type = if enabled {
        MSG_STREAM_ON
    } else {
        MSG_STREAM_OFF
    };
    write_message(&writer.writer, message_type, &[])
}

fn format_payload(format: &UvcActiveFormat) -> Vec<u8> {
    let mut payload = Vec::with_capacity(16);
    payload.extend_from_slice(&format.fourcc().to_le_bytes());
    payload.extend_from_slice(&format.width.to_le_bytes());
    payload.extend_from_slice(&format.height.to_le_bytes());
    payload.extend_from_slice(&format.fps.to_le_bytes());
    payload
}

fn write_message(
    writer: &Arc<Mutex<UnixStream>>,
    message_type: u16,
    payload: &[u8],
) -> io::Result<()> {
    let mut stream = writer.lock().unwrap();
    let payload_size =
        u32::try_from(payload.len()).map_err(|_| io::Error::other("payload size overflow"))?;
    let mut buffer = [0u8; MESSAGE_HEADER_SIZE];
    buffer[0..4].copy_from_slice(UVC_MAGIC);
    buffer[4..6].copy_from_slice(&UVC_PROTOCOL_VERSION.to_le_bytes());
    buffer[6..8].copy_from_slice(&message_type.to_le_bytes());
    buffer[8..12].copy_from_slice(&payload_size.to_le_bytes());
    stream.write_all(&buffer)?;
    stream.write_all(payload)?;
    stream.flush()?;
    Ok(())
}

fn read_message_header(stream: &mut UnixStream) -> io::Result<UvcMessageHeader> {
    let mut header_bytes = [0u8; MESSAGE_HEADER_SIZE];
    stream.read_exact(&mut header_bytes)?;
    if &header_bytes[0..4] != UVC_MAGIC {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "UVC magic 不匹配",
        ));
    }
    let version = u16::from_le_bytes([header_bytes[4], header_bytes[5]]);
    if version != UVC_PROTOCOL_VERSION {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "UVC protocol version 不匹配",
        ));
    }
    Ok(UvcMessageHeader {
        message_type: u16::from_le_bytes([header_bytes[6], header_bytes[7]]),
        payload_size: u32::from_le_bytes([
            header_bytes[8],
            header_bytes[9],
            header_bytes[10],
            header_bytes[11],
        ]),
    })
}

fn read_payload(stream: &mut UnixStream, payload_size: u32) -> io::Result<Vec<u8>> {
    let payload_size = usize::try_from(payload_size)
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "payload size overflow"))?;
    if payload_size > MAX_MESSAGE_SIZE {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "frame payload 过大",
        ));
    }
    let mut payload = vec![0u8; payload_size];
    if payload_size > 0 {
        stream.read_exact(&mut payload)?;
    }
    Ok(payload)
}

fn prepare_socket(path: &str) -> UsbResult<()> {
    let path = Path::new(path);
    if path.exists() {
        if path.is_dir() {
            return Err(UsbError::Unavailable(format!(
                "UVC Socket 路径被目录占用：{}",
                path.display()
            )));
        }
        std::fs::remove_file(path)
            .map_err(|error| UsbError::Unavailable(format!("无法删除旧 UVC Socket：{error}")))?;
    }
    if let Some(parent) = path.parent() {
        if !parent.exists() {
            return Err(UsbError::Unavailable(format!(
                "WORK 目录不存在，无法创建 UVC Runtime：{}",
                parent.display()
            )));
        }
    }
    Ok(())
}

fn cleanup_socket(path: &str) -> io::Result<()> {
    let path = Path::new(path);
    if path.exists() {
        match path.symlink_metadata() {
            Ok(metadata) if metadata.file_type().is_socket() => {
                std::fs::remove_file(path)?;
            }
            Ok(_) => {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    "UVC Socket 路径被非 Socket 文件占用",
                ));
            }
            Err(_) => {}
        }
    }
    Ok(())
}

fn is_format_supported(format: &UvcActiveFormat, supported: &[UvcFormat]) -> bool {
    supported.iter().any(|entry| {
        entry.format == format.kind
            && entry.frames.iter().any(|frame| {
                frame.width == format.width
                    && frame.height == format.height
                    && frame.fps.contains(&format.fps)
            })
    })
}

fn default_negotiated_format(config: &UvcConfig) -> Option<UvcActiveFormat> {
    config.formats.first().and_then(|format| {
        format.frames.first().map(|frame| UvcActiveFormat {
            kind: format.format,
            width: frame.width,
            height: frame.height,
            fps: frame.fps.first().copied().unwrap_or(0),
        })
    })
}

const fn fourcc_from_bytes(bytes: [u8; 4]) -> u32 {
    u32::from_le_bytes(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::mpsc;

    #[test]
    fn frame_size_guard_handles_yuyv_and_mjpeg_rules() {
        let format_mjpeg = UvcActiveFormat {
            kind: UvcFormatKind::Mjpeg,
            width: 1280,
            height: 720,
            fps: 30,
        };
        assert!(format_mjpeg.expected_data_size().is_none());

        let format_yuyv = UvcActiveFormat {
            kind: UvcFormatKind::Yuyv,
            width: 2,
            height: 1,
            fps: 30,
        };
        assert_eq!(format_yuyv.expected_data_size(), Some(4));
    }

    #[test]
    fn shutdown_producer_unblocks_a_blocked_reader() {
        let config = UvcConfig {
            formats: vec![UvcFormat {
                format: UvcFormatKind::Mjpeg,
                frames: vec![crate::usb_sub::UvcFrame {
                    width: 640,
                    height: 480,
                    fps: vec![30],
                }],
            }],
        };
        let mut state = RuntimeState::new(&config);
        let (mut reader, peer) = UnixStream::pair().unwrap();
        let control = peer.try_clone().unwrap();
        state.producer = Some(ProducerConnection {
            writer: Arc::new(Mutex::new(peer.try_clone().unwrap())),
            socket: Arc::new(Mutex::new(control)),
        });
        let (done_tx, done_rx) = mpsc::channel();
        let reader_thread = thread::spawn(move || {
            let mut byte = [0u8; 1];
            let result = reader.read_exact(&mut byte);
            done_tx.send(result.is_err()).unwrap();
        });

        state.shutdown_producer();
        assert!(done_rx.recv_timeout(Duration::from_secs(1)).unwrap());
        reader_thread.join().unwrap();
    }
}

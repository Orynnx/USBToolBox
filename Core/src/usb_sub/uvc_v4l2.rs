//! Linux UVC Gadget 的 V4L2 控制与视频输出后端。
//!
//! `f_uvc` 绑定后会创建一个 V4L2 output 节点。这个模块负责两件事：
//!
//! - 通过 V4L2 event 完成 UVC Probe/Commit 和 Stream ON/OFF；
//! - 把 `uvc_runtime` 收到的完整视频帧写入 MMAP output buffer。
//!
//! 这里故意只保留内核 UAPI 所需的最小结构，不把 V4L2/UVC 细节暴露给 Producer。

use std::collections::VecDeque;
use std::ffi::CString;
use std::fs;
use std::io;
use std::mem::{size_of, zeroed};
use std::os::fd::RawFd;
use std::path::{Path, PathBuf};
use std::ptr;
use std::time::{Duration, Instant};

use log::{debug, info, warn};

use super::{send_format, send_stream, RuntimeState, UvcActiveFormat, UvcFormat, UvcFormatKind};
use crate::usb_sub::{UsbError, UsbResult};

const VIDEO_OUTPUT: u32 = 2;
const MEMORY_MMAP: u32 = 1;
const FIELD_NONE: u32 = 1;
const CAP_VIDEO_OUTPUT: u32 = 0x0000_0002;
const CAP_STREAMING: u32 = 0x0400_0000;
const BUFFER_COUNT: u32 = 4;
const V4L2_EVENT_PRIVATE_START: u32 = 0x0800_0000;
const UVC_EVENT_STREAMON: u32 = V4L2_EVENT_PRIVATE_START + 2;
const UVC_EVENT_STREAMOFF: u32 = V4L2_EVENT_PRIVATE_START + 3;
const UVC_EVENT_SETUP: u32 = V4L2_EVENT_PRIVATE_START + 4;
const UVC_EVENT_DATA: u32 = V4L2_EVENT_PRIVATE_START + 5;

const UVC_SET_CUR: u8 = 0x01;
const UVC_GET_CUR: u8 = 0x81;
const UVC_GET_MIN: u8 = 0x82;
const UVC_GET_MAX: u8 = 0x83;
const UVC_GET_RES: u8 = 0x84;
const UVC_GET_LEN: u8 = 0x85;
const UVC_GET_INFO: u8 = 0x86;
const UVC_GET_DEF: u8 = 0x87;
const UVC_VS_PROBE_CONTROL: u8 = 0x01;
const UVC_VS_COMMIT_CONTROL: u8 = 0x02;
const UVC_STREAMING_CONTROL_SIZE: usize = 34;
const UVC_DEFAULT_PAYLOAD_SIZE: u32 = 3072;
const UVC_SETUP_STALL: i32 = -51; // -EL2HLT, used by the kernel reference application.
const UVC_FUNCTION_NAME: &str = "uvc.hyperusb";
const CONFIGFS_GADGET_ROOT: &str = "/config/usb_gadget";
const USB_TYPE_MASK: u8 = 0x60;
const USB_TYPE_CLASS: u8 = 0x20;
const USB_RECIPIENT_MASK: u8 = 0x1f;
const USB_RECIPIENT_INTERFACE: u8 = 0x01;

const VIDIOC_QUERYCAP: libc::c_int = ioc_read(b'V', 0, size_of::<V4l2Capability>()) as _;
const VIDIOC_S_FMT: libc::c_int = ioc_read_write(b'V', 5, size_of::<V4l2Format>()) as _;
const VIDIOC_REQBUFS: libc::c_int = ioc_read_write(b'V', 8, size_of::<V4l2RequestBuffers>()) as _;
const VIDIOC_QUERYBUF: libc::c_int = ioc_read_write(b'V', 9, size_of::<V4l2Buffer>()) as _;
const VIDIOC_QBUF: libc::c_int = ioc_read_write(b'V', 15, size_of::<V4l2Buffer>()) as _;
const VIDIOC_DQBUF: libc::c_int = ioc_read_write(b'V', 17, size_of::<V4l2Buffer>()) as _;
const VIDIOC_STREAMON: libc::c_int = ioc_write(b'V', 18, size_of::<u32>()) as _;
const VIDIOC_STREAMOFF: libc::c_int = ioc_write(b'V', 19, size_of::<u32>()) as _;
const VIDIOC_S_PARM: libc::c_int = ioc_read_write(b'V', 22, size_of::<V4l2StreamParm>()) as _;
const VIDIOC_DQEVENT: libc::c_int = ioc_read(b'V', 89, size_of::<V4l2Event>()) as _;
const VIDIOC_SUBSCRIBE_EVENT: libc::c_int =
    ioc_write(b'V', 90, size_of::<V4l2EventSubscription>()) as _;
const UVCIOC_SEND_RESPONSE: libc::c_int = ioc_write(b'U', 1, size_of::<UvcRequestData>()) as _;

#[repr(C)]
#[derive(Clone, Copy)]
struct V4l2Capability {
    driver: [u8; 16],
    card: [u8; 32],
    bus_info: [u8; 32],
    version: u32,
    capabilities: u32,
    device_caps: u32,
    reserved: [u32; 3],
}

#[repr(C)]
#[derive(Clone, Copy)]
struct V4l2RequestBuffers {
    count: u32,
    type_: u32,
    memory: u32,
    capabilities: u32,
    flags: u8,
    reserved: [u8; 3],
}

#[repr(C)]
#[derive(Clone, Copy)]
struct V4l2Timecode {
    type_: u32,
    flags: u32,
    frames: u8,
    seconds: u8,
    minutes: u8,
    hours: u8,
    userbits: [u8; 4],
}

#[repr(C)]
union V4l2BufferMemory {
    offset: u32,
    userptr: usize,
    fd: i32,
}

#[repr(C)]
struct V4l2Buffer {
    index: u32,
    type_: u32,
    bytesused: u32,
    flags: u32,
    field: u32,
    timestamp: libc::timeval,
    timecode: V4l2Timecode,
    sequence: u32,
    memory: u32,
    m: V4l2BufferMemory,
    length: u32,
    reserved2: u32,
    request_fd: i32,
}

#[repr(C)]
#[derive(Clone, Copy)]
struct V4l2Format {
    type_: u32,
    // The v4l2_format union has 8-byte alignment on ARM64. This padding is
    // part of the ioctl ABI: omitting it changes VIDIOC_S_FMT's encoded size.
    _union_alignment: u32,
    raw: [u8; 200],
}

#[repr(C)]
#[derive(Clone, Copy)]
struct V4l2StreamParm {
    type_: u32,
    raw: [u8; 200],
}

#[repr(C)]
#[derive(Clone, Copy)]
struct V4l2EventSubscription {
    type_: u32,
    id: u32,
    flags: u32,
    reserved: [u32; 5],
}

#[repr(C)]
#[derive(Clone, Copy)]
struct V4l2Event {
    type_: u32,
    // `v4l2_event.u` contains `v4l2_event_ctrl`, whose value64 member gives
    // the C union 8-byte alignment on ARM64. Without this explicit padding,
    // `u.data` is read four bytes early and VIDIOC_DQEVENT gets the wrong
    // ioctl structure size (128 rather than 136 bytes).
    _union_alignment: u32,
    data: [u8; 64],
    pending: u32,
    sequence: u32,
    timestamp: libc::timespec,
    id: u32,
    reserved: [u32; 8],
}

const _: () = assert!(size_of::<V4l2Capability>() == 104);
const _: () = assert!(size_of::<V4l2RequestBuffers>() == 20);
const _: () = assert!(size_of::<V4l2Buffer>() == 88);
const _: () = assert!(size_of::<V4l2Format>() == 208);
const _: () = assert!(size_of::<V4l2StreamParm>() == 204);
const _: () = assert!(size_of::<V4l2Event>() == 136);

#[repr(C)]
#[derive(Clone, Copy)]
struct UvcRequestData {
    length: i32,
    data: [u8; 60],
}

struct V4l2Device {
    fd: RawFd,
    path: PathBuf,
}

impl Drop for V4l2Device {
    fn drop(&mut self) {
        // SAFETY: fd was returned by open() and is owned by this value.
        unsafe {
            libc::close(self.fd);
        }
    }
}

struct MappedBuffer {
    address: *mut u8,
    length: usize,
}

impl Drop for MappedBuffer {
    fn drop(&mut self) {
        if !self.address.is_null() && self.length != 0 {
            // SAFETY: address/length are the exact pair returned by mmap().
            unsafe {
                libc::munmap(self.address.cast(), self.length);
            }
        }
    }
}

struct SelectedMode {
    format_index: u8,
    frame_index: u8,
    active: UvcActiveFormat,
}

#[derive(Debug, Clone, Copy)]
struct UvcInterfaces {
    control: u8,
    streaming: u8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum StreamState {
    Idle,
    /// The producer has been notified and buffers are waiting for the first frame.
    Priming,
    /// Every MMAP buffer was queued before VIDIOC_STREAMON.
    Running,
}

/// V4L2 backend owned by the Runtime worker thread.
pub(super) struct UvcV4l2Backend {
    device: Option<V4l2Device>,
    buffers: Vec<MappedBuffer>,
    available_buffers: VecDeque<usize>,
    stream_state: StreamState,
    last_frame: Option<super::QueuedFrame>,
    probe: [u8; UVC_STREAMING_CONTROL_SIZE],
    commit: [u8; UVC_STREAMING_CONTROL_SIZE],
    pending_control: Option<u8>,
    interfaces: Option<UvcInterfaces>,
    next_open_attempt: Instant,
}

impl UvcV4l2Backend {
    pub(super) fn start(state: &std::sync::Arc<std::sync::Mutex<RuntimeState>>) -> UsbResult<Self> {
        let mut backend = Self {
            device: None,
            buffers: Vec::new(),
            available_buffers: VecDeque::new(),
            stream_state: StreamState::Idle,
            last_frame: None,
            probe: [0; UVC_STREAMING_CONTROL_SIZE],
            commit: [0; UVC_STREAMING_CONTROL_SIZE],
            pending_control: None,
            interfaces: None,
            next_open_attempt: Instant::now(),
        };
        if let Err(error) = backend.open_device(state) {
            debug!("UVC V4L2 video node 尚未就绪，将在后台重试：{error}");
            backend.next_open_attempt = Instant::now() + Duration::from_millis(250);
        }
        Ok(backend)
    }

    pub(super) fn poll(&mut self, state: &std::sync::Arc<std::sync::Mutex<RuntimeState>>) {
        if self.device.is_none() {
            if Instant::now() < self.next_open_attempt {
                return;
            }
            self.next_open_attempt = Instant::now() + Duration::from_millis(250);
            if let Err(error) = self.open_device(state) {
                debug!("UVC V4L2 video node 尚未就绪：{error}");
            }
            return;
        }

        if let Err(error) = self.drain_events(state) {
            warn!("UVC V4L2 event 处理失败：{error}");
            self.disconnect(state);
            return;
        }
        let stream_result = match self.stream_state {
            StreamState::Idle => Ok(()),
            StreamState::Priming => self.prime_stream(state),
            StreamState::Running => self
                .reclaim_buffers()
                .and_then(|()| self.submit_frames(state)),
        };
        if let Err(error) = stream_result {
            warn!("UVC V4L2 buffer 流程失败：{error}");
            self.disconnect(state);
        }
    }

    pub(super) fn reset(&mut self, state: &std::sync::Arc<std::sync::Mutex<RuntimeState>>) {
        self.stop_stream(state);
        self.buffers.clear();
        self.available_buffers.clear();
        self.device.take();
        self.interfaces = None;
        self.next_open_attempt = Instant::now();
    }

    pub(super) fn stop(&mut self, state: &std::sync::Arc<std::sync::Mutex<RuntimeState>>) {
        self.stop_stream(state);
        self.buffers.clear();
        self.available_buffers.clear();
        self.device.take();
        self.interfaces = None;
    }

    fn open_device(
        &mut self,
        state: &std::sync::Arc<std::sync::Mutex<RuntimeState>>,
    ) -> UsbResult<()> {
        let interfaces = find_uvc_interfaces()?;
        let device = find_uvc_video_device()?;
        subscribe_events(device.fd)?;
        self.device = Some(device);
        self.interfaces = Some(interfaces);
        let default = state
            .lock()
            .map_err(|_| UsbError::Unavailable("UVC Runtime 状态锁已损坏".into()))?
            .negotiated_format
            .clone();
        if let Some(format) = default {
            let _ = self.set_video_format(&format);
            let _ = self.set_frame_rate(format.fps);
            self.probe = control_for_active(&format);
            self.commit = self.probe;
        }
        info!(
            "UVC V4L2 backend attached to {} (VC={}, VS={})",
            self.device_path().display(),
            interfaces.control,
            interfaces.streaming,
        );
        Ok(())
    }

    fn device_path(&self) -> &Path {
        self.device
            .as_ref()
            .map(|device| device.path.as_path())
            .unwrap_or_else(|| Path::new("/dev/video?"))
    }

    fn drain_events(
        &mut self,
        state: &std::sync::Arc<std::sync::Mutex<RuntimeState>>,
    ) -> io::Result<()> {
        loop {
            let mut event: V4l2Event = unsafe { zeroed() };
            match self.ioctl(VIDIOC_DQEVENT, &mut event) {
                Ok(()) => self.handle_event(&event, state)?,
                // Xiaomi's g_uvc implementation reports ENOENT while its
                // event queue is empty. This does not mean that the video
                // node disappeared, so do not tear down a healthy stream.
                Err(error) if is_no_event_available(&error) => break,
                Err(error) => return Err(error),
            }
        }
        Ok(())
    }

    fn handle_event(
        &mut self,
        event: &V4l2Event,
        state: &std::sync::Arc<std::sync::Mutex<RuntimeState>>,
    ) -> io::Result<()> {
        match event.type_ {
            UVC_EVENT_SETUP => self.handle_setup(event, state),
            UVC_EVENT_DATA => self.handle_data(event, state),
            UVC_EVENT_STREAMON => self.start_stream(state),
            UVC_EVENT_STREAMOFF => {
                self.stop_stream(state);
                Ok(())
            }
            _ => Ok(()),
        }
    }

    fn handle_setup(
        &mut self,
        event: &V4l2Event,
        state: &std::sync::Arc<std::sync::Mutex<RuntimeState>>,
    ) -> io::Result<()> {
        let request = &event.data[..8];
        let request_type = request[0];
        let request_code = request[1];
        let value = u16::from_le_bytes([request[2], request[3]]);
        let index = u16::from_le_bytes([request[4], request[5]]);
        let length = u16::from_le_bytes([request[6], request[7]]) as usize;
        let selector = (value >> 8) as u8;
        let interface = index as u8;

        // Every SETUP starts a new control transaction. Keeping a stale pending selector
        // would make an unrelated control-interface DATA packet overwrite Probe/Commit.
        self.pending_control = None;
        let mut response = UvcRequestData {
            length: UVC_SETUP_STALL,
            data: [0; 60],
        };
        let interfaces = self.interfaces;
        info!(
            "UVC setup: type=0x{request_type:02x} request=0x{request_code:02x} selector=0x{selector:02x} interface={interface} length={length}"
        );
        if (request_type & USB_TYPE_MASK) == USB_TYPE_CLASS
            && (request_type & USB_RECIPIENT_MASK) == USB_RECIPIENT_INTERFACE
        {
            match interfaces {
                Some(interfaces) if interface == interfaces.control => {
                    // We intentionally advertise no VC controls. Keep this conservative
                    // response for hosts that query a generic control capability anyway.
                    response.data[0] = 0x03;
                    response.length = min_response_length(length, 60);
                }
                Some(interfaces) if interface == interfaces.streaming => {
                    if request_code == UVC_SET_CUR
                        && (selector == UVC_VS_PROBE_CONTROL || selector == UVC_VS_COMMIT_CONTROL)
                    {
                        self.pending_control = Some(selector);
                        // For SET_CUR OUT this tells f_uvc exactly how many bytes will
                        // arrive in the matching UVC_EVENT_DATA.
                        response.length = UVC_STREAMING_CONTROL_SIZE as i32;
                    } else if matches!(
                        request_code,
                        UVC_GET_CUR
                            | UVC_GET_MIN
                            | UVC_GET_MAX
                            | UVC_GET_RES
                            | UVC_GET_LEN
                            | UVC_GET_INFO
                            | UVC_GET_DEF
                    ) && (selector == UVC_VS_PROBE_CONTROL
                        || selector == UVC_VS_COMMIT_CONTROL)
                    {
                        self.fill_get_response(
                            selector,
                            request_code,
                            length,
                            state,
                            &mut response,
                        );
                    }
                }
                _ => {}
            }
        }
        info!("UVC setup response length={}", response.length);
        self.ioctl(UVCIOC_SEND_RESPONSE, &mut response)
    }

    fn fill_get_response(
        &self,
        selector: u8,
        request: u8,
        requested_length: usize,
        state: &std::sync::Arc<std::sync::Mutex<RuntimeState>>,
        response: &mut UvcRequestData,
    ) {
        if selector != UVC_VS_PROBE_CONTROL && selector != UVC_VS_COMMIT_CONTROL {
            return;
        }

        match request {
            UVC_GET_CUR => {
                let control = if selector == UVC_VS_PROBE_CONTROL {
                    &self.probe
                } else {
                    &self.commit
                };
                response.data[..UVC_STREAMING_CONTROL_SIZE].copy_from_slice(control);
                response.length = min_response_length(requested_length, UVC_STREAMING_CONTROL_SIZE);
            }
            UVC_GET_MIN | UVC_GET_MAX | UVC_GET_DEF => {
                // The actual mode is normalized against Config, so the first/last declared
                // mode provides the discrete minimum/maximum advertised by this Core.
                let control = self.edge_control(request == UVC_GET_MAX, state);
                response.data[..UVC_STREAMING_CONTROL_SIZE].copy_from_slice(&control);
                response.length = min_response_length(requested_length, UVC_STREAMING_CONTROL_SIZE);
            }
            UVC_GET_RES => {
                response.length = min_response_length(requested_length, UVC_STREAMING_CONTROL_SIZE);
            }
            UVC_GET_LEN => {
                response.data[..2]
                    .copy_from_slice(&(UVC_STREAMING_CONTROL_SIZE as u16).to_le_bytes());
                response.length = min_response_length(requested_length, 2);
            }
            UVC_GET_INFO => {
                response.data[0] = 0x03;
                response.length = min_response_length(requested_length, 1);
            }
            _ => {}
        }
    }

    fn edge_control(
        &self,
        maximum: bool,
        state: &std::sync::Arc<std::sync::Mutex<RuntimeState>>,
    ) -> [u8; UVC_STREAMING_CONTROL_SIZE] {
        let Ok(runtime) = state.lock() else {
            return self.probe;
        };
        let formats = &runtime.supported_formats;
        let Some(format) = (if maximum {
            formats.last()
        } else {
            formats.first()
        }) else {
            return self.probe;
        };
        let Some(frame) = (if maximum {
            format.frames.last()
        } else {
            format.frames.first()
        }) else {
            return self.probe;
        };
        let Some(fps) = (if maximum {
            frame.fps.last()
        } else {
            frame.fps.first()
        })
        .copied() else {
            return self.probe;
        };
        control_for_mode(&SelectedMode {
            format_index: (if maximum { formats.len() } else { 1 }) as u8,
            frame_index: (if maximum { format.frames.len() } else { 1 }) as u8,
            active: UvcActiveFormat {
                kind: format.format,
                width: frame.width,
                height: frame.height,
                fps,
            },
        })
    }

    fn handle_data(
        &mut self,
        event: &V4l2Event,
        state: &std::sync::Arc<std::sync::Mutex<RuntimeState>>,
    ) -> io::Result<()> {
        let Some(selector) = self.pending_control.take() else {
            return Ok(());
        };
        let length = i32::from_le_bytes(event.data[0..4].try_into().unwrap_or([0; 4]));
        if length <= 0 {
            return Ok(());
        }
        let data_len = (length as usize).min(UVC_STREAMING_CONTROL_SIZE).min(60);
        let data = &event.data[4..4 + data_len.min(event.data.len().saturating_sub(4))];
        let requested_format = parse_requested_control(data);
        let selected = {
            let runtime = state
                .lock()
                .map_err(|_| io::Error::other("UVC Runtime 状态锁已损坏"))?;
            select_mode(
                &runtime.supported_formats,
                requested_format.0,
                requested_format.1,
                requested_format.2,
            )
            .ok_or_else(|| {
                io::Error::new(io::ErrorKind::InvalidData, "UVC Probe/Commit 模式无效")
            })?
        };
        let normalized = control_for_mode(&selected);
        if selector == UVC_VS_PROBE_CONTROL {
            self.probe = normalized;
            info!("UVC Probe accepted: {:?}", selected.active);
            return Ok(());
        }

        self.commit = normalized;
        self.set_video_format(&selected.active)?;
        self.set_frame_rate(selected.active.fps)?;
        let mut runtime = state
            .lock()
            .map_err(|_| io::Error::other("UVC Runtime 状态锁已损坏"))?;
        runtime.negotiated_format = Some(selected.active.clone());
        if let Some(writer) = &runtime.producer {
            let _ = send_format(writer, selected.active);
        }
        info!("UVC Commit accepted: {:?}", runtime.negotiated_format);
        Ok(())
    }

    fn start_stream(
        &mut self,
        state: &std::sync::Arc<std::sync::Mutex<RuntimeState>>,
    ) -> io::Result<()> {
        if self.stream_state != StreamState::Idle {
            return Ok(());
        }
        self.allocate_buffers()?;
        let mut runtime = state
            .lock()
            .map_err(|_| io::Error::other("UVC Runtime 状态锁已损坏"))?;
        runtime.stream_on = true;
        runtime.pending_frames.clear();
        if let Some(writer) = &runtime.producer {
            let _ = send_stream(writer, true);
        }
        self.stream_state = StreamState::Priming;
        info!(
            "UVC Host STREAMON：等待 producer 首帧以预填 {} 个 MMAP buffer",
            self.buffers.len()
        );
        Ok(())
    }

    fn stop_stream(&mut self, state: &std::sync::Arc<std::sync::Mutex<RuntimeState>>) {
        if self.stream_state == StreamState::Running {
            let mut buffer_type = VIDEO_OUTPUT;
            let _ = self.ioctl(VIDIOC_STREAMOFF, &mut buffer_type);
        }
        self.stream_state = StreamState::Idle;
        self.release_buffers();
        if let Ok(mut runtime) = state.lock() {
            runtime.stream_on = false;
            runtime.pending_frames.clear();
            if let Some(writer) = &runtime.producer {
                let _ = send_stream(writer, false);
            }
        }
        info!("UVC Host STREAMOFF");
    }

    fn prime_stream(
        &mut self,
        state: &std::sync::Arc<std::sync::Mutex<RuntimeState>>,
    ) -> io::Result<()> {
        let frame = {
            let mut runtime = state
                .lock()
                .map_err(|_| io::Error::other("UVC Runtime 状态锁已损坏"))?;
            let frame = runtime.pending_frames.pop_back();
            runtime.pending_frames.clear();
            frame
        };
        let Some(frame) = frame else {
            return Ok(());
        };

        self.last_frame = Some(frame.clone());
        while let Some(index) = self.available_buffers.pop_front() {
            if let Err(error) = self.queue_buffer(index, &frame) {
                self.available_buffers.push_front(index);
                return Err(error);
            }
        }
        if self.buffers.is_empty() {
            return Err(io::Error::other("UVC V4L2 没有可启动的 MMAP buffer"));
        }

        let mut buffer_type = VIDEO_OUTPUT;
        self.ioctl(VIDIOC_STREAMON, &mut buffer_type)?;
        self.stream_state = StreamState::Running;
        info!(
            "UVC V4L2 已预填并排队 {} 个 MMAP buffer，随后执行 VIDIOC_STREAMON",
            self.buffers.len()
        );
        Ok(())
    }

    fn allocate_buffers(&mut self) -> io::Result<()> {
        self.release_buffers();
        let mut request = V4l2RequestBuffers {
            count: BUFFER_COUNT,
            type_: VIDEO_OUTPUT,
            memory: MEMORY_MMAP,
            capabilities: 0,
            flags: 0,
            reserved: [0; 3],
        };
        self.ioctl(VIDIOC_REQBUFS, &mut request)?;
        if request.count == 0 {
            return Err(io::Error::other("UVC V4L2 没有分配到 output buffer"));
        }
        for index in 0..request.count {
            let mut buffer: V4l2Buffer = unsafe { zeroed() };
            buffer.index = index;
            buffer.type_ = VIDEO_OUTPUT;
            buffer.memory = MEMORY_MMAP;
            self.ioctl(VIDIOC_QUERYBUF, &mut buffer)?;
            let length = usize::try_from(buffer.length)
                .map_err(|_| io::Error::other("UVC V4L2 buffer length 溢出"))?;
            let offset = unsafe { buffer.m.offset } as libc::off_t;
            // SAFETY: the kernel owns this MMAP range and returns its length/offset via QUERYBUF.
            let address = unsafe {
                libc::mmap(
                    ptr::null_mut(),
                    length,
                    libc::PROT_READ | libc::PROT_WRITE,
                    libc::MAP_SHARED,
                    self.fd(),
                    offset,
                )
            };
            if address == libc::MAP_FAILED {
                return Err(io::Error::last_os_error());
            }
            self.buffers.push(MappedBuffer {
                address: address.cast(),
                length,
            });
            self.available_buffers.push_back(index as usize);
        }
        Ok(())
    }

    fn release_buffers(&mut self) {
        self.available_buffers.clear();
        self.buffers.clear();
        self.last_frame = None;
        if self.device.is_some() {
            let mut request = V4l2RequestBuffers {
                count: 0,
                type_: VIDEO_OUTPUT,
                memory: MEMORY_MMAP,
                capabilities: 0,
                flags: 0,
                reserved: [0; 3],
            };
            let _ = self.ioctl(VIDIOC_REQBUFS, &mut request);
        }
    }

    fn reclaim_buffers(&mut self) -> io::Result<()> {
        loop {
            let mut buffer: V4l2Buffer = unsafe { zeroed() };
            buffer.type_ = VIDEO_OUTPUT;
            buffer.memory = MEMORY_MMAP;
            match self.ioctl(VIDIOC_DQBUF, &mut buffer) {
                Ok(()) => {
                    let index = buffer.index as usize;
                    if index < self.buffers.len() && !self.available_buffers.contains(&index) {
                        self.available_buffers.push_back(index);
                    }
                }
                Err(error) if is_would_block(&error) => break,
                Err(error) => return Err(error),
            }
        }
        Ok(())
    }

    fn submit_frames(
        &mut self,
        state: &std::sync::Arc<std::sync::Mutex<RuntimeState>>,
    ) -> io::Result<()> {
        while let Some(index) = self.available_buffers.pop_front() {
            let next_frame = {
                let mut runtime = state
                    .lock()
                    .map_err(|_| io::Error::other("UVC Runtime 状态锁已损坏"))?;
                runtime.pending_frames.pop_front()
            };
            if let Some(frame) = next_frame {
                self.last_frame = Some(frame);
            }
            let Some(frame) = self.last_frame.clone() else {
                self.available_buffers.push_front(index);
                break;
            };
            if let Err(error) = self.queue_buffer(index, &frame) {
                self.available_buffers.push_front(index);
                return Err(error);
            }
        }
        Ok(())
    }

    fn queue_buffer(&self, index: usize, frame: &super::QueuedFrame) -> io::Result<()> {
        let buffer = self
            .buffers
            .get(index)
            .ok_or_else(|| io::Error::other("UVC V4L2 buffer index 越界"))?;
        if frame.data.len() > buffer.length {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                format!(
                    "UVC 帧超过 V4L2 buffer：frame={} buffer={}",
                    frame.data.len(),
                    buffer.length
                ),
            ));
        }

        // SAFETY: the frame is copied into the exact MMAP range returned by QUERYBUF.
        unsafe {
            ptr::copy_nonoverlapping(frame.data.as_ptr(), buffer.address, frame.data.len());
        }
        let mut v4l2_buffer: V4l2Buffer = unsafe { zeroed() };
        v4l2_buffer.index = index as u32;
        v4l2_buffer.type_ = VIDEO_OUTPUT;
        v4l2_buffer.bytesused = frame.data.len() as u32;
        v4l2_buffer.field = FIELD_NONE;
        v4l2_buffer.memory = MEMORY_MMAP;
        v4l2_buffer.sequence = frame.sequence as u32;
        v4l2_buffer.timestamp.tv_sec = (frame.timestamp_ns / 1_000_000_000) as _;
        v4l2_buffer.timestamp.tv_usec = ((frame.timestamp_ns % 1_000_000_000) / 1_000) as _;
        self.ioctl(VIDIOC_QBUF, &mut v4l2_buffer)
    }

    fn set_video_format(&mut self, format: &UvcActiveFormat) -> io::Result<()> {
        let mut value = V4l2Format {
            type_: VIDEO_OUTPUT,
            _union_alignment: 0,
            raw: [0; 200],
        };
        set_u32(&mut value.raw, 0, format.width);
        set_u32(&mut value.raw, 4, format.height);
        set_u32(&mut value.raw, 8, format.fourcc());
        set_u32(&mut value.raw, 12, FIELD_NONE);
        set_u32(
            &mut value.raw,
            16,
            if matches!(format.kind, UvcFormatKind::Yuyv) {
                format.width.saturating_mul(2)
            } else {
                0
            },
        );
        set_u32(
            &mut value.raw,
            20,
            format.width.saturating_mul(format.height).saturating_mul(2),
        );
        set_u32(&mut value.raw, 24, 8); // V4L2_COLORSPACE_SRGB
        self.ioctl(VIDIOC_S_FMT, &mut value)
    }

    fn set_frame_rate(&mut self, fps: u32) -> io::Result<()> {
        if fps == 0 {
            return Ok(());
        }
        let mut value = V4l2StreamParm {
            type_: VIDEO_OUTPUT,
            raw: [0; 200],
        };
        // v4l2_outputparm.timeperframe starts at parm offset 8, i.e. raw[8..16].
        set_u32(&mut value.raw, 8, 1);
        set_u32(&mut value.raw, 12, fps);
        self.ioctl(VIDIOC_S_PARM, &mut value)
    }

    fn fd(&self) -> RawFd {
        self.device.as_ref().expect("UVC V4L2 device missing").fd
    }

    fn ioctl<T>(&self, request: libc::c_int, value: &mut T) -> io::Result<()> {
        // SAFETY: all values passed here are repr(C) UAPI structures with the matching ioctl size.
        let result = unsafe { libc::ioctl(self.fd(), request, value as *mut T) };
        if result < 0 {
            Err(io::Error::last_os_error())
        } else {
            Ok(())
        }
    }

    fn disconnect(&mut self, state: &std::sync::Arc<std::sync::Mutex<RuntimeState>>) {
        self.stop_stream(state);
        self.buffers.clear();
        self.available_buffers.clear();
        self.device.take();
        self.interfaces = None;
        self.next_open_attempt = Instant::now() + Duration::from_millis(250);
    }
}

fn subscribe_events(fd: RawFd) -> io::Result<()> {
    for event_type in [
        UVC_EVENT_SETUP,
        UVC_EVENT_DATA,
        UVC_EVENT_STREAMON,
        UVC_EVENT_STREAMOFF,
    ] {
        let mut subscription = V4l2EventSubscription {
            type_: event_type,
            id: 0,
            flags: 0,
            reserved: [0; 5],
        };
        // SAFETY: the fd is an opened V4L2 device and the structure is UAPI-compatible.
        let result = unsafe {
            libc::ioctl(
                fd,
                VIDIOC_SUBSCRIBE_EVENT,
                &mut subscription as *mut V4l2EventSubscription,
            )
        };
        if result < 0 {
            return Err(io::Error::last_os_error());
        }
    }
    Ok(())
}

fn find_uvc_video_device() -> UsbResult<V4l2Device> {
    let mut candidates = Vec::new();
    if let Ok(entries) = fs::read_dir("/dev") {
        for entry in entries.flatten() {
            let name = entry.file_name();
            let name = name.to_string_lossy();
            if name.starts_with("video") && name[5..].chars().all(|ch| ch.is_ascii_digit()) {
                candidates.push(entry.path());
            }
        }
    }
    candidates.sort();

    let mut has_function_name = false;
    let mut function_name_read_failed = false;
    for path in candidates {
        match read_function_name(&path) {
            Ok(Some(function_name)) => {
                has_function_name = true;
                if function_name != UVC_FUNCTION_NAME {
                    continue;
                }
                if let Ok(device) = open_candidate(&path) {
                    return Ok(device);
                }
            }
            Ok(None) => {}
            Err(error) => {
                function_name_read_failed = true;
                debug!("无法读取 {} 的 UVC function_name：{error}", path.display());
            }
        }
    }

    // Older kernels may not expose function_name. Keep a deterministic compatibility
    // fallback only when no function_name attribute was available at all; never choose a
    // different function after a readable, non-matching function_name was found.
    if !has_function_name && !function_name_read_failed {
        let mut fallback_candidates = Vec::new();
        if let Ok(entries) = fs::read_dir("/dev") {
            for entry in entries.flatten() {
                let name = entry.file_name();
                let name = name.to_string_lossy();
                if name.starts_with("video") && name[5..].chars().all(|ch| ch.is_ascii_digit()) {
                    fallback_candidates.push(entry.path());
                }
            }
        }
        fallback_candidates.sort();
        for path in fallback_candidates {
            if let Ok(device) = open_candidate(&path) {
                return Ok(device);
            }
        }
    }
    Err(UsbError::Unavailable(format!(
        "找不到 function_name={UVC_FUNCTION_NAME} 的 V4L2 output 节点；请确认内核启用了 USB_CONFIGFS_F_UVC/USB_F_UVC"
    )))
}

/// 读取当前 ConfigFS Function 分配的接口号，而非假定 VC/VS 固定为 0/1。
///
/// UVC Function 可以和 HID、ACM、NCM 等任意组合，接口编号由链接顺序决定。只有
/// 将 SETUP 的 wIndex 与这里的实际编号对齐，才能避免把 VC 请求误解为 VS 的
/// Probe/Commit。
fn find_uvc_interfaces() -> UsbResult<UvcInterfaces> {
    let root = Path::new(CONFIGFS_GADGET_ROOT);
    let entries = fs::read_dir(root).map_err(|error| {
        UsbError::Unavailable(format!(
            "无法枚举 UVC ConfigFS Gadget 根目录 {}：{error}",
            root.display()
        ))
    })?;
    for entry in entries.flatten() {
        let function = entry.path().join("functions").join(UVC_FUNCTION_NAME);
        let control = function.join("control/bInterfaceNumber");
        let streaming = function.join("streaming/bInterfaceNumber");
        if !control.is_file() || !streaming.is_file() {
            continue;
        }
        return Ok(UvcInterfaces {
            control: read_interface_number(&control)?,
            streaming: read_interface_number(&streaming)?,
        });
    }
    Err(UsbError::Unavailable(format!(
        "未找到 UVC Function {UVC_FUNCTION_NAME} 的 ConfigFS 接口号"
    )))
}

fn read_interface_number(path: &Path) -> UsbResult<u8> {
    let value = fs::read_to_string(path).map_err(|error| {
        UsbError::Unavailable(format!("读取 UVC 接口号 {} 失败：{error}", path.display()))
    })?;
    value.trim().parse::<u8>().map_err(|error| {
        UsbError::Unavailable(format!(
            "解析 UVC 接口号 {} 的值 {:?} 失败：{error}",
            path.display(),
            value.trim()
        ))
    })
}

fn read_function_name(path: &Path) -> io::Result<Option<String>> {
    let Some(video_name) = path.file_name() else {
        return Ok(None);
    };
    let function_name_path = Path::new("/sys/class/video4linux")
        .join(video_name)
        .join("function_name");
    match fs::read_to_string(function_name_path) {
        Ok(value) => Ok(Some(value.trim().to_owned())),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error),
    }
}

fn open_candidate(path: &Path) -> UsbResult<V4l2Device> {
    let path_text = path
        .to_str()
        .ok_or_else(|| UsbError::Unavailable("UVC video 节点路径不是有效 UTF-8".into()))?;
    let c_path = CString::new(path_text)
        .map_err(|_| UsbError::Unavailable("UVC video 节点路径包含 NUL".into()))?;
    // SAFETY: c_path is NUL-terminated and open returns an owned fd.
    let fd = unsafe {
        libc::open(
            c_path.as_ptr(),
            libc::O_RDWR | libc::O_NONBLOCK | libc::O_CLOEXEC,
        )
    };
    if fd < 0 {
        return Err(UsbError::Io(io::Error::last_os_error()));
    }
    let mut capability: V4l2Capability = unsafe { zeroed() };
    // SAFETY: fd is an open video node and capability is the matching UAPI structure.
    let result =
        unsafe { libc::ioctl(fd, VIDIOC_QUERYCAP, &mut capability as *mut V4l2Capability) };
    if result < 0 {
        unsafe { libc::close(fd) };
        return Err(UsbError::Io(io::Error::last_os_error()));
    }
    let caps = capability.device_caps | capability.capabilities;
    let driver = c_string(&capability.driver);
    if caps & CAP_VIDEO_OUTPUT == 0
        || caps & CAP_STREAMING == 0
        || !driver.to_ascii_lowercase().contains("uvc")
    {
        unsafe { libc::close(fd) };
        return Err(UsbError::Unavailable("不是 UVC Gadget output 节点".into()));
    }
    Ok(V4l2Device {
        fd,
        path: path.to_path_buf(),
    })
}

fn c_string(bytes: &[u8]) -> String {
    let length = bytes
        .iter()
        .position(|byte| *byte == 0)
        .unwrap_or(bytes.len());
    String::from_utf8_lossy(&bytes[..length]).into_owned()
}

fn parse_requested_control(data: &[u8]) -> (u8, u8, u32) {
    if data.len() < 8 {
        return (1, 1, 0);
    }
    (
        data[2].max(1),
        data[3].max(1),
        u32::from_le_bytes([data[4], data[5], data[6], data[7]]),
    )
}

fn select_mode(
    formats: &[UvcFormat],
    requested_format: u8,
    requested_frame: u8,
    requested_interval: u32,
) -> Option<SelectedMode> {
    let format_index =
        usize::from(requested_format.saturating_sub(1)).min(formats.len().saturating_sub(1));
    let format = formats.get(format_index)?;
    let frame_index =
        usize::from(requested_frame.saturating_sub(1)).min(format.frames.len().saturating_sub(1));
    let frame = format.frames.get(frame_index)?;
    let fps = select_fps(&frame.fps, requested_interval)?;
    Some(SelectedMode {
        format_index: (format_index + 1) as u8,
        frame_index: (frame_index + 1) as u8,
        active: UvcActiveFormat {
            kind: format.format,
            width: frame.width,
            height: frame.height,
            fps,
        },
    })
}

fn select_fps(fps_values: &[u32], requested_interval: u32) -> Option<u32> {
    if requested_interval == 0 {
        return fps_values.first().copied();
    }
    let requested_interval = u64::from(requested_interval);
    fps_values.iter().copied().min_by_key(|fps| {
        let interval = 10_000_000u64 / u64::from(*fps);
        interval.abs_diff(requested_interval)
    })
}

fn control_for_active(format: &UvcActiveFormat) -> [u8; UVC_STREAMING_CONTROL_SIZE] {
    let selected = SelectedMode {
        format_index: 1,
        frame_index: 1,
        active: format.clone(),
    };
    control_for_mode(&selected)
}

fn control_for_mode(mode: &SelectedMode) -> [u8; UVC_STREAMING_CONTROL_SIZE] {
    let mut control = [0u8; UVC_STREAMING_CONTROL_SIZE];
    control[0..2].copy_from_slice(&1u16.to_le_bytes());
    control[2] = mode.format_index;
    control[3] = mode.frame_index;
    control[4..8].copy_from_slice(&(10_000_000 / mode.active.fps).to_le_bytes());
    control[18..22].copy_from_slice(
        &mode
            .active
            .width
            .saturating_mul(mode.active.height)
            .saturating_mul(2)
            .to_le_bytes(),
    );
    control[22..26].copy_from_slice(&UVC_DEFAULT_PAYLOAD_SIZE.to_le_bytes());
    control[30] = 3;
    control[31] = 1;
    control[32] = 1;
    control[33] = 1;
    control
}

fn min_response_length(requested: usize, available: usize) -> i32 {
    requested.min(available).min(60) as i32
}

fn set_u32(bytes: &mut [u8], offset: usize, value: u32) {
    bytes[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
}

fn is_would_block(error: &io::Error) -> bool {
    error.raw_os_error() == Some(libc::EAGAIN)
}

fn is_no_event_available(error: &io::Error) -> bool {
    is_would_block(error) || error.raw_os_error() == Some(libc::ENOENT)
}

const fn ioc_read(type_: u8, number: u8, size: usize) -> u32 {
    ioc(2, type_, number, size)
}

const fn ioc_write(type_: u8, number: u8, size: usize) -> u32 {
    ioc(1, type_, number, size)
}

const fn ioc_read_write(type_: u8, number: u8, size: usize) -> u32 {
    ioc(3, type_, number, size)
}

const fn ioc(direction: u32, type_: u8, number: u8, size: usize) -> u32 {
    (direction << 30) | ((size as u32) << 16) | ((type_ as u32) << 8) | number as u32
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn selects_declared_mode_and_clamps_host_request() {
        let formats = vec![UvcFormat {
            format: UvcFormatKind::Mjpeg,
            frames: vec![crate::usb_sub::UvcFrame {
                width: 1280,
                height: 720,
                fps: vec![30, 60],
            }],
        }];
        let selected = select_mode(&formats, 99, 99, 166_666).unwrap();
        assert_eq!(selected.active.width, 1280);
        assert_eq!(selected.active.fps, 60);
    }

    #[test]
    fn selects_nearest_advertised_fps() {
        assert_eq!(select_fps(&[30, 60], 333_333), Some(30));
        assert_eq!(select_fps(&[30, 60], 166_666), Some(60));
        assert_eq!(select_fps(&[30], 166_666), Some(30));
    }

    #[test]
    fn streaming_control_is_the_uvc_1_1_34_byte_shape() {
        let format = UvcActiveFormat {
            kind: UvcFormatKind::Mjpeg,
            width: 1920,
            height: 1080,
            fps: 30,
        };
        let control = control_for_active(&format);
        assert_eq!(control.len(), 34);
        assert_eq!(
            u32::from_le_bytes(control[4..8].try_into().unwrap()),
            333_333
        );
    }
}

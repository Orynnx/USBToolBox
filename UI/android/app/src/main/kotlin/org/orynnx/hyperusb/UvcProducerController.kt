package org.orynnx.hyperusb

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.ImageFormat
import android.graphics.PixelFormat
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.Image
import android.media.ImageReader
import android.media.MediaMetadataRetriever
import android.media.projection.MediaProjection
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Size
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.Closeable
import java.io.InputStream
import java.io.OutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * The app-side UVC Producer.  Core owns ConfigFS/V4L2; this class only turns
 * Android sources into frames for Core's documented uvc.sock protocol.
 */
class UvcProducerController(private val activity: Activity) : Closeable {
    companion object {
        private const val SOCKET_PATH = "/data/adb/usb_sub/uvc.sock"
        private const val WIDTH = 1280
        private const val HEIGHT = 720
        private const val FPS = 30
        private const val MSG_HELLO = 1
        private const val MSG_FORMAT = 2
        private const val MSG_STREAM_ON = 3
        private const val MSG_STREAM_OFF = 4
        private const val MSG_FRAME = 5
        private const val FOURCC_MJPG = 0x47504a4d // "MJPG" in little endian
    }

    private enum class Source { BACK, FRONT, SCREEN, FILE }

    private var source: Source? = null
    private var socket: RootUvcSocket? = null
    private var cameraThread: HandlerThread? = null
    private var camera: CameraDevice? = null
    private var cameraSession: CameraCaptureSession? = null
    private var reader: ImageReader? = null
    private var display: VirtualDisplay? = null
    private var registeredProjection: MediaProjection? = null
    private val fileExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var fileTask: Future<*>? = null
    private val running = AtomicBoolean(false)
    private var outputWidth = WIDTH
    private var outputHeight = HEIGHT
    private var outputFps = FPS

    fun cameraCapability(sourceName: String): Map<String, Any> {
        val front = when (sourceName) {
            "back" -> false
            "front" -> true
            else -> error("Camera capability requested for a non-camera source")
        }
        val capability = selectCameraCapability(front)
        return mapOf(
            "width" to capability.size.width,
            "height" to capability.size.height,
            "fps" to capability.fpsRange.upper,
            "format" to "mjpeg",
        )
    }

    fun start(sourceName: String, videoUri: String?, width: Int, height: Int, fps: Int): Map<String, Any> {
        stopInternal(stopScreenService = false)
        require(width > 0 && height > 0 && fps > 0) { "Invalid UVC output capability" }
        outputWidth = width
        outputHeight = height
        outputFps = fps
        val requestedSource = when (sourceName) {
            "back" -> Source.BACK
            "front" -> Source.FRONT
            "screen" -> Source.SCREEN
            "file" -> Source.FILE
            else -> error("Unsupported UVC source")
        }
        if ((requestedSource == Source.BACK || requestedSource == Source.FRONT) &&
            activity.checkSelfPermission(android.Manifest.permission.CAMERA) != android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            error("Camera permission has not been granted")
        }
        if (requestedSource == Source.SCREEN && UvcScreenCaptureService.projection == null) {
            error("Screen capture permission has not been granted")
        }
        if (requestedSource == Source.FILE && videoUri.isNullOrBlank()) {
            error("Select an MP4 file first")
        }

        val opened = RootUvcSocket(outputWidth, outputHeight, outputFps)
        opened.open()
        socket = opened
        this.source = requestedSource
        running.set(true)
        try {
            when (requestedSource) {
                Source.BACK -> startCamera(false)
                Source.FRONT -> startCamera(true)
                Source.SCREEN -> startScreen()
                Source.FILE -> startFile(videoUri!!)
            }
        } catch (error: Exception) {
            stopInternal(stopScreenService = true)
            throw error
        }
        return mapOf(
            "running" to true,
            "source" to sourceName,
            "width" to outputWidth,
            "height" to outputHeight,
            "fps" to outputFps,
            "format" to "mjpeg",
        )
    }

    fun status(): Map<String, Any> = mapOf(
        "running" to running.get(),
        "source" to (source?.name?.lowercase() ?: ""),
        "width" to outputWidth,
        "height" to outputHeight,
        "fps" to outputFps,
        "format" to "mjpeg",
    )

    fun stop(): Map<String, Any> = stopInternal(stopScreenService = true)

    private fun stopInternal(stopScreenService: Boolean): Map<String, Any> {
        running.set(false)
        val activeDisplay = display
        display = null
        val activeProjection = registeredProjection
        registeredProjection = null
        val activeReader = reader
        reader = null
        val activeSession = cameraSession
        cameraSession = null
        val activeCamera = camera
        camera = null
        val activeThread = cameraThread
        cameraThread = null
        val activeSocket = socket
        socket = null
        source = null

        // A file decoder can be waiting inside MediaMetadataRetriever. Cancel
        // it before releasing other frame consumers so it cannot emit again.
        fileTask?.cancel(true)
        fileTask = null
        try { activeSession?.stopRepeating() } catch (_: Exception) {}
        try { activeSession?.abortCaptures() } catch (_: Exception) {}
        try { activeSession?.close() } catch (_: Exception) {}
        try { activeCamera?.close() } catch (_: Exception) {}
        try { activeReader?.setOnImageAvailableListener(null, null) } catch (_: Exception) {}
        try { activeReader?.close() } catch (_: Exception) {}
        try { activeDisplay?.release() } catch (_: Exception) {}
        try { activeProjection?.unregisterCallback(projectionCallback) } catch (_: Exception) {}
        try { activeThread?.quitSafely() } catch (_: Exception) {}
        if (activeThread != null) {
            try { activeThread.join(750) } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            }
            if (activeThread.isAlive) activeThread.interrupt()
        }
        try { activeSocket?.close() } catch (_: Exception) {}
        if (stopScreenService) {
            try {
                activity.stopService(Intent(activity, UvcScreenCaptureService::class.java).apply {
                    action = UvcScreenCaptureService.ACTION_STOP
                })
            } catch (_: Exception) {}
        }
        return mapOf("running" to false)
    }

    override fun close() {
        stop()
        fileExecutor.shutdownNow()
    }

    private data class CameraCapability(val id: String, val size: Size, val fpsRange: android.util.Range<Int>)

    private fun selectCameraCapability(front: Boolean): CameraCapability {
        val manager = activity.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val cameraId = manager.cameraIdList.firstOrNull { id ->
            manager.getCameraCharacteristics(id)
                .get(CameraCharacteristics.LENS_FACING) == if (front) CameraCharacteristics.LENS_FACING_FRONT else CameraCharacteristics.LENS_FACING_BACK
        } ?: error("Requested camera is unavailable")
        val characteristics = manager.getCameraCharacteristics(cameraId)
        val sizes = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            ?.getOutputSizes(ImageFormat.JPEG)
            ?.toList()
            ?.filter { it.width > 0 && it.height > 0 }
            ?: emptyList()
        require(sizes.isNotEmpty()) { "This camera does not provide JPEG output" }
        val targetArea = WIDTH.toLong() * HEIGHT
        val targetRatio = WIDTH.toDouble() / HEIGHT
        val size = sizes.minWithOrNull(
            compareBy<Size>(
                { kotlin.math.abs(it.width.toDouble() / it.height - targetRatio) },
                { kotlin.math.abs(it.width.toLong() * it.height - targetArea) },
            ),
        )!!
        val ranges = characteristics.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
            ?.filter { it.upper > 0 }
            ?: emptyList()
        require(ranges.isNotEmpty()) { "This camera does not expose an AE frame-rate range" }
        val fpsRange = ranges.minWithOrNull(
            compareBy<android.util.Range<Int>>(
                { if (it.lower == it.upper) 0 else 1 },
                { kotlin.math.abs(it.upper - FPS) },
            ),
        )!!
        return CameraCapability(cameraId, size, fpsRange)
    }

    private fun startCamera(front: Boolean) {
        val manager = activity.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val capability = selectCameraCapability(front)
        require(capability.size == Size(outputWidth, outputHeight)) {
            "UVC descriptor does not match the selected camera output size"
        }
        val thread = HandlerThread("hyperusb-uvc-camera").also { it.start() }
        cameraThread = thread
        val handler = Handler(thread.looper)
        reader = ImageReader.newInstance(outputWidth, outputHeight, ImageFormat.JPEG, 3).also { imageReader ->
            imageReader.setOnImageAvailableListener({ sourceReader ->
                sourceReader.acquireLatestImage()?.use { image ->
                    sendMjpeg(readJpeg(image))
                }
            }, handler)
        }
        manager.openCamera(capability.id, object : CameraDevice.StateCallback() {
            override fun onOpened(device: CameraDevice) {
                if (!running.get()) {
                    device.close()
                    return
                }
                camera = device
                val output = reader?.surface ?: return
                device.createCaptureSession(listOf(output), object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(session: CameraCaptureSession) {
                        if (!running.get()) {
                            session.close()
                            return
                        }
                        cameraSession = session
                        val request = device.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                            addTarget(output)
                            set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, capability.fpsRange)
                        }.build()
                        session.setRepeatingRequest(request, null, handler)
                    }
                    override fun onConfigureFailed(session: CameraCaptureSession) {
                        session.close()
                    }
                }, handler)
            }
            override fun onDisconnected(device: CameraDevice) = device.close()
            override fun onError(device: CameraDevice, error: Int) = device.close()
        }, handler)
    }

    private fun startScreen() {
        val capture = UvcScreenCaptureService.projection
            ?: error("Screen capture permission has not been granted")
        capture.registerCallback(projectionCallback, Handler(activity.mainLooper))
        registeredProjection = capture
        reader = ImageReader.newInstance(outputWidth, outputHeight, PixelFormat.RGBA_8888, 3).also { imageReader ->
            imageReader.setOnImageAvailableListener({ sourceReader ->
                sourceReader.acquireLatestImage()?.use { image ->
                    sendMjpeg(rgbaToMjpeg(image))
                }
            }, Handler(activity.mainLooper))
        }
        display = capture.createVirtualDisplay(
            "HyperUSB UVC screen",
            outputWidth,
            outputHeight,
            activity.resources.displayMetrics.densityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            reader!!.surface,
            null,
            null,
        )
    }

    private fun startFile(uri: String) {
        fileTask = fileExecutor.submit {
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(activity, android.net.Uri.parse(uri))
                val durationUs = (retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L) * 1000L
                require(durationUs > 0) { "The selected MP4 has no video duration" }
                var timestampUs = 0L
                val frameIntervalUs = 1_000_000L / outputFps
                while (running.get() && source == Source.FILE && !Thread.currentThread().isInterrupted) {
                    if (!socketIsStreaming()) {
                        Thread.sleep(30)
                        continue
                    }
                    val bitmap = retriever.getFrameAtTime(timestampUs, MediaMetadataRetriever.OPTION_CLOSEST)
                    if (bitmap != null) {
                        val scaled = Bitmap.createScaledBitmap(bitmap, outputWidth, outputHeight, true)
                        val bytes = java.io.ByteArrayOutputStream().use { output ->
                            scaled.compress(Bitmap.CompressFormat.JPEG, 88, output)
                            output.toByteArray()
                        }
                        if (scaled !== bitmap) scaled.recycle()
                        bitmap.recycle()
                        sendMjpeg(bytes)
                    }
                    timestampUs += frameIntervalUs
                    if (timestampUs >= durationUs) timestampUs = 0L
                }
            } finally {
                retriever.release()
            }
        }
    }

    private fun socketIsStreaming(): Boolean = socket?.canSendFrames == true

    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            if (running.get() && source == Source.SCREEN) stop()
        }
    }

    private fun sendMjpeg(bytes: ByteArray) {
        if (running.get() && socketIsStreaming()) socket?.sendFrame(bytes)
    }

    private fun readJpeg(image: Image): ByteArray {
        val buffer = image.planes[0].buffer
        return ByteArray(buffer.remaining()).also(buffer::get)
    }

    private fun rgbaToMjpeg(image: Image): ByteArray {
        val plane = image.planes[0]
        val buffer = plane.buffer
        val rowStride = plane.rowStride
        val pixelStride = plane.pixelStride
        val pixels = IntArray(outputWidth * outputHeight)
        var outputIndex = 0
        for (y in 0 until outputHeight) {
            for (x in 0 until outputWidth) {
                val position = y * rowStride + x * pixelStride
                val r = buffer.get(position).toInt() and 0xff
                val g = buffer.get(position + 1).toInt() and 0xff
                val b = buffer.get(position + 2).toInt() and 0xff
                pixels[outputIndex++] = android.graphics.Color.rgb(r, g, b)
            }
        }
        val bitmap = Bitmap.createBitmap(pixels, outputWidth, outputHeight, Bitmap.Config.ARGB_8888)
        return try {
            java.io.ByteArrayOutputStream().use { output ->
                check(bitmap.compress(Bitmap.CompressFormat.JPEG, 85, output)) {
                    "Unable to encode the screen frame as MJPEG"
                }
                output.toByteArray()
            }
        } finally {
            bitmap.recycle()
        }
    }

    private class RootUvcSocket(
        private val expectedWidth: Int,
        private val expectedHeight: Int,
        private val expectedFps: Int,
    ) : Closeable {
        private var process: Process? = null
        private var input: InputStream? = null
        private var output: OutputStream? = null
        private var controlThread: Thread? = null
        private val writeLock = Any()
        @Volatile var streaming = false
            private set
        @Volatile private var formatCompatible = false

        val canSendFrames: Boolean
            get() = streaming && formatCompatible
        private var sequence = 0L

        fun open() {
            process = ProcessBuilder("su", "-c", "exec toybox nc -U $SOCKET_PATH").start()
            input = BufferedInputStream(process!!.inputStream)
            output = BufferedOutputStream(process!!.outputStream)
            writeMessage(MSG_HELLO, ByteArray(0))
            controlThread = Thread({ readControlLoop() }, "hyperusb-uvc-control").apply {
                isDaemon = true
                start()
            }
        }

        fun sendFrame(data: ByteArray) {
            val payload = ByteBuffer.allocate(24 + data.size).order(ByteOrder.LITTLE_ENDIAN)
                .putLong(sequence++)
                .putLong(SystemClock.elapsedRealtimeNanos())
                .putInt(data.size)
                .putInt(0)
                .put(data)
                .array()
            writeMessage(MSG_FRAME, payload)
        }

        private fun readControlLoop() {
            try {
                val source = input ?: return
                while (true) {
                    val header = readExact(source, 12)
                    require(header.copyOfRange(0, 4).contentEquals(byteArrayOf('H'.code.toByte(), 'U'.code.toByte(), 'V'.code.toByte(), 'C'.code.toByte()))) { "Invalid UVC socket magic" }
                    val values = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN)
                    values.position(6)
                    val type = values.short.toInt() and 0xffff
                    val size = values.int
                    require(size in 0..(128 * 1024 * 1024)) { "Invalid UVC control payload size" }
                    val payload = readExact(source, size)
                    when (type) {
                        MSG_FORMAT -> {
                            val format = ByteBuffer.wrap(payload).order(ByteOrder.LITTLE_ENDIAN)
                            if (payload.size == 16) {
                                val fourcc = format.int
                                val width = format.int
                                val height = format.int
                                val fps = format.int
                                formatCompatible = fourcc == FOURCC_MJPG &&
                                    width == expectedWidth &&
                                    height == expectedHeight &&
                                    fps == expectedFps
                            }
                        }
                        MSG_STREAM_ON -> streaming = true
                        MSG_STREAM_OFF -> streaming = false
                    }
                }
            } catch (_: Exception) {
                streaming = false
                formatCompatible = false
            }
        }

        private fun writeMessage(type: Int, payload: ByteArray) = synchronized(writeLock) {
            val sink = output ?: error("UVC socket is closed")
            val header = ByteBuffer.allocate(12).order(ByteOrder.LITTLE_ENDIAN)
                .put(byteArrayOf('H'.code.toByte(), 'U'.code.toByte(), 'V'.code.toByte(), 'C'.code.toByte()))
                .putShort(1)
                .putShort(type.toShort())
                .putInt(payload.size)
                .array()
            sink.write(header)
            sink.write(payload)
            sink.flush()
        }

        private fun readExact(stream: InputStream, size: Int): ByteArray {
            val result = ByteArray(size)
            var offset = 0
            while (offset < size) {
                val count = stream.read(result, offset, size - offset)
                if (count < 0) error("UVC socket closed")
                offset += count
            }
            return result
        }

        override fun close() {
            streaming = false
            val currentProcess = process
            val currentControlThread = controlThread
            process = null
            controlThread = null
            synchronized(writeLock) {
                try { output?.close() } catch (_: Exception) {}
                try { input?.close() } catch (_: Exception) {}
                output = null
                input = null
            }
            currentControlThread?.interrupt()
            if (currentProcess != null) {
                currentProcess.destroy()
                try {
                    if (!currentProcess.waitFor(500, TimeUnit.MILLISECONDS)) {
                        currentProcess.destroyForcibly()
                        currentProcess.waitFor(500, TimeUnit.MILLISECONDS)
                    }
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                    currentProcess.destroyForcibly()
                }
            }
            try { currentControlThread?.join(500) } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            }
        }
    }
}

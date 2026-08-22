package org.orynnx.hyperusb

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.StatFs
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.io.FileOutputStream
import java.io.IOException
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private val documentsChannel = "org.orynnx.hyperusb/documents"
    private val documentEventsChannel = "org.orynnx.hyperusb/document_events"
    private val uvcChannel = "org.orynnx.hyperusb/uvc"
    private val cameraPermissionRequest = 4201
    private val screenCaptureRequest = 4202
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val copyCancellation = ConcurrentHashMap<String, AtomicBoolean>()
    private var documentEventSink: EventChannel.EventSink? = null
    private var pendingPicker: MethodChannel.Result? = null
    private var pendingCameraPermission: MethodChannel.Result? = null
    private var pendingScreenCapture: MethodChannel.Result? = null
    private lateinit var uvcProducer: UvcProducerController

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        uvcProducer = UvcProducerController(this)
        MethodChannel(engine.dartExecutor.binaryMessenger, documentsChannel)
            .setMethodCallHandler(::handleDocumentCall)
        EventChannel(engine.dartExecutor.binaryMessenger, documentEventsChannel)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    documentEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    documentEventSink = null
                }
            })
        MethodChannel(engine.dartExecutor.binaryMessenger, uvcChannel)
            .setMethodCallHandler(::handleUvcCall)
    }

    private fun handleUvcCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "requestCameraPermission" -> requestCameraPermission(result)
                "requestScreenCapture" -> requestScreenCapture(result)
                "cameraCapability" -> result.success(
                    uvcProducer.cameraCapability(requiredString(call, "source")),
                )
                "start" -> result.success(
                    uvcProducer.start(
                        requiredString(call, "source"),
                        call.argument<String>("videoUri"),
                        (call.argument<Number>("width") ?: error("Missing width")).toInt(),
                        (call.argument<Number>("height") ?: error("Missing height")).toInt(),
                        (call.argument<Number>("fps") ?: error("Missing fps")).toInt(),
                    ),
                )
                "stop" -> result.success(uvcProducer.stop())
                "status" -> result.success(uvcProducer.status())
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("uvc_failed", error.message ?: error.javaClass.simpleName, null)
        }
    }

    private fun requestCameraPermission(result: MethodChannel.Result) {
        if (checkSelfPermission(android.Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        if (pendingCameraPermission != null) {
            result.error("busy", "A camera permission request is already open", null)
            return
        }
        pendingCameraPermission = result
        requestPermissions(arrayOf(android.Manifest.permission.CAMERA), cameraPermissionRequest)
    }

    private fun requestScreenCapture(result: MethodChannel.Result) {
        if (pendingScreenCapture != null) {
            result.error("busy", "A screen-capture permission request is already open", null)
            return
        }
        pendingScreenCapture = result
        val manager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        startActivityForResult(manager.createScreenCaptureIntent(), screenCaptureRequest)
    }

    private fun handleDocumentCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickFile" -> openPicker(
                Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "application/octet-stream"
                    putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/octet-stream", "application/x-iso9660-image", "*/*"))
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                },
                4101,
                result,
            )
            "pickVideo" -> openPicker(
                Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "video/*"
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                },
                4103,
                result,
            )
            "pickDirectory" -> openPicker(
                Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                            Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
                    )
                },
                4102,
                result,
            )
            "createSparse" -> runIo(result) { createSparse(call) }
            "copyDocument" -> runIo(result) { copyDocument(call) }
            "cancelCopy" -> {
                val operationId = requiredString(call, "operationId")
                result.success(copyCancellation[operationId]?.let { it.set(true); true } ?: false)
            }
            "deleteDocument" -> runIo(result) {
                val uri = requiredUri(call, "uri")
                check(DocumentsContract.deleteDocument(contentResolver, uri)) { "The document provider refused deletion" }
                emptyMap()
            }
            else -> result.notImplemented()
        }
    }

    private fun openPicker(intent: Intent, requestCode: Int, result: MethodChannel.Result) {
        if (pendingPicker != null) {
            result.error("busy", "A document picker is already open", null)
            return
        }
        pendingPicker = result
        startActivityForResult(intent, requestCode)
    }

    private fun runIo(result: MethodChannel.Result, work: () -> Map<String, Any>) {
        ioExecutor.execute {
            try {
                val value = work()
                runOnUiThread { result.success(value) }
            } catch (error: DocumentOperationException) {
                runOnUiThread { result.error(error.code, error.message, null) }
            } catch (error: Exception) {
                runOnUiThread { result.error("document_io_failed", error.message ?: error.javaClass.simpleName, null) }
            }
        }
    }

    private fun createSparse(call: MethodCall): Map<String, Any> {
        val treeUri = requiredUri(call, "treeUri")
        val directoryPath = requiredString(call, "directoryPath").trimEnd('/')
        val requestedName = requiredString(call, "name")
        val size = (call.argument<Number>("size") ?: error("Missing size")).toLong()
        require(size > 0) { "Image size must be positive" }

        val documentUri = createDocument(treeUri, requestedName, "application/octet-stream")
        try {
            contentResolver.openFileDescriptor(documentUri, "rw")?.use { descriptor ->
                FileOutputStream(descriptor.fileDescriptor).channel.use { channel ->
                    channel.position(size - 1)
                    channel.write(ByteBuffer.wrap(byteArrayOf(0)))
                    channel.force(true)
                }
            } ?: error("Unable to open the created image")
        } catch (error: Exception) {
            DocumentsContract.deleteDocument(contentResolver, documentUri)
            throw error
        }
        val actualName = queryDisplayName(documentUri) ?: requestedName
        return documentResult(documentUri, "$directoryPath/$actualName", actualName, size)
    }

    private fun copyDocument(call: MethodCall): Map<String, Any> {
        val sourceUri = requiredUri(call, "sourceUri")
        val treeUri = requiredUri(call, "treeUri")
        val directoryPath = requiredString(call, "directoryPath").trimEnd('/')
        val operationId = requiredString(call, "operationId")
        val cancelled = AtomicBoolean(false)
        check(copyCancellation.putIfAbsent(operationId, cancelled) == null) { "Duplicate copy operation" }
        val requestedName = queryDisplayName(sourceUri) ?: error("Unable to determine source filename")
        val mimeType = contentResolver.getType(sourceUri) ?: "application/octet-stream"
        val total = querySize(sourceUri)
        val available = StatFs(directoryPath).availableBytes
        if (total > 0 && total > available) {
            copyCancellation.remove(operationId)
            throw DocumentOperationException("insufficient_space", "Not enough free space in the selected directory")
        }
        var targetUri: Uri? = null
        var copied = 0L
        try {
            val createdUri = createDocument(treeUri, requestedName, mimeType)
            targetUri = createdUri
            emitCopyProgress(operationId, copied, total)
            contentResolver.openInputStream(sourceUri)?.use { input ->
                contentResolver.openOutputStream(createdUri, "w")?.use { output ->
                    val buffer = ByteArray(1024 * 1024)
                    while (true) {
                        if (cancelled.get()) {
                            throw DocumentOperationException("copy_cancelled", "Copy cancelled")
                        }
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        copied += count
                        emitCopyProgress(operationId, copied, total)
                    }
                    output.flush()
                } ?: error("Unable to open destination file")
            } ?: error("Unable to open source file")
        } catch (error: Exception) {
            targetUri?.let { runCatching { DocumentsContract.deleteDocument(contentResolver, it) } }
            throw error
        } finally {
            copyCancellation.remove(operationId)
        }
        val completedUri = checkNotNull(targetUri)
        val actualName = queryDisplayName(completedUri) ?: requestedName
        emitCopyProgress(operationId, copied, if (total > 0) total else copied)
        return documentResult(completedUri, "$directoryPath/$actualName", actualName, copied)
    }

    private fun emitCopyProgress(operationId: String, copied: Long, total: Long) {
        runOnUiThread {
            documentEventSink?.success(
                mapOf("operationId" to operationId, "copiedBytes" to copied, "totalBytes" to total),
            )
        }
    }

    private fun createDocument(treeUri: Uri, name: String, mimeType: String): Uri {
        val parent = DocumentsContract.buildDocumentUriUsingTree(
            treeUri,
            DocumentsContract.getTreeDocumentId(treeUri),
        )
        return DocumentsContract.createDocument(contentResolver, parent, mimeType, name)
            ?: error("The selected provider refused to create the file")
    }

    private fun documentResult(uri: Uri, path: String, name: String, size: Long) = mapOf<String, Any>(
        "uri" to uri.toString(),
        "path" to path,
        "name" to name,
        "size" to size,
    )

    private fun requiredString(call: MethodCall, key: String): String =
        call.argument<String>(key)?.takeIf { it.isNotBlank() } ?: error("Missing $key")

    private fun requiredUri(call: MethodCall, key: String): Uri = Uri.parse(requiredString(call, key))

    private fun queryDisplayName(uri: Uri): String? =
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }

    private fun querySize(uri: Uri): Long =
        contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getLong(0) else 0L
        } ?: 0L

    @Deprecated("Deprecated in Android API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == screenCaptureRequest) {
            val result = pendingScreenCapture ?: return
            pendingScreenCapture = null
            if (resultCode != Activity.RESULT_OK || data == null) {
                result.success(false)
            } else {
                startForegroundService(
                    Intent(this, UvcScreenCaptureService::class.java).apply {
                        action = UvcScreenCaptureService.ACTION_START
                        putExtra(UvcScreenCaptureService.EXTRA_RESULT_CODE, resultCode)
                        putExtra(UvcScreenCaptureService.EXTRA_RESULT_DATA, data)
                    },
                )
                result.success(true)
            }
            return
        }
        val result = pendingPicker ?: return
        pendingPicker = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        val grantedFlags = data.flags and
            (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        try {
            contentResolver.takePersistableUriPermission(uri, grantedFlags)
        } catch (error: SecurityException) {
            // Xiaomi FileExplorer can return a temporary FileProvider grant
            // even for ACTION_OPEN_DOCUMENT. A direct, Core-verified shared-
            // storage path does not depend on persisting that URI grant. Tree
            // selections still require persistence for later managed deletes.
            if (requestCode == 4102) {
                result.error("permission_failed", error.message, null)
                return
            }
        }

        if (requestCode == 4101 || requestCode == 4103) {
            val name = queryDisplayName(uri)
            if (name == null) {
                result.error("invalid_document", "Unable to determine the selected filename", null)
            } else {
                val value = mutableMapOf<String, Any>(
                    "uri" to uri.toString(),
                    "name" to name,
                    "size" to querySize(uri),
                )
                resolvePrimaryStoragePath(uri)?.let { value["directPath"] = it }
                result.success(value)
            }
            return
        }

        val documentId = DocumentsContract.getTreeDocumentId(uri)
        if (!documentId.startsWith("primary:")) {
            result.error("unsupported_directory", "Select a folder in internal shared storage", null)
            return
        }
        val relative = documentId.removePrefix("primary:").trim('/')
        val path = if (relative.isEmpty()) "/storage/emulated/0" else "/storage/emulated/0/$relative"
        result.success(mapOf("uri" to uri.toString(), "path" to path))
    }

    private fun resolvePrimaryStoragePath(uri: Uri): String? {
        PrimaryStoragePathResolver.resolveXiaomiFileProvider(uri.authority, uri.pathSegments)?.let {
            return it
        }
        if (!DocumentsContract.isDocumentUri(this, uri)) return null
        val documentId = runCatching { DocumentsContract.getDocumentId(uri) }.getOrNull() ?: return null
        return PrimaryStoragePathResolver.resolve(uri.authority, documentId)
    }

    private class DocumentOperationException(val code: String, message: String) : IOException(message)

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == cameraPermissionRequest) {
            val result = pendingCameraPermission ?: return
            pendingCameraPermission = null
            result.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
        }
    }

    override fun onDestroy() {
        uvcProducer.close()
        ioExecutor.shutdown()
        super.onDestroy()
    }
}

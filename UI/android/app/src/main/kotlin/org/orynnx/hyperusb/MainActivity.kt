package org.orynnx.hyperusb

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val documentsChannel = "org.orynnx.hyperusb/documents"
    private val uvcChannel = "org.orynnx.hyperusb/uvc"
    private val cameraPermissionRequest = 4201
    private val screenCaptureRequest = 4202
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private var pendingPicker: MethodChannel.Result? = null
    private var pendingCameraPermission: MethodChannel.Result? = null
    private var pendingScreenCapture: MethodChannel.Result? = null
    private lateinit var uvcProducer: UvcProducerController

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        uvcProducer = UvcProducerController(this)
        MethodChannel(engine.dartExecutor.binaryMessenger, documentsChannel)
            .setMethodCallHandler(::handleDocumentCall)
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
                },
                4101,
                result,
            )
            "pickVideo" -> openPicker(
                Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "video/*"
                },
                4103,
                result,
            )
            "pickDirectory" -> openPicker(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE), 4102, result)
            "createSparse" -> runIo(result) { createSparse(call) }
            "copyDocument" -> runIo(result) { copyDocument(call) }
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
        val requestedName = queryDisplayName(sourceUri) ?: error("Unable to determine source filename")
        val mimeType = contentResolver.getType(sourceUri) ?: "application/octet-stream"
        val targetUri = createDocument(treeUri, requestedName, mimeType)
        var copied = 0L
        try {
            contentResolver.openInputStream(sourceUri)?.use { input ->
                contentResolver.openOutputStream(targetUri, "w")?.use { output ->
                    val buffer = ByteArray(1024 * 1024)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        copied += count
                    }
                    output.flush()
                } ?: error("Unable to open destination file")
            } ?: error("Unable to open source file")
        } catch (error: Exception) {
            DocumentsContract.deleteDocument(contentResolver, targetUri)
            throw error
        }
        val actualName = queryDisplayName(targetUri) ?: requestedName
        return documentResult(targetUri, "$directoryPath/$actualName", actualName, copied)
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
            result.error("permission_failed", error.message, null)
            return
        }

        if (requestCode == 4101 || requestCode == 4103) {
            val name = queryDisplayName(uri)
            if (name == null) {
                result.error("invalid_document", "Unable to determine the selected filename", null)
            } else {
                result.success(mapOf("uri" to uri.toString(), "name" to name, "size" to querySize(uri)))
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

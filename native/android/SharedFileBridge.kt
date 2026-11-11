package com.yahia.sharem

import android.content.ContentValues
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.net.URLConnection
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Handles Android Sharesheet ACTION_SEND / ACTION_SEND_MULTIPLE and exports
 * received files to Downloads/ShareM (Android 10+).
 *
 * Uri streams are copied off the UI thread with a hard cache quota. The app
 * never treats an external URI string as a filesystem path, and shared files
 * still go through the normal explicit receiver-approval transfer flow.
 */
class SharedFileBridge(
    private val activity: FlutterActivity,
    messenger: BinaryMessenger
) : EventChannel.StreamHandler {
    private val worker = Executors.newSingleThreadExecutor()
    private val lock = Any()
    private val pending = ArrayList<Map<String, Any>>()
    private var eventSink: EventChannel.EventSink? = null
    private val staging = File(activity.cacheDir, "sharem_incoming_shares")
    private val maxSharedFileBytes = 2L * 1024L * 1024L * 1024L
    private val maxSharedItems = 50

    init {
        MethodChannel(messenger, "sharem/shared_files").setMethodCallHandler {
            call, result ->
            when (call.method) {
                "takePending" -> {
                    val items = synchronized(lock) {
                        val queued = pending.toList()
                        pending.clear()
                        queued
                    }
                    result.success(items)
                }
                "saveToDownloads" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty()) {
                        result.error("bad_path", "Missing file path", null)
                    } else {
                        saveToDownloads(path, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "sharem/shared_files/events")
            .setStreamHandler(this)
        worker.execute { clearStaleCache() }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        if (synchronized(lock) { pending.isNotEmpty() }) {
            eventSink?.success("ready")
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun accept(intent: Intent?) {
        if (intent == null ||
            (intent.action != Intent.ACTION_SEND &&
             intent.action != Intent.ACTION_SEND_MULTIPLE)) return

        // Read the URI references now, while Android has granted access.
        @Suppress("DEPRECATION")
        val single = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        @Suppress("DEPRECATION")
        val multiple = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
        val uris = if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            multiple?.toList() ?: emptyList()
        } else {
            listOfNotNull(single)
        }
        val selected = if (uris.isNotEmpty()) uris else {
            val clip = intent.clipData
            if (clip == null) emptyList() else
                (0 until clip.itemCount).mapNotNull { clip.getItemAt(it).uri }
        }
        if (selected.isEmpty()) {
            enqueue(mapOf("error" to
                "لم يصل ملف قابل للإرسال. افتح مشاركة ملف من التطبيق الآخر."))
            return
        }
        worker.execute {
            if (selected.size > maxSharedItems) {
                enqueue(mapOf("error" to "يمكن مشاركة 50 ملفًا دفعة واحدة كحد أقصى."))
                return@execute
            }
            try {
                staging.mkdirs()
                var totalBytes = 0L
                selected.forEachIndexed { index, uri ->
                    if (uri.scheme != "content") {
                        enqueue(mapOf("error" to "تعذر قراءة الملف المحدد."))
                        return@forEachIndexed
                    }
                    try {
                        val item = stage(uri, index)
                        totalBytes += (item["size"] as Long)
                        if (totalBytes > 4L * 1024L * 1024L * 1024L) {
                            File(item["path"] as String).delete()
                            enqueue(mapOf("error" to
                                "حجم الملفات المشتركة كبير جدًا. اخترها من داخل ShareM."))
                            return@execute
                        }
                        enqueue(item)
                    } catch (error: Exception) {
                        enqueue(mapOf("error" to
                            "تعذر استيراد أحد الملفات: " +
                            (error.message ?: "تعذر الوصول إلى الملف")))
                    }
                }
            } catch (_: Exception) {
                enqueue(mapOf("error" to "تعذّر استيراد الملفات المشتركة."))
            }
        }
    }

    private fun stage(uri: Uri, index: Int): Map<String, Any> {
        val resolver = activity.contentResolver
        var original: String? = null
        var declaredSize: Long? = null
        resolver.query(uri, arrayOf(
            OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
            null, null, null)?.use { cursor: Cursor ->
            if (cursor.moveToFirst()) {
                val nameColumn = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                val sizeColumn = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (nameColumn >= 0 && !cursor.isNull(nameColumn)) {
                    original = cursor.getString(nameColumn)
                }
                if (sizeColumn >= 0 && !cursor.isNull(sizeColumn)) {
                    declaredSize = cursor.getLong(sizeColumn)
                }
            }
        }
        if ((declaredSize ?: 0L) > maxSharedFileBytes) {
            throw IllegalArgumentException("يتجاوز الملف حجم المشاركة المباشرة المسموح")
        }
        val name = safeName(original ?: ("shared-" + (index + 1)))
        val output = File(staging, UUID.randomUUID().toString() + "-" + name)
        var written = 0L
        try {
            val input = resolver.openInputStream(uri)
                ?: throw IllegalArgumentException("تعذر فتح محتوى الملف")
            input.use { source ->
                FileOutputStream(output).use { sink ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val size = source.read(buffer)
                        if (size == -1) break
                        written += size
                        if (written > maxSharedFileBytes) {
                            throw IllegalArgumentException("الملف كبير جدًا")
                        }
                        if (written > activity.cacheDir.usableSpace +
                            output.length()) {
                            throw IllegalArgumentException("لا توجد مساحة كافية")
                        }
                        sink.write(buffer, 0, size)
                    }
                    sink.fd.sync()
                }
            }
            return mapOf("name" to name, "path" to output.absolutePath,
                "size" to written)
        } catch (error: Exception) {
            output.delete()
            throw error
        }
    }

    private fun safeName(raw: String): String {
        val leaf = raw.substringAfterLast('/').substringAfterLast('\\')
            .map { char ->
                if (char.code < 32 || char in "<>:\"|?*") '_' else char
            }.joinToString("").trim().trim('.', ' ')
        return if (leaf.isEmpty()) "shared-file"
            else leaf.takeLast(120)
    }

    private fun enqueue(message: Map<String, Any>) {
        synchronized(lock) { pending.add(message) }
        activity.runOnUiThread { eventSink?.success("ready") }
    }

    private fun clearStaleCache() {
        val now = System.currentTimeMillis()
        staging.listFiles()?.forEach { file ->
            if (file.isFile &&
                now - file.lastModified() > 24L * 60L * 60L * 1000L) {
                file.delete()
            }
        }
    }

    private fun saveToDownloads(path: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("unsupported",
                "حفظ التنزيلات المباشر يتطلب Android 10 أو أحدث. استخدم مشاركة الملف.",
                null)
            return
        }
        worker.execute {
            var created: Uri? = null
            try {
                val source = File(path).canonicalFile
                val privateRoot = File(activity.applicationInfo.dataDir)
                    .canonicalFile
                if (!source.path.startsWith(privateRoot.path + File.separator) ||
                    !source.path.contains("/ShareM/Received/") ||
                    !source.isFile) {
                    throw IllegalArgumentException("الملف غير موجود في ملفات ShareM المستقبلة")
                }
                val name = safeName(source.name)
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                    put(MediaStore.MediaColumns.MIME_TYPE,
                        URLConnection.guessContentTypeFromName(name)
                            ?: "application/octet-stream")
                    put(MediaStore.MediaColumns.RELATIVE_PATH,
                        Environment.DIRECTORY_DOWNLOADS + "/ShareM")
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                val resolver = activity.contentResolver
                created = resolver.insert(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                    ?: throw IllegalStateException("تعذّر إنشاء ملف في التنزيلات")
                val target = created
                    ?: throw IllegalStateException("تعذّر فتح ملف التنزيلات")
                resolver.openOutputStream(target, "w")?.use { sink ->
                    source.inputStream().use { input -> input.copyTo(sink, 64 * 1024) }
                } ?: throw IllegalStateException("لا يمكن الكتابة في التنزيلات")
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(target, values, null, null)
                activity.runOnUiThread { result.success(target.toString()) }
            } catch (error: Exception) {
                created?.let { uri ->
                    try { activity.contentResolver.delete(uri, null, null) }
                    catch (_: Exception) {}
                }
                activity.runOnUiThread {
                    result.error("export_failed",
                        error.message ?: "تعذّر حفظ الملف في التنزيلات", null)
                }
            }
        }
    }

    fun close() {
        worker.shutdown()
    }
}

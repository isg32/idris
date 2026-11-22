package com.isg32.idris

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * "On this phone" (see lib/platform/local_music.dart): folders the user
 * chooses through Android's folder picker (the Storage Access Framework),
 * which also grants lasting access to just that folder, so no storage
 * permission is needed. Lists the audio in them, reads their tags and
 * embedded pictures. Playback reads the content:// URIs directly.
 */
object LocalMusic {
    private const val CHANNEL = "idris/local"
    private const val PICK = 4711

    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null

    private val audioExtensions = setOf(
        "mp3", "m4a", "aac", "flac", "ogg", "oga", "opus", "wav", "wma", "alac", "aiff", "aif", "mka", "webm",
    )

    fun register(activity: Activity, messenger: BinaryMessenger) {
        val app = activity.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFolder" -> {
                    pending?.success(null)
                    pending = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
                    )
                    activity.startActivityForResult(intent, PICK)
                }
                "list" -> background(result) { list(app, Uri.parse(call.argument<String>("uri")!!)) }
                "tags" -> background(result) { call.argument<List<String>>("uris")!!.map { tags(app, it) } }
                "art" -> background(result) { art(app, call.argument<String>("uri")!!, call.argument<String>("out")!!) }
                "forget" -> {
                    try {
                        app.contentResolver.releasePersistableUriPermission(
                            Uri.parse(call.argument<String>("uri")!!),
                            Intent.FLAG_GRANT_READ_URI_PERMISSION,
                        )
                    } catch (_: SecurityException) {
                        // Already gone.
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /** The folder picker's answer (from MainActivity.onActivityResult). */
    fun onActivityResult(context: Context, requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK) return false
        val result = pending ?: return true
        pending = null
        val tree = data?.data
        if (resultCode != Activity.RESULT_OK || tree == null) {
            result.success(null)
            return true
        }
        try {
            context.contentResolver.takePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            result.success(mapOf("uri" to tree.toString(), "name" to folderName(context, tree)))
        } catch (e: Exception) {
            result.error("local", e.message ?: e.javaClass.simpleName, null)
        }
        return true
    }

    private fun <T> background(result: MethodChannel.Result, work: () -> T) {
        io.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("local", e.message ?: e.javaClass.simpleName, null) }
            }
        }
    }

    private fun folderName(context: Context, tree: Uri): String {
        val doc = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        context.contentResolver.query(
            doc, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null,
        )?.use { c -> if (c.moveToFirst()) return c.getString(0) ?: "" }
        return ""
    }

    /** Every audio file in [tree] and the folders inside it. */
    private fun list(context: Context, tree: Uri): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        val todo = ArrayDeque<String>().apply { add(DocumentsContract.getTreeDocumentId(tree)) }
        val columns = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        while (todo.isNotEmpty()) {
            val parent = todo.removeFirst()
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parent)
            context.contentResolver.query(children, columns, null, null, null)?.use { c ->
                while (c.moveToNext()) {
                    val id = c.getString(0) ?: continue
                    val name = c.getString(1) ?: ""
                    val mime = c.getString(2) ?: ""
                    if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                        // Hidden folders (".thumbnails") hold no music.
                        if (!name.startsWith(".")) todo.add(id)
                        continue
                    }
                    val ext = name.substringAfterLast('.', "").lowercase()
                    if (!mime.startsWith("audio/") && ext !in audioExtensions) continue
                    out.add(
                        mapOf(
                            "uri" to DocumentsContract.buildDocumentUriUsingTree(tree, id).toString(),
                            "name" to name,
                            "bytes" to if (c.isNull(3)) 0L else c.getLong(3),
                            "modified" to if (c.isNull(4)) 0L else c.getLong(4),
                        ),
                    )
                }
            }
        }
        return out
    }

    private fun tags(context: Context, uri: String): Map<String, Any?> {
        val r = MediaMetadataRetriever()
        return try {
            r.setDataSource(context, Uri.parse(uri))
            mapOf(
                "title" to r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE),
                "artist" to (
                    r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST)
                        ?: r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUMARTIST)
                    ),
                "duration" to (r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L),
            )
        } catch (_: Exception) {
            // Unreadable tags: the file name stands in.
            emptyMap()
        } finally {
            r.release()
        }
    }

    private fun art(context: Context, uri: String, out: String): Boolean {
        val r = MediaMetadataRetriever()
        return try {
            r.setDataSource(context, Uri.parse(uri))
            val picture = r.embeddedPicture ?: return false
            val file = File(out)
            file.parentFile?.mkdirs()
            val tmp = File("$out.part")
            tmp.writeBytes(picture)
            tmp.renameTo(file)
        } catch (_: Exception) {
            false
        } finally {
            r.release()
        }
    }
}

package com.example.electrowave_mobile

import android.app.Activity
import android.app.RecoverableSecurityException
import android.content.ContentUris
import android.content.Intent
import android.content.IntentSender
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.MediaStore
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.FileInputStream
import java.util.concurrent.Executors

/**
 * Write access to audio files the app does not own.
 *
 * Under scoped storage (Android 10+) every shared-storage file another app
 * created, or the user copied over USB, is read-only to us: READ_MEDIA_AUDIO
 * covers reading, and a plain `File` write fails with EACCES. The only way to
 * modify such a file is to ask the user — [MediaStore.createWriteRequest] on
 * 11+, the [RecoverableSecurityException] dialog on 10 — then write through
 * the ContentResolver: the grant is on the content URI, not the file path.
 *
 * Android 9 and older keep using direct file writes (WRITE_EXTERNAL_STORAGE,
 * requested from Dart).
 */
class MediaWriteAccess(private val activity: Activity) : MethodChannel.MethodCallHandler {

    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    /** The `request` call waiting on the system consent dialog. */
    private var pending: MethodChannel.Result? = null
    private var pendingUri: Uri? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "request" -> {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("bad_args", "path is required", null)
                } else {
                    request(path, result)
                }
            }
            "write" -> {
                val uri = call.argument<String>("uri")
                val source = call.argument<String>("source")
                if (uri == null || source == null) {
                    result.error("bad_args", "uri and source are required", null)
                } else {
                    write(Uri.parse(uri), source, result)
                }
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Resolves [path] to its MediaStore item and makes sure we may write it.
     *
     * Answers `{mode: "legacy"}` below Android 10 (Dart writes the path
     * directly), `{mode: "uri", uri}` once write access is held, or
     * `{mode: "denied"}` when the user declines.
     */
    private fun request(path: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success(mapOf("mode" to "legacy"))
            return
        }
        io.execute {
            val uri = findUri(path) ?: scanThenFind(path)
            if (uri == null) {
                main.post { result.error("not_indexed", "No MediaStore entry for $path", null) }
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                main.post { requestWrite(uri, result) }
            } else {
                requestWriteQ(uri, result)
            }
        }
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private fun requestWrite(uri: Uri, result: MethodChannel.Result) {
        val granted = activity.checkUriPermission(
            uri,
            Process.myPid(),
            Process.myUid(),
            Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) {
            result.success(grantedAnswer(uri))
            return
        }
        try {
            val intent = MediaStore.createWriteRequest(activity.contentResolver, listOf(uri))
            askUser(intent.intentSender, uri, result)
        } catch (e: Exception) {
            result.error("request_failed", e.toString(), null)
        }
    }

    /**
     * Android 10 has no createWriteRequest: opening the file for writing
     * either succeeds, or throws a [RecoverableSecurityException] carrying the
     * consent dialog. Runs on [io]; "rw" opens without truncating.
     */
    @RequiresApi(Build.VERSION_CODES.Q)
    private fun requestWriteQ(uri: Uri, result: MethodChannel.Result) {
        try {
            activity.contentResolver.openFileDescriptor(uri, "rw")?.close()
            main.post { result.success(grantedAnswer(uri)) }
        } catch (e: RecoverableSecurityException) {
            main.post { askUser(e.userAction.actionIntent.intentSender, uri, result) }
        } catch (e: Exception) {
            main.post { result.error("request_failed", e.toString(), null) }
        }
    }

    private fun askUser(sender: IntentSender, uri: Uri, result: MethodChannel.Result) {
        // One dialog at a time; a second request supersedes the first.
        pending?.error("superseded", "Another write request started", null)
        pending = result
        pendingUri = uri
        try {
            activity.startIntentSenderForResult(sender, REQUEST_CODE, null, 0, 0, 0)
        } catch (e: Exception) {
            pending = null
            pendingUri = null
            result.error("request_failed", e.toString(), null)
        }
    }

    private fun grantedAnswer(uri: Uri) = mapOf("mode" to "uri", "uri" to uri.toString())

    /** Called from the activity; true when the result was ours. */
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pending ?: return true
        val uri = pendingUri
        pending = null
        pendingUri = null
        if (resultCode == Activity.RESULT_OK && uri != null) {
            result.success(grantedAnswer(uri))
        } else {
            result.success(mapOf("mode" to "denied"))
        }
        return true
    }

    /**
     * Replaces the content of [uri] with the bytes of [source]. Runs off the
     * main thread: lossless files are tens of megabytes.
     */
    private fun write(uri: Uri, source: String, result: MethodChannel.Result) {
        io.execute {
            try {
                val out = activity.contentResolver.openOutputStream(uri, "wt")
                    ?: throw IllegalStateException("Could not open $uri for writing")
                out.use { stream ->
                    FileInputStream(source).use { input -> input.copyTo(stream, 1 shl 16) }
                }
                main.post { result.success(null) }
            } catch (e: Exception) {
                main.post { result.error("write_failed", e.toString(), null) }
            }
        }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun findUri(path: String): Uri? {
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.VOLUME_NAME,
            MediaStore.Files.FileColumns.MEDIA_TYPE,
        )
        activity.contentResolver.query(
            MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL),
            projection,
            "${MediaStore.MediaColumns.DATA} = ?",
            arrayOf(path),
            null,
        )?.use { cursor ->
            if (!cursor.moveToFirst()) return null
            val id = cursor.getLong(0)
            val volume = cursor.getString(1)
            val mediaType = cursor.getInt(2)
            val collection = if (mediaType == MediaStore.Files.FileColumns.MEDIA_TYPE_AUDIO) {
                MediaStore.Audio.Media.getContentUri(volume)
            } else {
                MediaStore.Files.getContentUri(volume)
            }
            return ContentUris.withAppendedId(collection, id)
        }
        return null
    }

    /** A file MediaStore has not indexed yet (just copied in): index it now. */
    @RequiresApi(Build.VERSION_CODES.Q)
    private fun scanThenFind(path: String): Uri? {
        val done = java.util.concurrent.CountDownLatch(1)
        MediaScannerConnection.scanFile(activity, arrayOf(path), null) { _, _ -> done.countDown() }
        done.await(10, java.util.concurrent.TimeUnit.SECONDS)
        return findUri(path)
    }

    private companion object {
        const val REQUEST_CODE = 0x7a65
    }
}

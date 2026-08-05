package com.mycompany.CounterApp

import android.content.Intent
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Hosts the "markless/drive_picker" channel: opens the Google Drive app's
/// OWN picker (not the generic system Files UI) so "From Drive" actually
/// lands the teacher in their Drive. Falls back with an error code the
/// Dart side catches when the Drive app isn't installed.
/// FlutterFragmentActivity (not FlutterActivity) because RevenueCat's
/// paywall and Customer Center render in fragments.
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "markless/drive_picker"
    private val requestCode = 4471
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            if (call.method == "pickFromDrive") {
                if (pendingResult != null) {
                    result.error("busy", "A picker is already open", null)
                    return@setMethodCallHandler
                }
                val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                    type = "*/*"
                    putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "application/pdf"))
                    addCategory(Intent.CATEGORY_OPENABLE)
                    putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                    // Target the Drive app directly instead of the system picker.
                    setPackage("com.google.android.apps.docs")
                }
                try {
                    pendingResult = result
                    startActivityForResult(intent, requestCode)
                } catch (e: Exception) {
                    pendingResult = null
                    result.error("no_drive", "Google Drive app not available", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != this.requestCode) return
        val res = pendingResult ?: return
        pendingResult = null

        if (resultCode != RESULT_OK || data == null) {
            res.success(mapOf("picked" to 0, "files" to emptyList<Any>()))
            return
        }

        val uris = mutableListOf<android.net.Uri>()
        val clip = data.clipData
        if (clip != null) {
            for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)
        } else {
            data.data?.let { uris.add(it) }
        }

        // Drive files may need a real download — never block the UI thread.
        Thread {
            val out = mutableListOf<Map<String, Any>>()
            for (u in uris) {
                try {
                    contentResolver.openInputStream(u)?.use { stream ->
                        val bytes = stream.readBytes()
                        var name = "drive_image.jpg"
                        contentResolver.query(u, null, null, null, null)?.use { c ->
                            val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                            if (c.moveToFirst() && idx >= 0) name = c.getString(idx) ?: name
                        }
                        val mime = contentResolver.getType(u) ?: ""
                        out.add(mapOf("name" to name, "mime" to mime, "bytes" to bytes))
                    }
                } catch (_: Exception) {
                    // Unreadable entry — the Dart side reports the shortfall.
                }
            }
            runOnUiThread { res.success(mapOf("picked" to uris.size, "files" to out)) }
        }.start()
    }
}

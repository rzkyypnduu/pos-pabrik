package com.poskrupuk.pos_krupuk

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingSafPickerResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "pos_krupuk/storage",
        ).setMethodCallHandler { call, result ->
            try {
                handleCall(call, result)
            } catch (e: Exception) {
                result.error("SAF_FAILED", e.message, null)
            }
        }
    }

    private fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasAllFilesAccess" -> {
                result.success(hasAllFilesAccess())
            }
            "requestAllFilesAccess" -> {
                if (hasAllFilesAccess()) {
                    result.success(true)
                } else {
                    runOnUiThread {
                        try {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                                    android.net.Uri.parse("package:$packageName"),
                                ),
                            )
                        } catch (_: Exception) {
                            startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
                        }
                    }
                    result.success(false)
                }
            }
            "pickSafDirectory" -> {
                pendingSafPickerResult = result
                runOnUiThread {
                    try {
                        startActivityForResult(
                            Intent(Intent.ACTION_OPEN_DOCUMENT_TREE),
                            SAF_PICKER_REQUEST_CODE,
                        )
                    } catch (e: Exception) {
                        val r = pendingSafPickerResult
                        pendingSafPickerResult = null
                        r?.error("SAF_FAILED", e.message, null)
                    }
                }
            }
            "safFileExists" -> {
                val args = call.arguments as Map<*, *>
                val treeUri = Uri.parse(args["treeUri"] as String)
                val subDir = args["subDir"] as String?
                val fileName = args["fileName"] as String
                val root = DocumentFile.fromTreeUri(this, treeUri)
                val target = if (subDir.isNullOrEmpty()) root else root?.findFile(subDir)
                result.success(target?.findFile(fileName)?.exists() ?: false)
            }
            "writeSafFile" -> {
                val args = call.arguments as Map<*, *>
                val treeUri = Uri.parse(args["treeUri"] as String)
                val subDir = args["subDir"] as String?
                val fileName = args["fileName"] as String
                val bytes = args["bytes"] as ByteArray
                val root = DocumentFile.fromTreeUri(this, treeUri)
                    ?: throw Exception("Folder tidak ditemukan")
                var target = root
                if (!subDir.isNullOrEmpty()) {
                    target = root.findFile(subDir)
                        ?: root.createDirectory(subDir)
                        ?: throw Exception("Gagal membuat folder")
                }
                target.findFile(fileName)?.delete()
                val created = target.createFile("application/octet-stream", fileName)
                    ?: throw Exception("Gagal membuat file")
                contentResolver.openOutputStream(created.uri).use { out ->
                    out?.write(bytes) ?: throw Exception("Gagal membuka file")
                }
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == SAF_PICKER_REQUEST_CODE) {
            val r = pendingSafPickerResult
            pendingSafPickerResult = null
            if (r == null) return
            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val uri = data.data!!
                try {
                    contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                    )
                } catch (_: Exception) {}
                r.success(uri.toString())
            } else {
                r.success(null)
            }
        }
    }

    private fun hasAllFilesAccess(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.R ||
            Environment.isExternalStorageManager()
    }

    companion object {
        private const val SAF_PICKER_REQUEST_CODE = 0x1001
    }
}

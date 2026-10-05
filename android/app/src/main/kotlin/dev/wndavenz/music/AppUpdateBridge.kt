package dev.wndavenz.music

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

object AppUpdateBridge {
    const val CHANNEL = "musicplayer/app_update"

    fun register(context: Context, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getVersionInfo" -> {
                        val info = context.packageManager.getPackageInfo(
                            context.packageName,
                            0
                        )
                        result.success(
                            mapOf(
                                "versionName" to (info.versionName ?: ""),
                                "versionCode" to versionCode(info)
                            )
                        )
                    }

                    "startApkDownload" -> {
                        val url = call.argument<String>("url")
                        val fileName = call.argument<String>("fileName")
                        if (url.isNullOrBlank() || fileName.isNullOrBlank()) {
                            result.error("INVALID_ARGUMENT", "URL/fileName kosong.", null)
                            return@setMethodCallHandler
                        }

                        val request = DownloadManager.Request(Uri.parse(url))
                            .setTitle("Music Player")
                            .setDescription("Mengunduh pembaruan $fileName")
                            .setMimeType("application/vnd.android.package-archive")
                            .setNotificationVisibility(
                                DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED
                            )
                            .setDestinationInExternalFilesDir(
                                context,
                                Environment.DIRECTORY_DOWNLOADS,
                                fileName
                            )
                            .setAllowedOverMetered(true)
                            .setAllowedOverRoaming(false)

                        val manager = context.getSystemService(
                            Context.DOWNLOAD_SERVICE
                        ) as DownloadManager

                        result.success(manager.enqueue(request))
                    }

                    "getDownloadStatus" -> {
                        val id = call.argument<Long>("id")
                            ?: call.argument<Int>("id")?.toLong()

                        if (id == null) {
                            result.error("INVALID_ARGUMENT", "Download ID kosong.", null)
                            return@setMethodCallHandler
                        }

                        result.success(getDownloadStatus(context, id))
                    }

                    "canInstallPackages" -> {
                        result.success(
                            Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                                context.packageManager.canRequestPackageInstalls()
                        )
                    }

                    "openInstallPermissionSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:${context.packageName}")
                            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            context.startActivity(intent)
                        }
                        result.success(null)
                    }

                    "installDownloadedApk" -> {
                        val id = call.argument<Long>("id")
                            ?: call.argument<Int>("id")?.toLong()

                        if (id == null) {
                            result.error("INVALID_ARGUMENT", "Download ID kosong.", null)
                            return@setMethodCallHandler
                        }

                        val manager = context.getSystemService(
                            Context.DOWNLOAD_SERVICE
                        ) as DownloadManager
                        val uri = manager.getUriForDownloadedFile(id)

                        if (uri == null) {
                            result.success(false)
                            return@setMethodCallHandler
                        }

                        val installIntent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(
                                uri,
                                "application/vnd.android.package-archive"
                            )
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        context.startActivity(installIntent)
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun versionCode(info: android.content.pm.PackageInfo): Long {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
    }

    private fun getDownloadStatus(context: Context, id: Long): Map<String, Any> {
        val manager = context.getSystemService(
            Context.DOWNLOAD_SERVICE
        ) as DownloadManager

        val query = DownloadManager.Query().setFilterById(id)
        manager.query(query).use { cursor ->
            if (!cursor.moveToFirst()) {
                return mapOf("status" to "failed", "downloaded" to 0L, "total" to 0L)
            }

            val status = cursor.getInt(
                cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
            )
            val downloaded = cursor.getLong(
                cursor.getColumnIndexOrThrow(
                    DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR
                )
            )
            val total = cursor.getLong(
                cursor.getColumnIndexOrThrow(
                    DownloadManager.COLUMN_TOTAL_SIZE_BYTES
                )
            )

            val state = when (status) {
                DownloadManager.STATUS_SUCCESSFUL -> "successful"
                DownloadManager.STATUS_FAILED -> "failed"
                else -> "running"
            }

            return mapOf(
                "status" to state,
                "downloaded" to downloaded,
                "total" to total
            )
        }
    }
}

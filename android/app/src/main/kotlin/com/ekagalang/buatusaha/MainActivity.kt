package com.ekagalang.buatusaha

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Saluran `buatusaha/app` untuk pembaruan dari dalam aplikasi (PRD
/// FR-11.4): jenis CPU HP, izin "pasang dari sumber ini", membuka penginstal
/// APK, dan membuka tautan di browser.
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "buatusaha/app")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "supportedAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
                        "canInstall" -> result.success(
                            Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                                packageManager.canRequestPackageInstalls()
                        )
                        "openInstallSettings" -> {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startActivity(
                                    Intent(
                                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                        Uri.parse("package:$packageName")
                                    )
                                )
                            }
                            result.success(null)
                        }
                        "install" -> {
                            val file = File(call.argument<String>("path")!!)
                            val uri = FileProvider.getUriForFile(
                                this, "$packageName.updates", file
                            )
                            startActivity(
                                Intent(Intent.ACTION_VIEW)
                                    .setDataAndType(uri, "application/vnd.android.package-archive")
                                    .addFlags(
                                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                            Intent.FLAG_ACTIVITY_NEW_TASK
                                    )
                            )
                            result.success(null)
                        }
                        "openUrl" -> {
                            startActivity(
                                Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url")))
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: ActivityNotFoundException) {
                    result.error("no_activity", e.message, null)
                } catch (e: Exception) {
                    result.error("failed", e.message, null)
                }
            }
    }
}

/// FileProvider sendiri supaya tidak bentrok dengan provider plugin lain.
class UpdateFileProvider : FileProvider()

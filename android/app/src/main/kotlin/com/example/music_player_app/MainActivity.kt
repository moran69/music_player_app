package com.example.music_player_app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.annotation.NonNull
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : AudioServiceActivity() {
    companion object {
        const val CHANNEL = "music_player/floating_capsule"
        const val INSTALL_CHANNEL = "music_player/install"
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val appContext = applicationContext

        // APK 在线更新安装：不依赖第三方插件，直接用系统安装器
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALL_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "installApk") {
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty()) {
                        result.error("BAD_PATH", "APK 路径为空", null)
                        return@setMethodCallHandler
                    }
                    val file = File(path)
                    if (!file.exists()) {
                        result.error("FILE_NOT_FOUND", "APK 文件不存在: $path", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val uri: Uri = FileProvider.getUriForFile(
                            appContext,
                            "${packageName}.fileProvider",
                            file
                        )
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        runOnUiThread {
                            try {
                                startActivity(intent)
                                result.success(null)
                            } catch (e: ActivityNotFoundException) {
                                result.error("NO_INSTALLER", "未找到可用的安装程序", null)
                            }
                        }
                    } catch (e: Exception) {
                        result.error("INSTALL_FAIL", e.message ?: "安装失败", null)
                    }
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasPermission" -> result.success(FloatCapsuleManager.hasPermission(appContext))
                    "openPermissionSettings" -> {
                        FloatCapsuleManager.openPermissionSettings(appContext)
                        result.success(null)
                    }
                    "show" -> {
                        val title = call.argument<String>("title") ?: ""
                        val artist = call.argument<String>("artist") ?: ""
                        val coverUrl = call.argument<String>("coverUrl")
                        val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                        runOnUiThread {
                            FloatCapsuleManager.show(
                                appContext, title, artist, coverUrl, isPlaying,
                                onPlayPause = {
                                    runOnUiThread {
                                        MethodChannel(
                                            flutterEngine.dartExecutor.binaryMessenger, CHANNEL
                                        ).invokeMethod("onPlayPauseTap", null)
                                    }
                                },
                                onTap = {
                                    runOnUiThread {
                                        MethodChannel(
                                            flutterEngine.dartExecutor.binaryMessenger, CHANNEL
                                        ).invokeMethod("onCapsuleTap", null)
                                    }
                                }
                            )
                        }
                        result.success(null)
                    }
                    "update" -> {
                        val title = call.argument<String>("title") ?: ""
                        val artist = call.argument<String>("artist") ?: ""
                        val coverUrl = call.argument<String>("coverUrl")
                        val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                        runOnUiThread {
                            FloatCapsuleManager.update(title, artist, coverUrl, isPlaying)
                        }
                        result.success(null)
                    }
                    "updatePlayState" -> {
                        val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                        runOnUiThread { FloatCapsuleManager.updatePlayState(isPlaying) }
                        result.success(null)
                    }
                    "hide" -> {
                        runOnUiThread { FloatCapsuleManager.hide() }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}

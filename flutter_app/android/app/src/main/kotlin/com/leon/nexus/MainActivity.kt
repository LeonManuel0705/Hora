package com.leon.nexus

import android.app.ActivityManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.StatFs
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    private val CHANNEL = "app/focus_mode"
    private val ASSISTANT_MODEL_CHANNEL = "app/assistant_model"
    private var previousInterruptionFilter: Int = NotificationManager.INTERRUPTION_FILTER_ALL

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enableFocusMode" -> {
                    result.success(enableDoNotDisturb())
                }
                "disableFocusMode" -> {
                    result.success(disableDoNotDisturb())
                }
                "hasPermission" -> {
                    result.success(hasDoNotDisturbPermission())
                }
                "requestPermission" -> {
                    requestDoNotDisturbPermission()
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ASSISTANT_MODEL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "profile" -> result.success(assistantModelProfile())
                "memory" -> result.success(memorySnapshot())
                "freeSpace" -> {
                    val path = call.argument<String>("path")
                    result.success(if (path == null) null else freeBytes(path))
                }
                "keepScreenOn" -> {
                    val on = call.argument<Boolean>("on") ?: false
                    runOnUiThread {
                        if (on) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                    }
                    result.success(null)
                }
                "excludeFromBackup" -> result.success(true)
                else -> result.notImplemented()
            }
        }
    }

    private fun assistantModelProfile(): Map<String, Any?> {
        val directory = File(noBackupFilesDir, "assistant-model")
        directory.mkdirs()
        val memory = memorySnapshot()
        return mapOf(
            "directory" to directory.absolutePath,
            "freeBytes" to freeBytes(directory.absolutePath),
            "totalMemory" to memory["total"],
            "availableMemory" to memory["available"],
        )
    }

    private fun memorySnapshot(): Map<String, Any> {
        val info = ActivityManager.MemoryInfo()
        (getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(info)
        return mapOf(
            "total" to info.totalMem,
            "available" to info.availMem,
            "low" to info.lowMemory,
        )
    }

    private fun freeBytes(path: String): Long? {
        return try {
            StatFs(path).availableBytes
        } catch (e: Exception) {
            null
        }
    }

    private fun hasDoNotDisturbPermission(): Boolean {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return notificationManager.isNotificationPolicyAccessGranted
    }

    private fun requestDoNotDisturbPermission() {
        if (!hasDoNotDisturbPermission()) {
            val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
            startActivity(intent)
        }
    }

    private fun enableDoNotDisturb(): Boolean {
        if (!hasDoNotDisturbPermission()) {
            return false
        }

        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            previousInterruptionFilter = notificationManager.currentInterruptionFilter

            notificationManager.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_PRIORITY)
            return true
        } catch (e: Exception) {
            return false
        }
    }

    private fun disableDoNotDisturb(): Boolean {
        if (!hasDoNotDisturbPermission()) {
            return false
        }

        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            notificationManager.setInterruptionFilter(previousInterruptionFilter)
            return true
        } catch (e: Exception) {
            return false
        }
    }
}

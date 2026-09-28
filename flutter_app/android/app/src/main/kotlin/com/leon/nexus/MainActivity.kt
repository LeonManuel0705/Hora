package com.leon.nexus

import android.app.ActivityManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    private val CHANNEL = "app/focus_mode"
    private val ASSISTANT_MODEL_CHANNEL = "app/assistant_model"
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
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
                "network" -> result.success(networkStatus())
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "$ASSISTANT_MODEL_CHANNEL/network").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    watchNetwork(events)
                }

                override fun onCancel(arguments: Any?) {
                    stopWatchingNetwork()
                }
            }
        )
    }

    override fun onDestroy() {
        stopWatchingNetwork()
        super.onDestroy()
    }

    private fun networkStatus(): Map<String, Boolean> {
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val capabilities = manager.activeNetwork?.let { manager.getNetworkCapabilities(it) }
        val connected = capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
        return mapOf("connected" to connected, "metered" to (connected && manager.isActiveNetworkMetered))
    }

    private fun watchNetwork(events: EventChannel.EventSink) {
        stopWatchingNetwork()
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val main = Handler(Looper.getMainLooper())
        var last: Map<String, Boolean>? = null
        fun report() {
            main.post {
                val status = networkStatus()
                if (status != last) {
                    last = status
                    events.success(status)
                }
            }
        }
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = report()
            override fun onLost(network: Network) = report()
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) = report()
        }
        try {
            manager.registerDefaultNetworkCallback(callback)
            networkCallback = callback
        } catch (e: Exception) {
            events.error("network", e.message, null)
            return
        }
        report()
    }

    private fun stopWatchingNetwork() {
        val callback = networkCallback ?: return
        networkCallback = null
        try {
            (getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager).unregisterNetworkCallback(callback)
        } catch (e: Exception) {
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

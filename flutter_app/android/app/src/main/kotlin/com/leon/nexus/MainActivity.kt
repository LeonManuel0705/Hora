package com.leon.nexus

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "app/focus_mode"
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

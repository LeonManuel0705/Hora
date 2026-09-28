import Flutter
import UIKit
import os
import workmanager
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    UNUserNotificationCenter.current().delegate = self

    // Register each BGAppRefresh task identifier the Dart code schedules. These
    // MUST match the uniqueNames in background_service.dart AND the
    // BGTaskSchedulerPermittedIdentifiers in Info.plist, otherwise
    // BGTaskScheduler rejects the submissions and no background task ever runs.
    // registerPeriodicTask installs a BGAppRefreshTask handler (the correct
    // type) — unlike the old registerTask, which wrongly installed a
    // BGProcessingTask handler.
    let refreshIdentifiers = [
      "email_sync_periodic",
      "calendar_sync_periodic",
      "iserv_sync_periodic",
      "update_check_periodic",
      "cache_cleanup_periodic",
      "offline_queue_periodic",
    ]
    for identifier in refreshIdentifiers {
      WorkmanagerPlugin.registerPeriodicTask(withIdentifier: identifier, frequency: NSNumber(value: 15 * 60))
    }

    if let registrar = self.registrar(forPlugin: "AssistantModelChannel") {
      AssistantModelChannel.register(messenger: registrar.messenger())
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.alert, .badge, .sound])
  }
}

enum AssistantModelChannel {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "app/assistant_model", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let arguments = call.arguments as? [String: Any]
      switch call.method {
      case "profile":
        result(profile())
      case "memory":
        result(memory())
      case "freeSpace":
        guard let path = arguments?["path"] as? String else {
          result(nil)
          return
        }
        result(freeBytes(URL(fileURLWithPath: path)))
      case "keepScreenOn":
        let on = arguments?["on"] as? Bool ?? false
        DispatchQueue.main.async {
          UIApplication.shared.isIdleTimerDisabled = on
        }
        result(nil)
      case "excludeFromBackup":
        guard let path = arguments?["path"] as? String else {
          result(false)
          return
        }
        result(excludeFromBackup(URL(fileURLWithPath: path)))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func profile() -> [String: Any] {
    var info = memory()
    info["totalMemory"] = info["total"]
    info["availableMemory"] = info["available"]
    guard let base = try? FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    else {
      return info
    }
    let directory = base.appendingPathComponent("assistant-model", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    _ = excludeFromBackup(directory)
    info["directory"] = directory.path
    info["freeBytes"] = freeBytes(directory)
    return info
  }

  private static func memory() -> [String: Any] {
    return [
      "total": Int64(ProcessInfo.processInfo.physicalMemory),
      "available": Int64(os_proc_available_memory()),
      "low": false,
    ]
  }

  private static func freeBytes(_ url: URL) -> Int64? {
    let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    return values?.volumeAvailableCapacityForImportantUsage
  }

  private static func excludeFromBackup(_ url: URL) -> Bool {
    var target = url
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    do {
      try target.setResourceValues(values)
      return true
    } catch {
      return false
    }
  }
}

import Flutter
import Network
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

final class AssistantNetworkWatcher: NSObject, FlutterStreamHandler {
  private let monitor = NWPathMonitor()
  private var sink: FlutterEventSink?
  private(set) var status: [String: Bool]?

  override init() {
    super.init()
    monitor.pathUpdateHandler = { [weak self] path in
      let connected = path.status == .satisfied
      let value = ["connected": connected, "metered": connected && (path.isExpensive || path.isConstrained)]
      DispatchQueue.main.async {
        guard let self else { return }
        let changed = self.status != value
        self.status = value
        if changed { self.sink?(value) }
      }
    }
    monitor.start(queue: DispatchQueue(label: "assistant-model-network"))
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    if let status { events(status) }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }
}

enum AssistantModelChannel {
  private static let network = AssistantNetworkWatcher()

  static func register(messenger: FlutterBinaryMessenger) {
    FlutterEventChannel(name: "app/assistant_model/network", binaryMessenger: messenger).setStreamHandler(network)
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
      case "network":
        result(network.status)
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

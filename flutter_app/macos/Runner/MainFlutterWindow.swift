import Cocoa
import FlutterMacOS
import UserNotifications

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    self.setContentSize(NSSize(width: 1280, height: 800))
    self.minSize = NSSize(width: 900, height: 600)
    self.center()
    self.title = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? ""

    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)

    self.backgroundColor = NSColor(red: 15.0/255, green: 15.0/255, blue: 26.0/255, alpha: 1.0)

    RegisterGeneratedPlugins(registry: flutterViewController)

    self.delegate = self

    let channel = FlutterMethodChannel(
      name: "app/notifications",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      if call.method == "showNotification" {
        guard let args = call.arguments as? [String: Any],
              let title = args["title"] as? String,
              let body = args["body"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "title and body required", details: nil))
          return
        }
        let id = args["id"] as? Int ?? 0

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
          DispatchQueue.main.async {
            guard settings.authorizationStatus == .authorized else {
              result(FlutterError(code: "NOT_AUTHORIZED",
                                  message: "status=\(settings.authorizationStatus.rawValue)",
                                  details: nil))
              return
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if let payload = args["payload"] as? String {
              content.userInfo = ["url": payload]
            }

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(
              identifier: "app-\(id)-\(Date().timeIntervalSince1970)",
              content: content,
              trigger: trigger
            )
            center.add(request) { error in
              DispatchQueue.main.async {
                if let error = error {
                  result(FlutterError(code: "DELIVERY_ERROR", message: error.localizedDescription, details: nil))
                } else {
                  result(nil)
                }
              }
            }
          }
        }
      } else if call.method == "requestPermissions" {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge]) { granted, error in
          DispatchQueue.main.async {
            if let error = error {
              result(FlutterError(code: "PERMISSION_ERROR", message: error.localizedDescription, details: nil))
            } else {
              result(granted)
            }
          }
        }
      } else if call.method == "getAuthorizationStatus" {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
          DispatchQueue.main.async {
            result([
              "status": settings.authorizationStatus.rawValue,
              "alertStyle": settings.alertStyle.rawValue,
              "alertSetting": settings.alertSetting.rawValue,
              "notificationCenter": settings.notificationCenterSetting.rawValue,
            ])
          }
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    self.orderOut(nil)
    return false
  }
}

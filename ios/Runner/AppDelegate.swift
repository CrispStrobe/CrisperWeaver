import UIKit
import Flutter
import Foundation

// UIScene lifecycle (required for apps built with the iOS 27 SDK: UIKit
// traps at launch otherwise). Info.plist's UIApplicationSceneManifest hands
// the window to FlutterSceneDelegate, so `window` is nil in
// didFinishLaunching; plugins and the channel below are wired when the
// implicit engine is ready instead.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // iOS helpers MethodChannel — currently exposes
    // `excludeFromBackup(path)` so the §5.23 batch persistence
    // service can flag the in-flight checkpoint directory
    // `NSURLIsExcludedFromBackupKey = true`, sparing the user's
    // iCloud bandwidth + storage during long batch runs.
    //
    // Other platforms (Android/desktop) don't have an equivalent
    // mechanism; the Dart wrapper is a no-op there, so this handler
    // doesn't need a non-iOS sibling.
    do {
      let channel = FlutterMethodChannel(
        name: "crisperweaver/ios_helpers",
        binaryMessenger: engineBridge.applicationRegistrar.messenger())
      channel.setMethodCallHandler { (call, result) in
        switch call.method {
        case "excludeFromBackup":
          guard let args = call.arguments as? [String: Any],
                let path = args["path"] as? String else {
            result(FlutterError(
              code: "BAD_ARGS",
              message: "expected {path: String}",
              details: nil))
            return
          }
          var url = URL(fileURLWithPath: path)
          var values = URLResourceValues()
          values.isExcludedFromBackup = true
          do {
            try url.setResourceValues(values)
            result(true)
          } catch {
            result(FlutterError(
              code: "SET_FAILED",
              message: error.localizedDescription,
              details: nil))
          }

        case "appGroupContainerPath":
          // Returns the on-disk path of the App Group's shared
          // container so Dart can park files that need to survive
          // app-reinstalls (model downloads, prefs the ShareExtension
          // also reads, etc.). Returns nil if the entitlement isn't
          // configured or the OS hasn't provisioned the container yet.
          guard let args = call.arguments as? [String: Any],
                let groupId = args["groupId"] as? String else {
            result(FlutterError(
              code: "BAD_ARGS",
              message: "expected {groupId: String}",
              details: nil))
            return
          }
          if let url = FileManager.default
              .containerURL(forSecurityApplicationGroupIdentifier: groupId) {
            result(url.path)
          } else {
            result(nil)
          }

        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}

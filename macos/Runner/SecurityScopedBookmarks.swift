import Cocoa
import FlutterMacOS

// Security-scoped bookmarks — the only way a sandboxed app can re-open a
// user-picked folder after relaunch.
//
// `com.apple.security.files.user-selected.read-write` grants access ONLY
// for the session in which the open panel ran. The watch-folder feature
// persisted a raw path string and restarted the watcher from it on every
// launch, so on the Mac App Store build the folder became unreadable the
// moment the app restarted. Worse, the failure was silent: a sandbox denial
// makes `stat` fail, so Dart's `Directory.existsSync()` returns false rather
// than throwing, and `WatchFolderService.start` took its "directory does not
// exist" branch and returned — with the setting still displayed as enabled
// and the path still shown.
//
// Wire protocol (matches lib/services/security_scoped_bookmarks.dart):
//   Channel: crisperweaver/security_bookmarks
//     create(path: String)      -> String?  base64 bookmark blob, nil on failure
//     resolve(bookmark: String) -> {path: String, stale: Bool}? , starts access
//     stopAccessing(path: String) -> nil
//
// The non-sandboxed direct-download build goes through the same path rather
// than branching on sandbox state: bookmark creation succeeds there too, so
// there is one code path exercised by both targets instead of a sandbox-only
// branch that only ever runs in the build nobody tests locally.

final class SecurityScopedBookmarks {
  static let shared = SecurityScopedBookmarks()

  /// Resolved URLs we currently hold a security scope on, keyed by path.
  /// Held so `stopAccessing` can balance `startAccessingSecurityScopedResource`
  /// — the scope leaks for the process lifetime otherwise, and macOS caps how
  /// many a process may hold open at once.
  private var activeScopes: [String: URL] = [:]

  func create(path: String) -> String? {
    let url = URL(fileURLWithPath: path, isDirectory: true)
    do {
      let data = try url.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil)
      return data.base64EncodedString()
    } catch {
      NSLog("[crisperweaver] security-scoped bookmark creation failed for "
            + "\(path): \(error.localizedDescription)")
      return nil
    }
  }

  /// Resolve a bookmark and begin accessing it. Returns the (possibly
  /// relocated) path and whether the blob is stale — a stale bookmark still
  /// resolves, but the caller should re-create and re-persist it, because it
  /// will eventually stop resolving.
  func resolve(bookmark: String) -> [String: Any]? {
    guard let data = Data(base64Encoded: bookmark) else {
      NSLog("[crisperweaver] security-scoped bookmark is not valid base64")
      return nil
    }
    var stale = false
    do {
      let url = try URL(
        resolvingBookmarkData: data,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &stale)
      guard url.startAccessingSecurityScopedResource() else {
        NSLog("[crisperweaver] startAccessingSecurityScopedResource denied for "
              + "\(url.path)")
        return nil
      }
      // Balance any scope we already held for this path before replacing it.
      if let previous = activeScopes[url.path], previous != url {
        previous.stopAccessingSecurityScopedResource()
      }
      activeScopes[url.path] = url
      return ["path": url.path, "stale": stale]
    } catch {
      NSLog("[crisperweaver] security-scoped bookmark resolution failed: "
            + "\(error.localizedDescription)")
      return nil
    }
  }

  func stopAccessing(path: String) {
    guard let url = activeScopes.removeValue(forKey: path) else { return }
    url.stopAccessingSecurityScopedResource()
  }
}

func registerSecurityScopedBookmarks(messenger: FlutterBinaryMessenger) {
  let channel = FlutterMethodChannel(
    name: "crisperweaver/security_bookmarks",
    binaryMessenger: messenger)

  channel.setMethodCallHandler { (call, result) in
    let args = call.arguments as? [String: Any]

    switch call.method {
    case "create":
      guard let path = args?["path"] as? String else {
        result(FlutterError(code: "INVALID_ARG",
                            message: "create expects {path: String}",
                            details: nil))
        return
      }
      result(SecurityScopedBookmarks.shared.create(path: path))

    case "resolve":
      guard let bookmark = args?["bookmark"] as? String else {
        result(FlutterError(code: "INVALID_ARG",
                            message: "resolve expects {bookmark: String}",
                            details: nil))
        return
      }
      result(SecurityScopedBookmarks.shared.resolve(bookmark: bookmark))

    case "stopAccessing":
      guard let path = args?["path"] as? String else {
        result(FlutterError(code: "INVALID_ARG",
                            message: "stopAccessing expects {path: String}",
                            details: nil))
        return
      }
      SecurityScopedBookmarks.shared.stopAccessing(path: path)
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

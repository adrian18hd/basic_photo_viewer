import Cocoa
import FlutterMacOS
import macos_window_utils

@main
class AppDelegate: FlutterAppDelegate {
  private var fileChannel: FlutterMethodChannel?
  private var pendingInvocations: [(method: String, arguments: Any)] = []
  private var isDartReady = false

  private let supportedExtensions: Set<String> = [
    "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp", "heic"
  ]

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // macos_window_utils wraps the FlutterViewController in a
    // MacOSWindowUtilsViewController, so reach it through that wrapper.
    if let controller = (mainFlutterWindow?.contentViewController as? MacOSWindowUtilsViewController)?.flutterViewController {
      fileChannel = FlutterMethodChannel(
        name: "com.example.basic_photo_viewer/file",
        binaryMessenger: controller.engine.binaryMessenger
      )

      // Files opened at launch (Finder double-click / Open With) arrive before
      // Dart has registered its handler. Messages sent then are dropped or
      // overwritten (Flutter buffers only one per channel), so hold them until
      // Dart reports "ready".
      fileChannel?.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { return }
        if call.method == "ready" {
          self.isDartReady = true
          self.flushPendingInvocations()
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  // Drain a local copy first so a re-entrant enqueue during invoke can't be lost.
  private func flushPendingInvocations() {
    let queued = pendingInvocations
    pendingInvocations = []
    for inv in queued {
      fileChannel?.invokeMethod(inv.method, arguments: inv.arguments)
    }
  }

  // MUST be called on the main thread.
  private func sendOrQueue(_ method: String, _ arguments: Any) {
    if isDartReady, let channel = fileChannel {
      channel.invokeMethod(method, arguments: arguments)
    } else {
      pendingInvocations.append((method, arguments))
    }
  }

  private func getImageFilesInDirectory(for fileURL: URL) -> [String: Any] {
    let filePath = fileURL.path
    let directoryURL = fileURL.deletingLastPathComponent()

    var imageFiles: [String] = []

    do {
      let contents = try FileManager.default.contentsOfDirectory(
        at: directoryURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      )

      for url in contents {
        let ext = url.pathExtension.lowercased()
        if supportedExtensions.contains(ext) {
          imageFiles.append(url.path)
        }
      }

      // Sort alphabetically (case-insensitive)
      imageFiles.sort { $0.lowercased() < $1.lowercased() }
    } catch {
      NSLog("PhotoViewer: Failed to read directory: \(error)")
      // If we can't read directory, just use the single file
      imageFiles = [filePath]
    }

    let currentIndex = imageFiles.firstIndex(of: filePath) ?? 0
    NSLog("PhotoViewer: Found \(imageFiles.count) images, current index: \(currentIndex)")

    return [
      "files": imageFiles,
      "currentIndex": currentIndex
    ]
  }

  // Handle files opened via "Open with" (newer URL-based API)
  override func application(_ application: NSApplication, open urls: [URL]) {
    guard let url = urls.first else { return }
    openImmediatelyThenScan(url)
  }

  // Handle files passed as command line arguments at launch
  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    openImmediatelyThenScan(URL(fileURLWithPath: filename))
    return true
  }

  // Show the opened image right away, then scan its folder off the main thread
  // and backfill the navigation list. Keeps launch instant for large folders.
  private func openImmediatelyThenScan(_ url: URL) {
    // Hold the file's scope across the async scan (a no-op while unsandboxed).
    let didStartAccess = url.startAccessingSecurityScopedResource()

    // Phase 1: render immediately with a single-element list.
    sendOrQueue("openFile", ["files": [url.path], "currentIndex": 0])

    // Phase 2: scan the directory in the background, then backfill.
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let data = self?.getImageFilesInDirectory(for: url) ?? [:]
      DispatchQueue.main.async {
        self?.sendOrQueue("setImageList", data)
        if didStartAccess {
          url.stopAccessingSecurityScopedResource()
        }
      }
    }
  }
}

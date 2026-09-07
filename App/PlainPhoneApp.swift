import SwiftUI
import UIKit

@main
struct PlainPhoneApp: App {
    @StateObject private var store: LauncherStore

    /// Process start stamp. App.init runs exactly once per process, so an
    /// onOpenURL arriving within the cold-start window means iOS launched
    /// this process because of the URL and the scene is still connecting.
    private static let launchedAt = Date()
    private static let coldStartWindow: TimeInterval = 1.0

    init() {
        // Force eager evaluation: static lets are lazy, and launchedAt must
        // stamp process start, not first use.
        _ = Self.launchedAt
        // Deterministic state reset for XCUITest runs.
        if ProcessInfo.processInfo.arguments.contains("-uiTestReset") {
            LauncherStore.wipeStoredData()
        }
        if ProcessInfo.processInfo.arguments.contains("-uiTestCorrupt") {
            LauncherStore.wipeStoredData()
            LauncherStore.plantCorruptData()
        }
        _store = StateObject(wrappedValue: LauncherStore())
        #if DEBUG
        PathBProbe.runIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .task { store.seedIfNeeded() }
                .onOpenURL { Self.relay($0) }
        }
    }

    /// SPEC-NEXT §4 M-3 path B: widget rows Link to `plainphone://open?…`
    /// and F-5 guarantees the URL lands here; the whitelisted target is
    /// then opened from inside the app, where opening a custom scheme is
    /// fully supported. The stdout prints are visible through
    /// `devicectl --console-pty`.
    private static func relay(_ url: URL) {
        print("[PathB] onOpenURL \(url.absoluteString)")
        guard let target = PlainPhoneURL.resolve(url) else {
            print("[PathB] rejected: missing target or non-whitelisted scheme \(url.absoluteString)")
            return
        }
        // Cold start: when iOS started this process because of the URL, an
        // immediate open() can be swallowed while the scene is still
        // connecting; give the launch a short grace period first. Warm
        // starts open immediately. W-6 accepts the latency either way.
        let coldStart = Date().timeIntervalSince(Self.launchedAt) < Self.coldStartWindow
        let delay: TimeInterval = coldStart ? 0.4 : 0
        print("[PathB] opening \(target.absoluteString) (coldStart: \(coldStart), delay: \(delay)s)")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            UIApplication.shared.open(target) { opened in
                print("[PathB] open \(opened ? "succeeded" : "FAILED"): \(target.absoluteString)")
            }
        }
    }
}

#if DEBUG
/// SPEC-NEXT Gate 0 diagnostic probe. Fire-and-forget: when the process is
/// launched with `-pathBProbe <shortcutName>`, opens
/// `shortcuts://run-shortcut?name=<name>` once after launch and records
/// START / OPEN / POST6 milestones to Documents/pathb-log.txt and stdout
/// (stdout is captured by `devicectl --console-pty`). No UI; absent the
/// launch argument it does nothing, so `-uiTestReset` launches and normal
/// usage are unaffected. The whole type is compiled out of Release builds.
enum PathBProbe {
    private static var hasRun = false
    private static let iso8601 = ISO8601DateFormatter()

    static func runIfRequested() {
        guard !hasRun else { return }
        // Two triggers: launch argument `-pathBProbe <name>` (Xcode/devicectl
        // argv) or environment variable PATHB_PROBE=<name>. devicectl's
        // argument parser rejects launch arguments that start with `-`, so
        // the env-var channel is the one `devicectl -e` can actually use.
        let name = ProcessInfo.processInfo.environment["PATHB_PROBE"]
            ?? {
                let args = ProcessInfo.processInfo.arguments
                guard let flagIndex = args.firstIndex(of: "-pathBProbe"),
                      flagIndex + 1 < args.count else { return nil }
                return args[flagIndex + 1]
            }()
        guard let name, !name.isEmpty else { return }
        hasRun = true
        // Defer to the main queue so the probe runs strictly after launch,
        // on the main thread, with UIApplication fully available.
        DispatchQueue.main.async { probe(name: name) }
    }

    private static func probe(name: String) {
        let urlString = ShortcutsURL.runShortcut(named: name)
        appendLog("START \(timestamp()) name=\(name) url=\(urlString)")
        guard let url = URL(string: urlString), !urlString.isEmpty else {
            appendLog("OPEN \(timestamp()) result=false error=unbuildable URL '\(urlString)'")
            appendLog("POST6 \(timestamp()) probe finished")
            return
        }
        UIApplication.shared.open(url, options: [:]) { success in
            // This completion handler exposes only a Bool; UIKit offers no
            // error object for external opens, so none can be logged.
            appendLog("OPEN \(timestamp()) result=\(success)")
        }
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 6) {
            appendLog("POST6 \(timestamp()) probe finished")
        }
    }

    private static func timestamp() -> String {
        iso8601.string(from: Date())
    }

    private static func appendLog(_ line: String) {
        print(line)
        let fm = FileManager.default
        guard let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("[PathBProbe] no documents directory; dropped: \(line)")
            return
        }
        let fileURL = documents.appendingPathComponent("pathb-log.txt")
        do {
            if fm.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data((line + "\n").utf8))
            } else {
                try (line + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
            }
        } catch {
            print("[PathBProbe] log write failed: \(error)")
        }
    }
}
#endif

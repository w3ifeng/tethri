import AppKit
import ScriptingBridge
import AutomationBridge
import FocusCore

@objc private protocol ChromeApplication { @objc optional func windows() -> SBElementArray }
@objc private protocol ChromeWindow {
    @objc optional var activeTab: SBObject { get }
    @objc optional func tabs() -> SBElementArray
}
@objc private protocol ChromeTab {
    @objc optional var URL: String { get }
    @objc optional func id() -> Any
    @objc optional func close()
}

extension SBApplication: ChromeApplication {}
extension SBObject: ChromeWindow, ChromeTab {}

/// One serial worker owns all Apple Events. No scripts, subprocesses, or page JS.
final class ChromeAutomation: NSObject, SBApplicationDelegate {
    private let queue = DispatchQueue(label: "companion.chrome", qos: .utility)
    private var failure: Error?
    struct Snapshot { var active: Target?; var tabs: Set<Target> }
    enum Failure: LocalizedError {
        case unavailable, automation, collectionChanged, changed
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Chrome is not running."
            case .automation: return "Website enforcement unavailable. Enable Focus Companion in System Settings → Privacy & Security → Automation."
            case .collectionChanged: return "Chrome windows or tabs changed during the read. Monitoring will retry automatically."
            case .changed: return "The captured tab changed; no tab was closed."
            }
        }
    }
    func eventDidFail(_ event: UnsafePointer<AppleEvent>, withError error: Error) -> Any? { failure = error; return nil }
    private func application(pid: Int32, launchedAt: Double) throws -> SBApplication {
        guard let running = NSRunningApplication(processIdentifier: pid), running.bundleIdentifier == "com.google.Chrome",
              running.launchDate?.timeIntervalSince1970 == launchedAt,
              let app = SBApplication(processIdentifier: pid) else { throw Failure.unavailable }
        app.timeout = 1; app.delegate = self; failure = nil; return app
    }
    private func target(_ tab: SBObject, pid: Int32, launchedAt: Double) -> Target? {
        let typed = tab as ChromeTab
        guard let raw = typed.URL, let url = URL(string: raw), let value = typed.id?() else { return nil }
        return Target(bundleID: "com.google.Chrome", processID: pid, launchedAt: launchedAt, tabID: String(describing: value), url: url)
    }
    private func elements(_ collection: SBElementArray) throws -> [SBObject] {
        var error: NSError?
        let snapshot = FCSnapshotElements(collection, &error) as? [SBObject]
        if failure != nil { throw Failure.automation }
        guard let snapshot, error == nil else { throw Failure.collectionChanged }
        return snapshot
    }
    func snapshot(pid: Int32, launchedAt: Double, inspectGrantedTabs: Bool = false) async throws -> Snapshot {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let app = try self.application(pid: pid, launchedAt: launchedAt)
                    guard let windows = (app as ChromeApplication).windows?() else { throw Failure.automation }
                    var all = Set<Target>(); var active: Target?
                    let deadline = monotonicNow() + 1.5
                    for (index, window) in try self.elements(windows).enumerated() {
                        guard monotonicNow() < deadline else { throw Failure.automation }
                        let typed = window as ChromeWindow
                        if index == 0, let tab = typed.activeTab { active = self.target(tab, pid: pid, launchedAt: launchedAt) }
                        if inspectGrantedTabs, let tabs = typed.tabs?() {
                            for tab in try self.elements(tabs) {
                                guard monotonicNow() < deadline else { throw Failure.automation }
                                if let t = self.target(tab, pid: pid, launchedAt: launchedAt) { all.insert(t) }
                            }
                        }
                        if !inspectGrantedTabs { break }
                    }
                    if self.failure != nil { throw Failure.automation }
                    continuation.resume(returning: Snapshot(active: active, tabs: all))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    /// Re-find by process + tab ID across all windows, then re-read the resource.
    /// The main-actor authorization runs immediately before the synchronous close.
    func close(_ captured: Target, authorized: @escaping @MainActor (Target) -> Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    let app = try self.application(pid: captured.processID, launchedAt: captured.launchedAt)
                    guard let windows = (app as ChromeApplication).windows?() else { throw Failure.automation }
                    let deadline = monotonicNow() + 1.5
                    for window in try self.elements(windows) {
                        guard monotonicNow() < deadline else { throw Failure.automation }
                        guard let tabs = (window as ChromeWindow).tabs?() else { continue }
                        for tab in try self.elements(tabs) {
                            guard monotonicNow() < deadline else { throw Failure.automation }
                            guard let rawID = (tab as ChromeTab).id?(), String(describing: rawID) == captured.tabID else { continue }
                            guard let current = self.target(tab, pid: captured.processID, launchedAt: captured.launchedAt), current == captured else { continue }
                            let approved = DispatchQueue.main.sync { MainActor.assumeIsolated { authorized(current) } }
                            guard approved else { throw Failure.changed }
                            // Re-read after authorization to narrow the unavoidable Apple Event race.
                            guard self.target(tab, pid: captured.processID, launchedAt: captured.launchedAt) == current else { throw Failure.changed }
                            (tab as ChromeTab).close?()
                            if self.failure != nil { throw Failure.automation }
                            continuation.resume(); return
                        }
                    }
                    throw Failure.changed
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}

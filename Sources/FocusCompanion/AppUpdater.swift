import AppKit
import Combine
import Sparkle
import SwiftUI

/// Sparkle owns download verification, installation and relaunch. Preview/CLI builds never start it.
@MainActor final class AppUpdater: NSObject, ObservableObject, NSMenuItemValidation, SPUUpdaterDelegate {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var status = "Automatic updates aren't enabled in this build."
    private var controller: SPUStandardUpdaterController?
    var isSessionActive: () -> Bool = { false }
    let isConfigured: Bool

    override init() {
        let bundle = Bundle.main
        let feed = (bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String).flatMap(URLComponents.init(string:))
        let key = (bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String).flatMap { Data(base64Encoded: $0) }
        isConfigured = bundle.bundleIdentifier == "com.focuscompanion.mac"
            && bundle.bundleURL.pathExtension == "app"
            && feed?.scheme == "https" && !(feed?.host?.isEmpty ?? true)
            && feed?.user == nil && feed?.password == nil && key?.count == 32
        super.init()
    }

    func start() {
        guard isConfigured, controller == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticallyChecksForUpdates)
        do {
            try controller.updater.start()
            status = "Checks daily. You choose when to install and restart."
        } catch {
            status = "Updates couldn't start. \(error.localizedDescription)"
        }
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    @objc func checkForUpdates(_ sender: Any?) {
        guard canCheckForUpdates else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(sender)
    }

    func menuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates(_:)), keyEquivalent: "")
        item.target = self
        item.isEnabled = canCheckForUpdates
        return item
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { canCheckForUpdates }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        // Manual checks remain available; scheduled checks wait until the focus session ends.
        if updateCheck != .updates && isSessionActive() {
            throw NSError(domain: "com.focuscompanion.updates", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Tethri will check for updates after your focus session."])
        }
    }
}

struct UpdateSettings: View {
    @ObservedObject var updater: AppUpdater
    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "Version \(info["CFBundleShortVersionString"] as? String ?? "Development") (\(info["CFBundleVersion"] as? String ?? "0"))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("App updates").fontWeight(.medium)
                Spacer()
                Button("Check for Updates…") { updater.checkForUpdates(nil) }
                    .buttonStyle(.borderless).disabled(!updater.canCheckForUpdates)
            }
            Text(version).foregroundStyle(.white.opacity(0.6))
            Toggle("Automatically check for updates", isOn: Binding(
                get: { updater.automaticallyChecksForUpdates }, set: { updater.setAutomaticChecks($0) }
            )).disabled(!updater.isConfigured)
            Text(updater.status).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }.font(.system(size: 12))
    }
}

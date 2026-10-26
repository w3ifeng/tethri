import AppKit
import Sparkle

// Runs inside a temporary bundle with a separate Sparkle defaults domain and automatic checks off.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    application.setActivationPolicy(.prohibited)
    let updater = AppUpdater()
    precondition(updater.isConfigured, "A configured production bundle must enable the updater")
    updater.start()
    precondition(updater.canCheckForUpdates, "Sparkle must start successfully in a packaged app")
    precondition(!updater.automaticallyChecksForUpdates, "The test must not make automatic requests")
    updater.setAutomaticChecks(true)
    precondition(updater.automaticallyChecksForUpdates, "Settings must observe Sparkle's enabled preference")
    updater.setAutomaticChecks(false)
    precondition(!updater.automaticallyChecksForUpdates, "Settings must observe Sparkle's disabled preference")

    let probe = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil).updater
    updater.isSessionActive = { true }
    var blocked = false
    do { try updater.updater(probe, mayPerform: .updatesInBackground) } catch { blocked = true }
    precondition(blocked, "Scheduled checks must skip active focus sessions")
    do { try updater.updater(probe, mayPerform: .updates) } catch { preconditionFailure("Manual checks must remain available") }
    updater.isSessionActive = { false }
    do { try updater.updater(probe, mayPerform: .updatesInBackground) } catch { preconditionFailure("Idle checks must be allowed") }
    precondition(updater.validateMenuItem(updater.menuItem()), "The menu must enable checking when ready")

    let domain = Bundle.main.object(forInfoDictionaryKey: "SUDefaultsDomain") as! String
    UserDefaults.standard.removePersistentDomain(forName: domain)
    print("PASS: packaged updater startup, preference observation, menu validation and focus-session deferral")
}

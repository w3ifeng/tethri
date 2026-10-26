import AppKit
import SwiftUI

final class CompanionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var dashboard: NSWindow!
    private var character: CompanionPanel!
    private var bubble: CompanionPanel!
    private var statusItem: NSStatusItem!
    private let updater = AppUpdater()
    private var lastChatActivity = ProcessInfo.processInfo.systemUptime
    private var lastChatMessage: UUID?
    private var chatEventMonitor: Any?
    #if DEBUG
    private var previewChat: NSWindow?
    #endif
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        #if DEBUG
        let preview = Bundle.main.bundleIdentifier == "com.focuscompanion.preview"
        if preview {
            let defaults = UserDefaults(suiteName: "com.focuscompanion.preview.fixture")!
            defaults.removeObject(forKey: "checkpoint")
            model = AppModel(client: PreviewCompanionClient(), defaults: defaults, servicesEnabled: false)
            model.preferences.consent = true; model.goal = "Write the first draft"
        } else { model = AppModel() }
        #else
        model = AppModel()
        #endif
        dashboard = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 660), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        dashboard.title = "Tethri"; dashboard.titlebarAppearsTransparent = true; dashboard.backgroundColor = .clear; dashboard.isOpaque = false; dashboard.isReleasedWhenClosed = false; dashboard.center(); dashboard.contentView = NSHostingView(rootView: Dashboard(model: model, updater: updater))
        character = makePanel(NSSize(width: 100, height: 108)); character.minSize = NSSize(width: 80, height: 100); character.maxSize = NSSize(width: 360, height: 400); character.title = "Focus Companion"; character.isMovableByWindowBackground = false
        let orb = DraggableOrbView(rootView: Button { [weak self] in self?.toggleBubble() } label: {
            DesktopOrb(model: model)
        }.buttonStyle(OrbButtonStyle()))
        orb.onClick = { [weak self] in self?.toggleBubble() }
        orb.onMove = { [weak self] in self?.positionBubble(resize: false) }
        orb.onDragEnd = { [weak self] in self?.savePosition() }
        character.contentView = orb
        bubble = makePanel(NSSize(width: 354, height: 424)); bubble.minSize = NSSize(width: 320, height: 340); bubble.maxSize = NSSize(width: 800, height: 900); bubble.title = "Focus Chat"; bubble.contentView = NSHostingView(rootView: ConversationBubble(model: model))
        model.showBubble = { [weak self] in self?.presentChat() }
        model.hideBubble = { [weak self] in self?.bubble.orderOut(nil) }
        model.showDashboard = { [weak self] in self?.openDashboard() }
        model.sessionDidStart = { [weak self] in
            self?.dashboard.orderOut(nil)
            self?.character.orderFrontRegardless()
            self?.updateMenu()
            self?.model.showBubble?()
        }
        model.recoverCharacter = { [weak self] in self?.recover() }
        model.updatePresentation = { [weak self] in
            self?.updateMenu()
            if self?.bubble.isVisible == true { self?.positionBubble(); self?.minimizeIdleChat() }
        }
        chatEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel, .leftMouseDragged]) { [weak self] event in
            if let self, event.window === self.bubble { self.lastChatActivity = ProcessInfo.processInfo.systemUptime }
            return event
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let mark = FocusOrb.dog.copy() as! NSImage
            mark.size = NSSize(width: 18, height: 18)
            mark.accessibilityDescription = "Tethri"
            button.image = mark; button.imagePosition = .imageLeading
        }
        updater.isSessionActive = { [weak self] in self?.model.engine.active ?? false }
        updater.start()
        updateMenu()
        let appMenu = NSMenu(); let item = NSMenuItem(); appMenu.addItem(item); let submenu = NSMenu(); submenu.addItem(withTitle: "Quit Tethri", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); item.submenu = submenu; let editItem = NSMenuItem(); appMenu.addItem(editItem); let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] { edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key) }
        submenu.insertItem(updater.menuItem(), at: 0)
        submenu.insertItem(.separator(), at: 1)
        editItem.submenu = edit; NSApp.mainMenu = appMenu
        restorePosition(); character.orderOut(nil)
        openTimer()
        #if DEBUG
        if preview {
            model.end(); model.selectedPage = "Settings"
            // A normal isolated preview window makes native snapshots reliable without changing production panels.
            let chat = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 354, height: 424), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            chat.title = "Chat Preview"; chat.backgroundColor = .clear; chat.isOpaque = false; chat.titlebarAppearsTransparent = true
            chat.contentView = NSHostingView(rootView: ConversationBubble(model: model)); chat.center(); chat.isReleasedWhenClosed = false; previewChat = chat
            model.showBubble = { [weak self] in
                guard let chat = self?.previewChat else { return }
                if let content = chat.contentView { chat.setContentSize(NSSize(width: 354, height: min(520, max(160, content.fittingSize.height)))) }
                NSApp.activate(ignoringOtherApps: true); chat.makeKeyAndOrderFront(nil)
            }
            model.hideBubble = { [weak self] in self?.previewChat?.orderOut(nil) }
            character.orderOut(nil); bubble.orderOut(nil); dashboard.orderOut(nil); model.showBubble?()
            if CommandLine.arguments.contains("--timer-preview") {
                model.preferences.rules.studyMinutes = 15; model.selectedPage = "Today"
                chat.orderOut(nil); openDashboard()
            }
        }
        #endif
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }
    private func makePanel(_ size: NSSize) -> CompanionPanel {
        let panel = CompanionPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true; panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false; panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true; panel.isReleasedWhenClosed = false
        return panel
    }
    private func positionBubble(resize: Bool = true) {
        guard bubble != nil else { return }
        let screen = NSScreen.screens.max { a, b in
            let left = a.visibleFrame.intersection(character.frame)
            let right = b.visibleFrame.intersection(character.frame)
            return (left.isNull ? 0 : left.width * left.height) < (right.isNull ? 0 : right.width * right.height)
        } ?? NSScreen.main
        guard let bounds = screen?.visibleFrame else { return }
        bubble.setFrameOrigin(CompanionPlacement.chatOrigin(orb: character.frame, chat: bubble.frame.size, bounds: bounds))
    }
    private func presentChat() {
        lastChatActivity = ProcessInfo.processInfo.systemUptime
        lastChatMessage = model.messages.last?.id
        positionBubble()
        guard !bubble.isVisible else { bubble.orderFrontRegardless(); return }
        bubble.alphaValue = 0; bubble.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.10 : 0.20
            bubble.animator().alphaValue = 1
        }
    }
    private func minimizeIdleChat() {
        let now = ProcessInfo.processInfo.systemUptime
        let latestMessage = model.messages.last?.id
        // History stays available, but only new content or current interaction keeps the panel open.
        if latestMessage != lastChatMessage || model.chatNeedsAttention || bubble.frame.contains(NSEvent.mouseLocation) {
            lastChatActivity = now
            lastChatMessage = latestMessage
            return
        }
        if now - lastChatActivity >= 5 { bubble.orderOut(nil) }
    }
    @objc private func toggleBubble() {
        guard model.engine.active else { openTimer(); return }
        if bubble.isVisible && bubble.isKeyWindow { bubble.orderOut(nil) }
        else {
            presentChat()
            // This is an explicit user click. Automatic interventions use presentChat only.
            bubble.makeKeyAndOrderFront(nil)
            bubble.makeFirstResponder(nil)
        }
    }
    @objc private func openChat() {
        #if DEBUG
        if previewChat != nil { model.showBubble?(); return }
        #endif
        presentChat(); bubble.makeKeyAndOrderFront(nil); bubble.makeFirstResponder(nil)
    }
    @objc private func openDashboard() { NSApp.activate(ignoringOtherApps: true); dashboard.makeKeyAndOrderFront(nil) }
    @objc private func openTimer() { model.selectedPage = "Today"; bubble.orderOut(nil); openDashboard() }
    @objc private func openSettings() { model.selectedPage = "Settings"; openDashboard() }
    @objc private func recover() {
        guard let screen = NSScreen.main?.visibleFrame else { return }; character.setFrameOrigin(NSPoint(x: screen.maxX - 132, y: screen.minY + 40)); positionBubble(); character.orderFrontRegardless(); savePosition()
    }
    private func restorePosition() {
        if let point = UserDefaults.standard.string(forKey: "characterPosition") { character.setFrameOrigin(NSPointFromString(point)); screensChanged() } else { recover() }
    }
    private func savePosition() { UserDefaults.standard.set(NSStringFromPoint(character.frame.origin), forKey: "characterPosition") }
    @objc private func screensChanged() { if !NSScreen.screens.contains(where: { $0.visibleFrame.contains(character.frame) }) { recover() }; positionBubble() }
    @objc private func startOrEnd() { if model.engine.active { model.end() } else { openTimer() }; updateMenu() }
    @objc private func toggleRain() { model.toggleRain(); updateMenu() }
    @objc private func muteRain() { model.preferences.rainMuted.toggle(); updateMenu() }
    private func updateMenu() {
        statusItem.button?.title = model.engine.active ? " " + (model.engine.breakAvailable ? "✓" : model.countdown) : ""
        let menu = NSMenu()
        let status = NSMenuItem(title: model.engine.active ? model.phase : "Ready when you are", action: nil, keyEquivalent: ""); status.isEnabled = false; menu.addItem(status)
        add(model.engine.active ? "Open timer" : model.saved != nil ? "Resume session…" : "Start session…", #selector(openTimer), to: menu)
        add("Open chat", #selector(openChat), to: menu)
        add("Settings…", #selector(openSettings), to: menu)
        menu.addItem(updater.menuItem())
        if model.engine.active { add("End Session", #selector(startOrEnd), to: menu) }
        menu.addItem(.separator()); add(model.rainRequested ? "Pause rain" : "Play rain", #selector(toggleRain), to: menu); add(model.preferences.rainMuted ? "Unmute rain" : "Mute rain", #selector(muteRain), to: menu)
        menu.addItem(.separator()); add("Recover companion", #selector(recover), to: menu)
        menu.addItem(withTitle: "Quit Tethri", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }
    private func add(_ title: String, _ action: Selector, to menu: NSMenu) { let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item) }
    func applicationWillTerminate(_ notification: Notification) {
        if let chatEventMonitor { NSEvent.removeMonitor(chatEventMonitor) }
        model.persist()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openTimer()
        return true
    }
}
#if DEBUG
if CommandLine.arguments.contains("--self-test") {
    Task { @MainActor in exit(await runAppChecks()) }
    RunLoop.main.run()
}
#endif
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}

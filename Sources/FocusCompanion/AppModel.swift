import AppKit
import SwiftUI
import FocusCore

struct ChatMessage: Identifiable {
    enum Sender { case user, companion }
    let id = UUID()
    let sender: Sender
    let text: String
    var policyStatus: String? = nil
    var contextText: String { ConversationText.bounded([text, policyStatus].compactMap { $0 }.joined(separator: "\nSession status: "), utf16Limit: 1000) }
}

@MainActor final class AppModel: ObservableObject {
    @Published var engine = SessionEngine()
    // Never mutate a @Published value inside its own observer: doing so re-enters the setter.
    @Published var preferences: Preferences {
        didSet {
            preferences.save(to: defaults)
            if preferences.rainVolume != oldValue.rainVolume || preferences.rainMuted != oldValue.rainMuted || preferences.rainPauseDuringBreak != oldValue.rainPauseDuringBreak { syncRain() }
        }
    }
    @Published private(set) var messages: [ChatMessage] = [ChatMessage(sender: .companion, text: "I’m here to keep you on task. Start a focus session when you’re ready.")]
    @Published var glassOpacity: Double { didSet { defaults.set(glassOpacity, forKey: "glassOpacity") } }
    @Published var selectedPage = "Today"
    @Published var goal = ""
    @Published var draft = ""
    @Published var busy = false
    @Published var fallback = false
    @Published var notice: String?
    @Published var websiteStatus = "Not checked"
    @Published var saved: Checkpoint?
    @Published var rainRequested = false
    @Published var sleeping = false
    let rain = RainPlayer()
    private let chrome = ChromeAutomation()
    private let client: any CompanionClient
    private let defaults: UserDefaults
    private let servicesEnabled: Bool
    private let conversationTargetProvider: (() async -> Target?)?
    private var lastExternalApplication: NSRunningApplication?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var monitoring = false
    private var announcedInterventions: Set<UUID> = []
    private var lastCheckpoint: Double = 0
    private var conversationTask: Task<Void, Never>?
    private var requestIdentity: UUID?
    private var idleConversationID = UUID()
    private var conversationID: UUID { engine.sessionID ?? idleConversationID }
    var showBubble: (() -> Void)?
    var hideBubble: (() -> Void)?
    var showDashboard: (() -> Void)?
    var sessionDidStart: (() -> Void)?
    var recoverCharacter: (() -> Void)?
    var updatePresentation: (() -> Void)?
    init(client: any CompanionClient = HTTPCompanionClient(), defaults: UserDefaults = .standard, servicesEnabled: Bool = true, conversationTargetProvider: (() async -> Target?)? = nil) {
        self.client = client; self.defaults = defaults; self.servicesEnabled = servicesEnabled
        self.conversationTargetProvider = conversationTargetProvider
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier { lastExternalApplication = app }
        self.preferences = Preferences.load(from: defaults)
        self.glassOpacity = min(0.85, max(0.05, defaults.object(forKey: "glassOpacity") as? Double ?? 0.20))
        if let data = defaults.data(forKey: "checkpoint") { saved = try? JSONDecoder().decode(Checkpoint.self, from: data) }
        guard servicesEnabled else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.monitor() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in guard let self else { return }; self.engine.sleep(now: monotonicNow()); self.sleeping = true; self.persist(); self.syncRain() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in guard let self else { return }; self.engine.wake(now: monotonicNow()); self.sleeping = false; self.syncRain(); self.drain(); await self.monitor() }
        })
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in await self?.pulse() } }
        timer?.tolerance = 0.2
    }
    var now: Double { monotonicNow() }
    var countdown: String {
        let seconds = engine.onBreak ? engine.breakRemaining(now: now) : engine.studyRemaining
        return String(format: "%02d:%02d", Int(ceil(seconds)) / 60, Int(ceil(seconds)) % 60)
    }
    var phase: String { !engine.active ? "Make room for focus" : engine.onBreak ? "A little breathing room" : engine.breakAvailable ? "A break, whenever you’re ready" : "One thing at a time" }
    var progress: Double { engine.onBreak ? engine.breakRemaining(now: now) / Double(engine.rules.breakMinutes * 60) : min(1, engine.studySeconds / Double(engine.rules.studyMinutes * 60)) }
    var characterState: String { busy ? "thinking" : engine.intervention != nil ? "questioning" : engine.onBreak ? "break" : engine.breakAvailable ? "celebration" : engine.active ? "focusing" : "idle" }
    var responseCountdown: Int? { engine.intervention.map { max(0, Int(ceil($0.deadline - now))) } }
    var awarenessTarget: Target? { engine.intervention?.target ?? engine.currentTarget }
    var awarenessClassification: Classification? {
        awarenessTarget.map { engine.rules.classification(of: $0) }
    }
    private func conversationContext() async -> String {
        let target: Target?
        if let conversationTargetProvider { target = await conversationTargetProvider() }
        else if servicesEnabled { target = await currentConversationTarget() }
        else { target = awarenessTarget }
        guard let target else {
            return engine.active ? "Focus session" : "No active session"
        }
        let classification = (engine.active ? engine.rules : preferences.rules).classification(of: target)
        let category = engine.grants.contains(target) ? "Productive; study video allowed for this session" : classification.label
        // Use the existing bounded label contract; never send the full address or page content.
        return "\(ConversationText.bounded(target.label, utf16Limit: 180)) (\(category))"
    }
    private func currentConversationTarget() async -> Target? {
        let foreground = NSWorkspace.shared.frontmostApplication
        let app = foreground?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? lastExternalApplication : foreground
        guard let app, !app.isTerminated else { return nil }
        let pid = app.processIdentifier
        let launchedAt = app.launchDate?.timeIntervalSince1970 ?? 0
        let bundle = app.bundleIdentifier ?? "pid.\(pid)"
        guard bundle == "com.google.Chrome" else { return Target(bundleID: bundle, processID: pid, launchedAt: launchedAt) }
        do {
            let snapshot = try await chrome.snapshot(pid: pid, launchedAt: launchedAt)
            websiteStatus = "Chrome website enforcement available"
            return snapshot.active
        } catch {
            websiteStatus = error.localizedDescription
            // Do not send an older website as though it were the currently open tab.
            return Target(bundleID: bundle, processID: pid, launchedAt: launchedAt)
        }
    }
    var chatNeedsAttention: Bool {
        busy || !draft.isEmpty || engine.intervention != nil || engine.fallbackRequired || fallback || notice != nil || saved != nil
    }
    func start() {
        guard saved == nil else { notice = "Resume or end your interrupted session first."; return }
        cancelConversationRequest()
        announcedInterventions.removeAll()
        engine.start(rules: preferences.rules, goal: goal, now: now); rainRequested = preferences.rainAutoplay
        appendCompanion("Session started. \(engine.rules.studyMinutes) minutes of focus — I’m here if you need me."); fallback = false; notice = nil; syncRain(); persist(); sessionDidStart?(); Task { await monitor() }
    }
    private func cancelConversationRequest() {
        if let id = requestIdentity { engine.cancelRequest(id) }
        conversationTask?.cancel(); requestIdentity = nil; busy = false
    }
    func end() {
        let wasActive = engine.active || saved != nil
        cancelConversationRequest(); engine.end(); saved = nil; fallback = false; notice = nil
        announcedInterventions.removeAll()
        idleConversationID = UUID()
        rainRequested = false; syncRain(); defaults.removeObject(forKey: "checkpoint")
        if wasActive { appendCompanion("Session ended. We can keep chatting, or start again when you’re ready."); showBubble?() }
    }
    func resume() {
        guard let saved else { return }; cancelConversationRequest(); engine.resume(saved, now: now, date: Date(), bootIdentifier: bootIdentifier()); self.saved = nil
        announcedInterventions.removeAll()
        drain(); goal = engine.goal; rainRequested = preferences.rainAutoplay; syncRain(); persist(); appendCompanion(engine.status); sessionDidStart?(); Task { await monitor() }
    }
    func persist() {
        if let checkpoint = engine.checkpoint(now: now, date: Date(), bootIdentifier: bootIdentifier()), let data = try? JSONEncoder().encode(checkpoint) { defaults.set(data, forKey: "checkpoint") }
    }
    func syncRain() { rain.set(playing: rainRequested && !sleeping && !(engine.onBreak && preferences.rainPauseDuringBreak), volume: preferences.rainVolume, muted: preferences.rainMuted) }
    func toggleRain() { rainRequested.toggle(); syncRain() }
    private func pulse() async {
        guard !sleeping else { return }
        let oldStatus = engine.status
        let wasBreak = engine.onBreak; let oldIntervention = engine.intervention?.id
        if engine.active { engine.tick(now: now); drain() }
        if engine.status != oldStatus { appendCompanion(engine.status) }
        if wasBreak != engine.onBreak { syncRain(); persist() }
        if oldIntervention != engine.intervention?.id { cancelStaleRequest() }
        if engine.active && now - lastCheckpoint >= 5 { persist(); lastCheckpoint = now }
        updatePresentation?()
        await monitor()
    }
    func requestAutomation() { Task { await monitor(force: true) } }
    func monitor(force: Bool = false) async {
        guard servicesEnabled, !sleeping else { return }
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        if app.processIdentifier != ProcessInfo.processInfo.processIdentifier { lastExternalApplication = app }
        guard !monitoring, engine.active || force else { return }
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            // Tethri's chat/settings are not a new activity or navigation.
            if !force { return }
        }
        let pid = app.processIdentifier
        let launchedAt = app.launchDate?.timeIntervalSince1970 ?? 0
        let bundle = app.bundleIdentifier ?? "pid.\(pid)"
        if force && bundle != "com.google.Chrome" {
            guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first else { websiteStatus = "Open Chrome, then check Automation access."; return }
            await inspectChrome(pid: running.processIdentifier, launchedAt: running.launchDate?.timeIntervalSince1970 ?? 0, observe: false); return
        }
        if bundle == "com.google.Chrome" { await inspectChrome(pid: pid, launchedAt: launchedAt, observe: true) }
        else if engine.active {
            let target = Target(bundleID: bundle, processID: pid, launchedAt: launchedAt)
            observe(target)
        }
    }
    private func inspectChrome(pid: Int32, launchedAt: Double, observe shouldObserve: Bool) async {
        monitoring = true; defer { monitoring = false }
        let session = engine.sessionID
        do {
            let snapshot = try await chrome.snapshot(pid: pid, launchedAt: launchedAt, inspectGrantedTabs: !engine.grants.isEmpty)
            websiteStatus = "Chrome website enforcement available"
            guard engine.sessionID == session else { return }
            engine.reconcileGrants(existing: snapshot.tabs)
            if shouldObserve, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { observe(snapshot.active) }
        } catch {
            websiteStatus = error.localizedDescription
            // An unreadable tab is unknown activity, not a navigation to another resource.
            // Enforcement still revalidates the real tab before acting.
            if shouldObserve, engine.sessionID == session,
               engine.currentTarget?.bundleID != "com.google.Chrome" || engine.currentTarget?.processID != pid || engine.currentTarget?.launchedAt != launchedAt {
                observe(Target(bundleID: "com.google.Chrome", processID: pid, launchedAt: launchedAt))
            }
        }
    }
    func observe(_ target: Target?) {
        let old = engine.intervention?.id
        engine.observe(target, now: now)
        if engine.intervention?.id != old {
            cancelStaleRequest(); fallback = false
            if let id = engine.intervention?.id, announcedInterventions.insert(id).inserted { appendCompanion(engine.status); showBubble?() }
        }
        drain()
    }
    private func cancelStaleRequest() {
        if requestIdentity != engine.intervention?.requestID {
            if let id = requestIdentity { engine.cancelRequest(id) }
            conversationTask?.cancel(); requestIdentity = nil; busy = false
        }
    }
    private func drain() {
        let actions = engine.takePending()
        guard servicesEnabled else { return }
        for action in actions {
            if action.target.tabID != nil {
                Task {
                    do { try await chrome.close(action.target) { [weak self] current in self?.engine.canEnforce(action, current: current) ?? false } }
                    catch ChromeAutomation.Failure.changed { /* Navigation or cancellation safely wins. */ }
                    catch { notice = error.localizedDescription }
                }
            } else {
                guard let running = NSRunningApplication(processIdentifier: action.target.processID), running.bundleIdentifier == action.target.bundleID,
                      running.launchDate?.timeIntervalSince1970 == action.target.launchedAt, engine.canEnforce(action, current: action.target) else { continue }
                if !running.hide() || !running.isHidden { notice = "Could not hide \(running.localizedName ?? "the app"). You can return to your work manually. Audio may continue in hidden apps." }
            }
        }
    }
    func send() {
        let message = ConversationText.bounded(draft.trimmingCharacters(in: .whitespacesAndNewlines), utf16Limit: 1000)
        guard !busy, !message.isEmpty else { return }
        let activeRequest = engine.active
        let session = conversationID
        guard let id = activeRequest ? engine.beginRequest(now: now) : UUID() else { return }
        let recent = messages.suffix(6).map { CompanionRequest.Message(role: $0.sender == .user ? "user" : "assistant", text: $0.contextText) }
        messages.append(ChatMessage(sender: .user, text: message))
        if messages.count > 40 { messages.removeFirst(messages.count - 40) }
        draft = ""; busy = true; requestIdentity = id; fallback = false; notice = nil
        let intervention = engine.intervention?.id
        let endpoint = preferences.backendURL
        conversationTask = Task {
            do {
                let context = await conversationContext()
                guard !Task.isCancelled, requestIdentity == id, conversationID == session else { return }
                let body = CompanionRequest(requestId: id, sessionId: session, interventionId: intervention, message: message,
                                            recentConversation: Array(recent.suffix(6)), label: context, studyGoal: ConversationText.bounded(activeRequest ? engine.goal : goal, utf16Limit: 500),
                                            breakEligible: engine.breakAvailable, studyRemainingSeconds: activeRequest ? Int(ceil(engine.studyRemaining)) : preferences.rules.studyMinutes * 60, maxBreakMinutes: activeRequest ? engine.rules.breakMinutes : preferences.rules.breakMinutes,
                                            context: engine.conversationContext(now: now))
                let response = try await withThrowingTaskGroup(of: Interpretation.self) { group in
                    group.addTask { try await self.client.interpret(body, endpoint: endpoint) }
                    group.addTask { try await Task.sleep(nanoseconds: 8_000_000_000); throw URLError(.timedOut) }
                    defer { group.cancelAll() }; return try await group.next()!
                }
                guard !Task.isCancelled, requestIdentity == id, conversationID == session else { return }
                guard response.requestId == id, response.sessionId == session, response.interventionId == body.interventionId else { throw ClientFailure.invalid }
                let reply = String(response.reply.prefix(600))
                var policyStatus: String?
                if activeRequest {
                    guard engine.apply(response, now: now) else {
                        busy = false; requestIdentity = nil; fallback = engine.fallbackRequired
                        if fallback { appendCompanion(engine.status) }
                        drain(); syncRain(); persist(); return
                    }
                    if response.intent == .breakRequest || (response.intent == .studyException && intervention != nil) { policyStatus = engine.status }
                } else {
                    // Pre-session conversation cannot mint study time, breaks or OS permissions.
                    if response.intent == .breakRequest { policyStatus = "No focus session is running. Start a session when you’re ready." }
                }
                appendCompanion(reply, policyStatus: policyStatus); showBubble?()
                busy = false; requestIdentity = nil; drain(); syncRain(); persist()
            } catch {
                guard !Task.isCancelled, requestIdentity == id, conversationID == session else { return }
                busy = false; requestIdentity = nil
                if !activeRequest || engine.requestFailed(id, now: now) {
                    fallback = activeRequest; notice = error.localizedDescription
                    appendCompanion(activeRequest ? "I can’t connect right now. Choose a reason below — your focus timer is still running." : "I can’t connect right now. You can still start a focus session here; conversation needs a connection to Gemini.")
                    showBubble?()
                }
            }
        }
    }
    func choose(_ intent: Intent) {
        cancelConversationRequest()
        engine.fallback(intent, now: now); appendCompanion(engine.status); fallback = false; notice = nil
        drain(); syncRain(); persist()
    }
    func endBreak() { engine.finishBreak(); appendCompanion(engine.status); drain(); syncRain(); persist() }
    private func appendCompanion(_ text: String, policyStatus: String? = nil) {
        guard messages.last?.text != text || messages.last?.sender != .companion || messages.last?.policyStatus != policyStatus else { return }
        messages.append(ChatMessage(sender: .companion, text: text, policyStatus: policyStatus))
        if messages.count > 40 { messages.removeFirst(messages.count - 40) }
    }
    #if DEBUG
    func previewDistraction() {
        guard !servicesEnabled else { return }
        messages = []
        observe(Target(bundleID: "com.google.Chrome", processID: 999_999, launchedAt: 0, tabID: "preview", url: URL(string: "https://youtube.com/watch?v=abcdefghijk")!))
    }
    #endif
    func addApp() {
        let panel = NSOpenPanel(); panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.allowedContentTypes = [.application]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier { preferences.rules.apps[id] = .distracting }
    }

}

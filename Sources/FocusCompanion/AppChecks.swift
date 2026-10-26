#if DEBUG
import Foundation
import AppKit
import FocusCore

struct PreviewCompanionClient: CompanionClient {
    var fails = false
    var echoContext = false
    var intent: Intent?
    var inspect: (@MainActor (CompanionRequest) -> Void)?
    func interpret(_ request: CompanionRequest, endpoint: String) async throws -> Interpretation {
        await inspect?(request)
        try await Task.sleep(nanoseconds: 250_000_000)
        if fails { throw URLError(.notConnectedToInternet) }
        return Interpretation(requestId: request.requestId, sessionId: request.sessionId, interventionId: request.interventionId,
                              intent: intent ?? (request.message.lowercased().contains("break") ? .breakRequest : .chat),
                              reply: echoContext ? request.label : "Let’s make it smaller. Pick one thing you can finish in the next few minutes. I’m right here.")
    }
}
@MainActor func runAppChecks() async -> Int32 {
    let suite = "com.focuscompanion.checks.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var failures = 0
    func check(_ value: Bool, _ description: String) {
        if !value { failures += 1; print("FAIL: \(description)") } else { print("PASS: \(description)") }
    }
    for bounds in [NSRect(x: 0, y: 0, width: 1440, height: 900), NSRect(x: -1440, y: 100, width: 1440, height: 900)] {
        for x in [bounds.minX, bounds.maxX - 100] {
            for y in [bounds.minY, bounds.midY, bounds.maxY - 108] {
                let orb = NSRect(x: x, y: y, width: 100, height: 108)
                let size = NSSize(width: 354, height: 520)
                let chat = NSRect(origin: CompanionPlacement.chatOrigin(orb: orb, chat: size, bounds: bounds), size: size)
                check(!chat.intersects(orb) && bounds.contains(chat), "chat stays on screen and clear of orb at \(orb.origin)")
            }
        }
    }
    let model = AppModel(client: PreviewCompanionClient(), defaults: defaults, servicesEnabled: false)
    // Exercise repeated nested preference writes and start with legacy consent unset.
    for _ in 0..<100 { model.preferences.consent.toggle() }
    model.preferences.consent = false
    check(!Preferences.load(from: defaults).consent, "preference updates persist without recursive publication")
    model.preferences.rainMuted.toggle(); model.preferences.rules.studyMinutes = 5
    check(Preferences.load(from: defaults).rules.studyMinutes == 5, "other settings writes persist")
    model.glassOpacity = 0.12
    check(defaults.double(forKey: "glassOpacity") == 0.12, "background opacity persists independently of consent and rules")
    func settle(_ model: AppModel) async {
        for _ in 0..<200 { if !model.busy { break }; try? await Task.sleep(nanoseconds: 10_000_000) }
    }
    check(!model.engine.active && model.messages.count == 1, "chat opens with a welcome before a session")
    check(!model.chatNeedsAttention, "read conversation history allows automatic minimization")
    model.draft = "unfinished message"
    check(model.chatNeedsAttention, "an unfinished draft keeps chat open")
    model.draft = "I feel stuck"; model.send()
    check(model.busy && model.messages.last?.sender == .user, "pre-session composer sends and shows thinking")
    check(model.chatNeedsAttention, "chat stays open while waiting for a reply")
    await settle(model)
    check(!model.busy && model.messages.count == 3 && model.messages.last?.text.contains("make it smaller") == true, "pre-session chat receives a reply without starting a timer")
    check(!model.chatNeedsAttention, "a completed reply allows chat to minimize after its reading delay")
    check(!model.engine.active, "ordinary conversation does not silently start a session")
    let studyChat = AppModel(client: PreviewCompanionClient(intent: .studyException), defaults: defaults, servicesEnabled: false)
    studyChat.draft = "Help me write an essay about volcanoes"; studyChat.send(); await settle(studyChat)
    check(studyChat.messages.last?.text.contains("make it smaller") == true, "pre-session study conversation preserves the provider reply")
    check(!studyChat.engine.active, "pre-session study conversation does not grant session access")
    let beforeStart = model.messages.map(\.id)
    model.start()
    check(model.engine.active && model.messages.starts(with: beforeStart, by: { $0.id == $1 }), "Start session preserves the same chat")
    model.draft = "hello again"; model.send(); await settle(model)
    check(model.messages.last?.text.contains("make it smaller") == true, "the same composer works during a session")
    model.draft = "I want a break"; model.send(); await settle(model)
    check(!model.engine.onBreak && model.messages.last?.policyStatus?.contains("until a break") == true, "early-break reply shows actual local policy separately")
    check(model.messages.last?.text.contains("make it smaller") == true, "early-break requests preserve Gemini's conversational reply")
    let beforeEnd = model.messages.map(\.id)
    model.end()
    check(!model.engine.active && model.messages.starts(with: beforeEnd, by: { $0.id == $1 }), "ending a session preserves the conversation")
    model.draft = "keep talking"; model.send(); await settle(model)
    check(!model.busy && model.messages.last?.text.contains("make it smaller") == true, "chat continues after the session ends")
    model.draft = "I want a break"; model.send(); await settle(model)
    check(!model.engine.active && !model.engine.onBreak && model.messages.last?.policyStatus?.contains("No focus session") == true, "pre-session requests cannot grant a break")
    check(model.messages.last?.text.contains("make it smaller") == true, "pre-session break requests preserve the provider reply")
    model.draft = "late reply"; model.send(); model.start()
    let afterTransition = model.messages.count
    try? await Task.sleep(nanoseconds: 350_000_000)
    check(!model.busy && model.messages.count == afterTransition, "starting a session cancels stale pre-session replies")
    model.end()
    let offline = AppModel(client: PreviewCompanionClient(fails: true), defaults: defaults, servicesEnabled: false)
    offline.draft = "hello"; offline.send(); await settle(offline)
    check(!offline.busy && !offline.fallback && offline.messages.last?.text.contains("can’t connect") == true, "offline pre-session chat keeps Start session available")
    offline.start(); offline.draft = "hello"; offline.send(); await settle(offline)
    check(offline.fallback && offline.messages.last?.text.contains("can’t connect") == true, "offline active chat exposes policy fallback")
    check(offline.chatNeedsAttention, "an unresolved connection notice keeps chat open")
    offline.choose(.breakRequest)
    check(!offline.engine.onBreak, "fallback cannot bypass earned-break rules")
    offline.end()
    let aware = AppModel(client: PreviewCompanionClient(echoContext: true), defaults: defaults, servicesEnabled: false)
    aware.start()
    for (host, category) in [("github.com", Classification.productive), ("google.com", .neutral), ("reddit.com", .distracting)] {
        let target = Target(bundleID: "com.google.Chrome", processID: 42, launchedAt: 1, tabID: "7", url: URL(string: "https://\(host)/private-path?q=secret")!)
        aware.engine.observe(target, now: aware.now)
        check(aware.awarenessClassification == category, "chat shows \(category.label) for \(host)")
        aware.draft = "Where am I working?"; aware.send(); await settle(aware)
        check(aware.messages.last?.text == "\(host) (\(category.label))", "conversation receives category and host without path or query")
    }
    aware.end()
    check(aware.awarenessTarget == nil, "ending the session clears site awareness")
    var currentSite: Target? = Target(bundleID: "com.google.Chrome", processID: 42, launchedAt: 1, tabID: "7", url: URL(string: "https://wikipedia.org/private?q=secret")!)
    let fresh = AppModel(client: PreviewCompanionClient(echoContext: true), defaults: defaults, servicesEnabled: false, conversationTargetProvider: { currentSite })
    fresh.draft = "What site am I on?"; fresh.send(); await settle(fresh)
    check(fresh.messages.last?.text == "wikipedia.org (Productive)", "pre-session answer includes the current website without path or query")
    fresh.start()
    fresh.engine.observe(currentSite, now: fresh.now)
    currentSite = Target(bundleID: "com.google.Chrome", processID: 42, launchedAt: 1, tabID: "8", url: URL(string: "https://reddit.com/private?q=secret")!)
    fresh.draft = "I switched tabs. Where am I?"; fresh.send(); await settle(fresh)
    check(fresh.messages.last?.text == "reddit.com (Unproductive)", "send-time website replaces a stale monitoring snapshot")
    currentSite = nil
    fresh.draft = "Is the website still known?"; fresh.send(); await settle(fresh)
    check(fresh.messages.last?.text == "Focus session", "unavailable current website does not reuse a stale domain")
    fresh.end()
    var captured: [CompanionRequest] = []
    let contextual = AppModel(client: PreviewCompanionClient(intent: .studyException, inspect: { captured.append($0) }), defaults: defaults, servicesEnabled: false)
    contextual.draft = "Help me plan an essay"; contextual.send(); await settle(contextual)
    check(captured.last?.context.sessionPhase == .idle && captured.last?.context.studyAccess == ConversationContext.StudyAccess.none, "Gemini receives idle state without invented video context")
    check(captured.last?.recentConversation.last?.text.contains("keep you on task") == true, "provider context includes the visible conversation")
    contextual.start()
    contextual.engine.observe(Target(bundleID: "com.google.Chrome", processID: 42, launchedAt: 1, tabID: "7", url: URL(string: "https://reddit.com/r/math")!), now: contextual.now)
    contextual.draft = "This discussion is for my assignment"; contextual.send(); await settle(contextual)
    check(captured.last?.context.interventionLabel == "reddit.com" && captured.last?.context.studyAccess == .ruleChangeRequired, "Gemini receives the captured resource and supported access policy")
    check(captured.last?.recentConversation.contains(where: { $0.text.contains("Session started") }) == true, "session transitions are included in provider history")
    check(contextual.messages.last?.text.contains("make it smaller") == true && contextual.messages.last?.policyStatus?.contains("marked distracting") == true, "unsupported study resources preserve the reply and expose the local restriction")
    check(contextual.messages.last?.policyStatus?.contains("YouTube") == false && contextual.engine.grants.isEmpty, "other websites neither redirect to YouTube nor gain unsupported access")
    contextual.end()
    contextual.draft = "What next?"; contextual.send(); await settle(contextual)
    check(captured.last?.context.sessionPhase == .idle && captured.last?.context.interventionLabel == nil, "ended sessions do not send stale intervention context")
    check(captured.last?.recentConversation.contains(where: { $0.text.contains("Session ended") }) == true, "Gemini sees the end of the session in recent history")
    var late: AppModel?
    late = AppModel(client: PreviewCompanionClient(intent: .studyException, inspect: { _ in
        if let late { late.engine.tick(now: late.now + 9) }
    }), defaults: defaults, servicesEnabled: false)
    late!.start()
    late!.engine.observe(Target(bundleID: "com.google.Chrome", processID: 42, launchedAt: 1, tabID: "7", url: URL(string: "https://youtube.com/watch?v=abcdefghijk")!), now: late!.now)
    late!.draft = "This is my lecture"; late!.send(); await settle(late!)
    check(late!.fallback && late!.engine.grants.isEmpty, "expired engine requests expose fallback without granting access")
    check(late!.messages.last?.text.contains("make it smaller") == false, "a rejected late reply is not added to the visible conversation")
    late!.end(); late = nil
    let repeated = AppModel(client: PreviewCompanionClient(intent: .clarify), defaults: defaults, servicesEnabled: false)
    repeated.start()
    let distracting = Target(bundleID: "com.google.Chrome", processID: 42, launchedAt: 1, tabID: "7", url: URL(string: "https://reddit.com/r/math")!)
    let working = Target(bundleID: "com.google.Chrome", processID: 42, launchedAt: 1, tabID: "8", url: URL(string: "https://github.com")!)
    var presentations = 0
    repeated.showBubble = { presentations += 1 }
    repeated.observe(distracting)
    let initialQuestion = repeated.messages.last!.text
    check(initialQuestion.contains("reddit.com") && !initialQuestion.contains("What are you doing"), "initial intervention names the resource it is asking about")
    repeated.draft = "This discussion helps my assignment"; repeated.send(); await settle(repeated)
    let countAfterReply = repeated.messages.count
    let presentationsAfterReply = presentations
    for _ in 0..<5 { repeated.observe(working); repeated.observe(distracting) }
    check(repeated.messages.count == countAfterReply && presentations == presentationsAfterReply, "switching away and back does not repeat the question or reopen the chat")
    check(repeated.messages.last?.text.contains("make it smaller") == true, "the existing answer remains the latest reply after switching activities")
    repeated.observe(nil); repeated.observe(distracting)
    check(repeated.messages.count == countAfterReply, "a temporary missing target does not duplicate a question")
    repeated.end()
    print("App checks: \(failures) failures")
    return failures == 0 ? 0 : 1
}
#endif

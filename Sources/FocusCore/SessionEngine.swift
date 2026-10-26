import Foundation

/// All permissions and clocks live here. Provider prose cannot mutate policy.
public struct SessionEngine {
    public private(set) var sessionID: UUID?
    public private(set) var rules = Rules()
    public private(set) var goal = ""
    public private(set) var studySeconds: Double = 0
    public private(set) var breakAvailable = false
    public private(set) var breakDeadline: Double?
    public private(set) var intervention: Intervention?
    public private(set) var fallbackRequired = false
    public private(set) var currentTarget: Target?
    public private(set) var grants: Set<Target> = []
    public private(set) var tracked: Set<Target> = []
    public private(set) var pending: [Enforcement] = []
    public private(set) var status = "Ready when you are."
    private var lastTick: Double?
    private var awake = true
    private var chatRequest: UUID?
    private var denied: Set<Target> = []
    private struct PausedIntervention {
        var question: Intervention
        let status: String
        let fallbackRequired: Bool
    }
    private var pausedInterventions: [Target: PausedIntervention] = [:]
    public init() {}
    public var active: Bool { sessionID != nil }
    public var onBreak: Bool { breakDeadline != nil }
    public var studyRemaining: Double { max(0, Double(rules.studyMinutes * 60) - studySeconds) }
    public func breakRemaining(now: Double) -> Double { max(0, (breakDeadline ?? now) - now) }
    public func conversationContext(now: Double) -> ConversationContext {
        let target = intervention?.target
        let access: ConversationContext.StudyAccess
        if let target {
            if target.videoID != nil { access = .videoAvailable }
            else if let host = target.host, URLPolicy.matches(host, domain: "youtube.com") || host == "youtu.be" { access = .videoRequired }
            else { access = .ruleChangeRequired }
        } else { access = .none }
        return ConversationContext(sessionPhase: !active ? .idle : onBreak ? .break : .focus,
                                   breakRemainingSeconds: onBreak ? Int(ceil(breakRemaining(now: now))) : 0,
                                   interventionLabel: target.map { ConversationText.bounded($0.label, utf16Limit: 255) }, studyAccess: access)
    }
    public mutating func start(rules: Rules, goal: String, now: Double) {
        self = SessionEngine(); self.rules = rules; self.rules.normalize(); self.goal = ConversationText.bounded(goal, utf16Limit: 500)
        sessionID = UUID(); lastTick = now; status = "One small step. Let’s focus."
    }
    public mutating func end() { self = SessionEngine() }
    public mutating func tick(now: Double) {
        guard active else { return }
        let delta = max(0, now - (lastTick ?? now)); lastTick = now
        if let deadline = breakDeadline {
            if now >= deadline { finishBreak() }
        } else if awake && intervention == nil && !isDenied(currentTarget) {
            studySeconds = min(Double(rules.studyMinutes * 60), studySeconds + delta)
            if studyRemaining == 0 { breakAvailable = true }
        }
        if let i = intervention, now >= i.deadline {
            if i.requestID != nil {
                intervention?.requestID = nil; intervention?.deadline = now + 20; fallbackRequired = true
                status = "Conversation timed out. Choose a reason below."
            } else { deny(i); status = "Let’s return to your goal." }
        }
    }
    public mutating func sleep(now: Double) { tick(now: now); awake = false }
    public mutating func wake(now: Double) { lastTick = now; awake = true; tick(now: now) }
    private func isDenied(_ target: Target?) -> Bool {
        guard let t = target else { return false }
        return rules.classification(of: t) == .distracting && !grants.contains(t)
    }
    public mutating func observe(_ target: Target?, now: Double) {
        tick(now: now)
        currentTarget = target
        // A grant ends on any observed navigation within its tab.
        if let t = target {
            grants = grants.filter { !$0.sameInstance(as: t) || $0 == t }
        }
        if var i = intervention, i.target != target {
            // Keep this resource's question and original deadline when focus moves away.
            // A cancelled provider request gets the same local recovery window as a failure.
            if i.requestID != nil { i.requestID = nil; i.deadline = now + 20 }
            if pausedInterventions.count >= 32, let oldest = pausedInterventions.min(by: { $0.value.question.deadline < $1.value.question.deadline })?.key {
                pausedInterventions.removeValue(forKey: oldest)
            }
            pausedInterventions[i.target] = PausedIntervention(question: i, status: status, fallbackRequired: fallbackRequired)
            intervention = nil; fallbackRequired = false
        }
        guard let t = target, isDenied(t) else { return }
        if onBreak { tracked = tracked.filter { !$0.sameInstance(as: t) }; tracked.insert(t); return }
        guard active, intervention == nil else { return }
        if denied.contains(t), let sessionID {
            if !pending.contains(where: { $0.target == t }) { pending.append(Enforcement(sessionID: sessionID, target: t, interventionID: nil)) }; return
        }
        if let paused = pausedInterventions.removeValue(forKey: t) {
            intervention = paused.question; status = paused.status; fallbackRequired = paused.fallbackRequired
            // Returning to a resource cannot reset or renew its question deadline.
            tick(now: now)
            return
        }
        intervention = Intervention(id: UUID(), target: t, deadline: now + 20)
        status = "\(t.label) is marked distracting. Is it part of your focus task?"
    }
    /// A snapshot of all existing granted tabs, without page content, invalidates background navigations.
    public mutating func reconcileGrants(existing: Set<Target>) { grants.formIntersection(existing) }
    public mutating func beginRequest(now: Double) -> UUID? {
        tick(now: now)
        guard active else { return nil }
        if intervention?.requestID != nil || chatRequest != nil { return nil }
        let id = UUID(); fallbackRequired = false
        if intervention != nil { intervention?.requestID = id; intervention?.deadline = now + 8 }
        else { chatRequest = id }
        return id
    }
    public mutating func cancelRequest(_ id: UUID) {
        if chatRequest == id { chatRequest = nil }
        if intervention?.requestID == id { intervention?.requestID = nil }
    }
    public mutating func requestFailed(_ id: UUID, now: Double) -> Bool {
        if intervention?.requestID == id { intervention?.requestID = nil; intervention?.deadline = now + 20; fallbackRequired = true; return true }
        if chatRequest == id { chatRequest = nil; fallbackRequired = true; return true }
        return false
    }
    @discardableResult public mutating func apply(_ response: Interpretation, now: Double) -> Bool {
        // Deadline wins even if the transport completes late.
        tick(now: now)
        guard response.sessionId == sessionID else { return false }
        if let i = intervention {
            guard response.interventionId == i.id, response.requestId == i.requestID else { return false }
            intervention?.requestID = nil
        } else {
            guard response.interventionId == nil, response.requestId == chatRequest else { return false }
            chatRequest = nil
        }
        decide(intent: response.intent, minutes: response.requestedBreakMinutes, reply: response.reply, now: now)
        return true
    }
    public mutating func fallback(_ intent: Intent, now: Double) {
        tick(now: now)
        guard active else { return }
        intervention?.requestID = nil; chatRequest = nil
        decide(intent: intent, minutes: nil, reply: "", now: now)
    }
    private mutating func decide(intent: Intent, minutes: Double?, reply: String, now: Double) {
        fallbackRequired = false
        switch intent {
        case .breakRequest:
            guard !onBreak else { status = "Your break is already running."; return }
            guard breakAvailable else {
                status = "Keep going — \(Int(ceil(studyRemaining / 60))) minutes until a break."
                if let i = intervention { deny(i) }; return
            }
            let duration = min(Double(rules.breakMinutes), max(1.0 / 60, minutes.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? Double(rules.breakMinutes)))
            if let i = intervention { tracked.insert(i.target) }
            breakAvailable = false; studySeconds = 0; breakDeadline = now + duration * 60; intervention = nil
            status = "Enjoy your break. I’ll keep time."
        case .studyException:
            guard let i = intervention else {
                status = reply.isEmpty ? "What would help with your task?" : String(reply.prefix(600))
                return
            }
            guard i.target.videoID != nil else {
                status = conversationContext(now: now).studyAccess == .videoRequired
                    ? "Open a specific study video on this site, then explain it here."
                    : "This resource is marked distracting. Change its rule before your next session."
                intervention?.deadline = now + 20; return
            }
            grants.insert(i.target); intervention = nil; status = "This video is allowed for study. Keep going."
        case .distraction:
            if let i = intervention { deny(i) }
            status = reply.isEmpty ? "Let’s take one small step toward your goal." : String(reply.prefix(600))
        case .clarify, .chat:
            status = reply.isEmpty ? "Tell me how this relates to your focus task." : String(reply.prefix(600))
            intervention?.deadline = now + 20
        }
    }
    private mutating func deny(_ i: Intervention) {
        guard let sessionID else { return }
        denied.insert(i.target); fallbackRequired = false
        pending.append(Enforcement(sessionID: sessionID, target: i.target, interventionID: i.id)); intervention = nil
    }
    public mutating func finishBreak() {
        guard breakDeadline != nil, let sessionID else { return }
        breakDeadline = nil; studySeconds = 0; breakAvailable = false
        denied.formUnion(tracked)
        pending.append(contentsOf: tracked.map { Enforcement(sessionID: sessionID, target: $0, interventionID: nil) })
        tracked.removeAll(); status = "Break finished. Let’s return to your goal."
    }
    public func canEnforce(_ action: Enforcement, current: Target) -> Bool {
        active && sessionID == action.sessionID && !onBreak && action.target == current && isDenied(current)
            && (intervention == nil || intervention?.target != current || intervention?.id == action.interventionID)
    }
    public mutating func takePending() -> [Enforcement] { defer { pending.removeAll() }; return pending }
    public func checkpoint(now: Double, date: Date, bootIdentifier: String = "test-boot") -> Checkpoint? {
        guard let sessionID else { return nil }
        return Checkpoint(sessionID: sessionID, rules: rules, goal: goal, studySeconds: studySeconds, breakAvailable: breakAvailable,
                          breakEnd: breakDeadline.map { date.addingTimeInterval(max(0, $0 - now)) },
                          breakMonotonicDeadline: breakDeadline, savedMonotonicTime: now, bootIdentifier: bootIdentifier, trackedTargets: tracked)
    }
    public mutating func resume(_ saved: Checkpoint, now: Double, date: Date, bootIdentifier: String = "test-boot") {
        self = SessionEngine(); sessionID = saved.sessionID; rules = saved.rules; rules.normalize(); goal = saved.goal
        studySeconds = max(0, min(saved.studySeconds, Double(rules.studyMinutes * 60))); breakAvailable = saved.breakAvailable; lastTick = now
        if let end = saved.breakEnd {
            studySeconds = 0; breakAvailable = false; tracked = saved.trackedTargets
            let remaining: Double
            if saved.bootIdentifier == bootIdentifier, now >= saved.savedMonotonicTime, let deadline = saved.breakMonotonicDeadline { remaining = deadline - now }
            else { remaining = min(end.timeIntervalSince(date), Double(rules.breakMinutes * 60)) }
            // Route expired interrupted breaks through the same revalidated enforcement queue.
            breakDeadline = now + max(0, remaining)
            if remaining <= 0 { finishBreak() }
        }
        status = "Session resumed. Let’s keep going."
    }
}

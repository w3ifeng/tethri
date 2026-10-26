import Foundation

/// Match the backend's UTF-16 string limits without splitting a visible character.
public enum ConversationText {
    public static func bounded(_ text: String, utf16Limit: Int) -> String {
        var end = text.startIndex
        var length = 0
        while end < text.endIndex {
            let next = text.index(after: end)
            let count = text[end..<next].utf16.count
            guard length + count <= utf16Limit else { break }
            length += count; end = next
        }
        return String(text[..<end])
    }
}

public enum Classification: String, Codable, CaseIterable {
    case productive, distracting, neutral
    public var label: String { self == .distracting ? "Unproductive" : rawValue.capitalized }
}
public struct Rules: Codable, Equatable {
    public var studyMinutes = 25
    public var breakMinutes = 5
    public var apps: [String: Classification] = ["com.microsoft.VSCode": .productive, "notion.id": .productive, "com.roblox.RobloxPlayer": .distracting]
    /// User overrides are stored separately so new built-in rules also reach existing installs.
    public var domains: [String: Classification] = [:]
    public static let builtInDomains: [String: Classification] = [
        "github.com": .productive, "gitlab.com": .productive, "stackoverflow.com": .productive,
        "developer.apple.com": .productive, "developer.mozilla.org": .productive,
        "docs.google.com": .productive, "notion.so": .productive, "notion.site": .productive,
        "overleaf.com": .productive, "khanacademy.org": .productive, "coursera.org": .productive,
        "edx.org": .productive, "wikipedia.org": .productive,
        "youtube.com": .distracting, "youtu.be": .distracting, "tiktok.com": .distracting,
        "instagram.com": .distracting, "facebook.com": .distracting, "reddit.com": .distracting,
        "x.com": .distracting, "twitter.com": .distracting, "twitch.tv": .distracting,
        "netflix.com": .distracting, "roblox.com": .distracting,
        "google.com": .neutral, "bing.com": .neutral, "duckduckgo.com": .neutral,
        "mail.google.com": .neutral, "calendar.google.com": .neutral
    ]
    public var knownDomains: [String: Classification] {
        Self.builtInDomains.merging(domains, uniquingKeysWith: { _, custom in custom })
    }
    public init() {}
    public mutating func normalize() {
        studyMinutes = min(180, max(5, studyMinutes)); breakMinutes = min(30, max(1, breakMinutes))
        domains = Dictionary(domains.compactMap { key, value in
            let host = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard !host.isEmpty, !host.contains("/"), !host.contains(":") else { return nil }
            return (host, value)
        }, uniquingKeysWith: { _, last in last })
    }
    public func classification(of target: Target) -> Classification {
        if let host = target.host {
            return classification(ofHost: host)
        }
        return apps[target.bundleID] ?? .neutral
    }
    public func classification(ofHost host: String) -> Classification {
        func match(in rules: [String: Classification]) -> Classification? {
            rules.keys.filter { URLPolicy.matches(host, domain: $0) }
                .sorted { $0.count > $1.count }.first.flatMap { rules[$0] }
        }
        return match(in: domains) ?? match(in: Self.builtInDomains) ?? .neutral
    }
}
public enum URLPolicy {
    public static func matches(_ host: String, domain: String) -> Bool {
        let h = host.lowercased(), d = domain.lowercased()
        return h == d || h.hasSuffix("." + d)
    }
    public static func videoID(_ url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let candidate: String?
        if host == "youtu.be" { candidate = url.pathComponents.dropFirst().first }
        else if matches(host, domain: "youtube.com"), url.path == "/watch" {
            candidate = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value
        } else { return nil }
        guard let id = candidate, id.count == 11, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) else { return nil }
        return id
    }
    public static func resource(_ url: URL) -> String {
        if let id = videoID(url) { return "youtube-video:" + id }
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        c?.fragment = nil
        return c?.string ?? url.absoluteString
    }
}
public struct Target: Codable, Hashable {
    public let bundleID: String
    public let processID: Int32
    public let launchedAt: Double
    public let tabID: String?
    public let resource: String
    public let host: String?
    public let videoID: String?
    public init(bundleID: String, processID: Int32, launchedAt: Double, tabID: String? = nil, url: URL? = nil) {
        self.bundleID = bundleID; self.processID = processID; self.launchedAt = launchedAt; self.tabID = tabID
        self.host = url?.host?.lowercased(); self.videoID = url.flatMap(URLPolicy.videoID)
        self.resource = url.map(URLPolicy.resource) ?? bundleID
    }
    public static func == (lhs: Target, rhs: Target) -> Bool { lhs.sameInstance(as: rhs) && lhs.resource == rhs.resource }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(bundleID); hasher.combine(processID); hasher.combine(launchedAt); hasher.combine(tabID); hasher.combine(resource)
    }
    public var label: String { host ?? bundleID }
    public func sameInstance(as other: Target) -> Bool {
        bundleID == other.bundleID && processID == other.processID && launchedAt == other.launchedAt && tabID == other.tabID
    }
}
public enum Intent: String, Codable { case breakRequest = "break_request", studyException = "study_exception", distraction, clarify, chat }
public struct ConversationContext: Codable {
    public enum Phase: String, Codable { case idle, focus, `break` }
    public enum StudyAccess: String, Codable {
        case none, videoAvailable = "video_available", videoRequired = "video_required", ruleChangeRequired = "rule_change_required"
    }
    public let sessionPhase: Phase
    public let breakRemainingSeconds: Int
    public let interventionLabel: String?
    public let studyAccess: StudyAccess
    private enum CodingKeys: String, CodingKey { case sessionPhase, breakRemainingSeconds, interventionLabel, studyAccess }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionPhase, forKey: .sessionPhase)
        try container.encode(breakRemainingSeconds, forKey: .breakRemainingSeconds)
        try container.encode(interventionLabel, forKey: .interventionLabel)
        try container.encode(studyAccess, forKey: .studyAccess)
    }
}
public struct Interpretation: Codable {
    public var requestId: UUID
    public var sessionId: UUID
    public var interventionId: UUID?
    public var intent: Intent
    public var requestedBreakMinutes: Double?
    public var reply: String
    public init(requestId: UUID, sessionId: UUID, interventionId: UUID?, intent: Intent, requestedBreakMinutes: Double? = nil, reply: String = "") {
        self.requestId = requestId; self.sessionId = sessionId; self.interventionId = interventionId; self.intent = intent; self.requestedBreakMinutes = requestedBreakMinutes; self.reply = reply
    }
}
public struct Intervention: Equatable {
    public let id: UUID
    public let target: Target
    public var deadline: Double
    public var requestID: UUID?
}
public struct Enforcement: Equatable {
    public let sessionID: UUID
    public let target: Target
    public let interventionID: UUID?
}
public struct Checkpoint: Codable {
    public var sessionID: UUID
    public var rules: Rules
    public var goal: String
    public var studySeconds: Double
    public var breakAvailable: Bool
    public var breakEnd: Date?
    public var breakMonotonicDeadline: Double?
    public var savedMonotonicTime: Double
    public var bootIdentifier: String
    public var trackedTargets: Set<Target>
}

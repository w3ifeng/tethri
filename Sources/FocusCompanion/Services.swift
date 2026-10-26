import AppKit
import AVFoundation
import FocusCore

func monotonicNow() -> Double {
    var timebase = mach_timebase_info_data_t(); mach_timebase_info(&timebase)
    return Double(mach_continuous_time()) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
}
func bootIdentifier() -> String {
    var value = timeval(); var size = MemoryLayout<timeval>.size
    guard sysctlbyname("kern.boottime", &value, &size, nil, 0) == 0 else { return "unknown" }
    return "\(value.tv_sec).\(value.tv_usec)"
}
struct Preferences: Codable {
    var rules = Rules()
    var rainAutoplay = false
    var rainPauseDuringBreak = false
    var rainVolume: Double = 0.35
    var rainMuted = false
    var backendURL = Bundle.main.object(forInfoDictionaryKey: "CompanionBackendURL") as? String ?? ""
    var consent = false
    static func load(from defaults: UserDefaults = .standard) -> Preferences {
        guard let data = defaults.data(forKey: "preferences"), var value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        if value.backendURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { value.backendURL = Self().backendURL }
        value.rules.normalize()
        value.rainVolume = min(1, max(0, value.rainVolume))
        return value
    }
    func save(to defaults: UserDefaults = .standard) { if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: "preferences") } }
}
enum ClientFailure: LocalizedError {
    case setup, invalid, server(Int)
    var errorDescription: String? {
        switch self {
        case .setup: return "The conversation service is unavailable. Try reopening Tethri."
        case .invalid: return "The companion returned an invalid response. Use a reason below."
        case .server(let code): return code == 429 ? "Conversation quota reached. Use a reason below." : "Conversation unavailable (\(code)). Use a reason below."
        }
    }
}
struct CompanionRequest: Codable {
    struct Message: Codable { let role: String; let text: String }
    let requestId: UUID
    let sessionId: UUID
    let interventionId: UUID?
    let message: String
    let recentConversation: [Message]
    let label: String
    let studyGoal: String
    let breakEligible: Bool
    let studyRemainingSeconds: Int
    let maxBreakMinutes: Int
    let context: ConversationContext
}
protocol CompanionClient { func interpret(_ request: CompanionRequest, endpoint: String) async throws -> Interpretation }
struct HTTPCompanionClient: CompanionClient {
    private func base(_ endpoint: String, path: String) throws -> URL {
        guard let url = URL(string: endpoint), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil, url.query == nil else { throw ClientFailure.setup }
        return url.appendingPathComponent(path)
    }
    func interpret(_ body: CompanionRequest, endpoint: String) async throws -> Interpretation {
        var request = URLRequest(url: try base(endpoint, path: "v1/companion/interpret")); request.httpMethod = "POST"; request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let defaults = UserDefaults.standard
        let clientID = defaults.string(forKey: "conversationClientID") ?? UUID().uuidString
        defaults.set(clientID, forKey: "conversationClientID")
        request.setValue(clientID, forHTTPHeaderField: "X-Focus-Client")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw ClientFailure.server((response as? HTTPURLResponse)?.statusCode ?? 0) }
        guard data.count < 16_384, let result = try? JSONDecoder().decode(Interpretation.self, from: data), result.requestId == body.requestId, result.sessionId == body.sessionId, result.interventionId == body.interventionId,
              !result.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, result.reply.count <= 600, result.requestedBreakMinutes.map({ $0.isFinite && $0 > 0 && $0 <= 180 }) ?? true else { throw ClientFailure.invalid }
        return result
    }
}
@MainActor final class RainPlayer: ObservableObject {
    @Published private(set) var playing = false
    @Published private(set) var error: String?
    private var player: AVAudioPlayer?
    private var fadeGeneration = UUID()
    init() {
        do {
            guard let url = Bundle.main.url(forResource: "rain", withExtension: "wav") ?? Bundle.module.url(forResource: "rain", withExtension: "wav", subdirectory: "Resources") else { return }
            player = try AVAudioPlayer(contentsOf: url); player?.numberOfLoops = -1; player?.prepareToPlay()
        } catch { self.error = "Rain audio could not be loaded." }
    }
    func set(playing: Bool, volume: Double, muted: Bool) {
        guard let player else { error = "Rain audio is unavailable."; return }
        self.playing = playing; fadeGeneration = UUID(); let generation = fadeGeneration
        if playing { if !player.isPlaying { player.volume = 0; player.play() }; player.setVolume(muted ? 0 : Float(volume), fadeDuration: 1) }
        else {
            player.setVolume(0, fadeDuration: 1)
            Task { try? await Task.sleep(nanoseconds: 1_000_000_000); if self.fadeGeneration == generation { player.pause() } }
        }
    }
}

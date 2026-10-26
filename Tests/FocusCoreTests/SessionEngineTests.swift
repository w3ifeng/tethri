import XCTest
@testable import FocusCore

final class SessionEngineTests: XCTestCase {
    func target(_ url: String = "https://youtube.com/watch?v=abcdefghijk", pid: Int32 = 42, tab: String = "7") -> Target {
        Target(bundleID: "com.google.Chrome", processID: pid, launchedAt: 100, tabID: tab, url: URL(string: url)!)
    }
    func engine() -> SessionEngine { var e = SessionEngine(); var r = Rules(); r.studyMinutes = 5; e.start(rules: r, goal: "Algebra", now: 0); return e }
    func respond(_ e: inout SessionEngine, _ intent: Intent, now: Double, minutes: Double? = nil) {
        let id = e.beginRequest(now: now)!
        e.apply(Interpretation(requestId: id, sessionId: e.sessionID!, interventionId: e.intervention?.id, intent: intent, requestedBreakMinutes: minutes), now: now + 0.1)
    }
    func testBreakIsQuietOptionalAndDoesNotAccumulate() {
        var e = engine(); e.tick(now: 300)
        XCTAssertTrue(e.breakAvailable); XCTAssertFalse(e.onBreak); XCTAssertNil(e.intervention)
        e.tick(now: 3000); respond(&e,.breakRequest,now: 3000,minutes: 20)
        XCTAssertEqual(e.breakRemaining(now: 3000.1),300,accuracy: 0.01)
        e.tick(now: 3301); XCTAssertFalse(e.onBreak); XCTAssertFalse(e.breakAvailable); XCTAssertEqual(e.studySeconds,0)
        respond(&e,.breakRequest,now: 3301); XCTAssertFalse(e.onBreak)
    }
    func testEarlyBreakAndPromptInjectionCannotChangePolicy() {
        var e = engine(); e.observe(target(),now: 5)
        respond(&e,.breakRequest,now: 6,minutes: 999999)
        XCTAssertFalse(e.onBreak); XCTAssertEqual(e.takePending().count,1)
    }
    func testStudyConversationPreservesProviderReplyWithoutGrantingAccess() {
        var e = engine()
        let id = e.beginRequest(now: 1)!
        let reply = "Write one sentence about the volcano’s tectonic plate boundary."
        e.apply(Interpretation(requestId: id, sessionId: e.sessionID!, interventionId: nil, intent: .studyException, reply: reply), now: 2)
        XCTAssertEqual(e.status, reply)
        XCTAssertTrue(e.grants.isEmpty)
        XCTAssertFalse(e.onBreak)
        XCTAssertTrue(e.takePending().isEmpty)
    }
    func testDistractionPreservesProviderReplyAndStillEnforcesCapturedTarget() {
        var e = engine(); let t = target(); e.observe(t, now: 1)
        let intervention = e.intervention!.id
        let id = e.beginRequest(now: 2)!
        let reply = "Put your phone across the room and draft the first sentence."
        e.apply(Interpretation(requestId: id, sessionId: e.sessionID!, interventionId: intervention, intent: .distraction, reply: reply), now: 3)
        XCTAssertEqual(e.status, reply)
        XCTAssertNil(e.intervention)
        let actions = e.takePending()
        XCTAssertEqual(actions.count, 1)
        XCTAssertTrue(e.canEnforce(actions[0], current: t))
        XCTAssertTrue(e.grants.isEmpty)
    }
    func testStudyPausesDuringInterventionAndSleep() {
        var e = engine(); e.observe(target(),now: 20); e.tick(now: 30)
        XCTAssertEqual(e.studySeconds,20)
        e.observe(nil,now: 31); e.sleep(now: 40); e.wake(now: 500)
        XCTAssertEqual(e.studySeconds,29); e.tick(now: 510); XCTAssertEqual(e.studySeconds,39)
    }
    func testIgnoredQuestionAndResubmittedClarificationDeadlines() {
        var e = engine(); e.observe(target(),now: 0); e.tick(now: 19); XCTAssertTrue(e.takePending().isEmpty)
        respond(&e,.clarify,now: 19); e.tick(now: 38); XCTAssertNotNil(e.intervention)
        e.tick(now: 40); XCTAssertNil(e.intervention); XCTAssertEqual(e.takePending().count,1)
    }
    func testRequestDeadlineCannotBeExtendedByLateResponse() {
        var e = engine(); e.observe(target(),now: 0); let i = e.intervention!; let id = e.beginRequest(now: 19)!
        e.apply(Interpretation(requestId:id,sessionId:e.sessionID!,interventionId:i.id,intent:.studyException),now:28)
        XCTAssertTrue(e.grants.isEmpty); XCTAssertTrue(e.fallbackRequired); XCTAssertTrue(e.takePending().isEmpty)
        e.tick(now:49); XCTAssertEqual(e.takePending().count,1)
    }
    func testStaleResponseAfterNavigationAndSessionChange() {
        var e = engine(); e.observe(target(),now: 0); let i = e.intervention!; let session = e.sessionID!; let id = e.beginRequest(now: 1)!
        e.observe(target("https://youtube.com/watch?v=12345678901"),now: 2)
        let response = Interpretation(requestId:id,sessionId:session,interventionId:i.id,intent:.studyException)
        e.apply(response,now:3); XCTAssertTrue(e.grants.isEmpty)
        e.end(); e.start(rules:Rules(),goal:"",now:4); e.apply(response,now:5); XCTAssertTrue(e.grants.isEmpty)
    }
    func testLectureIsSpecificAndCountsPastThreshold() {
        var e = engine(); let t = target(); e.observe(t,now:0); respond(&e,.studyException,now:1)
        e.observe(target("https://www.youtube.com/watch?v=abcdefghijk&t=50&utm_source=test"),now:2)
        // Harmless host and tracking changes preserve the canonical video grant.
        e.observe(target("https://youtube.com/watch?v=abcdefghijk&t=50"),now:3)
        e.tick(now:400); XCTAssertTrue(e.breakAvailable); XCTAssertFalse(e.onBreak)
        e.observe(target("https://youtube.com/watch?v=12345678901"),now:401)
        XCTAssertNotNil(e.intervention); XCTAssertTrue(e.grants.isEmpty)
    }
    func testHomepageAndNativeAppsDoNotGetLectureGrants() {
        for t in [target("https://youtube.com"),Target(bundleID:"com.roblox.RobloxPlayer",processID:4,launchedAt:1)] {
            var e = engine(); e.observe(t,now:0); respond(&e,.studyException,now:1); XCTAssertTrue(e.grants.isEmpty); XCTAssertNotNil(e.intervention)
        }
    }
    func testConversationContextTracksSessionBreakAndStudyCapabilities() throws {
        var e = SessionEngine()
        XCTAssertEqual(e.conversationContext(now: 0).sessionPhase, .idle)
        XCTAssertEqual(e.conversationContext(now: 0).studyAccess, .none)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(e.conversationContext(now: 0))) as! [String: Any]
        XCTAssertTrue(encoded["interventionLabel"] is NSNull)
        e = engine()
        e.observe(target("https://reddit.com/r/math"), now: 1)
        XCTAssertEqual(e.conversationContext(now: 1).sessionPhase, .focus)
        XCTAssertEqual(e.conversationContext(now: 1).interventionLabel, "reddit.com")
        XCTAssertEqual(e.conversationContext(now: 1).studyAccess, .ruleChangeRequired)
        respond(&e, .studyException, now: 2)
        XCTAssertFalse(e.status.contains("YouTube"))
        XCTAssertTrue(e.grants.isEmpty)
        e.observe(target("https://youtube.com"), now: 3)
        XCTAssertEqual(e.conversationContext(now: 3).studyAccess, .videoRequired)
        e.observe(target(), now: 4)
        XCTAssertEqual(e.conversationContext(now: 4).studyAccess, .videoAvailable)
        respond(&e, .studyException, now: 5)
        XCTAssertEqual(e.conversationContext(now: 6).studyAccess, .none)
        e.tick(now: 310); respond(&e, .breakRequest, now: 310, minutes: 1)
        XCTAssertEqual(e.conversationContext(now: 311).sessionPhase, .break)
        XCTAssertEqual(e.conversationContext(now: 311).breakRemainingSeconds, 60)
        XCTAssertNil(e.conversationContext(now: 311).interventionLabel)
        e.end()
        XCTAssertEqual(e.conversationContext(now: 312).sessionPhase, .idle)
    }
    func testLateInterpretationReportsRejectionToConversationUI() {
        var e = engine(); e.observe(target(), now: 0)
        let intervention = e.intervention!.id
        let request = e.beginRequest(now: 1)!
        XCTAssertFalse(e.apply(Interpretation(requestId: request, sessionId: e.sessionID!, interventionId: intervention, intent: .studyException, reply: "An obsolete reply."), now: 10))
        XCTAssertTrue(e.fallbackRequired)
        XCTAssertTrue(e.grants.isEmpty)
    }
    func testEnforcementRevalidatesProcessTabAndResource() {
        var e = engine(); let t = target(); e.observe(t,now:0); e.tick(now:20); let action = e.takePending()[0]
        XCTAssertTrue(e.canEnforce(action,current:t))
        XCTAssertFalse(e.canEnforce(action,current:target(pid:43)))
        XCTAssertFalse(e.canEnforce(action,current:target(tab:"8")))
        XCTAssertFalse(e.canEnforce(action,current:target("https://example.org")))
        e.end(); XCTAssertFalse(e.canEnforce(action,current:t))
    }
    func testBreakTracksOnlyEncounteredResourcesAndRevalidatesNavigation() {
        var e = engine(); e.tick(now:300); respond(&e,.breakRequest,now:300,minutes:1)
        e.observe(target(),now:301); e.observe(target(tab:"9"),now:302)
        XCTAssertNil(e.intervention); e.tick(now:361)
        let actions = e.takePending(); XCTAssertEqual(actions.count,2)
        XCTAssertFalse(e.canEnforce(actions[0],current:target("https://notion.so")))
    }
    func testCheckpointPreservesCreditAndConsumedBreakAcrossClockChange() throws {
        var e = engine(); e.tick(now:300)
        var resumed = SessionEngine(); resumed.resume(try XCTUnwrap(e.checkpoint(now:300,date:Date(timeIntervalSince1970:1000))),now:305,date:Date(timeIntervalSince1970:1005))
        XCTAssertTrue(resumed.breakAvailable)
        respond(&resumed,.breakRequest,now:306,minutes:1)
        resumed.observe(target(),now:307)
        let saved = try XCTUnwrap(resumed.checkpoint(now:308,date:Date(timeIntervalSince1970:1008)))
        var restarted = SessionEngine(); restarted.resume(saved,now:400,date:Date(timeIntervalSince1970:100))
        XCTAssertFalse(restarted.breakAvailable); XCTAssertFalse(restarted.onBreak); XCTAssertEqual(restarted.studySeconds,0)
        XCTAssertEqual(restarted.takePending().count,1)
    }
    func testFallbackUsesSamePolicyAndNoAIOnObservation() {
        var e = engine(); e.observe(target(),now:0); let id = e.beginRequest(now:1)!
        XCTAssertTrue(e.requestFailed(id,now:2)); e.fallback(.breakRequest,now:3)
        XCTAssertFalse(e.onBreak); XCTAssertEqual(e.takePending().count,1)
    }
    func testCancelledGeneralChatDoesNotBlockAnInterventionReply() {
        var e = engine()
        let old = e.beginRequest(now: 1)!
        e.observe(target(), now: 2)
        e.cancelRequest(old)
        let next = e.beginRequest(now: 3)
        XCTAssertNotNil(next)
        XCTAssertFalse(e.fallbackRequired)
        e.apply(Interpretation(requestId: old, sessionId: e.sessionID!, interventionId: nil, intent: .breakRequest), now: 4)
        XCTAssertFalse(e.onBreak)
        XCTAssertEqual(e.intervention?.requestID, next)
    }
    func testSessionCapturesRulesSnapshot() {
        var r = Rules(); var e = SessionEngine(); e.start(rules:r,goal:"",now:0); r.studyMinutes = 5
        XCTAssertEqual(e.rules.studyMinutes,25)
    }
    func testURLBoundariesAndCanonicalVideoIDs() {
        XCTAssertTrue(URLPolicy.matches("m.youtube.com",domain:"youtube.com")); XCTAssertFalse(URLPolicy.matches("youtube.com.example.org",domain:"youtube.com"))
        XCTAssertEqual(URLPolicy.videoID(URL(string:"https://youtu.be/abcdefghijk?t=30")!),"abcdefghijk")
        XCTAssertNil(URLPolicy.videoID(URL(string:"https://youtube.com/shorts/abcdefghijk")!))
        XCTAssertNil(URLPolicy.videoID(URL(string:"https://evil.test/watch?v=abcdefghijk")!))
    }
    func testAutomaticSiteCategoriesAndHostBoundaries() {
        let rules = Rules()
        XCTAssertEqual(rules.classification(of: target("https://github.com/project")), .productive)
        XCTAssertEqual(rules.classification(of: target("https://docs.google.com/document/d/example")), .productive)
        XCTAssertEqual(rules.classification(of: target("https://m.reddit.com/r/example")), .distracting)
        XCTAssertEqual(rules.classification(of: target("https://google.com/search?q=example")), .neutral)
        XCTAssertEqual(rules.classification(of: target("https://unknown.example")), .neutral)
        XCTAssertEqual(rules.classification(of: target("https://github.com.evil.example")), .neutral)
        XCTAssertEqual(rules.classification(of: target("https://notreddit.com")), .neutral)
    }
    func testCustomRulesOverrideDefaultsAndSurvivePersistence() throws {
        var rules = Rules()
        rules.domains["reddit.com"] = .productive
        rules.domains["google.com"] = .distracting
        rules.domains["docs.google.com"] = .neutral
        let restored = try JSONDecoder().decode(Rules.self, from: JSONEncoder().encode(rules))
        XCTAssertEqual(restored.classification(ofHost: "old.reddit.com"), .productive)
        XCTAssertEqual(restored.classification(ofHost: "docs.google.com"), .neutral)
        XCTAssertEqual(restored.classification(ofHost: "mail.google.com"), .distracting)
        XCTAssertEqual(restored.classification(ofHost: "github.com"), .productive)
        rules.domains.removeValue(forKey: "reddit.com")
        XCTAssertEqual(rules.classification(ofHost: "reddit.com"), .distracting)
    }
    func testAutomaticCategoriesOnlyInterveneOnUnproductiveSites() {
        var e = engine()
        for url in ["https://github.com", "https://google.com", "https://unknown.example"] {
            e.observe(target(url), now: 1)
            XCTAssertNil(e.intervention)
            XCTAssertTrue(e.takePending().isEmpty)
        }
        e.observe(target("https://reddit.com"), now: 2)
        XCTAssertNotNil(e.intervention)
    }
    func testReturningToPendingResourceKeepsQuestionReplyAndDeadline() {
        var e = engine(); let t = target("https://reddit.com/r/math")
        e.observe(t, now: 1)
        let original = e.intervention!.id
        let request = e.beginRequest(now: 2)!
        let reply = "Which part of that discussion helps your algebra assignment?"
        XCTAssertTrue(e.apply(Interpretation(requestId: request, sessionId: e.sessionID!, interventionId: original, intent: .clarify, reply: reply), now: 3))
        let deadline = e.intervention!.deadline
        e.observe(target("https://github.com"), now: 4)
        XCTAssertNil(e.intervention)
        e.observe(t, now: 5)
        XCTAssertEqual(e.intervention?.id, original)
        XCTAssertEqual(e.intervention?.deadline, deadline)
        XCTAssertEqual(e.status, reply)
        e.observe(nil, now: 6); e.observe(t, now: 7)
        XCTAssertEqual(e.intervention?.id, original)
        XCTAssertEqual(e.intervention?.deadline, deadline)
        XCTAssertTrue(e.grants.isEmpty)
    }
    func testSwitchingResourcesNeverReusesAnInflightReply() {
        var e = engine(); let t = target()
        e.observe(t, now: 1)
        let original = e.intervention!.id
        let request = e.beginRequest(now: 2)!
        let stale = Interpretation(requestId: request, sessionId: e.sessionID!, interventionId: original, intent: .studyException, reply: "An old reply.")
        e.observe(target("https://github.com"), now: 3)
        e.observe(t, now: 4)
        XCTAssertEqual(e.intervention?.id, original)
        XCTAssertNil(e.intervention?.requestID)
        XCTAssertFalse(e.apply(stale, now: 5))
        XCTAssertTrue(e.grants.isEmpty)
        XCTAssertNotNil(e.beginRequest(now: 6))
    }
    func testReturningAfterQuestionDeadlineDoesNotAskAgainOrExtendIt() {
        var e = engine(); let t = target()
        e.observe(t, now: 1); e.observe(nil, now: 2)
        e.observe(t, now: 30)
        XCTAssertNil(e.intervention)
        let actions = e.takePending()
        XCTAssertEqual(actions.count, 1)
        XCTAssertTrue(e.canEnforce(actions[0], current: t))
        XCTAssertFalse(e.canEnforce(actions[0], current: target("https://youtube.com/watch?v=12345678901")))
    }
    func testDifferentResourcesAndSessionsGetDistinctQuestions() {
        var e = engine(); let first = target(), second = target("https://youtube.com/watch?v=12345678901")
        e.observe(first, now: 1); let original = e.intervention!.id
        e.observe(second, now: 2)
        XCTAssertFalse(e.intervention?.id == original)
        XCTAssertEqual(e.intervention?.target, second)
        e.observe(first, now: 3)
        XCTAssertEqual(e.intervention?.id, original)
        e.end(); e.start(rules: Rules(), goal: "", now: 4)
        e.observe(first, now: 5)
        XCTAssertFalse(e.intervention?.id == original)
    }
}

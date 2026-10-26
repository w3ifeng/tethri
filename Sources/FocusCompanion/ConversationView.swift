import SwiftUI
import AppKit
import FocusCore

/// Individual bubbles float over the current app; there is no enclosing chat window surface.
struct ConversationBubble: View {
    @ObservedObject var model: AppModel
    private let blue = Color(red: 0.02, green: 0.55, blue: 1)
    private var unavailable: Bool { model.fallback || model.engine.fallbackRequired }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                if let target = model.awarenessTarget, let category = model.awarenessClassification {
                    Label("\(targetLabel(target)) · \(model.engine.grants.contains(target) ? "Study video" : category.label)", systemImage: target.tabID == nil ? "app" : "globe").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.8)).padding(.horizontal, 11).padding(.vertical, 6).background(surface, in: Capsule()).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { model.selectedPage = "Settings"; model.showDashboard?() } label: { Image(systemName: "slider.horizontal.3").font(.system(size: 10)).frame(width: 23, height: 23).background(surface, in: Circle()) }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.65)).accessibilityLabel("Settings")
                Button { model.hideBubble?() } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).frame(width: 23, height: 23).background(surface, in: Circle()) }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.65)).accessibilityLabel("Close chat").keyboardShortcut(.escape, modifiers: [])
            }
            transcript
            if model.engine.active && unavailable {
                HStack(spacing: 6) { reason("Break", .breakRequest); reason("Study video", .studyException); reason("Return to work", .distraction) }
            }
            if let notice = model.notice {
                Text(notice).font(.system(size: 10)).foregroundStyle(.white.opacity(0.75)).lineLimit(2).padding(10).background(surface, in: RoundedRectangle(cornerRadius: 14))
            }
            if !model.engine.active {
                HStack(spacing: 12) {
                    if model.saved != nil {
                        Button("Resume session") { model.resume() }.buttonStyle(PopupActionStyle())
                        Button("End saved session") { model.end() }.buttonStyle(.plain).font(.system(size: 10))
                    } else {
                        Button("Start session") { model.start() }.buttonStyle(PopupActionStyle())
                        Button {
                            model.selectedPage = "Today"; model.showDashboard?()
                        } label: {
                            Label("\(model.preferences.rules.studyMinutes)m focus · \(model.preferences.rules.breakMinutes)m break", systemImage: "timer")
                        }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.white.opacity(0.65)).accessibilityLabel("Set focus timer")
                    }
                    Spacer(minLength: 0)
                }.padding(10).background(surface, in: RoundedRectangle(cornerRadius: 20))
            }
            composer
            if model.engine.active { footer }
        }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) { ResizeHandle().frame(width: 26, height: 26) }.foregroundStyle(.white).tint(blue).preferredColorScheme(.dark)
    }
    private var surface: Color { Color(red: 0.13, green: 0.13, blue: 0.21).opacity(min(0.94, 0.70 + model.glassOpacity * 0.3)) }
    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.messages) { message in
                        HStack(spacing: 0) {
                            if message.sender == .user { Spacer(minLength: 18) }
                            VStack(alignment: .leading, spacing: 9) {
                                Text(message.text).font(.system(size: 12, weight: .medium)).lineSpacing(3).textSelection(.enabled)
                                if let status = message.policyStatus {
                                    Label(status, systemImage: "timer").font(.system(size: 10)).foregroundStyle(.white.opacity(0.7)).textSelection(.enabled)
                                }
                            }
                                .padding(.horizontal, 15).padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(message.sender == .user ? blue.opacity(0.95) : surface, in: RoundedRectangle(cornerRadius: 21))
                                .overlay(RoundedRectangle(cornerRadius: 21).strokeBorder(.white.opacity(0.06), lineWidth: 0.5))
                                .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                                .accessibilityLabel("\(message.sender == .user ? "You" : "Companion"): \(message.contextText)")
                            if message.sender == .companion { Spacer(minLength: 7) }
                        }.id(message.id)
                    }
                    if model.busy {
                        HStack(spacing: 7) { ProgressView().controlSize(.mini); Text("Thinking…").font(.system(size: 11)) }.padding(12).background(surface, in: Capsule()).accessibilityLabel("Companion is thinking")
                    }
                    if model.engine.fallbackRequired && !model.fallback { Text(model.engine.status).font(.system(size: 11)).padding(12).background(surface, in: RoundedRectangle(cornerRadius: 18)) }
                    Color.clear.frame(height: 1).id("bottom")
                }
            }.frame(minHeight: 42, maxHeight: .infinity)
                .onChange(of: model.messages.count) { _ in proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: model.busy) { _ in proxy.scrollTo("bottom", anchor: .bottom) }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }
    private var composer: some View {
        HStack(alignment: .center, spacing: 10) {
            TextField("Message…", text: $model.draft, axis: .vertical).lineLimit(1...3).textFieldStyle(.plain).font(.system(size: 12)).onSubmit { model.send() }.onChange(of: model.draft) { model.draft = String($0.prefix(1000)) }
            Button { model.send() } label: {
                Image(systemName: "paperplane.fill").font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(canSend ? 1 : 0.45)).frame(width: 35, height: 35).background(blue.opacity(canSend ? 1 : 0.35), in: Circle())
            }.buttonStyle(.plain).disabled(!canSend).accessibilityLabel("Send message")
        }.padding(10).background(surface, in: RoundedRectangle(cornerRadius: 21)).overlay(RoundedRectangle(cornerRadius: 21).strokeBorder(.white.opacity(0.08), lineWidth: 0.5)).shadow(color: .black.opacity(0.15), radius: 8, y: 3)
    }
    private var canSend: Bool { !model.busy && !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var footer: some View {
        HStack(spacing: 8) {
            if let target = model.engine.intervention?.target {
                Button { model.choose(.distraction) } label: { Label(target.tabID == nil ? "Hide distraction" : "Close distraction", systemImage: "xmark").foregroundStyle(Color(red: 1, green: 0.56, blue: 0.62)) }.buttonStyle(.plain)
            } else {
                Text(model.engine.breakAvailable ? "Break available" : "\(model.engine.onBreak ? "Break" : "Focus") · \(model.countdown)").foregroundStyle(.white.opacity(0.65)).monospacedDigit()
            }
            Spacer(minLength: 0)
            if let seconds = model.responseCountdown { Text("\(seconds)s").monospacedDigit().foregroundStyle(.white.opacity(0.65)) }
            Button("End session") { model.end() }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.55))
        }.font(.system(size: 9, weight: .medium)).padding(.horizontal, 11).padding(.vertical, 6).background(surface.opacity(0.8), in: Capsule())
    }
    private func targetLabel(_ target: Target) -> String {
        if let host = target.host { return host }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleID).map { FileManager.default.displayName(atPath: $0.path) } ?? target.bundleID
    }
    private func reason(_ title: String, _ intent: Intent) -> some View {
        Button(title) { model.choose(intent) }.buttonStyle(.plain).font(.system(size: 10)).padding(.horizontal, 11).padding(.vertical, 8).background(surface, in: Capsule())
    }
}
private struct PopupActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 10).background(Color(red: 0.02, green: 0.55, blue: 1).opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
    }
}

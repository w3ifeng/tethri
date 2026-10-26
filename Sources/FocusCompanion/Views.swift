import SwiftUI
import AppKit
import FocusCore

/// A small settings shell. Session controls stay functional without dashboard decoration.
struct Dashboard: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdater
    @State private var privacyExpanded = false
    private var page: String { model.selectedPage }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) { FocusOrb(size: 28); Text("Tethri").font(.system(size: 14, weight: .semibold)) }.padding(.bottom, 24)
                ForEach([("Today", "Focus", "circle.dotted"), ("Rules", "Rules", "slider.horizontal.3"), ("Sound", "Sound", "cloud.rain"), ("Settings", "Settings", "gearshape")], id: \.0) { key, title, icon in
                    Button { model.selectedPage = key } label: {
                        Label(title, systemImage: icon).font(.system(size: 12, weight: page == key ? .semibold : .regular)).frame(maxWidth: .infinity, alignment: .leading).padding(11).background(.white.opacity(page == key ? 0.10 : 0), in: RoundedRectangle(cornerRadius: 11))
                    }.buttonStyle(.plain).foregroundStyle(.white.opacity(page == key ? 1 : 0.6))
                }
                Spacer()
                if model.engine.active {
                    HStack(spacing: 6) { Circle().fill(Color.cyan).frame(width: 4, height: 4); Text(model.countdown).monospacedDigit(); Spacer(); Button { model.end() } label: { Image(systemName: "stop.circle") }.buttonStyle(.plain).accessibilityLabel("End session") }.font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)).padding(8)
                }
            }.padding(18).frame(width: 156).background(.black.opacity(0.10))
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(page == "Today" ? "Focus" : page).font(.system(size: 23, weight: .semibold)).padding(.bottom, 3)
                    if page == "Today" { session }
                    if page == "Rules" { rules }
                    if page == "Sound" { sound }
                    if page == "Settings" { settings }
                    if let notice = model.notice { Text(notice).font(.system(size: 11)).foregroundStyle(Color.softBlue).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.background(GlassBackdrop(tintOpacity: model.glassOpacity)).foregroundStyle(.white).tint(Color.softBlue).preferredColorScheme(.dark).frame(minWidth: 660, minHeight: 500)
    }
    private var session: some View {
        VStack(alignment: .leading, spacing: 18) {
            group {
                TextField("Study goal (optional)", text: $model.goal).textFieldStyle(.plain).font(.system(size: 13)).disabled(model.engine.active).onChange(of: model.goal) { model.goal = ConversationText.bounded($0, utf16Limit: 500) }
            }
            SessionTimerView(model: model)
            Button { model.showBubble?() } label: { Label("Open chat", systemImage: "bubble.left").font(.system(size: 11)) }
                .buttonStyle(.plain).foregroundStyle(.white.opacity(0.5)).frame(maxWidth: .infinity)
        }
    }
    private var rules: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("Changes apply to your next session.").font(.caption).foregroundStyle(.white.opacity(0.5))
            Text("Apps").font(.system(size: 12, weight: .semibold))
            group {
                ForEach(model.preferences.rules.apps.keys.sorted(), id: \.self) { id in
                    HStack {
                        Text(appName(id)).font(.system(size: 12)).lineLimit(1); Spacer()
                        Picker("Rule for \(id)", selection: Binding(get: { model.preferences.rules.apps[id] ?? .neutral }, set: { model.preferences.rules.apps[id] = $0 })) { ForEach(Classification.allCases, id: \.self) { Text($0.label).tag($0) } }.labelsHidden().frame(width: 120)
                        Button { model.preferences.rules.apps.removeValue(forKey: id) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).accessibilityLabel("Remove \(id)")
                    }
                }
                Button("Add app…") { model.addApp() }.buttonStyle(.borderless)
            }
            Text("Websites").font(.system(size: 12, weight: .semibold))
            group { DomainRules(model: model) }
            Text("Common sites are categorized automatically. Your choices override the defaults. Unknown apps and sites are neutral. Categories describe typical use, not page content.").font(.caption).foregroundStyle(.white.opacity(0.5))
        }
    }
    private var sound: some View {
        VStack(alignment: .leading, spacing: 18) {
            group {
                HStack { Label("Study rain", systemImage: "cloud.rain").font(.system(size: 14, weight: .medium)); Spacer(); Button(model.rainRequested ? "Pause" : "Play") { model.toggleRain() }.buttonStyle(.borderless) }
                HStack {
                    Button { model.preferences.rainMuted.toggle() } label: { Image(systemName: model.preferences.rainMuted ? "speaker.slash" : "speaker.wave.2") }.buttonStyle(.plain).accessibilityLabel("Mute rain")
                    Slider(value: $model.preferences.rainVolume, in: 0...1).accessibilityLabel("Rain volume")
                    Text("\(Int(model.preferences.rainVolume * 100))%").font(.caption).monospacedDigit().frame(width: 34)
                }
            }
            group {
                Toggle("Play when a session starts", isOn: $model.preferences.rainAutoplay)
                Toggle("Pause during breaks", isOn: $model.preferences.rainPauseDuringBreak)
            }.font(.system(size: 12))
            if let error = model.rain.error { Text(error).font(.caption).foregroundStyle(Color.softBlue) }
        }
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 18) {
            group { UpdateSettings(updater: updater) }
            group {
                HStack { Text("Background opacity"); Spacer(); Text("\(Int(model.glassOpacity * 100))%").monospacedDigit().foregroundStyle(.white.opacity(0.6)) }.font(.system(size: 12))
                Slider(value: $model.glassOpacity, in: 0.05...0.85).accessibilityLabel("Background opacity")
            }
            group {
                HStack { Text("Chrome access").font(.system(size: 12, weight: .medium)); Spacer(); Button("Check") { model.requestAutomation() }.buttonStyle(.borderless) }
                Text(model.websiteStatus).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
            }
            group {
                DisclosureGroup("Privacy information", isExpanded: $privacyExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Chrome Automation reads active addresses and can close captured distracting tabs. App hiding may leave audio playing. No screenshots, page content or microphone access are used.")
                        Text("Typed messages, your goal and minimal app/domain context go to Google Gemini through the conversation service. Unpaid inputs and outputs may be used for improvement and human review. Avoid sensitive content.")
                        Text("Chat stays in memory. An interrupted-session checkpoint retains timing, rules, your goal and encountered break targets until the session ends.")
                        Text("This app is for adults in eligible regions. Unpaid service is not offered in the EEA, Switzerland or UK.")
                        Link("Gemini terms & eligibility", destination: URL(string: "https://ai.google.dev/gemini-api/terms")!)
                    }.font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
                }.font(.system(size: 12))
            }
            Button("Recover companion") { model.recoverCharacter?() }.buttonStyle(.borderless).font(.system(size: 12))
        }
    }
    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13, content: content).padding(16).frame(maxWidth: .infinity, alignment: .leading).modifier(GlassSurface(radius: 20))
    }
    private func appName(_ id: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { FileManager.default.displayName(atPath: $0.path) } ?? id
    }
}
struct DomainRules: View {
    @ObservedObject var model: AppModel
    @State private var domain = ""
    var body: some View {
        VStack(spacing: 10) {
            ForEach(model.preferences.rules.knownDomains.keys.sorted(), id: \.self) { host in
                HStack {
                    Text(host); Spacer()
                    Picker("Rule for \(host)", selection: Binding(get: { model.preferences.rules.classification(ofHost: host) }, set: { model.preferences.rules.domains[host] = $0 })) { ForEach(Classification.allCases, id: \.self) { Text($0.label).tag($0) } }.labelsHidden().frame(width: 135)
                    Button { model.preferences.rules.domains.removeValue(forKey: host) } label: { Image(systemName: Rules.builtInDomains[host] == nil ? "minus.circle" : "arrow.counterclockwise") }.buttonStyle(.borderless).disabled(model.preferences.rules.domains[host] == nil).accessibilityLabel(Rules.builtInDomains[host] == nil ? "Remove \(host)" : "Reset \(host) to default")
                }
            }
            HStack { TextField("Domain, e.g. reddit.com", text: $domain); Button("Add") {
                let host = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard let url = URL(string: "https://" + host), url.host == host, host.contains("."), !host.contains("/"), url.port == nil, url.user == nil else { model.notice = "Enter a hostname, such as reddit.com."; return }
                model.preferences.rules.domains[host] = .distracting; domain = ""
            }.disabled(domain.isEmpty) }
        }
    }
}

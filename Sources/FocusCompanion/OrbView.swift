import SwiftUI

struct FocusOrb: View {
    var state = "idle"
    var size: CGFloat = 62
    static let dog: NSImage = {
        let url = Bundle.main.url(forResource: "CompanionDog", withExtension: "png")
            ?? Bundle.module.url(forResource: "CompanionDog", withExtension: "png", subdirectory: "Resources")!
        return NSImage(contentsOf: url)!
    }()
    var body: some View {
        Image(nsImage: Self.dog).resizable().interpolation(.none).scaledToFit()
            .frame(width: size, height: size)
            .opacity(state == "asleep" ? 0.45 : 1)
            .accessibilityLabel("Dog focus companion, \(state)")
    }
}
struct OrbButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
struct DesktopOrb: View {
    @ObservedObject var model: AppModel
    var body: some View {
        GeometryReader { geometry in
        VStack(spacing: 2) {
            if model.engine.active {
                HStack(spacing: 5) {
                    Circle().fill(model.engine.onBreak ? Color.mint : model.engine.breakAvailable ? Color.green : Color.cyan).frame(width: 4, height: 4)
                    Text(model.engine.breakAvailable ? "READY" : model.countdown).font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit()
                }.foregroundStyle(.white.opacity(0.95)).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color(red: 0.07, green: 0.075, blue: 0.13).opacity(0.90), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
                    .accessibilityLabel(model.engine.breakAvailable ? "Break available" : "\(model.engine.onBreak ? "Break" : "Focus") timer \(model.countdown)")
            } else { Color.clear.frame(height: 23) }
            FocusOrb(state: model.sleeping ? "asleep" : model.characterState, size: max(48, min(geometry.size.width - 16, geometry.size.height - 34)))
        }.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        }.overlay(alignment: .bottomTrailing) { ResizeHandle().frame(width: 26, height: 26) }
    }
}

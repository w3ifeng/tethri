import SwiftUI
import AppKit

extension Color {
    static let ink = Color.white
    static let sage = Color(red: 0.60, green: 0.83, blue: 1)
    static let paper = Color(red: 0.075, green: 0.09, blue: 0.13)
    static let focusYellow = Color(red: 1, green: 0.88, blue: 0.40)
    static let breakOrange = Color(red: 1, green: 0.61, blue: 0.37)
    static let softPurple = Color(red: 0.76, green: 0.62, blue: 0.97)
    static let softGreen = Color(red: 0.72, green: 0.94, blue: 0.43)
    static let softBlue = Color(red: 0.56, green: 0.83, blue: 0.96)
    static let cardInk = Color(red: 0.045, green: 0.06, blue: 0.09)
}
struct GlassBackdrop: View {
    var tintOpacity: Double = 0.20
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.paper.opacity(tintOpacity)
                Ellipse().fill(Color(red: 0.51, green: 0.54, blue: 0.54).opacity(0.12)).frame(width: proxy.size.width * 1.2, height: proxy.size.height * 0.85).blur(radius: 85).offset(x: -proxy.size.width * 0.10, y: -proxy.size.height * 0.48)
                Ellipse().fill(Color(red: 0.25, green: 0.33, blue: 0.46).opacity(0.07)).frame(width: proxy.size.width, height: proxy.size.height * 0.65).blur(radius: 80).offset(x: proxy.size.width * 0.40, y: -proxy.size.height * 0.04)
            }
        }.background(WindowGlass(intensity: tintOpacity)).allowsHitTesting(false)
    }
}
struct GlassSurface: ViewModifier {
    var radius: CGFloat = 24
    func body(content: Content) -> some View {
        content.background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).fill(LinearGradient(colors: [.white.opacity(0.10), .white.opacity(0.015)], startPoint: .topLeading, endPoint: .bottomTrailing)).allowsHitTesting(false))
            .shadow(color: .black.opacity(0.10), radius: 12, y: 5)
    }
}
struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.cardInk).padding(.horizontal, 18).padding(.vertical, 11)
            .background(Color.focusYellow.opacity(configuration.isPressed ? 0.85 : 1), in: Capsule())
    }
}

private struct WindowGlass: NSViewRepresentable {
    var intensity: Double
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(); view.material = .underWindowBackground; view.blendingMode = .behindWindow; view.state = .active; view.appearance = NSAppearance(named: .darkAqua); view.alphaValue = min(0.75, intensity * 1.5); return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.alphaValue = min(0.75, intensity * 1.5) }
}

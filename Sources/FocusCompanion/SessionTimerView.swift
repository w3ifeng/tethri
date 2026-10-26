import SwiftUI

/// A sixty-minute clock face, with the exact duration shown below for longer sessions.
struct SessionTimerView: View {
    @ObservedObject var model: AppModel
    private let accent = Color.softBlue
    @State private var dragMinutes: Double?
    @State private var previousAngle: Double?

    private var seconds: Double {
        if model.engine.active {
            return model.engine.onBreak ? model.engine.breakRemaining(now: model.now) : model.engine.studyRemaining
        }
        if let saved = model.saved {
            if let end = saved.breakEnd { return max(0, end.timeIntervalSinceNow) }
            return max(0, Double(saved.rules.studyMinutes * 60) - saved.studySeconds)
        }
        return Double(model.preferences.rules.studyMinutes * 60)
    }
    private var minutes: Double { seconds / 60 }
    private var editable: Bool { !model.engine.active && model.saved == nil }
    private var time: String {
        let value = Int(ceil(seconds))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    var body: some View {
        VStack(spacing: 0) {
            clock
                .frame(width: 232, height: 232)
                .padding(.top, 4)
            Text(time)
                .font(.system(size: 34, weight: .light, design: .rounded)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.90))
                .padding(.top, 12)
                .accessibilityLabel("\(model.engine.onBreak ? "Break" : "Focus") time, \(time)")
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let end = context.date.addingTimeInterval(seconds)
                HStack(spacing: 5) {
                    if model.saved != nil {
                        Text("Saved session")
                    } else {
                        Text(context.date, format: .dateTime.hour().minute())
                        Image(systemName: "arrow.right").font(.system(size: 10, weight: .medium))
                        Text(end, format: .dateTime.hour().minute())
                    }
                }
                .font(.system(size: 11, weight: .medium)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.50))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.white.opacity(0.045), in: Capsule())
            }.padding(.top, 8)

            Button {
                if model.engine.active { model.end() }
                else if model.saved != nil { model.resume() }
                else { model.start() }
            } label: {
                Label(model.engine.active ? "End session" : model.saved != nil ? "Resume session" : "Start session", systemImage: model.engine.active ? "stop.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(height: 42)
                    .foregroundStyle(Color.cardInk)
                    .background(LinearGradient(colors: [accent, Color(red: 0.40, green: 0.68, blue: 0.93)], startPoint: .topLeading, endPoint: .bottomTrailing), in: Capsule())
            }.buttonStyle(OrbButtonStyle()).frame(maxWidth: 218).padding(.top, 22)
            if editable {
                Text("Drag to set time · 5-minute steps")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.38)).padding(.top, 10)
            }
            if model.saved != nil {
                Button("End saved session") { model.end() }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).padding(.top, 12)
            }
        }
        .padding(.horizontal, 8).padding(.bottom, 4)
        .frame(maxWidth: .infinity)
    }

    private var clock: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = side * 0.48
            let face = side * 0.345
            func point(_ angle: Double, radius: Double) -> CGPoint {
                CGPoint(x: center.x + sin(angle) * radius, y: center.y - cos(angle) * radius)
            }
            for tick in 0..<60 {
                let major = tick % 5 == 0
                let angle = Double(tick) / 60 * .pi * 2
                var mark = Path()
                mark.move(to: point(angle, radius: outer - (major ? side * 0.045 : side * 0.018)))
                mark.addLine(to: point(angle, radius: outer))
                context.stroke(mark, with: .color(.white.opacity(major ? 0.55 : 0.22)), lineWidth: side * 0.006)
            }
            let rect = CGRect(x: center.x - face, y: center.y - face, width: face * 2, height: face * 2)
            context.fill(Path(ellipseIn: rect), with: .color(accent.opacity(0.065)))
            let remainder = max(0, minutes).truncatingRemainder(dividingBy: 60)
            let fraction = minutes > 0 && remainder == 0 ? 1 : remainder / 60
            let angle = fraction * .pi * 2
            if fraction > 0 {
                var sector = Path()
                sector.move(to: center)
                sector.addArc(center: center, radius: face, startAngle: .degrees(-90), endAngle: .degrees(fraction * 360 - 90), clockwise: false)
                sector.closeSubpath()
                context.fill(sector, with: .linearGradient(Gradient(colors: [accent.opacity(0.65), accent.opacity(0.16)]), startPoint: CGPoint(x: center.x, y: center.y - face), endPoint: CGPoint(x: center.x, y: center.y + face)))
            }
            var hand = Path()
            hand.move(to: center)
            hand.addLine(to: point(angle, radius: outer * 0.88))
            context.drawLayer { glow in
                glow.addFilter(.shadow(color: accent.opacity(0.25), radius: 5))
                glow.stroke(hand, with: .color(accent), style: StrokeStyle(lineWidth: side * 0.018, lineCap: .round))
            }
            let hub = side * 0.044
            context.drawLayer { glow in
                glow.addFilter(.shadow(color: accent.opacity(0.18), radius: 5, y: 2))
                glow.fill(Path(ellipseIn: CGRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2)), with: .color(Color(red: 0.43, green: 0.60, blue: 0.72)))
            }
            let cap = hub * 0.7
            context.fill(Path(ellipseIn: CGRect(x: center.x - cap, y: center.y - cap, width: cap * 2, height: cap * 2)), with: .color(Color(red: 0.82, green: 0.91, blue: 0.97)))
        }
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard editable else { return }
                let dx = value.location.x - 116, dy = value.location.y - 116
                guard hypot(dx, dy) > 20 else { return }
                let angle = atan2(dx, -dy)
                if let previous = previousAngle, let accumulated = dragMinutes {
                    var delta = angle - previous
                    if delta > .pi { delta -= 2 * .pi }
                    if delta < -.pi { delta += 2 * .pi }
                    dragMinutes = min(180, max(5, accumulated + delta / (.pi * 2) * 60))
                } else {
                    let fraction = (angle < 0 ? angle + .pi * 2 : angle) / (.pi * 2)
                    let current = Double(model.preferences.rules.studyMinutes)
                    let turn = ((current - fraction * 60) / 60).rounded()
                    dragMinutes = min(180, max(5, turn * 60 + fraction * 60))
                }
                previousAngle = angle
                model.preferences.rules.studyMinutes = snappedMinutes(dragMinutes ?? 5)
            }
            .onEnded { _ in dragMinutes = nil; previousAngle = nil })
        .focusable(editable)
        .onMoveCommand { direction in
            guard editable else { return }
            let delta = direction == .up || direction == .right ? 5 : -5
            model.preferences.rules.studyMinutes = snappedMinutes(Double(model.preferences.rules.studyMinutes + delta))
        }
        .onAppear {
            if editable { model.preferences.rules.studyMinutes = snappedMinutes(minutes) }
        }

        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus duration dial")
        .accessibilityValue(time)
        .accessibilityHint(editable ? "Drag to snap to five-minute intervals, continuing around the dial for longer sessions. Use arrow keys to adjust by five minutes." : "Time remaining in the current session")
    }

    private func snappedMinutes(_ value: Double) -> Int {
        min(180, max(5, Int((value / 5).rounded()) * 5))
    }
}

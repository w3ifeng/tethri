import Foundation
import CoreGraphics

/// Shared native geometry for the desktop mark, UI logo, and exported app icon.
enum RingGeometry {
    static func paths(size: CGFloat, count: Int = 38) -> [CGPath] {
        (0..<count).map { line in
            let u = Double(line) / Double(max(1, count - 1))
            let path = CGMutablePath()
            for step in 0...220 {
                let a = Double(step) / 220 * .pi * 2
                let wave = sin(3 * a + u * 3.6) * 0.025 + sin(5 * a - u * 1.8) * 0.009
                let radius = Double(size) * (0.284 + 0.125 * u + wave)
                let twist = a + 0.065 * sin(2 * a + u * 2)
                let point = CGPoint(x: Double(size) / 2 + cos(twist) * radius, y: Double(size) / 2 + sin(twist) * radius * 0.98)
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath(); return path
        }
    }
}

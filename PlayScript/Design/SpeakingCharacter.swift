import SwiftUI

/// Original vector actors, lit and animated by the actual spoken audio level.
struct SpeakingCharacter: View {
    let name: String
    var level: Double = 0
    var bold = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var juliet: Bool { name == "Juliet" }

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let energy = reduceMotion ? 0 : level
            func oval(_ x: Double, _ y: Double, _ width: Double, _ height: Double, _ color: Color) {
                context.fill(Path(ellipseIn: CGRect(x: x * w, y: y * h, width: width * w, height: height * h)), with: .color(color))
            }
            oval(0.08, 0.02, 0.84, 0.95, Color(hex: 0xE7B795).opacity(0.08))
            oval(0.29, 0.07, 0.42, juliet ? 0.5 : 0.3, Color(hex: juliet ? 0x35212B : 0x2D232B))
            var garment = Path()
            garment.move(to: CGPoint(x: w * 0.35, y: h * 0.4))
            garment.addQuadCurve(to: CGPoint(x: w * 0.65, y: h * 0.4), control: CGPoint(x: w * 0.5, y: h * 0.35))
            garment.addLine(to: CGPoint(x: w * 0.88, y: h * 0.96))
            garment.addQuadCurve(to: CGPoint(x: w * 0.12, y: h * 0.96), control: CGPoint(x: w * 0.5, y: h * 1.03))
            garment.closeSubpath()
            context.fill(garment, with: .linearGradient(Gradient(colors: [Color(hex: juliet ? 0xC88891 : 0x796278), Color(hex: 0x432837)]), startPoint: .zero, endPoint: CGPoint(x: w, y: h)))
            context.stroke(garment, with: .color(Color(hex: 0xF0CCB3).opacity(0.5)), lineWidth: 1)
            oval(0.45, 0.32, 0.1, 0.13, Color(hex: 0xDDA98B))
            oval(0.34, 0.12, 0.32, 0.26, Color(hex: 0xEDC3A2))
            oval(0.29, 0.085, 0.4, 0.12, Color(hex: juliet ? 0x35212B : 0x2D232B))
            oval(0.40, 0.235, 0.025, 0.018, Color(hex: 0x4E3032))
            oval(0.575, 0.235, 0.025, 0.018, Color(hex: 0x4E3032))
            oval(0.465, 0.306, 0.075, 0.008 + energy * 0.035, Color(hex: 0x975263))
            var arm = Path()
            arm.move(to: CGPoint(x: w * 0.64, y: h * 0.48))
            arm.addQuadCurve(to: CGPoint(x: w * (bold ? 0.89 : 0.69), y: h * (0.54 - energy * 0.10)), control: CGPoint(x: w * 0.86, y: h * 0.67))
            context.stroke(arm, with: .color(Color(hex: 0xDDA98B)), style: StrokeStyle(lineWidth: w * 0.055, lineCap: .round))
            if juliet {
                oval(0.29, 0.155, 0.065, 0.055, Color(hex: 0xDC8392))
                oval(0.46, 0.46, 0.08, 0.025, Color(hex: 0xF9D397))
            } else {
                var collar = Path()
                collar.move(to: CGPoint(x: w * 0.36, y: h * 0.40))
                collar.addLine(to: CGPoint(x: w * 0.50, y: h * 0.51))
                collar.addLine(to: CGPoint(x: w * 0.64, y: h * 0.40))
                context.stroke(collar, with: .color(Color(hex: 0xF1D8BA)), lineWidth: 3)
            }
        }
        .rotationEffect(.degrees(reduceMotion ? 0 : level * (juliet ? -2 : 2)), anchor: .bottom)
        .shadow(color: Color(hex: 0xFFD6A0).opacity(0.22), radius: 18)
        .accessibilityHidden(true)
    }
}

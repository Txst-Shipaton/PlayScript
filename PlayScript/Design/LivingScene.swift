import SwiftUI
import StoryCore

/// The scenery is a static drawing. Motion lives in the separate atmosphere,
/// light, and curtain layers, so a page left alone never reads as a paused slide.
struct LivingScene: View {
    let mood: Mood
    let beatID: String
    var quiet = false
    var resting = false
    var attention = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shifted = false

    private enum Setting { case orchard, chamber, tomb, road }

    private var setting: Setting {
        if mood == .grief || beatID == "in-time" { return .tomb }
        if mood == .uneasy { return .chamber }
        if mood == .dawn { return .road }
        return .orchard
    }
    private var chamber: Bool { setting == .chamber }
    private var tomb: Bool { setting == .tomb }
    private var motionPaused: Bool { reduceMotion || resting }

    private var lottieName: String {
        switch setting {
        case .orchard: "scene-orchard"
        case .chamber: "scene-chamber"
        case .tomb: "scene-tomb"
        case .road: "scene-road"
        }
    }
    /// A decision settles the scene instead of freezing it.
    private var calm: Double { quiet ? 0.4 : 1 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                scenery
                // A narrow curtain stirs once per cycle, rather than an endless camera pan.
                if !chamber && !tomb && mood != .dawn {
                    Curtain()
                        .fill(Color(hex: 0xAA777D).opacity(0.55))
                        .frame(width: geo.size.width * 0.23, height: geo.size.height * 0.48)
                        .rotationEffect(.degrees(shifted ? 2 : -1), anchor: .top)
                        .position(x: geo.size.width * 0.83, y: geo.size.height * 0.26)
                }
                Ellipse()
                    .fill(mood.light.opacity(attention ? 0.34 : (shifted ? 0.16 : 0.1)))
                    .frame(width: geo.size.width * 0.9, height: geo.size.height * 0.5)
                    .blur(radius: 45)
                    .position(x: geo.size.width * (attention ? 0.6 : 0.4), y: geo.size.height * 0.32)
                    .blendMode(.screen)
                atmosphere
                // Lottie carries each scene's choreographed motion; the Canvas
                // atmosphere above carries the dense particle fields.
                LottieLayer(name: lottieName, playing: !motionPaused,
                            speed: quiet ? 0.4 : 1)
                    .opacity(quiet ? 0.55 : 1)
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: reduceMotion ? 0 : 0.8), value: quiet)
                if tomb {
                    Rectangle().fill(Color(hex: 0xB6BDD5).opacity(shifted ? 0.13 : 0.05))
                        .frame(width: geo.size.width * 0.19, height: geo.size.height * 0.6)
                        .rotationEffect(.degrees(24))
                        .blur(radius: 10)
                        .position(x: geo.size.width * 0.56, y: geo.size.height * 0.35)
                }
            }
            .overlay(Color.black.opacity(quiet ? 0.18 : 0))
            .animation(.easeInOut(duration: reduceMotion ? 0 : 0.6), value: attention)
            .animation(.easeInOut(duration: reduceMotion ? 0 : 0.6), value: quiet)
        }
        .clipped()
        .accessibilityHidden(true)
        .task(id: "\(beatID)-\(quiet)-\(resting)-\(reduceMotion)") {
            guard !reduceMotion, !quiet, !resting else {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { shifted = false }
                return
            }
            while !Task.isCancelled {
                // Each setting keeps its own slow, discrete quirk under the fine motion.
                let interval: Double = switch setting {
                case .orchard: 22
                case .chamber: 17
                case .tomb: 31
                case .road: 25
                }
                do { try await Task.sleep(for: .seconds(interval)) } catch { return }
                withAnimation(.easeInOut(duration: 7)) { shifted.toggle() }
            }
        }
    }

    /// The dense particle fields: fireflies, embers, dust, and road grit. Paused
    /// for Reduce Motion, pause, and backgrounding; dimmed while a decision is open.
    private var atmosphere: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: motionPaused)) { timeline in
            Canvas { context, size in
                let time = motionPaused ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let w = Double(size.width), h = Double(size.height)
                switch setting {
                case .orchard: drawOrchard(&context, w, h, time)
                case .chamber: drawChamber(&context, w, h, time)
                case .tomb: drawTomb(&context, w, h, time)
                case .road: drawRoad(&context, w, h, time)
                }
            }
        }
    }

    /// Deterministic per-particle offsets; the scene looks scattered but never re-rolls.
    private func noise(_ index: Int, _ salt: Int) -> Double {
        let value = sin(Double(index) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return value - floor(value)
    }

    private func drawOrchard(_ context: inout GraphicsContext, _ w: Double, _ h: Double, _ time: Double) {
        for i in 0..<16 {
            let seedX = noise(i, 1), seedY = noise(i, 2)
            let speed = 0.35 + noise(i, 3) * 0.5
            let x = (seedX * 0.94 + sin(time * speed * 0.35 + seedY * 6.28) * 0.05) * w
            let y = (0.5 + seedY * 0.44 + cos(time * speed * 0.5 + seedX * 6.28) * 0.03) * h
            let pulse = 0.3 + 0.7 * pow(max(0, sin(time * (0.8 + speed) + seedX * 9)), 3)
            let r = w * (0.004 + noise(i, 4) * 0.003)
            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                         with: .color(Color(hex: 0xFFE9A8).opacity(pulse * 0.8 * calm)))
        }
    }

    private func drawChamber(_ context: inout GraphicsContext, _ w: Double, _ h: Double, _ time: Double) {
        // The flame itself is the Lottie layer; these embers rise from it.
        let flicker = sin(time * 9.3) * 0.3 + sin(time * 4.1) * 0.25 + sin(time * 17.7) * 0.1
        let baseX = w * 0.72, baseY = h * 0.395
        for i in 0..<12 {
            let seed = noise(i, 11)
            let life = (time * (0.07 + seed * 0.07) + seed).truncatingRemainder(dividingBy: 1)
            let x = baseX + (sin(time * 0.8 + seed * 6.28) * 0.018 + (seed - 0.5) * 0.045) * w
            let y = baseY - life * h * 0.22
            let size = w * 0.004
            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: size, height: size)),
                         with: .color(Color(hex: 0xFFAF63).opacity((1 - life) * 0.65 * calm)))
        }
        // The candle throws a shadow that never settles on the far wall.
        context.fill(Path(ellipseIn: CGRect(x: w * 0.08 + flicker * w * 0.022, y: h * 0.28,
                                            width: w * 0.34, height: h * 0.42)),
                     with: .color(.black.opacity(0.1 + flicker * 0.03)))
    }

    private func drawTomb(_ context: inout GraphicsContext, _ w: Double, _ h: Double, _ time: Double) {
        for i in 0..<26 {
            let seedX = noise(i, 21), seedY = noise(i, 22)
            let drift = (time * (0.01 + seedX * 0.018) + seedY).truncatingRemainder(dividingBy: 1)
            let x = (0.34 + seedX * 0.38 + sin(time * 0.25 + seedY * 6.28) * 0.02) * w
            let y = (0.04 + drift * 0.86) * h
            let r = w * (0.0018 + noise(i, 23) * 0.0024)
            let shimmer = 0.2 + 0.45 * abs(sin(time * 0.6 + seedX * 7))
            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                         with: .color(Color(hex: 0xD9DCEA).opacity(shimmer * calm)))
        }
    }

    private func drawRoad(_ context: inout GraphicsContext, _ w: Double, _ h: Double, _ time: Double) {
        // Birds and the lifting mist are the Lottie layer; this is road dust.
        for i in 0..<10 {
            let seed = noise(i, 33)
            let travel = (time * (0.03 + seed * 0.04) + seed).truncatingRemainder(dividingBy: 1)
            let x = (1.02 - travel * 1.1) * w
            let y = (0.66 + noise(i, 34) * 0.28 + sin(time * 0.7 + seed * 6.28) * 0.01) * h
            let r = w * (0.002 + noise(i, 35) * 0.003)
            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                         with: .color(Color(hex: 0xFFF0DC).opacity(0.4 * calm)))
        }
    }

    private var scenery: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let sky = CGRect(origin: .zero, size: size)
            context.fill(Path(sky), with: .linearGradient(
                Gradient(colors: [Color(hex: mood == .dawn ? 0xA77570 : 0x171E30), mood.background]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ color: Color) {
                context.fill(Path(CGRect(x: x*w, y: y*h, width: width*w, height: height*h)), with: .color(color))
            }
            func ellipse(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ color: Color) {
                context.fill(Path(ellipseIn: CGRect(x: x*w, y: y*h, width: width*w, height: height*h)), with: .color(color))
            }
            let stone = Color(hex: tomb ? 0x252535 : 0x342E3D)
            if !chamber {
                ellipse(0.19, 0.13, 0.12, 0.12*w/h, Color(hex: 0xE9D5B5).opacity(tomb ? 0.35 : 0.88))
                for i in 0..<29 {
                    let x = CGFloat((i * 73 + 19) % 100) / 100
                    let y = CGFloat((i * 31 + 7) % 38) / 100
                    ellipse(x, y, 0.003, 0.003*w/h, .white.opacity(0.35))
                }
            }
            // Three distant city layers, with deterministic irregular rooflines.
            for layer in 0..<3 {
                for i in 0..<12 {
                    let roof = CGFloat((i * 7 + layer * 3) % 5) * 0.013
                    rect(CGFloat(i)/11, 0.36 + CGFloat(layer)*0.07 - roof, 0.085, 0.35,
                         Color(hex: layer == 0 ? 0x51404B : layer == 1 ? 0x39303D : 0x262833))
                }
            }
            if chamber || tomb {
                rect(0, 0, 0.22, 1, stone)
                rect(0.78, 0, 0.22, 1, stone)
                rect(0, 0, 1, 0.12, stone)
                var arch = Path()
                arch.move(to: CGPoint(x: w*0.2, y: h*0.55))
                arch.addLine(to: CGPoint(x: w*0.2, y: h*0.28))
                arch.addQuadCurve(to: CGPoint(x: w*0.8, y: h*0.28), control: CGPoint(x: w*0.5, y: -h*0.04))
                arch.addLine(to: CGPoint(x: w*0.8, y: h*0.55))
                context.stroke(arch, with: .color(Color(hex: 0x68606A).opacity(0.7)), lineWidth: w*0.065)
                if chamber {
                    rect(0.35, 0.48, 0.55, 0.035, Color(hex: 0x76504E))
                    rect(0.4, 0.515, 0.025, 0.35, stone)
                    rect(0.83, 0.515, 0.025, 0.35, stone)
                    rect(0.707, 0.409, 0.025, 0.071, Color(hex: 0xDCC7A5))
                    ellipse(0.53, 0.44, 0.044, 0.044, Color(hex: 0x729C99).opacity(0.8))
                    rect(0.542, 0.428, 0.019, 0.018, Color(hex: 0xC2B595))
                } else {
                    rect(0.12, 0.52, 0.76, 0.09, Color(hex: 0x69606D))
                    rect(0.16, 0.61, 0.68, 0.2, stone)
                }
            } else if mood != .dawn {
                rect(0.88, 0, 0.12, 1, stone)
                rect(0.61, 0.46, 0.39, 0.025, Color(hex: 0xBA8B87))
                rect(0.62, 0.485, 0.38, 0.025, stone)
                for i in 0..<6 { rect(0.64 + CGFloat(i)*0.063, 0.51, 0.022, 0.1, stone) }
                rect(0.59, 0.61, 0.41, 0.028, stone)
                // Juliet, in silhouette at the balcony.
                ellipse(0.725, 0.338, 0.055, 0.034, Color(hex: 0xDBB29F))
                var dress = Path()
                dress.move(to: CGPoint(x: w*0.75, y: h*0.37))
                dress.addCurve(to: CGPoint(x: w*0.81, y: h*0.46), control1: CGPoint(x: w*0.79, y: h*0.39), control2: CGPoint(x: w*0.76, y: h*0.41))
                dress.addLine(to: CGPoint(x: w*0.69, y: h*0.46))
                dress.closeSubpath()
                context.fill(dress, with: .color(Color(hex: 0xB47E89)))
                for i in 0..<7 {
                    ellipse(-0.1 + CGFloat(i)*0.08, 0.53 + CGFloat(i%3)*0.03, 0.26, 0.19, Color(hex: 0x192B30))
                }
            } else {
                var road = Path()
                road.move(to: CGPoint(x: w*0.49, y: h*0.43))
                road.addCurve(to: CGPoint(x: w*0.05, y: h), control1: CGPoint(x: w*0.83, y: h*0.65), control2: CGPoint(x: w*0.1, y: h*0.74))
                road.addLine(to: CGPoint(x: w*0.88, y: h))
                road.addQuadCurve(to: CGPoint(x: w*0.49, y: h*0.43), control: CGPoint(x: w*0.93, y: h*0.6))
                context.fill(road, with: .color(Color(hex: 0xB68B7C)))
            }
        }
        .drawingGroup()
    }
}

private struct Curtain: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: .zero)
        p.addLine(to: CGPoint(x: r.width, y: 0))
        p.addCurve(to: CGPoint(x: r.width*0.8, y: r.height), control1: CGPoint(x: r.width*0.6, y: r.height*0.5), control2: CGPoint(x: r.width, y: r.height*0.7))
        p.addQuadCurve(to: CGPoint(x: 0, y: r.height*0.92), control: CGPoint(x: r.width*0.35, y: r.height*0.88))
        p.addQuadCurve(to: .zero, control: CGPoint(x: r.width*0.4, y: r.height*0.4))
        return p
    }
}

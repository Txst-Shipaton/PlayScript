import SwiftUI
import StoryCore

// MARK: - Drawing helpers
//
// Every coordinate in the scenery is normalised (0…1) so a composition reads the
// same on every iPhone. `Frame` converts; the free functions keep each drawing
// expression small enough to stay cheap to type-check.

private struct Frame {
    let w: CGFloat
    let h: CGFloat

    func rect(_ x: CGFloat, _ y: CGFloat, _ rw: CGFloat, _ rh: CGFloat) -> CGRect {
        CGRect(x: x * w, y: y * h, width: rw * w, height: rh * h)
    }

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x * w, y: y * h)
    }

    /// A true circle: both axes measured in width, so nothing turns into an egg.
    func disc(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) -> CGRect {
        CGRect(x: x * w - radius * w, y: y * h - radius * w,
               width: radius * 2 * w, height: radius * 2 * w)
    }

    var full: CGRect { CGRect(x: 0, y: 0, width: w, height: h) }
}

private func paint(_ context: inout GraphicsContext, _ rect: CGRect, _ color: Color) {
    context.fill(Path(rect), with: .color(color))
}

private func paint(_ context: inout GraphicsContext, _ path: Path, _ color: Color) {
    context.fill(path, with: .color(color))
}

private func paintOval(_ context: inout GraphicsContext, _ rect: CGRect, _ color: Color) {
    context.fill(Path(ellipseIn: rect), with: .color(color))
}

/// One standing body, as a single silhouette: shoulders that slope, a waist that
/// pinches, a hem that flares. Every character in the play is cut from this shape,
/// so a change of build — shoulder against hem — is what tells them apart.
private func bodyPath(_ f: Frame, _ x: CGFloat, _ shoulder: CGFloat, _ hem: CGFloat,
                      _ halfShoulder: CGFloat, _ halfHem: CGFloat) -> Path {
    let waist = shoulder + (hem - shoulder) * 0.45
    var path = Path()
    path.move(to: f.point(x - halfHem, hem))
    path.addQuadCurve(to: f.point(x - halfShoulder, shoulder),
                      control: f.point(x - halfShoulder * 0.7, waist))
    path.addQuadCurve(to: f.point(x + halfShoulder, shoulder),
                      control: f.point(x, shoulder - (hem - shoulder) * 0.1))
    path.addQuadCurve(to: f.point(x + halfHem, hem),
                      control: f.point(x + halfShoulder * 0.7, waist))
    path.closeSubpath()
    return path
}

/// A limb: one curve, stroked with round caps so it keeps its weight when small.
private func limb(_ context: inout GraphicsContext, _ f: Frame, _ from: CGPoint,
                  _ to: CGPoint, _ control: CGPoint, _ color: Color, _ weight: CGFloat) {
    var path = Path()
    path.move(to: from)
    path.addQuadCurve(to: to, control: control)
    context.stroke(path, with: .color(color),
                   style: StrokeStyle(lineWidth: weight, lineCap: .round, lineJoin: .round))
}

private func linePath(_ points: [CGPoint]) -> Path {
    var path = Path()
    guard let first = points.first else { return path }
    path.move(to: first)
    for point in points.dropFirst() { path.addLine(to: point) }
    path.closeSubpath()
    return path
}

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
    /// 0 the instant a new beat arrives, 1 once the camera has settled on it.
    @State private var entrance: CGFloat = 1

    private enum Setting { case orchard, chamber, tomb, road }

    private var setting: Setting {
        if mood == .grief || beatID == "in-time" { return .tomb }
        if mood == .uneasy { return .chamber }
        if mood == .dawn { return .road }
        return .orchard
    }
    private var chamber: Bool { setting == .chamber }
    private var tomb: Bool { setting == .tomb }
    /// The imagined ending returns to the same tomb, lit by dawn instead of by nothing.
    private var tombAtDawn: Bool { tomb && mood == .dawn }
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

    // MARK: - Arrival
    //
    // A beat change is a camera move, not a dissolve: the frame arrives from a
    // slightly different distance and settles, each setting in its own direction.
    // The cross-fade the reader applies on a mood change rides on top of this.

    /// How much wider the frame sits at the moment of arrival.
    private var arrivalPush: CGFloat {
        switch setting {
        case .orchard: 0.035
        case .chamber: 0.028
        case .tomb: 0.05
        case .road: 0.032
        }
    }

    /// Where the frame arrives from, in points, before it settles to centre.
    private var arrivalDrift: CGSize {
        switch setting {
        // The camera lifts toward the window.
        case .orchard: CGSize(width: -8, height: 22)
        // A step taken into the room, from the door side.
        case .chamber: CGSize(width: 14, height: 0)
        // It draws back off the slab rather than approaching it.
        case .tomb: CGSize(width: 0, height: -16)
        // The road keeps travelling; the frame catches up with it.
        case .road: CGSize(width: -26, height: 6)
        }
    }

    private var settled: CGFloat { 1 - entrance }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // The camera settles back and softens while a decision is open.
                scenery
                    .scaleEffect(reduceMotion ? 1 : (quiet ? 1.02 : 1))
                    .blur(radius: reduceMotion ? 0 : (quiet ? 3.5 : 0))
                    .saturation(quiet ? 0.86 : 1)
                // A narrow curtain stirs once per cycle, rather than an endless camera pan.
                if !chamber && !tomb && mood != .dawn {
                    Curtain()
                        .fill(Color(hex: 0xAA777D).opacity(0.55))
                        .frame(width: geo.size.width * 0.23, height: geo.size.height * 0.48)
                        .rotationEffect(.degrees(shifted ? 2 : -1), anchor: .top)
                        .position(x: geo.size.width * 0.83, y: geo.size.height * 0.26)
                }
                // The key light. It lifts and warms when a choice is being weighed,
                // so the scene answers the hover before anything is committed.
                Ellipse()
                    .fill(mood.light.opacity(attention ? 0.34 : (shifted ? 0.16 : 0.1)))
                    .frame(width: geo.size.width * 0.9, height: geo.size.height * 0.5)
                    .blur(radius: 45)
                    .position(x: geo.size.width * (attention ? 0.6 : 0.4), y: geo.size.height * 0.32)
                    .blendMode(.screen)
                Ellipse()
                    .fill(Color(hex: 0xFFD6A8).opacity(attention ? 0.16 : 0))
                    .frame(width: geo.size.width * 0.52, height: geo.size.height * 0.24)
                    .blur(radius: 55)
                    .position(x: geo.size.width * 0.5,
                              y: geo.size.height * (attention ? 0.27 : 0.34))
                    .blendMode(.screen)
                atmosphere
                // Lottie carries each scene's choreographed motion; the Canvas
                // atmosphere above carries the dense particle fields.
                LottieLayer(name: lottieName, playing: !motionPaused,
                            speed: quiet ? 0.4 : 1)
                    // The composition arrives first and the choreographed motion
                    // catches up with it, so a new beat lands as a held frame.
                    .opacity((quiet ? 0.55 : 1) * Double(min(1, entrance * 1.7)))
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: reduceMotion ? 0 : 0.8), value: quiet)
                if tomb {
                    Rectangle()
                        .fill(Color(hex: tombAtDawn ? 0xF3CE9C : 0xB6BDD5)
                            .opacity(shifted ? (tombAtDawn ? 0.2 : 0.13) : (tombAtDawn ? 0.11 : 0.05)))
                        .frame(width: geo.size.width * 0.19, height: geo.size.height * 0.6)
                        .rotationEffect(.degrees(24))
                        .blur(radius: 10)
                        .position(x: geo.size.width * 0.56, y: geo.size.height * 0.35)
                }
            }
            .overlay(Color.black.opacity(quiet ? 0.18 : 0))
            .animation(.easeInOut(duration: reduceMotion ? 0 : 0.6), value: attention)
            .animation(.easeInOut(duration: reduceMotion ? 0 : 0.9), value: quiet)
            // The move itself. It is driven explicitly from the arrival task below,
            // so none of the scoped animations above pick it up by accident.
            .scaleEffect(1 + arrivalPush * settled)
            .offset(x: arrivalDrift.width * settled, y: arrivalDrift.height * settled)
            .overlay(Color(hex: 0x0B0710).opacity(Double(settled) * 0.34).allowsHitTesting(false))
        }
        .clipped()
        .accessibilityHidden(true)
        // Each new beat cuts in from its own distance and settles. Reduce Motion and
        // the paused/cover cases skip straight to the settled frame.
        .task(id: "\(beatID)-\(reduceMotion)-\(resting)") {
            var immediate = Transaction(animation: nil)
            immediate.disablesAnimations = true
            guard !reduceMotion, !resting else {
                withTransaction(immediate) { entrance = 1 }
                return
            }
            withTransaction(immediate) { entrance = 0 }
            // One frame on the arriving composition before the move begins, so the
            // change registers as a cut and not as a drift.
            do {
                try await Task.sleep(for: .milliseconds(90))
            } catch {
                // Interrupted before the move began: never leave the frame off-centre.
                withTransaction(immediate) { entrance = 1 }
                return
            }
            withAnimation(.timingCurve(0.16, 0.84, 0.24, 1, duration: 1.3)) { entrance = 1 }
        }
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

    private func nz(_ index: Int, _ salt: Int) -> CGFloat { CGFloat(noise(index, salt)) }

    private func drawOrchard(_ context: inout GraphicsContext, _ w: Double, _ h: Double, _ time: Double) {
        for i in 0..<16 {
            let seedX = noise(i, 1), seedY = noise(i, 2)
            let speed = 0.35 + noise(i, 3) * 0.5
            let x = (seedX * 0.94 + sin(time * speed * 0.35 + seedY * 6.28) * 0.05) * w
            let y = (0.42 + seedY * 0.4 + cos(time * speed * 0.5 + seedX * 6.28) * 0.03) * h
            let pulse = 0.3 + 0.7 * pow(max(0, sin(time * (0.8 + speed) + seedX * 9)), 3)
            let r = w * (0.004 + noise(i, 4) * 0.003)
            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                         with: .color(Color(hex: 0xFFE9A8).opacity(pulse * 0.8 * calm)))
        }
    }

    private func drawChamber(_ context: inout GraphicsContext, _ w: Double, _ h: Double, _ time: Double) {
        // The flame itself is the Lottie layer, anchored to the drawn candle top at
        // (0.7195, 0.409). Embers lift off above the bright body, not from the wick.
        let flicker = sin(time * 9.3) * 0.3 + sin(time * 4.1) * 0.25 + sin(time * 17.7) * 0.1
        let baseX = w * 0.7195, baseY = h * 0.381
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
        let dust = tombAtDawn ? Color(hex: 0xF0D5AC) : Color(hex: 0xD9DCEA)
        for i in 0..<26 {
            let seedX = noise(i, 21), seedY = noise(i, 22)
            let drift = (time * (0.01 + seedX * 0.018) + seedY).truncatingRemainder(dividingBy: 1)
            let x = (0.34 + seedX * 0.38 + sin(time * 0.25 + seedY * 6.28) * 0.02) * w
            let y = (0.04 + drift * 0.86) * h
            let r = w * (0.0018 + noise(i, 23) * 0.0024)
            let shimmer = 0.2 + 0.45 * abs(sin(time * 0.6 + seedX * 7))
            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                         with: .color(dust.opacity(shimmer * calm)))
        }
    }

    private func drawRoad(_ context: inout GraphicsContext, _ w: Double, _ h: Double, _ time: Double) {
        // Birds and the lifting mist are the Lottie layer; this is road dust.
        for i in 0..<10 {
            let seed = noise(i, 33)
            let travel = (time * (0.03 + seed * 0.04) + seed).truncatingRemainder(dividingBy: 1)
            let x = (1.02 - travel * 1.1) * w
            let y = (0.52 + noise(i, 34) * 0.2 + sin(time * 0.7 + seed * 6.28) * 0.01) * h
            let r = w * (0.002 + noise(i, 35) * 0.003)
            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                         with: .color(Color(hex: 0xFFF0DC).opacity(0.4 * calm)))
        }
    }

    // MARK: - Static scenery

    private var scenery: some View {
        Canvas { context, size in
            let frame = Frame(w: size.width, h: size.height)
            paintSky(&context, frame)
            switch setting {
            case .orchard: paintOrchard(&context, frame)
            case .chamber: paintChamber(&context, frame)
            case .tomb: paintTomb(&context, frame)
            case .road: paintRoad(&context, frame)
            }
            paintCamera(&context, frame)
        }
        .drawingGroup()
    }

    /// Every setting starts with its own sky, graded top to bottom.
    private func paintSky(_ context: inout GraphicsContext, _ f: Frame) {
        var stops: [Gradient.Stop] = []
        switch setting {
        case .orchard:
            stops = [.init(color: Color(hex: 0x0C1226), location: 0),
                     .init(color: Color(hex: 0x222040), location: 0.28),
                     .init(color: Color(hex: mood == .tender ? 0x5A3946 : 0x3D2E46), location: 0.5),
                     .init(color: mood.background, location: 1)]
        case .chamber:
            stops = [.init(color: Color(hex: 0x14121C), location: 0),
                     .init(color: Color(hex: 0x352C38), location: 0.42),
                     .init(color: Color(hex: 0x1F1A26), location: 1)]
        case .tomb:
            stops = tombAtDawn
                ? [.init(color: Color(hex: 0x1B1620), location: 0),
                   .init(color: Color(hex: 0x3B2A2B), location: 0.5),
                   .init(color: Color(hex: 0x1E1822), location: 1)]
                : [.init(color: Color(hex: 0x0A0C14), location: 0),
                   .init(color: Color(hex: 0x1C1F2C), location: 0.5),
                   .init(color: Color(hex: 0x101220), location: 1)]
        case .road:
            stops = [.init(color: Color(hex: 0x2A3660), location: 0),
                     .init(color: Color(hex: 0x6C5779), location: 0.22),
                     .init(color: Color(hex: 0xBE8272), location: 0.37),
                     .init(color: Color(hex: 0xF3C892), location: 0.452),
                     .init(color: Color(hex: 0xB07B6C), location: 0.58),
                     .init(color: mood.background, location: 1)]
        }
        context.fill(Path(f.full), with: .linearGradient(
            Gradient(stops: stops), startPoint: .zero, endPoint: CGPoint(x: 0, y: f.h)))
    }

    /// The lens: a vignette that tightens the eye on the upper half, and a falloff
    /// so the lower half never argues with the narrative at any type size.
    private func paintCamera(_ context: inout GraphicsContext, _ f: Frame) {
        context.fill(Path(f.full), with: .radialGradient(
            Gradient(stops: [.init(color: .clear, location: 0.4),
                             .init(color: .black.opacity(0.16), location: 0.72),
                             .init(color: .black.opacity(0.5), location: 1)]),
            center: f.point(0.5, 0.34), startRadius: 0, endRadius: f.w * 1.05))
        context.fill(Path(f.rect(0, 0.42, 1, 0.58)), with: .linearGradient(
            Gradient(stops: [.init(color: .clear, location: 0),
                             .init(color: Color(hex: 0x120E17).opacity(0.42), location: 0.4),
                             .init(color: Color(hex: 0x0C0911).opacity(0.8), location: 1)]),
            startPoint: f.point(0, 0.42), endPoint: f.point(0, 1)))
    }

    // MARK: Orchard — the moon wears a halo, and its light comes through the trellis in bars.

    private func paintOrchard(_ context: inout GraphicsContext, _ f: Frame) {
        // Stars, thinning as they approach the horizon haze.
        for i in 0..<38 {
            let x = nz(i, 41)
            let y = nz(i, 42) * nz(i, 42) * 0.44
            let fade = max(0.08, 1 - Double(y) * 1.7)
            paintOval(&context, f.disc(x, y, 0.0012 + nz(i, 43) * 0.0016),
                      .white.opacity((0.2 + noise(i, 44) * 0.45) * fade))
        }

        // The moon, low and large, with the ring it always wears here.
        let moon = f.point(0.235, 0.145)
        context.fill(Path(ellipseIn: f.disc(0.235, 0.145, 0.46)), with: .radialGradient(
            Gradient(stops: [.init(color: Color(hex: 0xE9DABB).opacity(0.3), location: 0),
                             .init(color: Color(hex: 0xB295B0).opacity(0.13), location: 0.33),
                             .init(color: .clear, location: 1)]),
            center: moon, startRadius: 0, endRadius: f.w * 0.46))
        context.stroke(Path(ellipseIn: f.disc(0.235, 0.145, 0.228)),
                       with: .color(Color(hex: 0xDCC9D6).opacity(0.17)), lineWidth: f.w * 0.011)
        paintOval(&context, f.disc(0.235, 0.145, 0.082), Color(hex: 0xF4E7C9).opacity(0.96))
        paintOval(&context, f.disc(0.212, 0.126, 0.021), Color(hex: 0xDFCDAC).opacity(0.45))
        paintOval(&context, f.disc(0.263, 0.167, 0.014), Color(hex: 0xDFCDAC).opacity(0.38))

        // Three receding rooflines. Each nearer plane is darker and more defined.
        let planes: [(CGFloat, UInt32)] = [(0.418, 0x3A3A56), (0.45, 0x2C2942), (0.484, 0x201C2E)]
        for (index, plane) in planes.enumerated() {
            var path = Path()
            path.move(to: f.point(0, 1))
            path.addLine(to: f.point(0, plane.0))
            for i in 0..<14 {
                let x0 = CGFloat(i) / 13.0
                let top = plane.0 - nz(i * 3 + index * 7, 51) * 0.055
                path.addLine(to: f.point(x0, top))
                path.addLine(to: f.point(x0 + 1.0 / 13.0, top))
            }
            path.addLine(to: f.point(1, 1))
            path.closeSubpath()
            paint(&context, path, Color(hex: plane.1))
        }

        // Verona itself: a campanile and a dome, so the skyline is a place.
        let far = Color(hex: 0x2C2942)
        paint(&context, f.rect(0.655, 0.3, 0.044, 0.19), far)
        paint(&context, linePath([f.point(0.645, 0.302), f.point(0.677, 0.258), f.point(0.709, 0.302)]), far)
        paintOval(&context, f.rect(0.30, 0.368, 0.118, 0.08), far)
        paint(&context, f.rect(0.30, 0.405, 0.118, 0.08), far)
        paint(&context, f.rect(0.354, 0.348, 0.01, 0.026), far)

        // A handful of lit windows across the orchard: someone else is awake.
        for i in 0..<9 {
            paint(&context, f.rect(0.05 + nz(i, 61) * 0.86, 0.496 + nz(i, 62) * 0.04, 0.005, 0.01),
                  Color(hex: 0xFFD79B).opacity(0.25 + noise(i, 63) * 0.35))
        }

        // The canopy, three rows deep.
        let rows: [(CGFloat, UInt32, CGFloat)] = [(0.508, 0x24313B, 0.055),
                                                  (0.548, 0x1A2730, 0.065),
                                                  (0.6, 0x121C23, 0.078)]
        for (index, row) in rows.enumerated() {
            for i in 0..<11 {
                let x = -0.05 + CGFloat(i) * 0.108 + nz(i + index * 11, 71) * 0.04
                paintOval(&context, f.disc(x, row.0 - nz(i + index * 11, 72) * 0.03,
                                           row.2 + nz(i + index * 11, 73) * 0.03),
                          Color(hex: row.1))
            }
        }

        // Cypresses: the one tree that says Verona.
        for (i, x) in [CGFloat(0.075), 0.148, 0.442].enumerated() {
            let height = 0.14 + nz(i, 81) * 0.05
            var spire = Path()
            spire.move(to: f.point(x, 0.5 - height))
            spire.addQuadCurve(to: f.point(x + 0.026, 0.548), control: f.point(x + 0.031, 0.5 - height * 0.25))
            spire.addLine(to: f.point(x - 0.026, 0.548))
            spire.addQuadCurve(to: f.point(x, 0.5 - height), control: f.point(x - 0.031, 0.5 - height * 0.25))
            paint(&context, spire, Color(hex: 0x16222A))
        }

        // Moonlight through the trellis: this orchard is always striped.
        context.drawLayer { layer in
            layer.opacity = 0.14
            layer.addFilter(.blur(radius: f.w * 0.014))
            for i in 0..<5 {
                let x = 0.1 + CGFloat(i) * 0.14
                paint(&layer, linePath([f.point(x, 0.43), f.point(x + 0.048, 0.43),
                                        f.point(x - 0.085, 0.63), f.point(x - 0.145, 0.63)]),
                      Color(hex: 0xCFE0F0))
            }
        }

        paintRomeoBelow(&context, f)
        paintBalcony(&context, f)

        // Near foliage: the darkest value in the frame, and slightly out of focus.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: f.w * 0.013))
            for i in 0..<7 {
                paintOval(&layer, f.rect(-0.12 + CGFloat(i) * 0.085, 0.55 + CGFloat(i % 3) * 0.03, 0.28, 0.2),
                          Color(hex: 0x0B1418))
            }
            // The rose vine over the top edge, closest of all.
            var vine = Path()
            vine.move(to: f.point(-0.02, 0.005))
            vine.addQuadCurve(to: f.point(0.56, 0.05), control: f.point(0.26, 0.132))
            layer.stroke(vine, with: .color(Color(hex: 0x0D1418)), lineWidth: f.w * 0.013)
            for i in 0..<10 {
                let t = CGFloat(i) / 9.0
                let x = -0.02 + t * 0.58
                let y = 0.005 + CGFloat(sin(Double(t) * Double.pi)) * 0.058
                paintOval(&layer, f.rect(x - 0.026, y - 0.004, 0.052, 0.024), Color(hex: 0x0D1418))
                if i == 3 || i == 7 {
                    paintOval(&layer, f.disc(x, y + 0.022, 0.017), Color(hex: 0x5D2836))
                }
            }
        }
    }

    /// Romeo, down in the orchard and two thirds her height: he is further from the
    /// reader than she is, and the gap between the grass and the rail is the scene.
    /// He stands in one of the trellis bars so the silhouette has light to read against,
    /// and the near foliage takes his feet, which puts the hedge between them as well.
    private func paintRomeoBelow(_ context: inout GraphicsContext, _ f: Frame) {
        let x: CGFloat = 0.525
        let ink = Color(hex: 0x0E1218)
        let moonlit = Color(hex: 0xC8D8EA)

        // The patch of moonlight he is standing in.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: f.w * 0.05))
            paintOval(&layer, f.rect(x - 0.12, 0.5, 0.24, 0.115),
                      Color(hex: 0xBFD4E8).opacity(0.17))
        }
        // His shadow, thrown away from the moon.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: f.w * 0.02))
            paintOval(&layer, f.rect(x - 0.02, 0.562, 0.135, 0.026),
                      Color(hex: 0x070C10).opacity(0.5))
        }

        // Legs first, then the doublet over them: he has weight on the ground.
        paint(&context, f.rect(x - 0.019, 0.534, 0.014, 0.038), ink)
        paint(&context, f.rect(x + 0.007, 0.534, 0.014, 0.036), ink)
        paint(&context, bodyPath(f, x, 0.487, 0.546, 0.029, 0.033), ink)

        // The cloak, off the far shoulder and hanging behind him.
        var cloak = Path()
        cloak.move(to: f.point(x - 0.027, 0.487))
        cloak.addQuadCurve(to: f.point(x - 0.046, 0.553), control: f.point(x - 0.052, 0.519))
        cloak.addLine(to: f.point(x - 0.008, 0.547))
        cloak.closeSubpath()
        paint(&context, cloak, ink)

        paintOval(&context, f.disc(x + 0.004, 0.4695, 0.019), ink)
        // The arm lifted toward the rail. Her hand comes down to meet it; the two
        // curves point at each other across the widest gap in the frame.
        limb(&context, f, f.point(x + 0.023, 0.494), f.point(x + 0.062, 0.462),
             f.point(x + 0.05, 0.489), ink, f.w * 0.013)

        // The moon finds his near edge, the same way it finds hers.
        limb(&context, f, f.point(x - 0.031, 0.542), f.point(x - 0.028, 0.488),
             f.point(x - 0.036, 0.516), moonlit.opacity(0.42), f.w * 0.004)
        var headRim = Path()
        headRim.addArc(center: f.point(x + 0.004, 0.4695), radius: f.w * 0.0197,
                       startAngle: .degrees(118), endAngle: .degrees(242), clockwise: false)
        context.stroke(headRim, with: .color(moonlit.opacity(0.4)), lineWidth: f.w * 0.004)
    }

    private func paintBalcony(_ context: inout GraphicsContext, _ f: Frame) {
        let stone = Color(hex: 0x2A2430)
        paint(&context, f.rect(0.855, 0, 0.145, 1), Color(hex: 0x241E2A))

        // The lit doorway behind her: the only warm thing out here.
        var doorway = Path()
        doorway.move(to: f.point(0.885, 0.46))
        doorway.addLine(to: f.point(0.885, 0.265))
        doorway.addQuadCurve(to: f.point(0.99, 0.265), control: f.point(0.9375, 0.185))
        doorway.addLine(to: f.point(0.99, 0.46))
        doorway.closeSubpath()
        context.fill(doorway, with: .radialGradient(
            Gradient(colors: [Color(hex: 0xF3C68C).opacity(0.85),
                              Color(hex: 0x8C5742).opacity(0.5),
                              Color(hex: 0x291B1F)]),
            center: f.point(0.9375, 0.33), startRadius: 0, endRadius: f.w * 0.17))

        // Corbels carrying the balcony floor.
        for i in 0..<4 {
            paint(&context, f.rect(0.635 + CGFloat(i) * 0.093, 0.503, 0.034, 0.042), Color(hex: 0x393040))
        }
        // Rail cap, balusters, base.
        paint(&context, f.rect(0.595, 0.428, 0.405, 0.015), Color(hex: 0x6E5A63))
        paint(&context, f.rect(0.595, 0.488, 0.405, 0.017), Color(hex: 0x483D4C))
        for i in 0..<7 {
            let x = 0.615 + CGFloat(i) * 0.055
            paint(&context, f.rect(x, 0.443, 0.011, 0.045), stone)
            paintOval(&context, f.disc(x + 0.0055, 0.465, 0.013), stone)
        }

        // Juliet, against the doorway, with the moon finding her far edge.
        var figure = Path()
        figure.move(to: f.point(0.768, 0.49))
        figure.addLine(to: f.point(0.787, 0.4))
        figure.addQuadCurve(to: f.point(0.8135, 0.352), control: f.point(0.788, 0.366))
        figure.addQuadCurve(to: f.point(0.84, 0.4), control: f.point(0.839, 0.366))
        figure.addLine(to: f.point(0.859, 0.49))
        figure.closeSubpath()
        paint(&context, figure, Color(hex: 0x1B131B))
        paintOval(&context, f.disc(0.8135, 0.334, 0.026), Color(hex: 0x1B131B))
        paintOval(&context, f.rect(0.789, 0.322, 0.05, 0.05), Color(hex: 0x1B131B))

        var rim = Path()
        rim.move(to: f.point(0.768, 0.49))
        rim.addLine(to: f.point(0.787, 0.4))
        rim.addQuadCurve(to: f.point(0.8135, 0.352), control: f.point(0.788, 0.366))
        context.stroke(rim, with: .color(Color(hex: 0xD8B5BF).opacity(0.5)), lineWidth: f.w * 0.005)
        var headRim = Path()
        headRim.addArc(center: f.point(0.8135, 0.334), radius: f.w * 0.027,
                       startAngle: .degrees(125), endAngle: .degrees(235), clockwise: false)
        context.stroke(headRim, with: .color(Color(hex: 0xD8B5BF).opacity(0.45)), lineWidth: f.w * 0.005)

        // Her arm down the rail, toward the orchard. She is turned to him, not to us.
        limb(&context, f, f.point(0.7935, 0.3885), f.point(0.7405, 0.4355),
             f.point(0.7585, 0.3975), Color(hex: 0x1B131B), f.w * 0.011)
        limb(&context, f, f.point(0.7925, 0.3925), f.point(0.7435, 0.4345),
             f.point(0.7615, 0.4025), Color(hex: 0xD8B5BF).opacity(0.3), f.w * 0.003)
    }

    // MARK: Chamber — two lights that disagree, and the vial's one green caustic.

    private func paintChamber(_ context: inout GraphicsContext, _ f: Frame) {
        let stone = Color(hex: 0x2B2530)

        // The vault: a far rib and a near rib, so the ceiling has somewhere to go.
        context.stroke(archCurve(f, halfWidth: 0.31, spring: 0.44, crown: 0.06),
                       with: .color(Color(hex: 0x3B323F)), lineWidth: f.w * 0.05)
        context.stroke(archCurve(f, halfWidth: 0.44, spring: 0.5, crown: -0.02),
                       with: .color(Color(hex: 0x241F29)), lineWidth: f.w * 0.075)
        paint(&context, f.rect(0, 0, 0.09, 1), Color(hex: 0x241F29))
        paint(&context, f.rect(0.93, 0, 0.07, 1), Color(hex: 0x241F29))

        // The cold light. A mullioned window, moon-side, arched.
        paint(&context, f.rect(0.12, 0.13, 0.2, 0.31), Color(hex: 0x191924))
        context.fill(Path(f.rect(0.132, 0.142, 0.176, 0.29)), with: .linearGradient(
            Gradient(colors: [Color(hex: 0xA3B8D8).opacity(0.62), Color(hex: 0x5A6890).opacity(0.24)]),
            startPoint: f.point(0.132, 0.142), endPoint: f.point(0.308, 0.432)))
        for i in 0..<3 {
            paint(&context, f.rect(0.132 + CGFloat(i) * 0.059, 0.142, 0.006, 0.29), Color(hex: 0x191924))
        }
        for i in 0..<4 {
            paint(&context, f.rect(0.132, 0.142 + CGFloat(i) * 0.0725, 0.176, 0.005), Color(hex: 0x191924))
        }
        context.stroke(archCurve(f, halfWidth: 0.104, spring: 0.145, crown: 0.09, centerX: 0.22),
                       with: .color(Color(hex: 0x4A4150)), lineWidth: f.w * 0.024)

        // Its spill, falling across the floor toward the warm half of the room.
        context.drawLayer { layer in
            layer.opacity = 0.17
            layer.addFilter(.blur(radius: f.w * 0.025))
            paint(&layer, linePath([f.point(0.15, 0.46), f.point(0.33, 0.46),
                                    f.point(0.6, 0.78), f.point(0.33, 0.78)]),
                  Color(hex: 0xA9C1E1))
        }

        paintJulietAlone(&context, f)

        // The warm light. Everything near the candle is lit by it and nothing else.
        context.fill(Path(ellipseIn: f.disc(0.72, 0.4, 0.42)), with: .radialGradient(
            Gradient(stops: [.init(color: Color(hex: 0xFFC079).opacity(0.34), location: 0),
                             .init(color: Color(hex: 0xC97C4E).opacity(0.14), location: 0.35),
                             .init(color: .clear, location: 1)]),
            center: f.point(0.72, 0.4), startRadius: 0, endRadius: f.w * 0.42))

        // The table, and the shadows the candle throws away from itself.
        paint(&context, f.rect(0.35, 0.48, 0.55, 0.035), Color(hex: 0x7A534F))
        paint(&context, f.rect(0.35, 0.5, 0.55, 0.015), Color(hex: 0x4A3231))
        paint(&context, f.rect(0.4, 0.515, 0.025, 0.35), stone)
        paint(&context, f.rect(0.83, 0.515, 0.025, 0.35), stone)
        context.drawLayer { layer in
            layer.opacity = 0.5
            layer.addFilter(.blur(radius: f.w * 0.008))
            paint(&layer, linePath([f.point(0.53, 0.482), f.point(0.575, 0.482),
                                    f.point(0.42, 0.512), f.point(0.36, 0.512)]),
                  Color(hex: 0x1D1218))
            paint(&layer, linePath([f.point(0.705, 0.482), f.point(0.735, 0.482),
                                    f.point(0.53, 0.512), f.point(0.47, 0.512)]),
                  Color(hex: 0x1D1218))
        }

        // The candle. The Lottie flame is anchored to this top edge at (0.7195, 0.409).
        paint(&context, f.rect(0.707, 0.409, 0.025, 0.071), Color(hex: 0xDCC7A5))
        paint(&context, f.rect(0.707, 0.409, 0.008, 0.071), Color(hex: 0xF3E4C4))
        paintOval(&context, f.rect(0.699, 0.473, 0.041, 0.014), Color(hex: 0x8E6F52))

        // The vial, and the one cool thing the candle touches: its green caustic.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: f.w * 0.012))
            paintOval(&layer, f.rect(0.487, 0.472, 0.062, 0.022), Color(hex: 0x74A39C).opacity(0.55))
        }
        paint(&context, f.rect(0.541, 0.458, 0.02, 0.024), Color(hex: 0x6C918E).opacity(0.85))
        paintOval(&context, f.disc(0.551, 0.462, 0.023), Color(hex: 0x729C99).opacity(0.88))
        paint(&context, f.rect(0.545, 0.437, 0.013, 0.02), Color(hex: 0xC2B595))
        paintOval(&context, f.disc(0.544, 0.457, 0.006), .white.opacity(0.5))

        // The foreground: one bedpost and a fold of the canopy, closest to the reader.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: f.w * 0.016))
            paint(&layer, f.rect(0.035, 0.18, 0.055, 0.82), Color(hex: 0x120E15))
            paintOval(&layer, f.disc(0.0625, 0.185, 0.038), Color(hex: 0x120E15))
            var drape = Path()
            drape.move(to: f.point(0.02, 0.06))
            drape.addQuadCurve(to: f.point(0.2, 0.14), control: f.point(0.12, 0.05))
            drape.addQuadCurve(to: f.point(0.13, 0.62), control: f.point(0.23, 0.38))
            drape.addLine(to: f.point(0.02, 0.62))
            drape.closeSubpath()
            paint(&layer, drape, Color(hex: 0x150F18))
        }
    }

    /// Juliet at the cold window, cut out of it — she is the largest figure in the
    /// story because this is the room where she is nearest and most alone. Two lights
    /// find two different edges of her, and only one shadow leaves her: the room holds
    /// nobody else, and that is the whole point of the chamber.
    private func paintJulietAlone(_ context: inout GraphicsContext, _ f: Frame) {
        let x: CGFloat = 0.268
        let ink = Color(hex: 0x14101A)

        // The one shadow, reaching toward the candle that casts it.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: f.w * 0.022))
            paint(&layer, linePath([f.point(x - 0.05, 0.545), f.point(x + 0.05, 0.545),
                                    f.point(x - 0.14, 0.86), f.point(x - 0.33, 0.86)]),
                  Color(hex: 0x0D0912).opacity(0.55))
        }

        paint(&context, bodyPath(f, x, 0.2565, 0.55, 0.031, 0.064), ink)
        paintOval(&context, f.disc(x - 0.004, 0.2355, 0.024), ink)
        // Hair gathered low, so she reads as herself and not as an outline.
        paintOval(&context, f.rect(x - 0.03, 0.2275, 0.05, 0.048), ink)
        // One hand up against the glass; the other holds nothing yet.
        limb(&context, f, f.point(x - 0.024, 0.2655), f.point(x - 0.05, 0.2255),
             f.point(x - 0.048, 0.2555), ink, f.w * 0.012)

        // The window behind her takes her far edge; the candle only just reaches the near one.
        limb(&context, f, f.point(x - 0.034, 0.53), f.point(x - 0.03, 0.259),
             f.point(x - 0.042, 0.4), Color(hex: 0xA3B8D8).opacity(0.38), f.w * 0.004)
        limb(&context, f, f.point(x + 0.04, 0.53), f.point(x + 0.03, 0.262),
             f.point(x + 0.043, 0.4), Color(hex: 0xF3C68C).opacity(0.22), f.w * 0.004)
        var headRim = Path()
        headRim.addArc(center: f.point(x - 0.004, 0.2355), radius: f.w * 0.0252,
                       startAngle: .degrees(130), endAngle: .degrees(228), clockwise: false)
        context.stroke(headRim, with: .color(Color(hex: 0xA3B8D8).opacity(0.36)),
                       lineWidth: f.w * 0.004)
    }

    /// One arch, as a stroked curve. Used for vaults, windows, and tomb bays.
    private func archCurve(_ f: Frame, halfWidth: CGFloat, spring: CGFloat,
                           crown: CGFloat, centerX: CGFloat = 0.5) -> Path {
        var path = Path()
        path.move(to: f.point(centerX - halfWidth, spring + 0.3))
        path.addLine(to: f.point(centerX - halfWidth, spring))
        path.addQuadCurve(to: f.point(centerX + halfWidth, spring),
                          control: f.point(centerX, crown - (spring - crown) * 0.35))
        path.addLine(to: f.point(centerX + halfWidth, spring + 0.3))
        return path
    }

    // MARK: Tomb — four bays receding into the dark, and one patch of light on empty stone.

    private func paintTomb(_ context: inout GraphicsContext, _ f: Frame) {
        // The far end. In the imagined ending it is open to the dawn instead.
        if tombAtDawn {
            context.fill(Path(f.full), with: .radialGradient(
                Gradient(colors: [Color(hex: 0xF6D5A1), Color(hex: 0x8B5442), Color(hex: 0x241A1E)]),
                center: f.point(0.48, 0.36), startRadius: 0, endRadius: f.w * 0.36))
        } else {
            paint(&context, f.full, Color(hex: 0x090B12))
        }

        // Each bay is a wall with an arch cut out of it, nearest drawn last.
        let bays: [CGFloat] = [0.76, 0.51, 0.26, 0.0]
        let cool: [UInt32] = [0x151823, 0x1C1F2C, 0x242839, 0x2D3143]
        let warm: [UInt32] = [0x241B1D, 0x2F2224, 0x3A2B29, 0x453430]
        for (index, depth) in bays.enumerated() {
            var wall = Path(f.full)
            wall.addPath(tombOpening(f, depth))
            context.fill(wall, with: .color(Color(hex: tombAtDawn ? warm[index] : cool[index])),
                         style: FillStyle(eoFill: true))
            context.stroke(tombOpening(f, depth),
                           with: .color(.white.opacity(0.05 + Double(index) * 0.02)),
                           lineWidth: f.w * 0.004)
        }

        // The grate the light comes through, and the ribs it catches.
        let grate = Color(hex: tombAtDawn ? 0xF0CE9E : 0xAEB8D2)
        paint(&context, f.rect(0.755, 0.04, 0.115, 0.075), Color(hex: 0x0D0F17))
        paint(&context, f.rect(0.762, 0.047, 0.101, 0.061), grate.opacity(0.5))
        for i in 0..<3 {
            paint(&context, f.rect(0.762 + CGFloat(i) * 0.034, 0.047, 0.006, 0.061), Color(hex: 0x0D0F17))
        }
        paint(&context, f.rect(0.762, 0.075, 0.101, 0.005), Color(hex: 0x0D0F17))

        // Carved ribs on the nearest bay.
        for i in 0..<5 {
            let t = CGFloat(i) / 4.0
            context.stroke(archCurve(f, halfWidth: 0.4 - t * 0.012, spring: 0.7 - t * 0.004, crown: 0.13 + t * 0.01),
                           with: .color(.white.opacity(0.03)), lineWidth: f.w * 0.003)
        }

        // The slab, draped, and the only thing the light finds.
        paint(&context, f.rect(0.16, 0.508, 0.5, 0.02), Color(hex: tombAtDawn ? 0x6B5044 : 0x3F4355))
        paint(&context, f.rect(0.185, 0.528, 0.45, 0.055), Color(hex: tombAtDawn ? 0x422F2B : 0x282B39))
        var drape = Path()
        drape.move(to: f.point(0.225, 0.508))
        drape.addLine(to: f.point(0.56, 0.508))
        drape.addQuadCurve(to: f.point(0.5, 0.6), control: f.point(0.585, 0.562))
        drape.addQuadCurve(to: f.point(0.255, 0.6), control: f.point(0.38, 0.572))
        drape.closeSubpath()
        paint(&context, drape, Color(hex: tombAtDawn ? 0x6A5450 : 0x474154).opacity(0.85))

        paintStillForm(&context, f)

        context.drawLayer { layer in
            layer.addFilter(.blur(radius: f.w * 0.03))
            paintOval(&layer, f.rect(0.2, 0.486, 0.32, 0.048), grate.opacity(0.4))
        }

        paintKneeling(&context, f, grate)

        // Two urns, foreground, unlit: the room continues past the reader.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: f.w * 0.018))
            paintOval(&layer, f.rect(-0.02, 0.56, 0.24, 0.26), Color(hex: 0x080A10))
            paintOval(&layer, f.rect(0.82, 0.58, 0.26, 0.28), Color(hex: 0x080A10))
            paint(&layer, f.rect(0.86, 0.5, 0.14, 0.5), Color(hex: 0x080A10))
        }
    }

    /// The one who is still. Under the cloth, and no further than that: a long low
    /// rise along the slab with the head end lifted, and the grate's light laid across
    /// it. No face, no hands, nothing the eye can resolve into a body.
    private func paintStillForm(_ context: inout GraphicsContext, _ f: Frame) {
        var form = Path()
        form.move(to: f.point(0.225, 0.51))
        form.addQuadCurve(to: f.point(0.303, 0.4885), control: f.point(0.243, 0.487))
        form.addQuadCurve(to: f.point(0.455, 0.4965), control: f.point(0.385, 0.4885))
        form.addQuadCurve(to: f.point(0.6, 0.5095), control: f.point(0.552, 0.5065))
        form.closeSubpath()
        paint(&context, form, Color(hex: tombAtDawn ? 0x6E574B : 0x4A4E62))

        // A single fold, so the cloth reads as cloth and the shape stays unread.
        limb(&context, f, f.point(0.335, 0.4955), f.point(0.52, 0.506),
             f.point(0.43, 0.4995), Color(hex: tombAtDawn ? 0x513A33 : 0x363A4B), f.w * 0.004)
    }

    /// The one who is not. Kneeling at the head of the slab, bowed, one hand on the
    /// stone — Juliet in the dark of the real tomb, Romeo in the dawn of the imagined
    /// one. The same pose either way: the scene does not change, only the light does.
    private func paintKneeling(_ context: inout GraphicsContext, _ f: Frame, _ key: Color) {
        let x: CGFloat = 0.735
        let ink = Color(hex: tombAtDawn ? 0x1A1013 : 0x0D0F18)
        // Romeo carries the wider shoulders and the shorter hem; Juliet the narrower
        // build and the dress that pools on the floor.
        let halfShoulder: CGFloat = tombAtDawn ? 0.036 : 0.03
        let halfHem: CGFloat = tombAtDawn ? 0.072 : 0.082
        let shoulder: CGFloat = tombAtDawn ? 0.442 : 0.447

        paint(&context, bodyPath(f, x, shoulder, 0.605, halfShoulder, halfHem), ink)
        paintOval(&context, f.disc(x - 0.012, shoulder - 0.021, 0.023), ink)
        if !tombAtDawn {
            // Her hair, fallen forward with her head.
            paintOval(&context, f.rect(x - 0.038, shoulder - 0.03, 0.05, 0.05), ink)
        }
        // The hand that reaches the stone. It is the only line that crosses between them.
        limb(&context, f, f.point(x - 0.03, shoulder + 0.012), f.point(0.645, 0.5065),
             f.point(x - 0.066, shoulder + 0.026), ink, f.w * 0.013)

        // The grate's light catches the curve of the back and the crown of the head.
        limb(&context, f, f.point(x + halfHem * 0.8, 0.59), f.point(x + halfShoulder, shoulder + 0.004),
             f.point(x + halfShoulder + 0.014, 0.52), key.opacity(tombAtDawn ? 0.34 : 0.22), f.w * 0.004)
        var headRim = Path()
        headRim.addArc(center: f.point(x - 0.012, shoulder - 0.021), radius: f.w * 0.0242,
                       startAngle: .degrees(300), endAngle: .degrees(40), clockwise: false)
        context.stroke(headRim, with: .color(key.opacity(tombAtDawn ? 0.32 : 0.2)),
                       lineWidth: f.w * 0.004)
    }

    /// The arch cut through one bay. `depth` runs 0 (nearest, widest) to 1 (farthest).
    private func tombOpening(_ f: Frame, _ depth: CGFloat) -> Path {
        let halfWidth = 0.4 - depth * 0.3
        let spring = 0.28 + depth * 0.13
        let crown = 0.13 + depth * 0.16
        let floor = 0.74 - depth * 0.26
        var path = Path()
        path.move(to: f.point(0.48 - halfWidth, floor))
        path.addLine(to: f.point(0.48 - halfWidth, spring))
        path.addQuadCurve(to: f.point(0.48 + halfWidth, spring),
                          control: f.point(0.48, crown - (spring - crown) * 0.6))
        path.addLine(to: f.point(0.48 + halfWidth, floor))
        path.closeSubpath()
        return path
    }

    // MARK: Road — the sun sits in the vanishing point and the cypresses reach for the reader.

    private func paintRoad(_ context: inout GraphicsContext, _ f: Frame) {
        let horizon: CGFloat = 0.452
        let vanish = f.point(0.56, horizon)

        // The sun, breaking exactly where the road goes.
        context.fill(Path(ellipseIn: f.disc(0.56, horizon, 0.5)), with: .radialGradient(
            Gradient(stops: [.init(color: Color(hex: 0xFFE7BE).opacity(0.65), location: 0),
                             .init(color: Color(hex: 0xEDA878).opacity(0.3), location: 0.28),
                             .init(color: .clear, location: 1)]),
            center: vanish, startRadius: 0, endRadius: f.w * 0.5))
        paintOval(&context, f.disc(0.56, horizon + 0.004, 0.058), Color(hex: 0xFFF1D2).opacity(0.95))

        // Cloud bars, lit from underneath.
        for i in 0..<6 {
            let y = 0.16 + CGFloat(i) * 0.042 + nz(i, 91) * 0.018
            let x = -0.1 + nz(i, 92) * 0.55
            let width = 0.3 + nz(i, 93) * 0.5
            paintOval(&context, f.rect(x, y, width, 0.022 + nz(i, 94) * 0.016),
                      Color(hex: 0x8B6779).opacity(0.5))
            paintOval(&context, f.rect(x + 0.02, y + 0.012, width * 0.8, 0.012),
                      Color(hex: 0xE9A98A).opacity(0.45))
        }

        // Hills, palest at the horizon: distance is haze, not just size.
        let ridges: [(CGFloat, CGFloat, UInt32, Double)] = [(0.428, 0.05, 0xC49A92, 0.55),
                                                           (0.442, 0.065, 0xA77C7E, 0.7),
                                                           (0.458, 0.085, 0x7E5C68, 0.9)]
        for (index, ridge) in ridges.enumerated() {
            var path = Path()
            path.move(to: f.point(-0.05, 1))
            path.addLine(to: f.point(-0.05, ridge.0))
            for i in 0..<7 {
                let x = -0.05 + CGFloat(i) * 0.19
                path.addQuadCurve(to: f.point(x + 0.19, ridge.0 + nz(i + index * 7, 101) * 0.012),
                                  control: f.point(x + 0.095, ridge.0 - ridge.1 * nz(i + index * 7, 102)))
            }
            path.addLine(to: f.point(1.05, 1))
            path.closeSubpath()
            paint(&context, path, Color(hex: ridge.2).opacity(ridge.3))
        }

        // Verona on its hill, small and far and pale.
        let town = Color(hex: 0x86657A).opacity(0.8)
        for i in 0..<7 {
            paint(&context, f.rect(0.8 + CGFloat(i) * 0.024, 0.428 - nz(i, 111) * 0.022, 0.018,
                                   0.03 + nz(i, 111) * 0.022), town)
        }
        paint(&context, f.rect(0.862, 0.398, 0.014, 0.05), town)

        // The road: pale dust running out of the light.
        var road = Path()
        road.move(to: f.point(0.545, horizon))
        road.addCurve(to: f.point(-0.08, 1), control1: f.point(0.5, 0.62), control2: f.point(0.16, 0.8))
        road.addLine(to: f.point(0.78, 1))
        road.addCurve(to: f.point(0.575, horizon), control1: f.point(0.74, 0.76), control2: f.point(0.62, 0.6))
        road.closeSubpath()
        context.fill(road, with: .linearGradient(
            Gradient(colors: [Color(hex: 0xE4BE9A), Color(hex: 0xB2836F), Color(hex: 0x6A4A47)]),
            startPoint: f.point(0, horizon), endPoint: f.point(0, 1)))

        context.drawLayer { layer in
            layer.clip(to: road)
            // Ruts, converging on the sun.
            for offset in [CGFloat(-0.13), 0.09] {
                var rut = Path()
                rut.move(to: f.point(0.56 + offset * 0.06, horizon + 0.01))
                rut.addQuadCurve(to: f.point(0.36 + offset * 2.4, 1),
                                 control: f.point(0.46 + offset, 0.72))
                layer.stroke(rut, with: .color(Color(hex: 0x6E4A44).opacity(0.35)), lineWidth: f.w * 0.012)
            }
            // The long shadows. Dawn reaches the reader before the rider does.
            layer.opacity = 0.32
            for (i, x) in [CGFloat(0.66), 0.735, 0.3].enumerated() {
                let spread = 0.1 + CGFloat(i) * 0.06
                paint(&layer, linePath([f.point(x, 0.49 + CGFloat(i) * 0.012),
                                        f.point(x + 0.03, 0.49 + CGFloat(i) * 0.012),
                                        f.point(x - 0.5 - spread * 2, 1),
                                        f.point(x - 0.66 - spread * 2, 1)]),
                      Color(hex: 0x4B2F35))
            }
        }

        // The cypresses that cast them, sized by distance.
        for (i, x) in [CGFloat(0.66), 0.735, 0.3].enumerated() {
            let height = 0.09 + CGFloat(i) * 0.055
            let base = 0.492 + CGFloat(i) * 0.012
            let halfWidth = 0.016 + CGFloat(i) * 0.008
            var spire = Path()
            spire.move(to: f.point(x + 0.015, base - height))
            spire.addQuadCurve(to: f.point(x + 0.015 + halfWidth, base),
                               control: f.point(x + 0.015 + halfWidth * 1.2, base - height * 0.25))
            spire.addLine(to: f.point(x + 0.015 - halfWidth, base))
            spire.addQuadCurve(to: f.point(x + 0.015, base - height),
                               control: f.point(x + 0.015 - halfWidth * 1.2, base - height * 0.25))
            paint(&context, spire, Color(hex: 0x4A3244).opacity(0.85 + Double(i) * 0.05))
        }

        paintRider(&context, f)

        // A milestone, and the near banks framing the road.
        paint(&context, f.rect(0.175, 0.53, 0.028, 0.055), Color(hex: 0x6B5259))
        paintOval(&context, f.disc(0.189, 0.531, 0.015), Color(hex: 0x7A5E63))
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: f.w * 0.014))
            paintOval(&layer, f.rect(-0.2, 0.6, 0.55, 0.32), Color(hex: 0x2A1C25))
            paintOval(&layer, f.rect(0.72, 0.58, 0.55, 0.36), Color(hex: 0x2A1C25))
        }
    }
}

extension LivingScene {
    /// Where the rider sits on the road. He is halted when the messenger reaches him,
    /// moving and further up the road once he rides, and a long way off — almost in
    /// the light — in the beats that come after.
    private var riderStaging: (x: CGFloat, base: CGFloat, size: CGFloat) {
        switch beatID {
        case "road": return (0.537, 0.545, 0.31)
        case "ride": return (0.552, 0.532, 0.28)
        default: return (0.559, 0.494, 0.17)
        }
    }

    /// Romeo, mounted, small against the light he is riding into. Drawn in width
    /// units around his hooves so the horse keeps its proportions on every screen.
    fileprivate func paintRider(_ context: inout GraphicsContext, _ f: Frame) {
        let staging = riderStaging
        let cx = staging.x, base = staging.base, s = staging.size
        let ink = Color(hex: 0x33202E)

        func q(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
            CGPoint(x: f.w * cx + dx * s * f.w, y: f.h * base + dy * s * f.w)
        }
        func oval(_ dx: CGFloat, _ dy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGRect {
            CGRect(x: f.w * cx + (dx - rx) * s * f.w, y: f.h * base + (dy - ry) * s * f.w,
                   width: rx * 2 * s * f.w, height: ry * 2 * s * f.w)
        }

        // The shadow comes back toward the reader: the light is ahead of him.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: f.w * 0.008))
            paintOval(&layer, oval(-0.03, -0.005, 0.135, 0.03),
                      Color(hex: 0x4B2F35).opacity(0.5))
        }

        // Legs, as tapered quadrilaterals: top at the barrel, bottom at the road.
        let legs: [(CGFloat, CGFloat)] = [(-0.062, -0.072), (-0.04, -0.016),
                                          (0.046, 0.068), (0.068, 0.042)]
        for leg in legs {
            paint(&context, linePath([q(leg.0 - 0.013, -0.1), q(leg.0 + 0.013, -0.1),
                                      q(leg.1 + 0.009, 0), q(leg.1 - 0.009, 0)]), ink)
        }

        // Barrel, rump, and chest.
        paintOval(&context, oval(0, -0.118, 0.095, 0.052), ink)
        paintOval(&context, oval(-0.068, -0.128, 0.055, 0.05), ink)
        paintOval(&context, oval(0.058, -0.125, 0.05, 0.048), ink)
        // Neck and head, reaching forward.
        paint(&context, linePath([q(0.072, -0.152), q(0.104, -0.232),
                                  q(0.134, -0.222), q(0.098, -0.13)]), ink)
        paint(&context, linePath([q(0.1, -0.238), q(0.163, -0.216),
                                  q(0.162, -0.198), q(0.104, -0.203)]), ink)
        // Tail, carried out behind him.
        limb(&context, f, q(-0.098, -0.155), q(-0.142, -0.055),
             q(-0.146, -0.116), ink, f.w * 0.012 * s)

        // The rider himself: seat, back, head, and the cloak the road takes.
        paint(&context, linePath([q(-0.058, -0.152), q(0.012, -0.25),
                                  q(0.04, -0.24), q(0.03, -0.148)]), ink)
        paint(&context, linePath([q(0.004, -0.168), q(0.03, -0.162),
                                  q(0.056, -0.098), q(0.03, -0.096)]), ink)
        paintOval(&context, oval(0.03, -0.272, 0.027, 0.027), ink)
        limb(&context, f, q(0.036, -0.238), q(0.092, -0.196),
             q(0.07, -0.226), ink, f.w * 0.017 * s)

        // Dawn takes his shoulder and the horse's crest, so the pair are lit from ahead.
        limb(&context, f, q(0.014, -0.252), q(0.108, -0.232),
             q(0.062, -0.262), Color(hex: 0xFFE7BE).opacity(0.5), f.w * 0.007 * s)
        limb(&context, f, q(0.05, -0.16), q(0.088, -0.128),
             q(0.082, -0.156), Color(hex: 0xFFE7BE).opacity(0.35), f.w * 0.006 * s)
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

import SwiftUI

/// A gentle, in-world confirmation for starting the story over.
/// Always mounted as an overlay so its entrance and exit can animate.
struct RestartPrompt: View {
    @Binding var isPresented: Bool
    let onConfirm: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AccessibilityFocusState private var titleFocused: Bool
    @State private var revealed = false
    @State private var iconTurns = 0
    @State private var confirmations = 0

    private static let deepRose = Color(hex: 0x7E2F45)
    private static let petal = Color(hex: 0xC97786)

    var body: some View {
        ZStack {
            if isPresented {
                backdrop
                    .transition(.opacity)
                card
                    .padding(.horizontal, 24)
                    .padding(.vertical, 32)
                    .frame(maxWidth: 460)
                    .transition(cardTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sensoryFeedback(.impact(weight: .medium), trigger: confirmations)
        .onChange(of: isPresented) { _, presented in
            if presented { appear() } else { revealed = false }
        }
    }

    // MARK: Pieces

    private var backdrop: some View {
        ZStack {
            if reduceTransparency {
                Palette.ink.opacity(0.55)
            } else {
                Rectangle().fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .light)
                LinearGradient(colors: [Palette.ink.opacity(0.18), Palette.rose.opacity(0.28)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { cancel() }
        .accessibilityHidden(true)
    }

    private var card: some View {
        ViewThatFits(in: .vertical) {
            cardContent
            ScrollView { cardContent }
                .scrollBounceBehavior(.basedOnSize)
        }
        .background { cardSurface }
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.9), Palette.blush.opacity(0.5)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
        }
        .shadow(color: Palette.rose.opacity(0.28), radius: 30, x: 0, y: 16)
        .foregroundStyle(Palette.ink)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { cancel() }
    }

    @ViewBuilder private var cardSurface: some View {
        let shape = RoundedRectangle(cornerRadius: 32, style: .continuous)
        if reduceTransparency {
            shape.fill(Palette.paper)
        } else {
            shape.fill(.regularMaterial)
                .environment(\.colorScheme, .light)
                .overlay(shape.fill(LinearGradient(
                    colors: [Palette.paper.opacity(0.82), Palette.blush.opacity(0.78)],
                    startPoint: .top, endPoint: .bottom)))
                .overlay(alignment: .top) {
                    RadialGradient(colors: [Self.petal.opacity(0.35), .clear],
                                   center: .top, startRadius: 0, endRadius: 220)
                        .frame(height: 220)
                        .allowsHitTesting(false)
                }
        }
    }

    private var cardContent: some View {
        VStack(spacing: 22) {
            medallion
                .padding(.top, 6)
                .reveal(revealed, delay: 0.04, reduceMotion: reduceMotion)

            VStack(spacing: 10) {
                SmallLabel(text: "Begin again")
                    .foregroundStyle(Palette.rose)
                Text("Start Romeo & Juliet\nfrom the first page?")
                    .literary(25, relativeTo: .title2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel("Start Romeo and Juliet from the first page?")
                    .accessibilityFocused($titleFocused)
                Text("Juliet’s story will begin anew, and the place you saved will be let go. This can’t be undone.")
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .reveal(revealed, delay: 0.1, reduceMotion: reduceMotion)

            VStack(spacing: 10) {
                Button(action: confirm) {
                    HStack(spacing: 9) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 15, weight: .medium))
                            .accessibilityHidden(true)
                        Text("Begin again")
                            .font(.system(.body, design: .serif, weight: .medium))
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .padding(.horizontal, 18)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(colors: [Palette.rose, Self.deepRose],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                    .shadow(color: Self.deepRose.opacity(0.3), radius: 10, x: 0, y: 5)
                    .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityHint("Erases your saved place and starts the story from the beginning.")
                .accessibilityIdentifier("confirmRestart")

                Button(action: cancel) {
                    Text("Keep reading")
                        .font(.system(.body, design: .serif))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .padding(.horizontal, 18)
                        .foregroundStyle(Palette.ink)
                        .glass(radius: 26)
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityHint("Returns to the library with your place kept.")
                .accessibilityIdentifier("cancelRestart")
            }
            .reveal(revealed, delay: 0.16, reduceMotion: reduceMotion)
        }
        .padding(.horizontal, 24)
        .padding(.top, 26)
        .padding(.bottom, 22)
    }

    private var medallion: some View {
        ZStack {
            halo
            Circle()
                .fill(LinearGradient(colors: [Self.petal, Palette.rose, Self.deepRose],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 64, height: 64)
                .overlay(Circle().strokeBorder(.white.opacity(0.45), lineWidth: 1))
                .shadow(color: Palette.rose.opacity(0.35), radius: 12, x: 0, y: 6)
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.white)
                .symbolEffect(.rotate, value: iconTurns)
        }
        .frame(width: 96, height: 96)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var halo: some View {
        let glow = Circle()
            .fill(RadialGradient(colors: [Palette.blush, Self.petal.opacity(0.0)],
                                 center: .center, startRadius: 20, endRadius: 48))
        if reduceMotion {
            glow.opacity(0.7)
        } else {
            glow.phaseAnimator([false, true]) { content, expanded in
                content
                    .scaleEffect(expanded ? 1.12 : 0.9)
                    .opacity(expanded ? 0.95 : 0.55)
            } animation: { _ in
                .easeInOut(duration: 1.9)
            }
        }
    }

    // MARK: Behaviour

    private var cardTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .scale(scale: 0.88).combined(with: .opacity).combined(with: .offset(y: 28)),
                removal: .scale(scale: 0.94).combined(with: .opacity).combined(with: .offset(y: 16)))
    }

    private func appear() {
        revealed = false
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.55, bounce: 0.2)) {
            revealed = true
        }
        if !reduceMotion {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { iconTurns += 1 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { titleFocused = true }
    }

    private func cancel() {
        withAnimation(Self.dismissAnimation(reduceMotion)) { isPresented = false }
    }

    private func confirm() {
        confirmations += 1
        withAnimation(Self.dismissAnimation(reduceMotion)) { isPresented = false }
        onConfirm()
    }

    static func presentAnimation(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.22) : .spring(duration: 0.5, bounce: 0.24)
    }

    static func dismissAnimation(_ reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.38, bounce: 0)
    }
}

private extension View {
    /// Staggered rise-in for the card's contents; a plain fade under Reduce Motion.
    func reveal(_ shown: Bool, delay: Double, reduceMotion: Bool) -> some View {
        self
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 12)
            .animation(reduceMotion ? .easeOut(duration: 0.2)
                                    : .spring(duration: 0.55, bounce: 0.2).delay(delay),
                       value: shown)
    }
}

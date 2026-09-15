import SwiftUI
import UIKit

/// The opening page of the story: sign in, create an account, or step
/// straight in as a guest. Sits in front of LibraryView as the app's
/// true entry point.
struct LoginView: View {
    @Bindable var auth: AuthModel
    @FocusState private var focusedField: Field?
    @State private var showPassword = false
    @State private var showConfirmPassword = false
    @State private var errorPulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Field { case email, password, confirmPassword }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AmbientAuthBackground(reduceMotion: reduceMotion)
                ScrollView {
                    VStack(spacing: 32) {
                        header
                        card
                        guestButton
                    }
                    .padding(.horizontal, 27)
                    .padding(.top, max(48, geometry.size.height * 0.09))
                    .padding(.bottom, 40)
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .foregroundStyle(Palette.ink)
        .tint(Palette.rose)
        .onChange(of: auth.shakeToken) { _, _ in
            withAnimation(.easeOut(duration: 0.12)) { errorPulse = true }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            Task {
                try? await Task.sleep(for: .milliseconds(420))
                withAnimation(.easeOut(duration: 0.3)) { errorPulse = false }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 26, weight: .ultraLight))
                .foregroundStyle(Palette.rose)
                .frame(width: 64, height: 64)
                .glass(radius: 32)
            VStack(spacing: 6) {
                Text("PlayScript")
                    .literary(38, relativeTo: .largeTitle)
                    .tracking(-1)
                Text("A love story waiting for your voice.")
                    .literary(16, relativeTo: .subheadline)
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .modifier(ThoughtArrival(delay: 0, reduceMotion: reduceMotion))
    }

    // MARK: - Card

    private var card: some View {
        VStack(spacing: 16) {
            Text(auth.mode == .signIn ? "Welcome back" : "Begin your story")
                .literary(20)
                .padding(.bottom, 2)

            fieldStack

            if let message = auth.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(auth.isGentleMessage ? Palette.muted : Palette.rose)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .accessibilityIdentifier("authMessage")
            }

            primaryButton

            HStack(spacing: 10) {
                Rectangle().fill(Palette.muted.opacity(0.25)).frame(height: 1)
                Text("or").font(.caption2).foregroundStyle(Palette.muted)
                Rectangle().fill(Palette.muted.opacity(0.25)).frame(height: 1)
            }
            .padding(.vertical, 2)

            providerButtons

            toggleModeLink
        }
        .padding(24)
        .glass(radius: 28)
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Palette.rose.opacity(errorPulse ? 0.55 : 0), lineWidth: 2)
        }
        .modifier(ShakeEffect(travelDistance: reduceMotion ? 0 : 7, animatableData: CGFloat(auth.shakeToken)))
        .animation(.easeInOut(duration: reduceMotion ? 0 : 0.35), value: auth.mode)
        .animation(.easeOut(duration: reduceMotion ? 0 : 0.3), value: auth.message)
        .animation(.easeOut(duration: reduceMotion ? 0 : 0.45), value: auth.shakeToken)
        .modifier(ThoughtArrival(delay: reduceMotion ? 0 : 0.1, reduceMotion: reduceMotion))
    }

    private var fieldStack: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "envelope")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(Palette.muted)
                TextField("", text: $auth.email, prompt: Text("Email").foregroundStyle(Palette.muted.opacity(0.7)))
                    .literary(16)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
                    .focused($focusedField, equals: .email)
                    .accessibilityIdentifier("emailField")
            }
            .modifier(GlassFieldBackground(isFocused: focusedField == .email))

            HStack(spacing: 10) {
                Image(systemName: "lock")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(Palette.muted)
                Group {
                    if showPassword {
                        TextField("", text: $auth.password, prompt: Text("Password").foregroundStyle(Palette.muted.opacity(0.7)))
                    } else {
                        SecureField("", text: $auth.password, prompt: Text("Password").foregroundStyle(Palette.muted.opacity(0.7)))
                    }
                }
                .literary(16)
                .textContentType(auth.mode == .signIn ? .password : .newPassword)
                .submitLabel(auth.mode == .signUp ? .next : .go)
                .onSubmit {
                    if auth.mode == .signUp { focusedField = .confirmPassword } else { runSubmit() }
                }
                .focused($focusedField, equals: .password)
                .accessibilityIdentifier("passwordField")
                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel(showPassword ? "Hide password" : "Show password")
            }
            .modifier(GlassFieldBackground(isFocused: focusedField == .password))

            if auth.mode == .signUp {
                HStack(spacing: 10) {
                    Image(systemName: "lock.rotation")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(Palette.muted)
                    Group {
                        if showConfirmPassword {
                            TextField("", text: $auth.confirmPassword, prompt: Text("Confirm password").foregroundStyle(Palette.muted.opacity(0.7)))
                        } else {
                            SecureField("", text: $auth.confirmPassword, prompt: Text("Confirm password").foregroundStyle(Palette.muted.opacity(0.7)))
                        }
                    }
                    .literary(16)
                    .submitLabel(.go)
                    .onSubmit { runSubmit() }
                    .focused($focusedField, equals: .confirmPassword)
                    .accessibilityIdentifier("confirmPasswordField")
                    Button {
                        showConfirmPassword.toggle()
                    } label: {
                        Image(systemName: showConfirmPassword ? "eye.slash" : "eye")
                            .font(.system(size: 14, weight: .light))
                            .foregroundStyle(Palette.muted)
                            .frame(width: 30, height: 30)
                    }
                    .accessibilityLabel(showConfirmPassword ? "Hide password" : "Show password")
                }
                .modifier(GlassFieldBackground(isFocused: focusedField == .confirmPassword))
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity))
            }
        }
    }

    private var primaryButton: some View {
        Button {
            runSubmit()
        } label: {
            HStack {
                Spacer()
                if auth.isSubmitting {
                    ProgressView().tint(.white)
                } else {
                    Text(auth.mode == .signIn ? "Sign In" : "Create Account")
                        .font(.system(.body, design: .serif, weight: .medium))
                }
                Spacer()
            }
            .padding(.vertical, 18)
            .foregroundStyle(.white)
            .background(Palette.rose, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(PressStyle())
        .disabled(auth.isSubmitting)
        .accessibilityIdentifier("primaryAuthButton")
    }

    private var providerButtons: some View {
        VStack(spacing: 12) {
            ProviderButton(icon: "apple.logo", title: "Continue with Apple") {
                run { await auth.submitApple() }
            }
            .accessibilityIdentifier("appleSignIn")

            ProviderButton(icon: "g.circle", title: "Continue with Google") {
                run { await auth.submitGoogle() }
            }
            .accessibilityIdentifier("googleSignIn")
        }
    }

    private var toggleModeLink: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            focusedField = nil
            withAnimation(.easeInOut(duration: reduceMotion ? 0 : 0.3)) {
                auth.toggleMode()
            }
        } label: {
            Group {
                if auth.mode == .signIn {
                    (Text("New to PlayScript? ") + Text("Create an account").fontWeight(.semibold))
                } else {
                    (Text("Already have an account? ") + Text("Sign in").fontWeight(.semibold))
                }
            }
            .font(.footnote)
            .foregroundStyle(Palette.muted)
            .frame(minHeight: 44)
        }
        .accessibilityIdentifier("toggleAuthMode")
    }

    private var guestButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            auth.continueAsGuest()
        } label: {
            HStack(spacing: 6) {
                Text("Continue as Guest")
                Image(systemName: "arrow.right").font(.system(size: 12, weight: .light))
            }
            .font(.system(.subheadline, design: .serif))
            .foregroundStyle(Palette.muted)
            .padding(.vertical, 12)
            .padding(.horizontal, 22)
            .frame(minHeight: 44)
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("continueAsGuest")
        .modifier(ThoughtArrival(delay: reduceMotion ? 0 : 0.2, reduceMotion: reduceMotion))
    }

    // MARK: - Actions

    private func runSubmit() {
        run { await auth.submit() }
    }

    private func run(_ action: @escaping () async -> Void) {
        Task {
            let wasAuthenticated = auth.isAuthenticated
            await action()
            if auth.isAuthenticated && !wasAuthenticated {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }
}

// MARK: - Glass field styling

private struct GlassFieldBackground: ViewModifier {
    var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.22)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isFocused ? Palette.rose.opacity(0.55) : .white.opacity(0.55),
                                  lineWidth: isFocused ? 1.4 : 0.8)
            }
            .shadow(color: Palette.rose.opacity(isFocused ? 0.16 : 0), radius: isFocused ? 10 : 0, y: 3)
            .animation(.easeOut(duration: 0.2), value: isFocused)
    }
}

private struct ProviderButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Spacer(minLength: 0)
                Image(systemName: icon).font(.system(size: 16, weight: .regular))
                Text(title).font(.system(.subheadline, design: .rounded, weight: .medium))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 15)
            .frame(minHeight: 48)
        }
        .buttonStyle(PressStyle())
        .glass(radius: 18)
    }
}

/// A gentle shake, not a harsh error box: the card sways, then settles.
private struct ShakeEffect: GeometryEffect {
    var travelDistance: CGFloat = 8
    var numberOfShakes: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = travelDistance * sin(animatableData * .pi * numberOfShakes)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

/// Soft drifting light behind the card; subtle rather than distracting,
/// and stilled entirely under Reduce Motion.
private struct AmbientAuthBackground: View {
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.paper, Palette.blush.opacity(0.6), Palette.paper],
                           startPoint: .top, endPoint: .bottom)
            TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { timeline in
                Canvas { context, size in
                    let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    drawLight(&context, size, time)
                }
            }
            .blur(radius: 70)
            .opacity(0.85)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func noise(_ index: Int, _ salt: Int) -> Double {
        let value = sin(Double(index) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return value - floor(value)
    }

    private func drawLight(_ context: inout GraphicsContext, _ size: CGSize, _ time: Double) {
        let w = size.width, h = size.height
        let colors = [Palette.rose, Palette.blush, Palette.rose, Palette.blush]
        for i in 0..<4 {
            let seedX = noise(i, 5), seedY = noise(i, 9)
            let speed = 0.025 + noise(i, 13) * 0.02
            let x = (seedX * 0.7 + 0.15 + sin(time * speed + seedY * 6.28) * 0.12) * w
            let y = (seedY * 0.6 + 0.1 + cos(time * speed * 0.8 + seedX * 6.28) * 0.1) * h
            let radius = w * (0.34 + noise(i, 17) * 0.15)
            context.fill(
                Path(ellipseIn: CGRect(x: x - radius / 2, y: y - radius / 2, width: radius, height: radius)),
                with: .color(colors[i].opacity(0.16)))
        }
    }
}

#Preview {
    LoginView(auth: AuthModel(defaults: UserDefaults(suiteName: "preview")!))
}

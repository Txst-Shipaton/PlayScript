import Foundation

@MainActor @Observable
final class AuthModel {
    enum Mode { case signIn, signUp }

    var mode: Mode = .signIn
    var email = ""
    var password = ""
    var confirmPassword = ""
    private(set) var isSubmitting = false
    private(set) var message: String?
    private(set) var isGentleMessage = false
    private(set) var shakeToken = 0
    private(set) var user: AuthUser?
    private(set) var isGuest = false

    @ObservationIgnored private let service: AuthService
    @ObservationIgnored private let defaults: UserDefaults
    private static let sessionKey = "playscript.session.v1"

    var isAuthenticated: Bool { user != nil || isGuest }

    init(service: AuthService = PlaceholderAuthService(), defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--uitesting-auth") {
            defaults.removeObject(forKey: Self.sessionKey)
        } else if arguments.contains("--uitesting") {
            // Persist the bypass so a relaunch without arguments stays signed in,
            // the way a real guest session would.
            isGuest = true
            defaults.set("guest", forKey: Self.sessionKey)
            return
        }
        switch defaults.string(forKey: Self.sessionKey) {
        case "guest": isGuest = true
        case let savedEmail?: user = AuthUser(id: savedEmail, email: savedEmail)
        default: break
        }
    }

    func toggleMode() {
        mode = mode == .signIn ? .signUp : .signIn
        message = nil
        confirmPassword = ""
    }

    func continueAsGuest() {
        isGuest = true
        defaults.set("guest", forKey: Self.sessionKey)
    }

    func submit() async {
        guard !isSubmitting else { return }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try validate(email: trimmedEmail)
            isSubmitting = true
            message = nil
            let authedUser = mode == .signIn
                ? try await service.signIn(email: trimmedEmail, password: password)
                : try await service.signUp(email: trimmedEmail, password: password)
            isSubmitting = false
            complete(with: authedUser)
        } catch {
            isSubmitting = false
            fail(with: error)
        }
    }

    func submitApple() async { await submitProvider(service.signInWithApple) }
    func submitGoogle() async { await submitProvider(service.signInWithGoogle) }

    private func submitProvider(_ action: () async throws -> AuthUser) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        message = nil
        do {
            let authedUser = try await action()
            isSubmitting = false
            complete(with: authedUser)
        } catch {
            isSubmitting = false
            fail(with: error, shake: false)
        }
    }

    private func complete(with authedUser: AuthUser) {
        user = authedUser
        defaults.set(authedUser.email, forKey: Self.sessionKey)
    }

    private func validate(email: String) throws {
        guard !email.isEmpty, !password.isEmpty else { throw AuthError.missingFields }
        let parts = email.split(separator: "@")
        guard parts.count == 2, parts[1].contains("."), !parts[0].isEmpty else {
            throw AuthError.invalidEmailFormat
        }
        if mode == .signUp {
            guard password.count >= 6 else { throw AuthError.passwordTooShort }
            guard password == confirmPassword else { throw AuthError.passwordsDoNotMatch }
        }
    }

    private func fail(with error: Error, shake: Bool = true) {
        message = (error as? LocalizedError)?.errorDescription ?? AuthError.unknown.errorDescription
        isGentleMessage = !shake
        if shake { shakeToken += 1 }
    }
}

import Foundation

/// One signed-in player, as far as the rest of the app needs to know.
struct AuthUser: Equatable {
    let id: String
    let email: String
}

/// Soft, in-world messaging instead of blunt system error text.
enum AuthError: LocalizedError, Equatable {
    case missingFields
    case invalidEmailFormat
    case passwordTooShort
    case passwordsDoNotMatch
    case invalidCredentials
    case providerUnavailable(String)
    case unknown

    var errorDescription: String? {
        switch self {
        case .missingFields:
            "Every story needs a little information first."
        case .invalidEmailFormat:
            "That doesn't quite look like an email yet."
        case .passwordTooShort:
            "Choose a password with at least six characters."
        case .passwordsDoNotMatch:
            "Your passwords don't quite match."
        case .invalidCredentials:
            "That combination doesn't match our records. Try again?"
        case .providerUnavailable(let provider):
            "\(provider) sign-in is still being written. Try guest for now."
        case .unknown:
            "Something interrupted the story. Please try again."
        }
    }
}

/// The real backend (Firebase, Supabase, a custom API...) is wired in behind
/// this protocol. Nothing in the login screen knows or cares which one.
protocol AuthService {
    func signIn(email: String, password: String) async throws -> AuthUser
    func signUp(email: String, password: String) async throws -> AuthUser
    func signInWithApple() async throws -> AuthUser
    func signInWithGoogle() async throws -> AuthUser
}

/// Local stand-in used until a real provider is connected. Accepts any
/// well-formed email and a password of six or more characters.
struct PlaceholderAuthService: AuthService {
    func signIn(email: String, password: String) async throws -> AuthUser {
        try await Task.sleep(for: .milliseconds(600))
        guard password.count >= 6 else { throw AuthError.invalidCredentials }
        return AuthUser(id: email, email: email)
    }

    func signUp(email: String, password: String) async throws -> AuthUser {
        try await Task.sleep(for: .milliseconds(600))
        return AuthUser(id: email, email: email)
    }

    func signInWithApple() async throws -> AuthUser {
        try await Task.sleep(for: .milliseconds(300))
        throw AuthError.providerUnavailable("Apple")
    }

    func signInWithGoogle() async throws -> AuthUser {
        try await Task.sleep(for: .milliseconds(300))
        throw AuthError.providerUnavailable("Google")
    }
}

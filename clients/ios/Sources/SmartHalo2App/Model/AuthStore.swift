import Foundation
import Combine

/// Holds the server-session state (logged-in user + JWTs) and drives login/signup/logout against a
/// self-hosted `sh2-server`. Tokens live in the Keychain (`TokenStore`); the public user is cached in
/// UserDefaults so the account shows instantly on launch.
@MainActor
final class AuthStore: ObservableObject {
    static let shared = AuthStore()

    @Published private(set) var user: SH2User?
    @Published var busy = false
    @Published var lastError: String?

    private let userDefaultsKey = "sh2.user"

    var isLoggedIn: Bool { user != nil && TokenStore.load(.access) != nil }

    private init() { restore() }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let u = try? JSONDecoder().decode(SH2User.self, from: data) else { return }
        user = u
    }

    @discardableResult
    func login(serverURL: URL, email: String, password: String) async -> Bool {
        await run {
            let resp = try await SH2Server(baseURL: serverURL).login(email: email, password: password)
            self.persist(serverURL: serverURL, resp: resp)
        }
    }

    @discardableResult
    func signup(serverURL: URL, email: String, password: String,
                firstName: String, lastName: String) async -> Bool {
        await run {
            let resp = try await SH2Server(baseURL: serverURL)
                .signup(email: email, password: password, firstName: firstName, lastName: lastName)
            self.persist(serverURL: serverURL, resp: resp)
        }
    }

    /// Re-fetch the account from the server (also a cheap connectivity check).
    func refreshProfile() async {
        guard let url = AppSettings.shared.serverURL, let jwt = TokenStore.load(.access) else { return }
        if let u = try? await SH2Server(baseURL: url).whoami(accessJWT: jwt) {
            user = u
            cache(u)
        }
    }

    func logout() {
        user = nil
        TokenStore.clear()
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    // MARK: - Helpers

    private func run(_ work: @escaping () async throws -> Void) async -> Bool {
        busy = true; lastError = nil
        defer { busy = false }
        do { try await work(); return true }
        catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    private func persist(serverURL: URL, resp: SH2AuthResponse) {
        TokenStore.save(resp.access_jwt, .access)
        TokenStore.save(resp.refresh_jwt, .refresh)
        AppSettings.shared.serverURLString = serverURL.absoluteString
        if let u = resp.user { user = u; cache(u) }
    }

    private func cache(_ u: SH2User) {
        if let data = try? JSONEncoder().encode(u) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}

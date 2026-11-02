import Foundation

// Client for the self-hosted `sh2-server` (the open-source cloud reimplementation). Request/response
// shapes match `sh2-server/src/server.mjs` and the official app's API:
//   - `x-consumer-token` on signup/login/refresh and all v2 endpoints
//   - `x-access-token` (access JWT) on authenticated endpoints
//   - refresh uses a `{data:{…}}` envelope and replies `{data:[tokens]}`

struct SH2User: Codable, Equatable, Sendable {
    var id: Int?
    var email: String?
    var firstName: String?
    var lastName: String?
    var language: String?
    var isConfirmed: Bool?

    var displayName: String {
        let name = [firstName, lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? (email ?? "Account") : name
    }
}

struct SH2Tokens: Codable, Sendable {
    let access_jwt: String
    let refresh_jwt: String
}

struct SH2AuthResponse: Codable, Sendable {
    let access_jwt: String
    let refresh_jwt: String
    let user: SH2User?
}

/// A past ride as returned by `GET /api/v1/users/rides` (SHPastRide shape).
struct SH2PastRide: Codable, Identifiable, Sendable {
    var id: Int?
    var stamp: String?
    var start: String?
    var end: String?
    var createdAt: String?
    var duration: Double?
    var distance: Double?
    var averageSpeed: Double?
    var elevation: Double?
    var calories: Double?
    var co2: Double?
}

enum SH2ServerError: LocalizedError {
    case http(Int, String)
    case decode(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let msg): return "Server error \(code): \(msg)"
        case .decode(let m): return "Unexpected server response (\(m))"
        case .transport(let m): return "Can't reach the server: \(m)"
        }
    }
}

struct SH2Server: Sendable {
    let baseURL: URL
    let consumerToken: String
    static let defaultConsumerToken = ""

    init(baseURL: URL, consumerToken: String = SH2Server.defaultConsumerToken) {
        self.baseURL = baseURL
        self.consumerToken = consumerToken
    }

    // MARK: - Auth

    func login(email: String, password: String) async throws -> SH2AuthResponse {
        try await postJSON("/auth/local/login", body: ["email": email, "password": password],
                           consumer: true, decode: SH2AuthResponse.self)
    }

    func signup(email: String, password: String, firstName: String, lastName: String) async throws -> SH2AuthResponse {
        try await postJSON("/auth/local/signup",
                           body: ["email": email, "password": password,
                                  "firstName": firstName, "lastName": lastName],
                           consumer: true, decode: SH2AuthResponse.self)
    }

    func refresh(refreshJWT: String) async throws -> SH2Tokens {
        struct Envelope: Codable { let data: [SH2Tokens] }
        let env = try await postJSON("/auth/local/refresh_tokens",
                                     body: ["data": ["refresh_jwt": refreshJWT]],
                                     consumer: true, decode: Envelope.self)
        guard let t = env.data.first else { throw SH2ServerError.decode("no tokens in refresh") }
        return t
    }

    func whoami(accessJWT: String) async throws -> SH2User {
        try await get("/api/v1/users/whoami", accessJWT: accessJWT, decode: SH2User.self)
    }

    func rides(accessJWT: String) async throws -> [SH2PastRide] {
        try await get("/api/v1/users/rides", accessJWT: accessJWT, decode: [SH2PastRide].self)
    }

    func health() async throws {
        _ = try await rawRequest(makeRequest("GET", "/health"))
    }

    // MARK: - Plumbing

    private func url(_ path: String) -> URL {
        URL(string: baseURL.absoluteString + path) ?? baseURL
    }

    private func makeRequest(_ method: String, _ path: String,
                             accessJWT: String? = nil, consumer: Bool = false) -> URLRequest {
        var req = URLRequest(url: url(path))
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if consumer, !consumerToken.isEmpty { req.setValue(consumerToken, forHTTPHeaderField: "x-consumer-token") }
        if let jwt = accessJWT { req.setValue(jwt, forHTTPHeaderField: "x-access-token") }
        return req
    }

    private func rawRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw SH2ServerError.transport(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw SH2ServerError.transport("no HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            let msg = Self.errorMessage(from: data)
            throw SH2ServerError.http(http.statusCode, msg)
        }
        return (data, http)
    }

    private func postJSON<T: Decodable>(_ path: String, body: [String: Any],
                                        consumer: Bool, decode: T.Type) async throws -> T {
        var req = makeRequest("POST", path, consumer: consumer)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await rawRequest(req)
        return try Self.decodeBody(data, as: T.self)
    }

    private func get<T: Decodable>(_ path: String, accessJWT: String?, consumer: Bool = false,
                                   decode: T.Type) async throws -> T {
        let (data, _) = try await rawRequest(makeRequest("GET", path, accessJWT: accessJWT, consumer: consumer))
        return try Self.decodeBody(data, as: T.self)
    }

    private static func decodeBody<T: Decodable>(_ data: Data, as: T.Type) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw SH2ServerError.decode(error.localizedDescription) }
    }

    private static func errorMessage(from data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = obj["error"] as? String { return err }
        let s = String(data: data, encoding: .utf8) ?? ""
        return s.isEmpty ? "(no body)" : String(s.prefix(200))
    }
}

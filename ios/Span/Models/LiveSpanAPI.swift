//
//  LiveSpanAPI.swift
//  Span — talks to the India EC2 backend at http://3.6.234.236/v1.
//
//  STUB: the request plumbing, JSON decoding, and Sign-in-with-Apple token flow
//  are sketched so the app can be pointed at the real backend by swapping the
//  injected SpanAPI. Endpoints not yet live throw `.notImplemented`.
//
//  Thin client: no medical logic — every DTO is rendered as-is.
//

import Foundation

actor SpanTokenStore {
    /// Span's own KMS-signed access token (NOT the Apple identity token, which is
    /// discarded after bootstrap per SCREENS.md Screen 1).
    private(set) var accessToken: String?
    private(set) var refreshToken: String?

    func set(access: String?, refresh: String?) {
        accessToken = access
        refreshToken = refresh
    }
}

struct LiveSpanAPI: SpanAPI {
    let baseURL: URL
    let session: URLSession
    let tokens: SpanTokenStore

    init(baseURL: URL = URL(string: "http://3.6.234.236/v1")!,
         session: URLSession = .shared,
         tokens: SpanTokenStore = SpanTokenStore()) {
        self.baseURL = baseURL
        self.session = session
        self.tokens = tokens
    }

    // MARK: Sign in with Apple bootstrap

    /// Exchanges Apple's identityToken + authorizationCode for Span's own JWTs.
    /// POST /v1/auth/apple. The Apple token is never persisted.
    func exchangeApple(identityToken: String, authorizationCode: String, nonce: String) async throws {
        struct Body: Encodable {
            let identity_token: String
            let authorization_code: String
            let nonce: String
        }
        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String
        }
        let body = Body(identity_token: identityToken, authorization_code: authorizationCode, nonce: nonce)
        let resp: TokenResponse = try await post("auth/apple", body: body, authed: false)
        await tokens.set(access: resp.access_token, refresh: resp.refresh_token)
    }

    // MARK: SpanAPI

    func overview() async throws -> OverviewDTO { try await get("overview") }
    func systemDetail(_ key: SystemKey) async throws -> SystemDetailDTO { try await get("systems/\(key.rawValue)") }
    func parameterDetail(_ id: String) async throws -> ParameterDetailDTO { try await get("parameters/\(id)") }
    func bioAge() async throws -> BioAgeResult { try await get("bioage") }
    func citation(_ id: String) async throws -> Source { try await get("citations/\(id)") }
    func ingestionJobs() async throws -> [IngestionJob] { try await get("ingestion/jobs") }
    func checkinNext() async throws -> CheckinInstrument { try await get("checkin/next") }
    func prepReport() async throws -> PrepReport { throw SpanAPIError.notImplemented }

    // MARK: Transport

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private func get<T: Decodable>(_ path: String) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        if let token = await tokens.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return try await send(request)
    }

    private func post<B: Encodable, T: Decodable>(_ path: String, body: B, authed: Bool = true) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.encoder.encode(body)
        if authed, let token = await tokens.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return try await send(request)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SpanAPIError.transport(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 { throw SpanAPIError.unauthorized }
            guard (200..<300).contains(http.statusCode) else {
                throw SpanAPIError.transport("HTTP \(http.statusCode)")
            }
        }
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw SpanAPIError.transport("Could not read the server response.")
        }
    }
}

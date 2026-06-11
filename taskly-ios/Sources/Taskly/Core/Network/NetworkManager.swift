import Foundation
import Alamofire

@MainActor
final class NetworkManager: ObservableObject {
    static let shared = NetworkManager()

    private let session: Session
    private let decoder: JSONDecoder
    private let baseURL = APIConstants.baseURL

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        // Wait for connectivity (e.g. the cellular-data permission prompt on
        // first launch in China) instead of failing instantly — but cap the
        // TOTAL wait. Without timeoutIntervalForResource the connectivity wait
        // is unbounded (default 7 days), which showed up as forever-spinners.
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 20
        // Bypass any system/VPN HTTP proxy (Clash, Shadowrocket, …). The API is
        // hosted in mainland China, so direct is always the fast path — and local
        // proxies were breaking TLS to taskly.cnirv.com (-9816 handshake failures).
        config.connectionProxyDictionary = [:]

        self.session = Session(
            configuration: config,
            interceptor: AuthInterceptor(),
            eventMonitors: [NetworkLogger()]
        )

        self.decoder = JSONDecoder()
        // The Go backend emits RFC3339 timestamps WITH fractional seconds
        // (e.g. 2026-05-30T21:55:21.728649+08:00). Foundation's `.iso8601`
        // strategy rejects fractional seconds, so decode leniently: try the
        // fractional-seconds formatter first, then fall back to plain ISO8601.
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = NetworkManager.iso8601WithFractional.date(from: string)
                ?? NetworkManager.iso8601Plain.date(from: string) {
                return date
            }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "Unparseable ISO8601 date: \(string)"))
        }
        // NOTE: do NOT set `.convertFromSnakeCase` here. The model structs already
        // declare explicit snake_case CodingKeys (e.g. skillTags = "skill_tags").
        // With convertFromSnakeCase on, the decoder first rewrites "skill_tags" →
        // "skillTags" and then fails to match the CodingKey whose raw value is
        // "skill_tags" — so required fields like created_at go "missing" and every
        // decode throws. Explicit CodingKeys are the single source of truth.
    }

    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso8601Plain = ISO8601DateFormatter()

    func request<T: Codable>(
        _ path: String,
        method: HTTPMethod = .get,
        parameters: Parameters? = nil,
        encoding: ParameterEncoding = URLEncoding.default
    ) async throws -> T {
        let url = baseURL + path
        return try await withCheckedThrowingContinuation { continuation in
            session.request(url, method: method, parameters: parameters, encoding: encoding)
                .validate()
                .responseDecodable(of: APIResponse<T>.self, decoder: decoder) { response in
                    switch response.result {
                    case .success(let apiResponse):
                        if let data = apiResponse.data {
                            continuation.resume(returning: data)
                        } else {
                            continuation.resume(throwing: APIError.noData)
                        }
                    case .failure(let error):
                        continuation.resume(throwing: NetworkManager.resolveError(response.data, error))
                    }
                }
        }
    }

    func requestJSON<T: Codable>(
        _ path: String,
        method: HTTPMethod = .post,
        body: Encodable
    ) async throws -> T {
        let url = baseURL + path
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        // Dates must go out as RFC3339 strings — the Go side binds them as strings.
        // The default strategy encodes a raw Double (seconds since 2001), which the
        // server rejects with a 400.
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(body)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        return try await withCheckedThrowingContinuation { continuation in
            session.request(url, method: method, parameters: json, encoding: JSONEncoding.default)
                .validate()
                .responseDecodable(of: APIResponse<T>.self, decoder: decoder) { response in
                    switch response.result {
                    case .success(let apiResponse):
                        if let data = apiResponse.data {
                            continuation.resume(returning: data)
                        } else {
                            continuation.resume(throwing: APIError.noData)
                        }
                    case .failure(let error):
                        continuation.resume(throwing: NetworkManager.resolveError(response.data, error))
                    }
                }
        }
    }

    func uploadImage<T: Codable>(_ data: Data, path: String) async throws -> T {
        let url = baseURL + path
        return try await withCheckedThrowingContinuation { continuation in
            session.upload(
                multipartFormData: { form in
                    form.append(data, withName: "file", fileName: "image.jpg", mimeType: "image/jpeg")
                },
                to: url
            )
            .validate()
            .responseDecodable(of: APIResponse<T>.self, decoder: decoder) { response in
                switch response.result {
                case .success(let apiResponse):
                    if let data = apiResponse.data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: APIError.noData)
                    }
                case .failure(let error):
                    continuation.resume(throwing: NetworkManager.resolveError(response.data, error))
                }
            }
        }
    }

    // Dictionary body convenience (for simple [String: Any] payloads)
    func requestJSON<T: Codable>(_ path: String, body: [String: Any]) async throws -> T {
        let url = baseURL + path
        return try await withCheckedThrowingContinuation { continuation in
            session.request(url, method: .post, parameters: body, encoding: JSONEncoding.default)
                .validate()
                .responseDecodable(of: APIResponse<T>.self, decoder: decoder) { response in
                    switch response.result {
                    case .success(let apiResponse):
                        if let data = apiResponse.data {
                            continuation.resume(returning: data)
                        } else {
                            continuation.resume(throwing: APIError.noData)
                        }
                    case .failure(let error):
                        continuation.resume(throwing: NetworkManager.resolveError(response.data, error))
                    }
                }
        }
    }
}

// MARK: - Auth Interceptor

final class AuthInterceptor: RequestInterceptor {
    func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        var request = urlRequest
        if let token = UserDefaults.standard.string(forKey: "auth_token") {
            request.headers.add(.authorization(bearerToken: token))
        }
        completion(.success(request))
    }
}

// MARK: - Network Logger (前后端联调)

/// Logs every request and response to the console so client/server behaviour can be
/// matched up during integration debugging. Active in DEBUG builds only.
final class NetworkLogger: EventMonitor {
    let queue = DispatchQueue(label: "com.taskly.networklogger")

    func requestDidResume(_ request: Request) {
        #if DEBUG
        let method = request.request?.httpMethod ?? "?"
        let url = request.request?.url?.absoluteString ?? "?"
        var line = "➡️ [NET] \(method) \(url)"
        if let body = request.request?.httpBody, let s = String(data: body, encoding: .utf8) {
            line += "\n   body: \(s)"
        }
        print(line)
        #endif
    }

    func request(_ request: DataRequest, didParseResponse response: DataResponse<Data?, AFError>) {
        #if DEBUG
        let url = request.request?.url?.absoluteString ?? "?"
        let status = response.response?.statusCode ?? -1
        let icon = (200..<300).contains(status) ? "✅" : "❌"
        var line = "⬅️ [NET] \(icon) \(status) \(url)"
        if let data = response.data, let s = String(data: data, encoding: .utf8) {
            line += "\n   resp: \(s.prefix(800))"
        }
        if let error = response.error {
            line += "\n   error: \(error.localizedDescription)"
        }
        print(line)
        #endif
    }
}

// MARK: - Constants

enum APIConstants {
    #if DEBUG
    // Debug talks to the LIVE backend through an SSH tunnel:
    //   ssh -N -L 8430:127.0.0.1:8430 root@47.94.93.24
    // So localhost:8430 == the production server's :8430 (live RDS + live Stripe).
    // Using localhost sidesteps the Mac's VPN fake-ip DNS, and ATS already allows it.
//    static let baseURL = "http://localhost:8430/v1"
    static let baseURL = "https://taskly.cnirv.com/v1"
    #else
    static let baseURL = "https://taskly.cnirv.com/v1"
    #endif
}

enum APIError: LocalizedError {
    case noData
    case unauthorized
    case server(String)

    var errorDescription: String? {
        switch self {
        case .noData: return "No data returned"
        case .unauthorized: return "Please log in again"
        case .server(let message): return message
        }
    }
}

extension NetworkManager {
    private struct ServerEnvelope: Decodable { let code: Int; let message: String }

    /// Surface the backend's `{code,message}` instead of Alamofire's raw
    /// "Response status code was unacceptable: 500." which users were seeing.
    static func resolveError(_ data: Data?, _ fallback: Error) -> Error {
        // 401 must stay distinguishable from other failures: it's the only error
        // that should end the local session (see AuthManager.fetchCurrentUser).
        if fallback.asAFError?.responseCode == 401 {
            return APIError.unauthorized
        }
        if let data,
           let env = try? JSONDecoder().decode(ServerEnvelope.self, from: data),
           !env.message.isEmpty {
            return APIError.server(env.message)
        }
        if let urlError = (fallback.asAFError?.underlyingError ?? fallback) as? URLError {
            switch urlError.code {
            case .timedOut:
                return APIError.server("Connection timed out. Please check your network and try again.")
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return APIError.server("No internet connection. Please check your network and try again.")
            default:
                break
            }
        }
        return fallback
    }
}

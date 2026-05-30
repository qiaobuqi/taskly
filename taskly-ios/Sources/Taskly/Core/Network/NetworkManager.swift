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
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true

        self.session = Session(
            configuration: config,
            interceptor: AuthInterceptor()
        )

        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

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
                        continuation.resume(throwing: error)
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
                        continuation.resume(throwing: error)
                    }
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
                    continuation.resume(throwing: error)
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
                        continuation.resume(throwing: error)
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

// MARK: - Constants

enum APIConstants {
    static let baseURL = "https://api.taskly.app/v1"
    // during dev, swap to: "http://localhost:8080/v1"
}

enum APIError: LocalizedError {
    case noData
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .noData: return "No data returned"
        case .unauthorized: return "Please log in again"
        }
    }
}

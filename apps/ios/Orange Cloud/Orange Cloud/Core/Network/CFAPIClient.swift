//
//  CFAPIClient.swift
//  Orange Cloud
//
//  所有 Cloudflare API 调用的统一入口：
//  自动注入 Bearer Token、过期前主动刷新、401 刷新后重试一次、统一错误解析。
//

import Foundation

actor CFAPIClient {

    private let baseURL = URL(string: "https://api.cloudflare.com/client/v4")!
    private let session = URLSession.shared
    private let authManager: AuthManager

    init(authManager: AuthManager) {
        self.authManager = authManager
    }

    // MARK: - 核心请求方法

    func get<T: Codable & Sendable>(_ path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        try await request(method: "GET", path: path, queryItems: queryItems, body: nil)
    }

    func post<T: Codable & Sendable, B: Codable & Sendable>(_ path: String, body: B) async throws -> T {
        let data = try JSONEncoder().encode(body)
        return try await request(method: "POST", path: path, queryItems: [], body: data)
    }

    func put<T: Codable & Sendable, B: Codable & Sendable>(_ path: String, body: B) async throws -> T {
        let data = try JSONEncoder().encode(body)
        return try await request(method: "PUT", path: path, queryItems: [], body: data)
    }

    func patch<T: Codable & Sendable, B: Codable & Sendable>(_ path: String, body: B) async throws -> T {
        let data = try JSONEncoder().encode(body)
        return try await request(method: "PATCH", path: path, queryItems: [], body: data)
    }

    func delete(_ path: String) async throws {
        let _: EmptyResponse = try await request(method: "DELETE", path: path, queryItems: [], body: nil)
    }

    /// 返回原始响应体（KV value 等非 JSON 信封端点）
    func getRaw(_ path: String, queryItems: [URLQueryItem] = []) async throws -> Data {
        try await performRequest(method: "GET", path: path, queryItems: queryItems, body: nil, contentType: nil)
    }

    /// 原始字节 PUT（R2 对象上传等），自带 Content-Type
    func putRaw<T: Codable & Sendable>(_ path: String, body: Data, contentType: String) async throws -> T {
        let data = try await performRequest(
            method: "PUT", path: path, queryItems: [], body: body, contentType: contentType
        )
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    /// multipart/form-data 写入（KV 写值要求 value + metadata 两个 part）
    func putMultipart<T: Codable & Sendable>(_ path: String, fields: [String: String]) async throws -> T {
        let boundary = "OrangeCloud-\(UUID().uuidString)"
        var body = Data()
        for (name, value) in fields {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))

        let data = try await performRequest(
            method: "PUT", path: path, queryItems: [], body: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    /// GraphQL Analytics API。信封是 {data, errors}（GraphQL 错误时 HTTP 仍为 200），
    /// 与 REST 的 {result, success} 不同。复用 request 自动获得 Token 刷新与 401 重试。
    func graphQL<D: Codable & Sendable, V: Codable & Sendable>(
        query: String,
        variables: V
    ) async throws -> D {
        let body = try JSONEncoder().encode(GraphQLRequest(query: query, variables: variables))
        let envelope: GraphQLResponse<D> = try await request(
            method: "POST", path: "graphql", queryItems: [], body: body
        )
        if let first = envelope.errors?.first {
            throw APIError.cloudflareError(code: 0, message: first.message)
        }
        guard let data = envelope.data else {
            throw APIError.decodingError(URLError(.cannotDecodeContentData))
        }
        return data
    }

    // MARK: - 内部实现

    private func request<T: Codable & Sendable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem],
        body: Data?
    ) async throws -> T {
        let data = try await performRequest(
            method: method, path: path, queryItems: queryItems, body: body, contentType: "application/json"
        )
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    /// 统一的 HTTP 执行：Token 注入与刷新、401 重试一次、HTTP 错误映射，返回原始 Data
    private func performRequest(
        method: String,
        path: String,
        queryItems: [URLQueryItem],
        body: Data?,
        contentType: String?,
        isRetry: Bool = false
    ) async throws -> Data {

        // 1. 检查 Token 是否临期，如需则先刷新
        let token = try await validAccessToken()

        // 2. 构造请求。path 视为已编码（KV key 等特殊字符由调用方预先百分号编码，
        //    不能用 appendingPathComponent——它会把 % 二次编码）
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedPath += "/" + path
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = method
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let contentType {
            urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        urlRequest.httpBody = body

        // 3. 执行请求
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw APIError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        // 4. 401：Token 过期，刷新后重试一次
        if http.statusCode == 401 && !isRetry {
            _ = try await authManager.refreshAccessToken()
            return try await performRequest(
                method: method, path: path, queryItems: queryItems,
                body: body, contentType: contentType, isRetry: true
            )
        }

        // 5. HTTP 错误处理（优先透出 CF 返回的业务错误信息）
        switch http.statusCode {
        case 200...299:
            return data
        case 401:
            throw APIError.unauthorized
        case 429:
            throw APIError.rateLimited
        default:
            if let envelope = try? JSONDecoder().decode(CFAPIResponse<EmptyResponse>.self, from: data),
               let first = envelope.errors.first {
                throw APIError.cloudflareError(code: first.code, message: first.message)
            }
            switch http.statusCode {
            case 403:       throw APIError.forbidden
            case 404:       throw APIError.notFound
            case 500...599: throw APIError.serverError(statusCode: http.statusCode)
            default:        throw APIError.serverError(statusCode: http.statusCode)
            }
        }
    }

    /// 返回当前身份的有效 Token（临期则先刷新）
    private func validAccessToken() async throws -> String {
        guard let token = await authManager.currentToken else {
            throw APIError.unauthorized
        }
        if token.expiresAt.timeIntervalSinceNow < 60 {  // 提前 60 秒刷新
            do {
                return try await authManager.refreshAccessToken()
            } catch AuthError.notLoggedIn {
                throw APIError.unauthorized          // 刷新令牌确已失效：不再使用旧 token
            } catch {
                // 刷新瞬时失败但旧 token 仍在有效期内：先用旧 token，真过期了由 401 重试兜底
                if token.expiresAt.timeIntervalSinceNow > 0 {
                    return token.accessToken
                }
                throw error
            }
        }
        return token.accessToken
    }
}

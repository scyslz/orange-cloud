//
//  AuthManager.swift
//  Orange Cloud
//
//  OAuth 2.0 + PKCE，多登录身份：
//  - 每次 login 新增一个身份会话（独立 token，互不挤占）
//  - 退出单个身份只移除它；全部退出后回登录页
//  - Token 存 Keychain（按身份 UUID），身份索引（标签/scope）存 UserDefaults
//

import Foundation
import AuthenticationServices
import UIKit

nonisolated enum AuthError: LocalizedError {
    case invalidCallback
    case stateMismatch
    case oauthError(String)
    case tokenExchangeFailed(String)
    /// token 端点返回非 2xx。status 用于区分「刷新令牌确已失效」（400）与瞬时错误（5xx/429）。
    case tokenEndpointError(status: Int, body: String)
    case notLoggedIn

    var errorDescription: String? {
        switch self {
        case .invalidCallback:              return String(localized: "授权回调格式错误")
        case .stateMismatch:                return String(localized: "state 校验失败，请重试")
        case .oauthError(let message):      return message
        case .tokenExchangeFailed(let msg): return String(localized: "换取 Token 失败：\(msg)")
        case .tokenEndpointError(let status, let body):
            return String(localized: "换取 Token 失败：\(body.isEmpty ? "HTTP \(status)" : body)")
        case .notLoggedIn:                  return String(localized: "登录已过期，请重新登录")
        }
    }
}

/// 登录身份的展示信息（token 本体在 Keychain）
nonisolated struct AuthSessionMeta: Codable, Identifiable, Hashable, Sendable {
    let id:     UUID
    var label:  String       // 邮箱或占位名，展示用
    var scopes: [String]
}

@Observable
@MainActor
final class AuthManager {

    private(set) var sessions: [AuthSessionMeta] = []
    private(set) var currentSessionId: UUID?
    var isLoading = false
    var errorMessage: String?

    var isLoggedIn: Bool { currentSessionId != nil }

    var currentSession: AuthSessionMeta? {
        sessions.first { $0.id == currentSessionId }
    }

    /// 当前身份的 scope（展示与权限门控用）
    var grantedScopes: [String] { currentSession?.scopes ?? [] }

    func hasScope(_ scope: String) -> Bool {
        grantedScopes.contains(scope)
    }

    /// 当前身份的 token（CFAPIClient 取用）
    var currentToken: TokenStore.StoredToken? {
        currentSessionId.flatMap { TokenStore.load(sessionId: $0) }
    }

    private var currentWebSession: ASWebAuthenticationSession?
    /// 进行中的刷新任务：并发的 401/临期请求复用同一次刷新，避免刷新令牌轮换下的竞态
    private var refreshTask: Task<String, Error>?
    private let contextProvider = WebAuthContextProvider()
    private static let sessionsKey = "authSessions"
    private static let currentSessionKey = "currentSessionId"
    static let iCloudSyncKey = "iCloudSyncEnabled"

    var iCloudSyncEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.iCloudSyncKey)
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.sessionsKey),
           let list = try? JSONDecoder().decode([AuthSessionMeta].self, from: data) {
            sessions = list
        }
        if let idString = UserDefaults.standard.string(forKey: Self.currentSessionKey),
           let id = UUID(uuidString: idString),
           sessions.contains(where: { $0.id == id }) {
            currentSessionId = id
        } else {
            currentSessionId = sessions.first?.id
        }
        migrateLegacyTokenIfNeeded()
        migrateToSharedKeychainGroupIfNeeded()

        // iCloud：拉取云端身份索引（token 本体经 iCloud 钥匙串同步）+ 监听外部变更
        NSUbiquitousKeyValueStore.default.synchronize()
        mergeSessionsFromCloud()
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.mergeSessionsFromCloud()
            }
        }
    }

    /// 云端身份索引合并（只增不删：删除以本机操作为准，避免互相覆盖）
    private func mergeSessionsFromCloud() {
        guard iCloudSyncEnabled,
              let data = NSUbiquitousKeyValueStore.default.data(forKey: Self.sessionsKey),
              let cloud = try? JSONDecoder().decode([AuthSessionMeta].self, from: data) else { return }
        var changed = false
        for meta in cloud where !sessions.contains(where: { $0.id == meta.id }) {
            sessions.append(meta)
            changed = true
        }
        if changed {
            if currentSessionId == nil {
                currentSessionId = sessions.first?.id
            }
            persist()
        }
    }

    /// 切换 iCloud 同步：迁移钥匙串条目形态 + 推送/移除云端索引
    func setICloudSync(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.iCloudSyncKey)
        TokenStore.setSynchronizable(enabled, sessionIds: sessions.map(\.id))
        if enabled {
            persist()
            mergeSessionsFromCloud()
        } else {
            NSUbiquitousKeyValueStore.default.removeObject(forKey: Self.sessionsKey)
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }

    /// 旧版单 token → 第一个身份会话
    private func migrateLegacyTokenIfNeeded() {
        guard sessions.isEmpty, let legacy = TokenStore.loadLegacy() else { return }
        let id = UUID()
        TokenStore.save(legacy, sessionId: id)
        TokenStore.clearLegacy()
        let scopes = UserDefaults.standard.stringArray(forKey: "grantedScopes")
            ?? legacy.scope.components(separatedBy: " ").filter { !$0.isEmpty }.sorted()
        UserDefaults.standard.removeObject(forKey: "grantedScopes")
        sessions = [AuthSessionMeta(id: id, label: String(localized: "Cloudflare 账号"), scopes: scopes)]
        currentSessionId = id
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: Self.sessionsKey)
            if iCloudSyncEnabled {
                NSUbiquitousKeyValueStore.default.set(data, forKey: Self.sessionsKey)
                NSUbiquitousKeyValueStore.default.synchronize()
            }
        }
        // 当前选中身份是设备级状态，不参与同步；同时写入 App Group 供 Widget 定位 token
        UserDefaults.standard.set(currentSessionId?.uuidString, forKey: Self.currentSessionKey)
        UserDefaults(suiteName: WidgetSnapshot.appGroupID)?
            .set(currentSessionId?.uuidString, forKey: Self.currentSessionKey)
    }

    /// 一次性迁移：把既有 token 重存进共享钥匙串组（Widget 可读）
    private func migrateToSharedKeychainGroupIfNeeded() {
        let migrationKey = "keychainSharedGroupMigrated"
        guard !UserDefaults.standard.bool(forKey: migrationKey), !sessions.isEmpty else { return }
        for meta in sessions {
            if let token = TokenStore.load(sessionId: meta.id) {
                TokenStore.save(token, sessionId: meta.id)
            }
        }
        UserDefaults.standard.set(true, forKey: migrationKey)
        persist()   // 顺带写入 App Group 的当前身份指针
    }

    // MARK: - 身份切换

    func switchSession(_ id: UUID) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        currentSessionId = id
        persist()
    }

    /// 账号列表加载后回填真实账号名（与 Dashboard 同源），账号重命名时保持同步
    func updateSessionLabel(_ label: String, for id: UUID) {
        guard !label.isEmpty,
              let index = sessions.firstIndex(where: { $0.id == id }),
              sessions[index].label != label else { return }
        sessions[index].label = label
        persist()
    }

    // MARK: - 登录（新增身份）

    /// 发起 OAuth 登录并作为新身份加入。freshLogin 强制全新登录页（添加第二个身份时
    /// 必须为 true，否则浏览器 Cookie 会自动复用上一个 Cloudflare 登录态）。
    func login(scopeString: String, freshLogin: Bool = false) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let verifier  = PKCEHelper.generateCodeVerifier()
        let challenge = PKCEHelper.generateCodeChallenge(from: verifier)
        let state     = UUID().uuidString

        var components = URLComponents(url: OAuthConfig.authorizationURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type",         value: "code"),
            URLQueryItem(name: "client_id",             value: OAuthConfig.clientID),
            URLQueryItem(name: "redirect_uri",          value: OAuthConfig.redirectURI),
            URLQueryItem(name: "scope",                 value: scopeString),
            URLQueryItem(name: "state",                 value: state),
            URLQueryItem(name: "code_challenge",        value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        do {
            let callbackURL = try await authenticate(with: components.url!, ephemeral: freshLogin)
            let code = try Self.extractCode(from: callbackURL, expectedState: state)
            let token = try await exchangeCodeForToken(code: code, verifier: verifier)

            let id = UUID()
            TokenStore.save(token, sessionId: id)
            let scopes = token.scope.components(separatedBy: " ").filter { !$0.isEmpty }.sorted()
            let label = await fetchIdentityLabel(accessToken: token.accessToken)
                ?? String(localized: "Cloudflare 账号 \(sessions.count + 1)")
            sessions.append(AuthSessionMeta(id: id, label: label, scopes: scopes))
            currentSessionId = id
            persist()
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // 用户主动取消，不算错误
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 打开系统授权窗口，等待 orangecloud:// 回调
    private func authenticate(with url: URL, ephemeral: Bool) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callback: .customScheme(OAuthConfig.callbackScheme)
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? AuthError.invalidCallback)
                }
            }
            session.presentationContextProvider = contextProvider
            session.prefersEphemeralWebBrowserSession = ephemeral
            currentWebSession = session
            session.start()
        }
    }

    /// 从回调 URL 提取授权码并校验 state
    nonisolated private static func extractCode(from callbackURL: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let items = components.queryItems else {
            throw AuthError.invalidCallback
        }
        if let error = items.first(where: { $0.name == "error" })?.value {
            throw AuthError.oauthError(error)
        }
        guard let code = items.first(where: { $0.name == "code" })?.value,
              let state = items.first(where: { $0.name == "state" })?.value else {
            throw AuthError.invalidCallback
        }
        guard state == expectedState else {
            throw AuthError.stateMismatch
        }
        return code
    }

    /// 身份标签：userinfo 端点取邮箱（best-effort）
    private func fetchIdentityLabel(accessToken: String) async -> String? {
        var request = URLRequest(url: OAuthConfig.userInfoURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let info = try? JSONDecoder().decode(UserInfo.self, from: data) else {
            return nil
        }
        return info.email ?? info.name
    }

    nonisolated private struct UserInfo: Codable {
        let email: String?
        let name:  String?
    }

    // MARK: - Token 交换与刷新

    nonisolated private struct TokenResponse: Codable {
        let accessToken:  String
        let expiresIn:    Int
        let refreshToken: String?
        let scope:        String?

        enum CodingKeys: String, CodingKey {
            case accessToken  = "access_token"
            case expiresIn    = "expires_in"
            case refreshToken = "refresh_token"
            case scope
        }
    }

    private func exchangeCodeForToken(code: String, verifier: String) async throws -> TokenStore.StoredToken {
        let response = try await requestToken(parameters: [
            "grant_type":    "authorization_code",
            "client_id":     OAuthConfig.clientID,
            "code":          code,
            "redirect_uri":  OAuthConfig.redirectURI,
            "code_verifier": verifier,
        ])
        return TokenStore.StoredToken(
            accessToken:  response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt:    Date().addingTimeInterval(TimeInterval(response.expiresIn)),
            scope:        response.scope ?? ""
        )
    }

    /// 刷新当前身份的 access_token。并发去重：多个临期/401 请求只触发一次网络刷新，
    /// 否则刷新令牌轮换（每次刷新作废上一枚）会让并发请求互相把令牌作废，导致误登出。
    func refreshAccessToken() async throws -> String {
        if let inFlight = refreshTask {
            return try await inFlight.value
        }
        let task = Task<String, Error> { [weak self] in
            guard let self else { throw AuthError.notLoggedIn }
            return try await self.performTokenRefresh()
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    /// 实际刷新逻辑：仅在刷新令牌确已失效（token 端点 400）时移除该身份；
    /// 网络中断 / 超时 / 5xx / 429 等瞬时失败保留身份并原样抛出，交由调用方稍后重试，
    /// 避免一次网络抖动就把用户登出（其他身份始终不受影响）。
    private func performTokenRefresh() async throws -> String {
        guard let sessionId = currentSessionId,
              let stored = TokenStore.load(sessionId: sessionId) else {
            if let id = currentSessionId {
                removeSession(id)
            }
            throw AuthError.notLoggedIn
        }
        guard let refreshToken = stored.refreshToken else {
            // 没有刷新令牌则无从续期，只能重新授权
            removeSession(sessionId)
            throw AuthError.notLoggedIn
        }
        do {
            let response = try await requestToken(parameters: [
                "grant_type":    "refresh_token",
                "client_id":     OAuthConfig.clientID,
                "refresh_token": refreshToken,
            ])
            let newToken = TokenStore.StoredToken(
                accessToken:  response.accessToken,
                refreshToken: response.refreshToken ?? refreshToken,
                expiresAt:    Date().addingTimeInterval(TimeInterval(response.expiresIn)),
                scope:        response.scope ?? stored.scope
            )
            TokenStore.save(newToken, sessionId: sessionId)
            return newToken.accessToken
        } catch let AuthError.tokenEndpointError(status, _) where status == 400 {
            // OAuth 标准：刷新令牌失效 / 被撤销 / 过期返回 400，确需重新授权
            removeSession(sessionId)
            throw AuthError.notLoggedIn
        }
        // 其它错误（网络 / 超时 / 5xx / 429）：保留身份，原样向上抛出
    }

    private func requestToken(parameters: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: OAuthConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(parameters)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.tokenExchangeFailed(String(localized: "无效响应"))
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AuthError.tokenEndpointError(status: http.statusCode, body: body)
        }
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw AuthError.tokenExchangeFailed(String(localized: "响应解析失败"))
        }
    }

    // MARK: - 退出单个身份

    func logout(sessionId: UUID, revoke: Bool = true) async {
        if revoke, let token = TokenStore.load(sessionId: sessionId) {
            // 尽力撤销，失败不阻塞
            var request = URLRequest(url: OAuthConfig.revokeURL)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.formBody([
                "client_id": OAuthConfig.clientID,
                "token":     token.refreshToken ?? token.accessToken,
            ])
            _ = try? await URLSession.shared.data(for: request)
        }
        removeSession(sessionId)
    }

    private func removeSession(_ id: UUID) {
        TokenStore.clear(sessionId: id)
        sessions.removeAll { $0.id == id }
        if currentSessionId == id {
            currentSessionId = sessions.first?.id
        }
        persist()
        if sessions.isEmpty {
            SpotlightIndexer.deleteAll()
        }
    }

    // MARK: - 工具

    nonisolated private static func formBody(_ parameters: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return parameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)!
    }
}

// MARK: - ASWebAuthenticationSession 展示锚点

@MainActor
private final class WebAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWindow = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return keyWindow
        }
        // 登录界面可见时必然有前台 scene
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
            preconditionFailure("发起 OAuth 时找不到可用的 UIWindowScene")
        }
        return UIWindow(windowScene: scene)
    }
}

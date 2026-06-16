//
//  IdentityDetailView.swift
//  Orange Cloud
//
//  单个登录身份（Cloudflare 账号）详情：授权状态 + 设为当前 + 退出登录。
//  退出只移除此身份；所有身份退出后由 ContentView 自动回到登录页。
//

import SwiftUI

struct IdentityDetailView: View {

    let identity: AuthSessionMeta

    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var showSignOutConfirm = false
    @State private var isSigningOut = false

    private var isCurrent: Bool {
        auth.currentSessionId == identity.id
    }

    /// 此身份的 scope → 功能模块（中文名 + 读写级别）
    private var grantedFeatures: [(title: String, note: String)] {
        FeaturePermission.allFeatures.compactMap { feature in
            let readGranted = feature.readScopes.contains { identity.scopes.contains($0) }
            let editGranted = feature.editScopes.contains { identity.scopes.contains($0) }
            guard readGranted || editGranted else { return nil }
            return (feature.title, editGranted ? String(localized: "读写") : String(localized: "只读"))
        }
    }

    var body: some View {
        List {
            // ── 身份信息 ──
            Section {
                VStack(spacing: 10) {
                    Text(String(identity.label.first ?? "C").uppercased())
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 1, green: 0.65, blue: 0.31), .ocOrangePressed],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            in: Circle()
                        )
                        .accessibilityHidden(true)
                    Text(identity.label)
                        .font(.title3.bold())
                    Label("OAuth 2.0", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            // ── 当前身份 ──
            Section {
                if isCurrent {
                    Label("当前使用中的账号", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button {
                        auth.switchSession(identity.id)
                    } label: {
                        Label("切换到此账号", systemImage: "arrow.right.circle")
                    }
                }
            } footer: {
                Text("Zones、Workers、存储等页面的数据来自当前账号。")
            }
            .glassRow()

            // ── 已授权权限 ──
            Section {
                if grantedFeatures.isEmpty {
                    Text("无权限信息")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(grantedFeatures, id: \.title) { feature in
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(feature.title)
                            Spacer()
                            Text(feature.note)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("已授权权限")
            } footer: {
                Text("权限在登录时授予，无法在 App 内单独修改。如需调整请退出后重新登录，或在 Cloudflare Dashboard → Authorized Applications 中撤销。")
            }
            .glassRow()

            // ── 退出登录 ──
            Section {
                Button(role: .destructive) {
                    showSignOutConfirm = true
                } label: {
                    HStack(spacing: 12) {
                        TintIcon(systemImage: "rectangle.portrait.and.arrow.right", color: .red)
                        Text("退出登录")
                        if isSigningOut {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isSigningOut)
            } footer: {
                Text("仅退出此账号并撤销其授权，其他已登录账号不受影响。")
            }
            .glassRow()
        }
        .daybreakList()
        .navigationTitle(identity.label)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("退出此账号？", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("退出 \(identity.label)", role: .destructive) {
                Task { await signOut() }
            }
        } message: {
            Text(auth.sessions.count <= 1
                 ? String(localized: "这是最后一个账号，退出后将返回登录页。")
                 : String(localized: "此账号的 Token 将被撤销并从 App 移除。"))
        }
    }

    private func signOut() async {
        isSigningOut = true
        await auth.logout(sessionId: identity.id)
        isSigningOut = false
        // 还有其他身份时回设置页；全部退出由 ContentView 切到登录页
        if auth.isLoggedIn {
            dismiss()
        }
    }
}

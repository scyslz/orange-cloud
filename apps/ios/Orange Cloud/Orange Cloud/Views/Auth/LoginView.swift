//
//  LoginView.swift
//  Orange Cloud
//
//  登录欢迎页（晨昏）：天空画布 + 品牌云朵 + 地平线弧 + 橙色胶囊 CTA。
//  点击进入授权范围选择（PermissionSelectionView），OAuth 在那里发起。
//

import SwiftUI

struct LoginView: View {

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SkyBackground()

                VStack(spacing: 0) {
                    Spacer()

                    // 品牌区
                    VStack(spacing: 14) {
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 84))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(red: 1, green: 0.65, blue: 0.31), .ocOrange, .ocOrangePressed],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: Color.ocOrange.opacity(0.34), radius: 14, y: 10)
                            .accessibilityHidden(true)   // 品牌图标装饰，下方有「Orange Cloud」文字

                        Text("Orange Cloud")
                            .font(.system(.largeTitle, weight: .bold))   // 语义字号，随动态字体缩放
                            .foregroundStyle(.primary)

                        Text("Cloudflare 管理客户端")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        HorizonArc()
                            .frame(height: 48)
                            .padding(.horizontal, 36)
                            .padding(.top, 14)
                    }

                    Spacer()
                    Spacer()

                    // 操作区
                    VStack(spacing: 14) {
                        NavigationLink {
                            PermissionSelectionView()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "cloud.fill")
                                Text("使用 Cloudflare 账号登录")
                                    .fontWeight(.bold)
                            }
                            .font(.body)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.ocOrangePressed, in: Capsule())
                            .shadow(color: Color.ocOrange.opacity(0.34), radius: 11, y: 8)
                        }

                        Label {
                            Text("安全 OAuth 2.0 · 无需粘贴 API Token")
                        } icon: {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundStyle(.green)
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                        HStack(spacing: 6) {
                            Text("版本 \(appVersion)")
                            Text("·")
                            Link("隐私政策", destination: URL(string: "https://orange-cloud.chatiro.app/privacy")!)
                            Text("·")
                            Link("使用条款", destination: URL(string: "https://orange-cloud.chatiro.app/terms")!)
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }
            }
        }
        .tint(.ocOrange)
    }
}

#Preview {
    LoginView()
        .environment(AuthManager())
}

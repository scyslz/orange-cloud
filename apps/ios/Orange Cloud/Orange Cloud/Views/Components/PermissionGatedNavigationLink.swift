//
//  PermissionGatedNavigationLink.swift
//  Orange Cloud
//
//  当用户未授权某 scope 时，将 NavigationLink 替换为锁定状态的按钮并弹出权限提示。
//  图标使用设计稿的 TintIcon（彩色圆底）。
//

import SwiftUI

/// 有 scope 则正常导航，无 scope 则显示锁图标并弹出说明。
struct PermissionGatedNavigationLink<Destination: View>: View {

    let label:         String
    let systemImage:   String
    let requiredScope: String
    var tint: Color = .ocOrange
    /// List 内由系统提供 chevron；卡片等自定义容器中置 true 手动绘制
    var showsChevron: Bool = false
    @ViewBuilder let destination: () -> Destination

    @Environment(AuthManager.self) private var auth
    @State private var showDenied = false

    private var rowLabel: some View {
        HStack(spacing: 12) {
            TintIcon(systemImage: systemImage, color: tint)
            Text(label)
                .foregroundStyle(.primary)
            Spacer()
        }
    }

    var body: some View {
        if auth.hasScope(requiredScope) {
            NavigationLink(destination: destination()) {
                HStack {
                    rowLabel
                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        } else {
            Button { showDenied = true } label: {
                HStack {
                    rowLabel
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(.primary)
            .accessibilityHint("已锁定，需要额外授权")
            .alert("权限不足", isPresented: $showDenied) {
                Button("好", role: .cancel) {}
            } message: {
                Text("当前授权未包含「\(label)」的访问权限（\(requiredScope)）。\n请在设置中退出登录后重新授权以启用此功能。")
            }
        }
    }
}

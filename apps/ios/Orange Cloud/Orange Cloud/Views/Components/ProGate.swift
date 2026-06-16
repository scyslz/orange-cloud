//
//  ProGate.swift
//  Orange Cloud
//
//  Pro 付费闸门组件：触发场景枚举（ProFeature）、PRO 徽章、
//  行级闸门（ProGatedNavigationLink，先验 Pro 再走 scope 门控）、整页锁定态（ProLockedView）。
//  免费层 = 单账号 + 域名/DNS 全功能 + 24h 分析；其余场景由 ProFeature 枚举闸门。
//

import SwiftUI

/// 触发付费墙的场景，决定付费墙头部与锁定态文案
nonisolated enum ProFeature: String, Identifiable, Sendable {
    case multiAccount, storage, workerTail, waf, tunnel, analyticsRange, snippets

    var id: String { rawValue }

    var headline: String {
        switch self {
        case .multiAccount:   String(localized: "多账号需要 Pro")
        case .storage:        String(localized: "存储管理需要 Pro")
        case .workerTail:     String(localized: "实时日志需要 Pro")
        case .waf:            String(localized: "WAF 管理需要 Pro")
        case .tunnel:         String(localized: "Tunnel 需要 Pro")
        case .analyticsRange: String(localized: "更长时间范围需要 Pro")
        case .snippets:       String(localized: "Snippets 需要 Pro")
        }
    }

    var blurb: String {
        switch self {
        case .multiAccount:   String(localized: "免费版可登录一个 Cloudflare 账号；Pro 可添加多个账号并快速切换。")
        case .storage:        String(localized: "R2 对象存储、D1 数据库与 KV 键值管理属于 Orange Cloud Pro。")
        case .workerTail:     String(localized: "Workers 实时日志与灵动岛 Live Activity 属于 Orange Cloud Pro。")
        case .waf:            String(localized: "查看与启停 WAF 自定义规则属于 Orange Cloud Pro。")
        case .tunnel:         String(localized: "Cloudflare Tunnel 状态查看属于 Orange Cloud Pro。")
        case .analyticsRange: String(localized: "7 天与 30 天流量分析属于 Pro；24 小时视图永久免费。")
        case .snippets:       String(localized: "查看与管理域名的边缘 Snippets（JS 代码片段）属于 Orange Cloud Pro。")
        }
    }

    var systemImage: String {
        switch self {
        case .multiAccount:   "person.2"
        case .storage:        "externaldrive"
        case .workerTail:     "text.alignleft"
        case .waf:            "shield"
        case .tunnel:         "arrow.triangle.2.circlepath"
        case .analyticsRange: "chart.xyaxis.line"
        case .snippets:       "curlybraces"
        }
    }
}

/// 橙色 PRO 胶囊徽章
struct ProBadge: View {
    var body: some View {
        Text(verbatim: "PRO")
            .font(.caption2.weight(.heavy))
            .foregroundStyle(Color.ocOrangeText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.ocOrange.opacity(0.14), in: Capsule())
    }
}

/// 行级 Pro 闸门：已解锁则退化为既有的 scope 门控导航行；未解锁显示 PRO 徽章并弹付费墙。
struct ProGatedNavigationLink<Destination: View>: View {

    let label:         String
    let systemImage:   String
    let requiredScope: String
    let feature:       ProFeature
    var tint: Color = .ocOrange
    var showsChevron: Bool = false
    @ViewBuilder let destination: () -> Destination

    @Environment(EntitlementStore.self) private var entitlements
    @State private var paywallPresented = false

    var body: some View {
        if entitlements.isPro {
            PermissionGatedNavigationLink(
                label: label,
                systemImage: systemImage,
                requiredScope: requiredScope,
                tint: tint,
                showsChevron: showsChevron,
                destination: destination
            )
        } else {
            Button {
                paywallPresented = true
            } label: {
                HStack(spacing: 12) {
                    TintIcon(systemImage: systemImage, color: tint)
                    Text(label)
                        .foregroundStyle(.primary)
                    Spacer()
                    ProBadge()
                }
            }
            .foregroundStyle(.primary)
            .sheet(isPresented: $paywallPresented) {
                PaywallView(feature: feature)
            }
        }
    }
}

/// 整页锁定态（如存储 Tab）：占满内容区的 Pro 介绍 + 付费墙入口
struct ProLockedView: View {

    let feature: ProFeature

    @State private var paywallPresented = false

    var body: some View {
        ContentUnavailableView {
            Label(feature.headline, systemImage: feature.systemImage)
        } description: {
            Text(feature.blurb)
        } actions: {
            Button {
                paywallPresented = true
            } label: {
                Label(String(localized: "了解 Orange Cloud Pro"), systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.ocOrangePressed)
            .fontWeight(.bold)
        }
        .sheet(isPresented: $paywallPresented) {
            PaywallView(feature: feature)
        }
    }
}

#Preview("锁定态") {
    ProLockedView(feature: .storage)
        .environment(EntitlementStore.shared)
}

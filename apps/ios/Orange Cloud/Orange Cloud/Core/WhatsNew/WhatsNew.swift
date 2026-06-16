//
//  WhatsNew.swift
//  Orange Cloud
//
//  版本更新后的「新功能」展示：内容按版本curated，启动后比对 lastSeen 决定是否弹。
//  新增一个版本只需往 WhatsNewContent.releases 追加一条（version 用 MARKETING_VERSION）。
//

import Foundation

nonisolated struct WhatsNewItem: Identifiable, Sendable {
    let id = UUID()
    let icon:   String
    let title:  String
    let detail: String
}

nonisolated struct WhatsNewRelease: Sendable {
    let version: String
    let items:   [WhatsNewItem]
}

nonisolated enum WhatsNewContent {
    static let releases: [WhatsNewRelease] = [
        WhatsNewRelease(version: "1.2.0", items: [
            WhatsNewItem(
                icon:   "accessibility",
                title:  String(localized: "全面无障碍"),
                detail: String(localized: "VoiceOver、更大字体、不只靠颜色区分、足够对比度全面达标，配合系统辅助功能更顺手。")
            ),
        ]),
        WhatsNewRelease(version: "1.1.0", items: [
            WhatsNewItem(
                icon:   "curlybraces",
                title:  String(localized: "Snippets"),
                detail: String(localized: "在域名详情查看、编辑、新建 Cloudflare 边缘代码片段，并管理触发规则——轻量版 Workers，Pro 解锁。")
            ),
        ]),
    ]
}

nonisolated enum WhatsNewStore {

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// 数值分段比较：a 是否比 b 新（"1.1.0" > "1.0.1"，"1.10" > "1.9"）
    static func isNewer(_ a: String, than b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedDescending
    }

    /// (seen, current] 区间内所有版本的新功能，新版在前
    static func items(after seen: String, upTo current: String) -> [WhatsNewItem] {
        WhatsNewContent.releases
            .filter { isNewer($0.version, than: seen) && !isNewer($0.version, than: current) }
            .sorted { isNewer($0.version, than: $1.version) }
            .flatMap(\.items)
    }
}

/// 启动时拍一张「是否已登录」的快照，用于区分老用户升级 vs 全新安装：
/// 老用户升级到首个带 What's New 的版本（lastSeen 为空但启动即已登录）要补看一次；
/// 全新安装首次登录后不打扰。由 App.init 在创建 AuthManager 后写入。
enum WhatsNewGate {
    static var wasLoggedInAtLaunch = false
}

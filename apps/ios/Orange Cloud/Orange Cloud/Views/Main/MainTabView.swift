//
//  MainTabView.swift
//  Orange Cloud
//
//  iPhone 底部 Tab，iPad 自动侧边栏（sidebarAdaptable）；iOS 26 自动 Liquid Glass TabBar。
//

import SwiftUI

struct MainTabView: View {

    @Environment(SessionStore.self) private var session
    @Environment(AuthManager.self) private var auth
    @State private var selectedTab: AppTab = .dashboard
    private let router = AppRouter.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            // 各资源 Tab 用 .id(selectedAccount) 绑定当前账号：账号切换时整页重建，
            // 让按账号过滤的 @Query 谓词刷新、列表数据重新拉取（资源跟着选中账号走）。
            Tab("概览", systemImage: "square.grid.2x2", value: .dashboard) {
                DashboardView(session: session)
                    .id(session.selectedAccount?.id)
            }
            Tab("域名", systemImage: "globe", value: .zones) {
                ZoneListView(session: session)
                    .id(session.selectedAccount?.id)
            }
            Tab("Workers", systemImage: "bolt.fill", value: .workers) {
                // Tab 恒显示（可发现性），无权限时整页锁定态
                if auth.hasScope("workers-scripts.read") {
                    WorkerListView(session: session)
                        .id(session.selectedAccount?.id)
                } else {
                    NavigationStack {
                        PermissionDeniedView(
                            featureName: "Workers",
                            requiredScope: "workers-scripts.read"
                        )
                        .navigationTitle("Workers")
                    }
                }
            }
            Tab("存储", systemImage: "externaldrive", value: .storage) {
                StorageView(session: session)
                    .id(session.selectedAccount?.id)
            }
            Tab("设置", systemImage: "gear", value: .settings) {
                SettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .task {
            consumePendingRoute()
            await session.ensureAccounts()
        }
        .onChange(of: router.pendingModule) {
            consumePendingRoute()
        }
    }

    /// App Intent（Siri/快捷指令/Spotlight）发起的跳转
    private func consumePendingRoute() {
        guard let module = router.pendingModule else { return }
        router.pendingModule = nil
        selectedTab = switch module {
        case .dashboard: .dashboard
        case .zones:     .zones
        case .workers:   .workers
        case .storage:   .storage
        case .settings:  .settings
        }
    }

    enum AppTab: Hashable {
        case dashboard, zones, workers, storage, settings
    }
}

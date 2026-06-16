//
//  ZoneListView.swift
//  Orange Cloud
//
//  Zones 列表：
//  - iPhone（compact）：NavigationStack + 卡片 + zoom 过渡
//  - iPad（regular）：NavigationSplitView 双栏（P5）
//

import SwiftUI
import SwiftData
import TipKit

struct ZoneListView: View {

    @Environment(SessionStore.self) private var session
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query private var cachedZones: [CachedZone]

    @State private var viewModel: ZoneListViewModel
    @State private var searchText = ""
    @State private var selectedZone: CachedZone?
    @Namespace private var namespace

    init(session: SessionStore) {
        // 只读当前账号的域名；父视图用 .id(selectedAccount) 在切换账号时重建以刷新谓词。
        let accountId = session.selectedAccount?.id ?? ""
        _cachedZones = Query(
            filter: #Predicate<CachedZone> { $0.accountId == accountId },
            sort: \CachedZone.name
        )
        _viewModel = State(initialValue: ZoneListViewModel(zoneService: session.zoneService))
    }

    private var filteredZones: [CachedZone] {
        guard !searchText.isEmpty else { return cachedZones }
        return cachedZones.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var activeCount: Int {
        cachedZones.filter { $0.status == "active" }.count
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                splitLayout
            } else {
                stackLayout
            }
        }
        .task {
            await refresh()
        }
        .alert("加载失败", isPresented: .init(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }

    // MARK: - iPad 双栏（regular）

    private var splitLayout: some View {
        NavigationSplitView {
            Group {
                if cachedZones.isEmpty && viewModel.isLoading {
                    SkeletonList(rows: 8, icon: .circle(30), trailing: true)
                } else if cachedZones.isEmpty {
                    emptyState
                } else if filteredZones.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List(selection: $selectedZone) {
                        Section {
                            ForEach(filteredZones) { zone in
                                ZoneSidebarRow(zone: zone)
                                    .tag(zone)
                            }
                        } header: {
                            Text("\(cachedZones.count) 个域名 · \(activeCount) 个已启用")
                        }
                    }
                    .refreshable { await refresh() }
                }
            }
            .navigationTitle("域名")
            .searchable(text: $searchText, prompt: "搜索域名")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    refreshButton
                }
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 340)
        } detail: {
            if let zone = selectedZone {
                NavigationStack {
                    ZoneDetailView(zone: zone, session: session)
                }
            } else {
                ContentUnavailableView("选择一个域名", systemImage: "globe", description: Text("从左侧列表选择域名查看详情"))
            }
        }
    }

    // MARK: - iPhone 单栏（compact）

    private var stackLayout: some View {
        NavigationStack {
            Group {
                if cachedZones.isEmpty && viewModel.isLoading {
                    SkeletonCardList()
                } else if cachedZones.isEmpty {
                    emptyState
                } else if filteredZones.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    zoneList
                }
            }
            .background { SkyBackground() }
            .navigationTitle("域名")
            .searchable(text: $searchText, prompt: "搜索域名")
            .navigationDestination(for: CachedZone.self) { zone in
                ZoneDetailView(zone: zone, session: session)
                    .zoomNavigationTransition(sourceID: zone.id, in: namespace)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    refreshButton
                }
            }
        }
    }

    private var zoneList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: OCLayout.islandGap) {
                // 大标题下的统计副标题（设计稿 oc-subtitle）
                Text("\(cachedZones.count) 个域名 · \(activeCount) 个已启用")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                TipView(ZoneRefreshTip())
                ForEach(filteredZones) { zone in
                    NavigationLink(value: zone) {
                        ZoneCard(zone: zone, accountName: session.selectedAccount?.name ?? "")
                    }
                    .buttonStyle(.plain)
                    .zoomTransitionSource(id: zone.id, in: namespace)
                }
            }
            .padding(OCLayout.pagePadding)
        }
        .refreshable {
            await refresh()
        }
    }

    // MARK: - 共用

    private var refreshButton: some View {
        Button("刷新", systemImage: "arrow.clockwise") {
            Task { await refresh() }
        }
        .loadingSpinSymbolEffect(isActive: viewModel.isLoading)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("没有域名", systemImage: "globe.slash")
        } description: {
            Text("当前账号下还没有域名，去 Cloudflare 添加一个吧")
        } actions: {
            Button("刷新") {
                Task { await refresh() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.ocOrangePressed)
            .fontWeight(.bold)
        }
    }

    private func refresh() async {
        await session.ensureAccounts()
        guard let account = session.selectedAccount else { return }
        await viewModel.refresh(accountId: account.id, accountName: account.name, context: modelContext)
    }
}

// MARK: - iPad 侧栏行

private struct ZoneSidebarRow: View {
    let zone: CachedZone

    var body: some View {
        HStack(spacing: 10) {
            ZoneAvatar(domain: zone.name, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(zone.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                PlanBadge(planName: zone.planName)
            }
            Spacer()
            StatusDot(status: zone.status, size: 7)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Zone 卡片（iPhone）

struct ZoneCard: View {
    let zone: CachedZone
    var accountName: String = ""

    var body: some View {
        HStack(spacing: 12) {
            ZoneAvatar(domain: zone.name, size: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(zone.name)
                        .font(.headline)
                        .lineLimit(1)
                    PlanBadge(planName: zone.planName)
                }
                if !accountName.isEmpty {
                    Text(accountName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            StatusDot(status: zone.status)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(OCLayout.islandPadding)
        .glassIsland()
    }
}

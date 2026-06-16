//
//  WorkerListView.swift
//  Orange Cloud
//
//  Workers 列表（设计稿 workers.jsx）：
//  bolt 圆底图标 + mono 名称 + handlers 副标题 + 相对部署时间，左滑直达实时日志。
//

import SwiftUI
import SwiftData

struct WorkerListView: View {

    @Environment(SessionStore.self) private var session
    @Environment(AuthManager.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Query private var cachedScripts: [CachedWorkerScript]

    @State private var viewModel: WorkerListViewModel
    @State private var searchText = ""
    @State private var tailTarget: CachedWorkerScript?
    @State private var showTailDenied = false
    @Namespace private var namespace

    init(session: SessionStore) {
        // 只读当前账号的脚本（多账号切换后缓存里会留有别的账号的条目）。
        // 父视图用 .id(selectedAccount) 在切换账号时重建本视图，让谓词跟着更新。
        let accountId = session.selectedAccount?.id ?? ""
        _cachedScripts = Query(
            filter: #Predicate<CachedWorkerScript> { $0.accountId == accountId },
            sort: \CachedWorkerScript.id
        )
        _viewModel = State(initialValue: WorkerListViewModel(workerService: session.workerService))
    }

    private var filteredScripts: [CachedWorkerScript] {
        guard !searchText.isEmpty else { return cachedScripts }
        return cachedScripts.filter { $0.id.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if cachedScripts.isEmpty && viewModel.isLoading {
                    SkeletonList(rows: 8, trailing: true)
                } else if cachedScripts.isEmpty {
                    emptyState
                } else if filteredScripts.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    scriptList
                }
            }
            .background { SkyBackground() }
            .navigationTitle("Workers")
            .searchable(text: $searchText, prompt: "搜索脚本")
            .navigationDestination(for: CachedWorkerScript.self) { script in
                WorkerDetailView(script: script, session: session)
                    .zoomNavigationTransition(sourceID: script.key, in: namespace)
            }
            .navigationDestination(item: $tailTarget) { script in
                WorkerTailView(accountId: script.accountId, scriptName: script.id, session: session)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("刷新", systemImage: "arrow.clockwise") {
                        Task { await refresh() }
                    }
                    .loadingSpinSymbolEffect(isActive: viewModel.isLoading)
                }
            }
            .task {
                await refresh()
            }
            .alert("权限不足", isPresented: $showTailDenied) {
                Button("好", role: .cancel) {}
            } message: {
                Text("当前授权未包含实时日志权限（workers-tail.read）。\n请在设置中退出登录后重新授权以启用此功能。")
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
    }

    private var scriptList: some View {
        List {
            Section {
                ForEach(filteredScripts) { script in
                    NavigationLink(value: script) {
                        WorkerRow(script: script)
                    }
                    .zoomTransitionSource(id: script.key, in: namespace)
                    .swipeActions(edge: .trailing) {
                        Button {
                            if auth.hasScope("workers-tail.read") {
                                tailTarget = script
                            } else {
                                showTailDenied = true
                            }
                        } label: {
                            Label("查看日志", systemImage: "text.alignleft")
                        }
                        .tint(Color.ocOrange)
                    }
                }
            } header: {
                Text("\(cachedScripts.count) 个 Worker")
            } footer: {
                Label("向左滑动查看实时日志 · 点按查看详情", systemImage: "hand.draw")
                    .font(.caption)
            }
            .glassRow()
        }
        .scrollContentBackground(.hidden)
        .refreshable {
            await refresh()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("没有 Workers", systemImage: "bolt.slash")
        } description: {
            Text("在 Cloudflare Dashboard 部署你的第一个 Worker")
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
        guard let accountId = session.selectedAccount?.id else { return }
        await viewModel.refresh(accountId: accountId, context: modelContext)
    }
}

// MARK: - Worker 行（设计稿 WorkerRow）

struct WorkerRow: View {
    let script: CachedWorkerScript

    var body: some View {
        HStack(spacing: 12) {
            TintIcon(systemImage: "bolt.fill", color: .ocOrange, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(script.id)
                    .font(.callout.weight(.semibold).monospaced())
                    .lineLimit(1)
                if !script.handlers.isEmpty {
                    Text(script.handlers.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let modified = WorkerScript.parseDate(script.modifiedOn) {
                Text(modified, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

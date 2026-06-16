//
//  WAFRuleListView.swift
//  Orange Cloud
//
//  WAF 自定义规则：查看 / 新建 / 删除 / 启停，写操作按 zone-waf.write 门控。
//

import SwiftUI

struct WAFRuleListView: View {

    let zoneName: String

    @Environment(AuthManager.self) private var auth
    @State private var viewModel: WAFRulesViewModel
    @State private var showDenied = false
    @State private var showForm = false
    @State private var ruleToDelete: WAFRule?

    init(zoneId: String, zoneName: String, session: SessionStore) {
        self.zoneName = zoneName
        _viewModel = State(initialValue: WAFRulesViewModel(service: session.wafService, zoneId: zoneId))
    }

    private var canWrite: Bool { auth.hasScope("zone-waf.write") }

    var body: some View {
        Group {
            if viewModel.isLoading && !viewModel.loaded {
                SkeletonList(rows: 6, icon: .none, trailing: true)
            } else if viewModel.rules.isEmpty {
                ContentUnavailableView {
                    Label("没有自定义规则", systemImage: "shield")
                } description: {
                    Text(canWrite
                         ? String(localized: "点击右上角 + 创建第一条防火墙规则")
                         : String(localized: "在 Cloudflare Dashboard → 安全性 → WAF 中创建自定义规则"))
                } actions: {
                    if canWrite {
                        Button("添加规则") { showForm = true }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.ocOrangePressed)
                            .fontWeight(.bold)
                    }
                }
            } else {
                List {
                    Section {
                        ForEach(viewModel.rules) { rule in
                            WAFRuleRow(
                                rule: rule,
                                canWrite: canWrite,
                                isToggling: viewModel.togglingRuleId == rule.id,
                                onToggle: { enabled in
                                    Task { await viewModel.toggle(rule: rule, enabled: enabled) }
                                },
                                onDenied: { showDenied = true }
                            )
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    if canWrite {
                                        ruleToDelete = rule
                                    } else {
                                        showDenied = true
                                    }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    } footer: {
                        Text(canWrite
                             ? String(localized: "规则按从上到下的顺序执行，左滑可删除。")
                             : String(localized: "当前授权仅限读取（zone-waf.read），无法修改规则。"))
                    }
                    .glassRow()
                }
                .scrollContentBackground(.hidden)
                .refreshable { await viewModel.load() }
            }
        }
        .background { SkyBackground() }
        .navigationTitle("WAF 防火墙")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("添加", systemImage: "plus") {
                    if canWrite {
                        showForm = true
                    } else {
                        showDenied = true
                    }
                }
            }
        }
        .sheet(isPresented: $showForm) {
            WAFRuleFormView(viewModel: viewModel)
        }
        .task { await viewModel.load() }
        .confirmationDialog(
            "删除规则",
            isPresented: .init(
                get: { ruleToDelete != nil },
                set: { if !$0 { ruleToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let rule = ruleToDelete {
                Button("删除「\(rule.description ?? String(localized: "未命名规则"))」", role: .destructive) {
                    Task { await viewModel.delete(rule: rule) }
                }
            }
        } message: {
            Text("此操作不可撤销，规则将立即停止生效。")
        }
        .alert("权限不足", isPresented: $showDenied) {
            Button("好", role: .cancel) {}
        } message: {
            Text("当前授权未包含 WAF 编辑权限（zone-waf.write）。\n请在设置中退出登录后重新授权以启用此功能。")
        }
        .alert("出错了", isPresented: .init(
            get: { viewModel.error != nil && !showForm },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
    }
}

// MARK: - 新建规则表单

private struct WAFRuleFormView: View {

    let viewModel: WAFRulesViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var action: WAFRuleAction = .block
    @State private var expression = ""
    @State private var enabled = true

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !viewModel.isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("规则") {
                    TextField("规则名称", text: $name)
                    Picker("动作", selection: $action) {
                        ForEach(WAFRuleAction.allCases) { action in
                            Text(action.label).tag(action)
                        }
                    }
                    Toggle("启用", isOn: $enabled)
                }

                Section {
                    TextEditor(text: $expression)
                        .font(.callout.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minHeight: 100)
                } header: {
                    Text("表达式")
                } footer: {
                    Text("Cloudflare Rules 语言，例如：\n(http.request.uri.path contains \"/admin\") or (ip.src eq 198.51.100.4)")
                }

                if let error = viewModel.error {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("新建规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if viewModel.isSaving {
                            ProgressView()
                        } else {
                            Text("保存").fontWeight(.semibold)
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(viewModel.isSaving)
        }
    }

    private func save() async {
        viewModel.error = nil
        let draft = WAFRuleCreate(
            action: action.rawValue,
            expression: expression.trimmingCharacters(in: .whitespacesAndNewlines),
            description: name.trimmingCharacters(in: .whitespaces),
            enabled: enabled
        )
        if await viewModel.addRule(draft) {
            dismiss()
        }
    }
}

// MARK: - 规则行

private struct WAFRuleRow: View {

    let rule: WAFRule
    let canWrite: Bool
    let isToggling: Bool
    let onToggle: (Bool) -> Void
    let onDenied: () -> Void

    private var actionColor: Color {
        switch rule.action {
        case "block":                                    .red
        case "challenge", "managed_challenge", "js_challenge": .orange
        case "log":                                      .blue
        case "allow", "skip":                            .green
        default:                                         .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(rule.description ?? String(localized: "未命名规则"))
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(rule.actionText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(actionColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(actionColor.opacity(0.14), in: Capsule())
                if isToggling {
                    ProgressView()
                        .controlSize(.small)
                } else if canWrite {
                    Toggle("", isOn: Binding(
                        get: { rule.enabled ?? true },
                        set: { onToggle($0) }
                    ))
                    .labelsHidden()
                    .accessibilityLabel("启用规则")
                } else {
                    Button {
                        onDenied()
                    } label: {
                        Image(systemName: (rule.enabled ?? true) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle((rule.enabled ?? true) ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel((rule.enabled ?? true) ? "已启用" : "已停用")
                    .accessibilityHint("需要写入权限才能修改")
                }
            }
            if let expression = rule.expression {
                Text(expression)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 4)
        .opacity((rule.enabled ?? true) ? 1 : 0.5)
    }
}

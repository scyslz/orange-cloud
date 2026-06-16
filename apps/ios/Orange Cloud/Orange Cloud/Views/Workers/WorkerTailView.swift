//
//  WorkerTailView.swift
//  Orange Cloud
//
//  实时日志控制台：连接状态条、等宽日志行、自动滚底、暂停/清屏。
//

import SwiftUI
import TipKit

struct WorkerTailView: View {

    @State private var viewModel: WorkerTailViewModel

    init(accountId: String, scriptName: String, session: SessionStore) {
        _viewModel = State(initialValue: WorkerTailViewModel(
            service: session.workerTailService,
            accountId: accountId,
            scriptName: scriptName
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider()
            logConsole
        }
        .navigationTitle("实时日志")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(
                    viewModel.isPaused ? String(localized: "继续") : String(localized: "暂停"),
                    systemImage: viewModel.isPaused ? "play.fill" : "pause.fill"
                ) {
                    viewModel.isPaused.toggle()
                }
                .popoverTip(TailPauseTip())
                Button("清屏", systemImage: "xmark.bin") {
                    viewModel.clear()
                }
                .disabled(viewModel.lines.isEmpty)
            }
        }
        .task {
            await viewModel.start()
        }
        .onDisappear {
            Task { await viewModel.stop() }
        }
    }

    // MARK: - 连接状态条

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            if case .disconnected = viewModel.state {
                Button("重新连接") {
                    Task { await viewModel.start() }
                }
                .font(.footnote)
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(Color.ocOrange)
            }
            if viewModel.isPaused {
                Label("已暂停", systemImage: "pause.fill")
                    .font(.caption)
                    .foregroundStyle(Color.ocOrangeText)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private var statusColor: Color {
        switch viewModel.state {
        case .connected:    .green
        case .connecting:   .orange
        case .idle:         .gray
        case .disconnected: .red
        }
    }

    private var statusText: String {
        switch viewModel.state {
        case .idle:                      String(localized: "未连接")
        case .connecting:                String(localized: "连接中…")
        case .connected:                 String(localized: "已连接，等待事件")
        case .disconnected(let reason):  reason ?? String(localized: "连接已断开")
        }
    }

    // MARK: - 日志控制台

    private var logConsole: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.lines.isEmpty {
                    emptyHint
                } else {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(viewModel.lines) { line in
                            LogLineRow(line: line)
                                .id(line.id)
                        }
                    }
                    .padding(12)
                }
            }
            .background { SkyBackground() }
            .onChange(of: viewModel.lines.count) {
                guard !viewModel.isPaused, let last = viewModel.lines.last else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var emptyHint: some View {
        ContentUnavailableView {
            Label("等待事件", systemImage: "dot.radiowaves.left.and.right")
        } description: {
            Text("向这个 Worker 发起一次请求，日志会实时出现在这里")
        }
        .padding(.top, 60)
    }
}

// MARK: - 单条日志行

private struct LogLineRow: View {
    let line: WorkerTailViewModel.LogLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(line.timestamp, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)

            Text(line.text)
                .font(.caption.monospaced())
                .foregroundStyle(levelColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
    }

    private var levelColor: Color {
        switch line.level {
        case "error", "exception": .red
        case "warn":               .orange
        case "event":              .secondary
        default:                   .primary
        }
    }
}

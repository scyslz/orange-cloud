//
//  WhatsNewView.swift
//  Orange Cloud
//
//  「新功能」弹窗（晨昏风），及 .whatsNewSheet() 触发修饰器。
//  修饰器挂在登录后的 MainTabView 上，只在版本更新且有 curated 内容时弹一次。
//

import SwiftUI

struct WhatsNewView: View {

    let items: [WhatsNewItem]
    let onContinue: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 32) {
                    VStack(spacing: 6) {
                        Text("新功能")
                            .font(.largeTitle.weight(.bold))
                        Text("版本 \(WhatsNewStore.currentVersion)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 56)

                    VStack(alignment: .leading, spacing: 26) {
                        ForEach(items) { item in
                            HStack(alignment: .top, spacing: 16) {
                                Image(systemName: item.icon)
                                    .font(.title)
                                    .foregroundStyle(Color.ocOrange)
                                    .frame(width: 42, alignment: .center)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(.headline)
                                    Text(item.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
            }

            Button {
                onContinue()
                dismiss()
            } label: {
                Text("继续")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.ocOrangePressed)
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background { SkyBackground().ignoresSafeArea() }
        .interactiveDismissDisabled()   // 必须点「继续」，确保 lastSeen 被写入
    }
}

// MARK: - 触发修饰器

extension View {
    /// 登录后的主界面挂这个：版本更新且有未看过的新功能时弹一次「新功能」。
    func whatsNewSheet() -> some View { modifier(WhatsNewModifier()) }
}

private struct WhatsNewModifier: ViewModifier {

    /// 呈现与内容绑定到同一个值：sheet 内容闭包始终拿到 evaluate() 算好的条目。
    /// 旧写法用 .sheet(isPresented:) + 旁路 @State 存条目，两者在同一拍一起改时，
    /// iOS 17 的内容闭包会捕获到赋值生效前一拍的空数组——弹窗弹出但条目全空
    /// （iOS 18 正常）。改用 .sheet(item:) 让「弹」与「内容」原子绑定，跨版本一致。
    private struct Payload: Identifiable {
        let id = UUID()
        let items: [WhatsNewItem]
    }

    @AppStorage("lastSeenWhatsNewVersion") private var lastSeen = ""
    @State private var payload: Payload?

    func body(content: Content) -> some View {
        content
            .task { evaluate() }
            .sheet(item: $payload) { payload in
                WhatsNewView(items: payload.items) {
                    lastSeen = WhatsNewStore.currentVersion
                }
            }
    }

    private func evaluate() {
        guard payload == nil else { return }
        let current = WhatsNewStore.currentVersion

        // 全新安装（无 lastSeen 且本次启动并非已登录态）：静默对齐，不打扰新用户
        if lastSeen.isEmpty && !WhatsNewGate.wasLoggedInAtLaunch {
            lastSeen = current
            return
        }

        // 老用户升级到首个带 What's New 的版本时 lastSeen 为空，用 "0" 兜底展示全部 ≤ current
        let baseline = lastSeen.isEmpty ? "0" : lastSeen
        let unseen = WhatsNewStore.items(after: baseline, upTo: current)
        if unseen.isEmpty {
            lastSeen = current          // 版本升了但无可展示内容：对齐，避免反复评估
        } else {
            payload = Payload(items: unseen)   // 内容与呈现同时确定，避免 iOS 17 捕获旧值
        }
    }
}

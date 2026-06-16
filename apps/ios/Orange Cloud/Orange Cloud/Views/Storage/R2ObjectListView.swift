//
//  R2ObjectListView.swift
//  Orange Cloud
//
//  R2 对象列表（上传/删除/游标分页）→ 对象详情（QuickLook 预览）。
//  入口：StorageView 的 R2 段。
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import QuickLook

struct R2ObjectListView: View {

    let bucket: R2Bucket

    @Environment(SessionStore.self) private var session
    @Environment(AuthManager.self) private var auth
    @State private var viewModel: R2ObjectListViewModel
    @State private var selectedObject: R2Object?
    @State private var objectToDelete: R2Object?
    @State private var showDenied = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var previewURL: URL?

    init(bucket: R2Bucket, session: SessionStore) {
        self.bucket = bucket
        _viewModel = State(initialValue: R2ObjectListViewModel(
            service: session.r2Service,
            accountId: session.selectedAccount?.id ?? "",
            bucketName: bucket.name
        ))
    }

    private var canWrite: Bool { auth.hasScope("workers-r2.write") }

    var body: some View {
        Group {
            if viewModel.objects.isEmpty && viewModel.isLoading {
                SkeletonList(rows: 9, trailing: true)
            } else if viewModel.objects.isEmpty {
                ContentUnavailableView {
                    Label("空存储桶", systemImage: "archivebox")
                } description: {
                    Text(canWrite ? String(localized: "点击右上角上传第一个文件") : String(localized: "这个存储桶里还没有对象"))
                }
            } else {
                objectList
            }
        }
        .background { SkyBackground() }
        .navigationTitle(bucket.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isUploading {
                    ProgressView()
                } else {
                    Menu {
                        if canWrite {
                            Button {
                                showPhotoPicker = true
                            } label: {
                                Label("上传照片或视频", systemImage: "photo")
                            }
                            Button {
                                showFileImporter = true
                            } label: {
                                Label("上传文件", systemImage: "doc")
                            }
                        } else {
                            Button {
                                showDenied = true
                            } label: {
                                Label("需要 R2 写权限", systemImage: "lock")
                            }
                        }
                    } label: {
                        Label("上传", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .any(of: [.images, .videos]))
        .quickLookPreview($previewURL)
        .overlay {
            if viewModel.isDownloading {
                ZStack {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProgressView("下载中…")
                        .padding(18)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .task { await viewModel.load() }
        .onChange(of: photoItem) {
            guard let item = photoItem else { return }
            photoItem = nil
            guard canWrite else { showDenied = true; return }
            Task { await uploadPhoto(item) }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { result in
            guard canWrite else { showDenied = true; return }
            if case .success(let url) = result {
                Task { await uploadFile(url) }
            }
        }
        .sheet(item: $selectedObject) { object in
            R2ObjectDetailView(object: object, viewModel: viewModel, canWrite: canWrite)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "删除对象",
            isPresented: .init(
                get: { objectToDelete != nil },
                set: { if !$0 { objectToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let object = objectToDelete {
                Button("删除 \(object.key)", role: .destructive) {
                    Task { _ = await viewModel.delete(key: object.key) }
                }
            }
        } message: {
            Text("此操作不可撤销。")
        }
        .alert("权限不足", isPresented: $showDenied) {
            Button("好", role: .cancel) {}
        } message: {
            Text("当前授权未包含 R2 写权限（workers-r2.write）。\n请在设置中退出登录后重新授权以启用此功能。")
        }
        .alert("出错了", isPresented: .init(
            get: { viewModel.error != nil && selectedObject == nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "")
        }
        .sensoryFeedback(.success, trigger: viewModel.didUpload)
    }

    /// 可预览：50 MB 以内（QuickLook 需要完整下载）
    private func previewable(_ object: R2Object) -> Bool {
        (object.size ?? 0) <= 50_000_000
    }

    /// 点击对象：可预览的直接下载打开，超限的退回详情页
    private func open(_ object: R2Object) {
        guard previewable(object) else {
            selectedObject = object
            return
        }
        guard !viewModel.isDownloading else { return }
        Task {
            previewURL = await viewModel.downloadToTemp(object: object)
        }
    }

    private var objectList: some View {
        List {
            ForEach(viewModel.objects) { object in
                HStack(spacing: 8) {
                    Button {
                        open(object)
                    } label: {
                        R2ObjectRow(object: object)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.primary)

                    Button {
                        selectedObject = object
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Color.ocOrangeText)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("详细信息")
                }
                .contextMenu {
                    if previewable(object) {
                        Button {
                            open(object)
                        } label: {
                            Label("预览", systemImage: "eye")
                        }
                    }
                    Button {
                        selectedObject = object
                    } label: {
                        Label("详情", systemImage: "info.circle")
                    }
                    Button(role: .destructive) {
                        if canWrite {
                            objectToDelete = object
                        } else {
                            showDenied = true
                        }
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        if canWrite {
                            objectToDelete = object
                        } else {
                            showDenied = true
                        }
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
                .glassRow()
            }
            if viewModel.hasMore {
                Button {
                    Task { await viewModel.loadMore() }
                } label: {
                    if viewModel.isLoadingMore {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("加载更多").frame(maxWidth: .infinity)
                    }
                }
                .glassRow()
            }
        }
        .scrollContentBackground(.hidden)
        .refreshable { await viewModel.load() }
    }

    // MARK: - 上传

    private func uploadPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let type = item.supportedContentTypes.first
        let ext = type?.preferredFilenameExtension ?? "bin"
        let mime = type?.preferredMIMEType ?? "application/octet-stream"
        let name = "upload-\(Date().formatted(.iso8601.year().month().day().timeSeparator(.omitted).time(includingFractionalSeconds: false))).\(ext)"
        _ = await viewModel.upload(data: data, filename: name, contentType: mime)
    }

    private func uploadFile(_ url: URL) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        _ = await viewModel.upload(data: data, filename: url.lastPathComponent, contentType: mime)
    }
}

private struct R2ObjectRow: View {
    let object: R2Object

    private var icon: String {
        let ext = (object.key as NSString).pathExtension.lowercased()
        if let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .image) { return "photo" }
            if type.conforms(to: .movie) || type.conforms(to: .video) { return "film" }
            if type.conforms(to: .audio) { return "waveform" }
            if type.conforms(to: .pdf) { return "doc.richtext" }
            if type.conforms(to: .text) { return "doc.text" }
        }
        return "doc"
    }

    var body: some View {
        HStack(spacing: 12) {
            TintIcon(systemImage: icon, color: .ocOrange, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(object.key)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    if let size = object.size {
                        Text(Int64(size).formatted(.byteCount(style: .file)))
                    }
                    if let modified = WorkerScript.parseDate(object.lastModified) {
                        Text(modified, format: .relative(presentation: .named))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

// MARK: - 对象详情（元数据 + QuickLook 预览 + 删除）

private struct R2ObjectDetailView: View {

    let object: R2Object
    let viewModel: R2ObjectListViewModel
    let canWrite: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var previewURL: URL?
    @State private var showDeleteConfirm = false

    /// 预览大小阈值：50 MB
    private var previewable: Bool {
        (object.size ?? 0) <= 50_000_000
    }

    var body: some View {
        NavigationStack {
            List {
                Section("对象") {
                    LabeledContent("Key") {
                        Text(object.key)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                    }
                    if let size = object.size {
                        LabeledContent("大小", value: Int64(size).formatted(.byteCount(style: .file)))
                    }
                    if let contentType = object.httpMetadata?.contentType {
                        LabeledContent("Content-Type", value: contentType)
                    }
                    if let storageClass = object.storageClass {
                        LabeledContent("存储类型", value: storageClass)
                    }
                    if let etag = object.etag {
                        LabeledContent("ETag") {
                            Text(etag)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                    if let modified = WorkerScript.parseDate(object.lastModified) {
                        LabeledContent("修改时间") {
                            Text(modified, format: .dateTime.year().month().day().hour().minute())
                        }
                    }
                }

                Section {
                    Button {
                        Task {
                            previewURL = await viewModel.downloadToTemp(object: object)
                        }
                    } label: {
                        HStack {
                            Label("预览", systemImage: "eye")
                            Spacer()
                            if viewModel.isDownloading {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!previewable || viewModel.isDownloading)

                    if canWrite {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("删除对象", systemImage: "trash")
                        }
                    }
                } footer: {
                    if !previewable {
                        Text("超过 50 MB 的对象暂不支持在 App 内预览。")
                    } else {
                        Text("图片、视频、PDF、Office 文档等均可预览（QuickLook）。")
                    }
                }
            }
            .navigationTitle("对象详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .quickLookPreview($previewURL)
            .confirmationDialog("删除对象？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("删除 \(object.key)", role: .destructive) {
                    Task {
                        if await viewModel.delete(key: object.key) {
                            dismiss()
                        }
                    }
                }
            } message: {
                Text("此操作不可撤销。")
            }
        }
    }
}

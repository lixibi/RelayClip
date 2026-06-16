import AppKit
import SwiftUI

struct HeaderView: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.title.weight(.bold))
                .foregroundStyle(Color.textSyncBrown)

            Text(title)
                .font(.title.weight(.bold))
                .foregroundStyle(Color.textSyncBrown)

            Spacer()
        }
        .padding(18)
        .background(TextSyncPanelBackground(tint: Color.textSyncCream))
    }
}

struct LatestTextView: View {
    let entry: SyncEntry?
    let serverAddress: String
    @Binding var text: String
    let isLoading: Bool
    let copyAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(entry?.isImage == true ? "最新图片" : "最新文本")
                    .font(.headline)
                    .foregroundStyle(Color.textSyncBrown)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if entry?.isLocallyEdited == true {
                        Text("本地已改")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.textSyncWarning)
                    }

                    if let entry {
                        Text(entry.time.textSyncFormatted)
                            .font(.caption)
                            .foregroundStyle(Color.textSyncMuted)
                    }
                }
            }

            if let entry, entry.isImage {
                ImagePreview(entry: entry, serverAddress: serverAddress, minHeight: 88)
            } else {
                Text(displayedText)
                    .font(.callout)
                    .foregroundStyle(entry == nil ? Color.textSyncMuted : Color.textSyncBrown)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                    .padding(10)
                    .background(Color.textSyncPaper)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.textSyncLine, lineWidth: 1)
                    )
            }

            Button(action: copyAction) {
                Label(entry?.isImage == true ? "复制最新图片" : "复制最新文本", systemImage: entry?.isImage == true ? "photo.on.rectangle.angled" : "doc.on.doc.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(TextSyncPillButtonStyle(color: Color.textSyncTeal))
            .disabled(entry == nil)
            .keyboardShortcut("c", modifiers: [.command, .shift])
        }
        .padding(16)
        .background(TextSyncPanelBackground(tint: Color.textSyncPanel))
    }

    private var displayedText: String {
        if isLoading && entry == nil {
            return "正在同步..."
        }
        guard entry != nil else { return "暂无数据" }
        return text.isEmpty ? entry?.content ?? "" : text
    }
}

struct ComposerView: View {
    @Binding var draft: String
    let isSending: Bool
    let pasteAction: () -> Void
    let uploadImageAction: () -> Void
    let sendAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("发送文本")
                    .font(.headline)
                    .foregroundStyle(Color.textSyncBrown)

                Spacer()

                Text("\(draft.count) 字")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSyncMuted)
            }

            TextEditor(text: $draft)
                .scrollContentBackground(.hidden)
                .font(.body)
                .foregroundStyle(Color.textSyncBrown)
                .frame(minHeight: 86)
                .padding(10)
                .background(Color.textSyncPaper)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.textSyncLine, lineWidth: 1)
                )

            HStack(spacing: 10) {
                Button(action: pasteAction) {
                    Label("粘贴", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TextSyncPillButtonStyle(color: Color.textSyncBrown))
                .keyboardShortcut("v", modifiers: [.command, .shift])

                Button(action: uploadImageAction) {
                    Label("上传图片", systemImage: "photo.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TextSyncPillButtonStyle(color: Color.textSyncTeal))
                .disabled(isSending)

                Button(action: sendAction) {
                    Label(isSending ? "上传中" : "上传", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TextSyncPillButtonStyle(color: Color.textSyncGreen))
                .disabled(isSending)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(16)
        .background(TextSyncPanelBackground(tint: Color.textSyncPanel))
    }
}

struct SyncModePanel: View {
    let recordLocalAction: () -> Void
    let sendClipboardAction: () -> Void
    let syncRemoteAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
                Button(action: recordLocalAction) {
                    Label("保存本机", systemImage: "tray.and.arrow.down.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TextSyncPillButtonStyle(color: Color.textSyncBrown))

                Button(action: sendClipboardAction) {
                    Label("发送远程", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TextSyncPillButtonStyle(color: Color.textSyncGreen))

                Button(action: syncRemoteAction) {
                    Label("同步", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TextSyncPillButtonStyle(color: Color.textSyncTeal))
        }
        .padding(16)
        .background(TextSyncPanelBackground(tint: Color.textSyncPanel))
    }
}

struct CategoryFilterView: View {
    @Binding var selectedCategory: EntryCategoryFilter
    let countProvider: (EntryCategoryFilter) -> Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("分类")
                .font(.headline)
                .foregroundStyle(Color.textSyncBrown)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: [GridItem(.fixed(36)), GridItem(.fixed(36))], spacing: 8) {
                    ForEach(EntryCategoryFilter.allCases) { category in
                        Button {
                            selectedCategory = category
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: category.systemImage)
                                Text(category.title)
                                Text("\(countProvider(category))")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.white.opacity(selectedCategory == category ? 0.24 : 0.46)))
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(selectedCategory == category ? .white : Color.textSyncBrown)
                            .padding(.horizontal, 12)
                            .frame(minWidth: 96, maxWidth: 132, minHeight: 36)
                            .background(Capsule().fill(selectedCategory == category ? Color.textSyncTeal : Color.textSyncPaper))
                            .overlay(Capsule().stroke(Color.textSyncLine, lineWidth: selectedCategory == category ? 0 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(TextSyncPanelBackground(tint: Color.textSyncPanel))
    }
}

struct HistorySection: View {
    let pinnedEntries: [SyncEntry]
    let items: [HistoryListItem]
    let serverAddress: String
    let totalCount: Int
    let hiddenCount: Int
    let latestID: Int?
    let canLoadMore: Bool
    let copyAction: (SyncEntry) -> Void
    let editAction: (SyncEntry) -> Void
    let updateFromCloudAction: (SyncEntry) -> Void
    let uploadToRemoteAction: (SyncEntry) -> Void
    let pinAction: (SyncEntry) -> Void
    let hideAction: (SyncEntry) -> Void
    let deleteAction: (SyncEntry) -> Void
    let restoreHiddenAction: (HiddenEntryRange) -> Void
    let loadMoreAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("历史记录")
                    .font(.headline)
                    .foregroundStyle(Color.textSyncBrown)

                Spacer()

                if totalCount > 0 {
                    HStack(spacing: 6) {
                        if hiddenCount > 0 {
                            Label("\(hiddenCount)", systemImage: "eye.slash")
                                .labelStyle(.titleAndIcon)
                        }

                        Text("\(entryCount)/\(totalCount)")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textSyncMuted)
                } else if !pinnedEntries.isEmpty {
                    Text("\(pinnedEntries.count) 个置顶")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.textSyncMuted)
                }
            }

            if items.isEmpty && pinnedEntries.isEmpty {
                Text("本机缓存暂无历史，点工具栏同步远程列表。")
                    .font(.callout)
                    .foregroundStyle(Color.textSyncMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.textSyncPaper)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.textSyncLine, lineWidth: 1)
                    )
            } else {
                ForEach(pinnedEntries) { entry in
                    historyButton(entry)
                }

                ForEach(items) { item in
                    switch item {
                    case .entry(let entry):
                        historyButton(entry)
                    case .hiddenRange(let range):
                        HiddenRangeButton(range: range, restoreAction: restoreHiddenAction)
                    }
                }

                if canLoadMore {
                    Button(action: loadMoreAction) {
                        Label("加载更多", systemImage: "chevron.down.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TextSyncPillButtonStyle(color: Color.textSyncTeal))
                }
            }
        }
    }

    private var entryCount: Int {
        items.reduce(0) { count, item in
            if case .entry = item {
                return count + 1
            }
            return count
        }
    }

    private func historyButton(_ entry: SyncEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HistoryRow(entry: entry, serverAddress: serverAddress, isLatest: entry.id == latestID)
                .contentShape(Rectangle())
                .onTapGesture {
                    copyAction(entry)
                }

            HStack(spacing: 8) {
                Button {
                    copyAction(entry)
                } label: {
                    Image(systemName: entry.isImage ? "photo.on.rectangle.angled" : "doc.on.doc.fill")
                }
                .buttonStyle(TextSyncIconButtonStyle(color: Color.textSyncBrown))
                .help("复制")
                .accessibilityLabel("复制")

                Button {
                    uploadToRemoteAction(entry)
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .buttonStyle(TextSyncIconButtonStyle(color: Color.textSyncGreen))
                .help("发送到远程")
                .accessibilityLabel("发送到远程")

                Spacer()
            }
        }
        .contextMenu {
            Button {
                copyAction(entry)
            } label: {
                Label("复制", systemImage: "doc.on.doc.fill")
            }

            if !entry.isImage {
                ForEach(entry.detectedActions.prefix(4)) { action in
                    Button {
                        NSWorkspace.shared.open(action.url)
                    } label: {
                        Label(action.menuTitle, systemImage: action.systemImage)
                    }
                }

                Button {
                    editAction(entry)
                } label: {
                    Label("编辑本地文本", systemImage: "pencil.circle.fill")
                }
            }

            Button {
                if entry.isLocalOnly {
                    uploadToRemoteAction(entry)
                } else {
                    updateFromCloudAction(entry)
                }
            } label: {
                Label(entry.isLocalOnly ? "发送到远程" : "更新", systemImage: entry.isLocalOnly ? "paperplane.fill" : "icloud.and.arrow.down.fill")
            }

            if !entry.isLocalOnly {
                Button {
                    pinAction(entry)
                } label: {
                    Label(entry.isPinned ? "取消置顶" : "置顶", systemImage: entry.isPinned ? "pin.slash" : "pin.fill")
                }
            }

            Button(role: .destructive) {
                hideAction(entry)
            } label: {
                Label("隐藏", systemImage: "eye.slash")
            }

            Button(role: .destructive) {
                deleteAction(entry)
            } label: {
                Label(entry.isLocalOnly ? "删除本机记录" : "删除到回收站", systemImage: "trash")
            }
        }
    }
}

struct TrashView: View {
    let entries: [SyncEntry]
    let serverAddress: String
    let restoreAction: (SyncEntry) -> Void
    let permanentDeleteAction: (SyncEntry) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppBackground()

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("回收站", systemImage: "trash")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.textSyncBrown)

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Label("关闭", systemImage: "xmark.circle")
                    }
                }

                if entries.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "trash")
                            .font(.system(size: 42, weight: .semibold))
                        Text("回收站为空")
                            .font(.headline)
                        Text("删除到回收站的远端内容会显示在这里。")
                            .font(.footnote)
                    }
                    .foregroundStyle(Color.textSyncMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(entries) { entry in
                                VStack(alignment: .leading, spacing: 12) {
                                    HistoryRow(entry: entry, serverAddress: serverAddress, isLatest: false)

                                    HStack(spacing: 10) {
                                        Button {
                                            restoreAction(entry)
                                        } label: {
                                            Label("恢复", systemImage: "arrow.uturn.backward.circle.fill")
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(TextSyncPillButtonStyle(color: Color.textSyncTeal))

                                        Button(role: .destructive) {
                                            permanentDeleteAction(entry)
                                        } label: {
                                            Label("永久删除", systemImage: "trash.fill")
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(TextSyncPillButtonStyle(color: Color.textSyncWarning))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(22)
            .frame(width: 560, height: 620)
        }
    }
}

struct HistoryRow: View {
    let entry: SyncEntry
    let serverAddress: String
    let isLatest: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if entry.isPinned {
                    Label("置顶", systemImage: "pin.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.textSyncTeal)
                }

                CategoryBadge(entry: entry)

                Spacer()

                HStack(spacing: 6) {
                    if entry.isLocalOnly {
                        StatusIcon(systemName: "internaldrive.fill", color: Color.textSyncWarning, label: "本机记录")
                    }

                    if isLatest {
                        StatusIcon(systemName: "sparkles", color: Color.textSyncWarning, label: "最新")
                    }

                    if entry.isLocallyEdited {
                        StatusIcon(systemName: "pencil.circle.fill", color: Color.textSyncWarning, label: "本地修改")
                    }
                }

                Text(entry.time.textSyncFormatted)
                    .font(.caption)
                    .foregroundStyle(Color.textSyncMuted)
            }

            if entry.isImage {
                ImagePreview(entry: entry, serverAddress: serverAddress, minHeight: 112)
            } else {
                Text(entry.content.textSyncPreviewPreservingLines(limit: 360))
                    .font(.callout)
                    .foregroundStyle(Color.textSyncBrown)
                    .lineLimit(4)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
            }
        }
        .padding(14)
        .background(Color.textSyncPaper)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.textSyncLine, lineWidth: 1)
        )
    }
}

struct ImagePreview: View {
    let entry: SyncEntry
    let serverAddress: String
    let minHeight: CGFloat
    @State private var cachedImage: NSImage?
    @State private var isLoadingRemote = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let cachedImage {
                    Image(nsImage: cachedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: 260)
                } else if isLoadingRemote {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: minHeight)
                } else {
                    Label("图片预览不可用", systemImage: "photo")
                        .frame(maxWidth: .infinity, minHeight: minHeight)
                        .foregroundStyle(Color.textSyncMuted)
                }
            }
            .background(Color.textSyncPaper)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.textSyncLine, lineWidth: 1)
            )

            Text(entry.imageDetailText)
                .font(.caption)
                .foregroundStyle(Color.textSyncMuted)
                .lineLimit(1)
        }
        .task(id: cacheTaskID) {
            await loadImage()
        }
    }

    private var cacheTaskID: String {
        "\(entry.id)-\(entry.thumbnailURL ?? entry.assetURL ?? "")-\(serverAddress)"
    }

    @MainActor
    private func loadImage() async {
        if let image = ImageDiskCache.cachedImage(for: entry, serverAddress: serverAddress, variant: "thumb") {
            cachedImage = image
            return
        }

        guard !entry.isLocalOnly,
              let url = entry.resolvedThumbnailURL(serverAddress: serverAddress) else {
            cachedImage = nil
            return
        }

        isLoadingRemote = true
        defer { isLoadingRemote = false }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let image = NSImage(data: data) else {
                cachedImage = nil
                return
            }
            try? ImageDiskCache.store(data, for: entry, serverAddress: serverAddress, variant: "thumb")
            ImageDiskCache.prune()
            cachedImage = image
        } catch {
            cachedImage = nil
        }
    }
}

private struct CategoryBadge: View {
    let entry: SyncEntry

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.textSyncBrown)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.textSyncCream.opacity(0.92)))
            .overlay(Capsule().stroke(Color.textSyncLine, lineWidth: 1))
    }

    private var title: String {
        switch EntryCategoryFilter(rawValue: entry.normalizedCategory) {
        case .image: return "图片"
        case .link: return "链接"
        case .email: return "邮箱"
        case .phone: return "电话"
        case .text, .all, .none: return "文本"
        }
    }

    private var icon: String {
        switch EntryCategoryFilter(rawValue: entry.normalizedCategory) {
        case .image: return "photo"
        case .link: return "link"
        case .email: return "envelope"
        case .phone: return "phone"
        case .text, .all, .none: return "text.alignleft"
        }
    }
}

struct HiddenRangeButton: View {
    let range: HiddenEntryRange
    let restoreAction: (HiddenEntryRange) -> Void

    var body: some View {
        Button {
            restoreAction(range)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "eye.slash")
                    .font(.caption2.weight(.semibold))

                Text(range.title)
                    .font(.caption2.weight(.medium))

                Spacer()

                Text("\(range.count)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.textSyncMuted.opacity(0.16)))
            }
            .foregroundStyle(Color.textSyncMuted.opacity(0.72))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.textSyncPaper.opacity(0.26))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.textSyncLine.opacity(0.24), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct StatusIcon: View {
    let systemName: String
    let color: Color
    let label: String

    var body: some View {
        Image(systemName: systemName)
            .font(.caption.weight(.bold))
            .foregroundStyle(color)
            .accessibilityLabel(label)
    }
}

struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.textSyncBrown.opacity(0.92)))
            .padding(.bottom, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

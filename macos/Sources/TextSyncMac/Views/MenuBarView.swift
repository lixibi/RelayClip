import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var viewModel: TextSyncViewModel
    @Environment(\.openWindow) private var openWindow
    @State private var isSettingsPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label("RelayClip", systemImage: "bolt.horizontal.circle.fill")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.textSyncBrown)

                    Text("快捷复制历史")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.textSyncMuted)
                }

                Spacer()

	                Button {
	                    openQuickPanel()
	                } label: {
	                    Label("浮动", systemImage: "rectangle.on.rectangle")
	                }
	                .buttonStyle(TextSyncInlineButtonStyle(color: Color.textSyncTeal))
	                .help("打开可缩放快捷列表")

	                Button {
	                    openMainWindow()
	                } label: {
	                    Image(systemName: "house.fill")
	                }
	                .buttonStyle(TextSyncIconButtonStyle(color: Color.textSyncBrown))
	                .help("打开主界面")

                Button {
                    isSettingsPresented = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(TextSyncIconButtonStyle(color: Color.textSyncBrown))
                .help("设置")
            }

            HStack(spacing: 8) {
                Picker("分类", selection: $viewModel.quickCategory) {
                    ForEach(EntryCategoryFilter.allCases) { category in
                        Text("\(category.title) \(viewModel.count(for: category))").tag(category)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Spacer()

                Text("\(viewModel.quickCopyEntries.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textSyncMuted)
            }

            if viewModel.quickCopyEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 26, weight: .semibold))
                    Text("暂无记录")
                        .font(.callout.weight(.medium))
                }
                .foregroundStyle(Color.textSyncMuted)
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
	                ScrollView {
	                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.quickCopyEntries) { entry in
	                            Button {
	                                let menuWindow = NSApp.keyWindow
	                                Task {
	                                    await viewModel.copy(entry)
	                                }
	                                MenuBarPanelCloser.close(menuWindow)
	                            } label: {
	                                QuickCopyRow(entry: entry, serverAddress: viewModel.serverAddress)
	                            }
                            .buttonStyle(.plain)
	                            .contextMenu {
	                                Button {
	                                    let menuWindow = NSApp.keyWindow
	                                    Task { await viewModel.copy(entry) }
	                                    MenuBarPanelCloser.close(menuWindow)
	                                } label: {
	                                    Label("复制", systemImage: "doc.on.doc.fill")
	                                }
                            }
                        }
	                    }
	                    .padding(.vertical, 2)
		                }
		                .frame(height: menuListHeight)
		            }
		        }
        .padding(14)
        .frame(width: 340)
        .background(
            ZStack {
                AppBackground()
                    .opacity(0.92)
                Rectangle()
                    .fill(.regularMaterial)
            }
        )
        .task {
            await viewModel.bootstrap()
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView(
                appTitle: viewModel.appTitle,
                serverAddress: viewModel.serverAddress,
                automaticRemoteUploadEnabled: viewModel.automaticRemoteUploadEnabled,
                hotKeyShortcut: viewModel.hotKeyShortcut,
                quickPanelPlacement: viewModel.quickPanelPlacement,
                isTestingConnection: viewModel.isTestingConnection,
                connectionTestMessage: viewModel.connectionTestMessage,
                didLastConnectionTestSucceed: viewModel.didLastConnectionTestSucceed
            ) { serverAddress in
                Task { await viewModel.testConnection(serverAddress: serverAddress) }
            } saveAction: { appTitle, serverAddress, automaticRemoteUploadEnabled, hotKeyShortcut, quickPanelPlacement in
                viewModel.saveSettings(
                    appTitle: appTitle,
                    serverAddress: serverAddress,
                    automaticRemoteUploadEnabled: automaticRemoteUploadEnabled,
                    hotKeyShortcut: hotKeyShortcut,
                    quickPanelPlacement: quickPanelPlacement
                )
                isSettingsPresented = false
                Task { await viewModel.refresh(allowOverwriteLocalEdits: false) }
            } resetLocalDataAction: {
                viewModel.resetLocalData()
            }
        }
    }

	    private func openMainWindow() {
	        let menuWindow = NSApp.keyWindow
	        openWindow(id: WindowID.main)
	        NSApp.activate(ignoringOtherApps: true)
	        MenuBarPanelCloser.close(menuWindow)
	    }

	    private func openQuickPanel() {
	        let menuWindow = NSApp.keyWindow
	        QuickPanelController.shared.show(viewModel: viewModel, placement: viewModel.quickPanelPlacement)
	        MenuBarPanelCloser.close(menuWindow)
	    }

	    private var menuListHeight: CGFloat {
	        let rowHeight: CGFloat = 78
	        let idealHeight = CGFloat(viewModel.quickCopyEntries.count) * rowHeight
	        return min(menuMaxHeight, max(220, idealHeight))
	    }

	    private var menuMaxHeight: CGFloat {
	        min(520, max(320, (NSScreen.main?.visibleFrame.height ?? 760) - 220))
	    }
}

struct QuickPickerPanelView: View {
    @ObservedObject var viewModel: TextSyncViewModel
    let closeAction: () -> Void
    @State private var isPinned = QuickPanelController.shared.isPinned

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("RelayClip", systemImage: "bolt.horizontal.circle.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.textSyncBrown)

                Spacer()

                Button {
                    isPinned.toggle()
                    QuickPanelController.shared.setPinned(isPinned)
                } label: {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                }
                .buttonStyle(TextSyncIconButtonStyle(color: isPinned ? Color.textSyncTeal : Color.textSyncBrown))
                .help(isPinned ? "取消钉住" : "钉住窗口")

                Picker("分类", selection: $viewModel.quickCategory) {
                    ForEach(EntryCategoryFilter.allCases) { category in
                        Text("\(category.title) \(viewModel.count(for: category))").tag(category)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            Divider()

            if viewModel.quickCopyEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 28, weight: .semibold))
                    Text("暂无记录")
                        .font(.callout.weight(.medium))
                }
                .foregroundStyle(Color.textSyncMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 7) {
	                        ForEach(viewModel.quickCopyEntries) { entry in
	                            Button {
	                                Task { await viewModel.copy(entry) }
	                                if !isPinned {
	                                    closeAction()
	                                }
	                            } label: {
	                                QuickCopyRow(entry: entry, serverAddress: viewModel.serverAddress)
	                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(14)
        .frame(minWidth: 330, minHeight: 360)
        .background(
            ZStack {
                AppBackground()
                    .opacity(0.92)
                Rectangle()
                    .fill(.regularMaterial)
            }
        )
        .task {
            await viewModel.bootstrap()
        }
    }
}

private enum MenuBarPanelCloser {
	    static func close(_ window: NSWindow?) {
	        DispatchQueue.main.async {
	            window?.orderOut(nil)
	            window?.close()
	        }
	    }
}

private struct QuickCopyRow: View {
    let entry: SyncEntry
    let serverAddress: String

    var body: some View {
        HStack(spacing: 10) {
            QuickCopyThumbnail(entry: entry, serverAddress: serverAddress)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.textSyncBrown)
                    .lineLimit(3)
                    .lineSpacing(1)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)

                Text(entry.time.textSyncFormatted)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.textSyncMuted)
                .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color.textSyncPaper.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.textSyncLine.opacity(0.6), lineWidth: 1)
        )
    }

    private var title: String {
        if entry.isImage {
            return entry.imageDetailText.isEmpty ? "图片" : entry.imageDetailText
        }
        return entry.content.textSyncPreviewPreservingLines(limit: 120)
    }

}

private struct QuickCopyThumbnail: View {
    let entry: SyncEntry
    let serverAddress: String
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.textSyncCream.opacity(0.8))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(entry.isImage ? Color.textSyncTeal : Color.textSyncBrown)
            }
        }
        .frame(width: 44, height: 44)
        .task(id: taskID) {
            await loadImageIfNeeded()
        }
    }

    private var icon: String {
        switch EntryCategoryFilter(rawValue: entry.normalizedCategory) {
        case .image: return "photo"
        case .link: return "link"
        case .email: return "envelope"
        case .phone: return "phone"
        case .text, .all, .none: return "doc.text"
        }
    }

    private var taskID: String {
        "\(entry.id)-\(entry.thumbnailURL ?? entry.assetURL ?? "")-\(serverAddress)"
    }

    @MainActor
    private func loadImageIfNeeded() async {
        guard entry.isImage else {
            image = nil
            return
        }

        if let cached = ImageDiskCache.cachedImage(for: entry, serverAddress: serverAddress, variant: "thumb")
            ?? ImageDiskCache.cachedImage(for: entry, serverAddress: serverAddress, variant: "asset") {
            image = cached
            return
        }

        guard !entry.isLocalOnly,
              let url = entry.resolvedThumbnailURL(serverAddress: serverAddress) else {
            image = nil
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let loaded = NSImage(data: data) else {
                return
            }
            try? ImageDiskCache.store(data, for: entry, serverAddress: serverAddress, variant: "thumb")
            ImageDiskCache.prune()
            image = loaded
        } catch {
            image = nil
        }
    }
}

import AppKit
import Foundation

@MainActor
final class TextSyncViewModel: ObservableObject {
    private let pageSize = 10
    private let maxClipboardImageBytes = 8 * 1024 * 1024
    private let service = TextSyncService()
    private let localStore = TextSyncLocalStore()
    private var hasBootstrapped = false
    private var clipboardMonitorTimer: Timer?
    private var lastClipboardChangeCount = ClipboardClient.changeCount
    private var lastCapturedClipboardSignature = ""

    @Published var serverAddress = ""
    @Published var appTitle = TextSyncLocalStore.defaultAppTitle
    @Published var draft = ""
    @Published var latestDraft = ""
    @Published var entries: [SyncEntry] = []
    @Published var hiddenEntries: [SyncEntry] = []
    @Published var trashEntries: [SyncEntry] = []
    @Published var selectedCategory: EntryCategoryFilter = .all
    @Published var quickCategory: EntryCategoryFilter = .all
    @Published var visibleHistoryCount = 10
    @Published var isLoading = false
    @Published var isSending = false
    @Published var isTestingConnection = false
    @Published var connectionTestMessage: String?
    @Published var didLastConnectionTestSucceed = false
    @Published var automaticRemoteUploadEnabled = false
    @Published var hotKeyShortcut: HotKeyShortcut = .defaultValue
    @Published var quickPanelPlacement: QuickPanelPlacement = .mouse
    @Published var message: String?

    init() {
        do {
            serverAddress = try localStore.serverAddress()
            self.appTitle = try localStore.appTitle()
            automaticRemoteUploadEnabled = try localStore.automaticRemoteUploadEnabled()
            hotKeyShortcut = try localStore.hotKeyShortcut()
            quickPanelPlacement = try localStore.quickPanelPlacement()
        } catch {
            serverAddress = ""
            appTitle = TextSyncLocalStore.defaultAppTitle
            automaticRemoteUploadEnabled = false
            hotKeyShortcut = .defaultValue
            quickPanelPlacement = .mouse
        }
        configureHotKey()
    }

    var latest: SyncEntry? {
        entries.last
    }

    var filteredEntries: [SyncEntry] {
        guard selectedCategory != .all else { return entries }
        return entries.filter { $0.normalizedCategory == selectedCategory.rawValue }
    }

    var history: [SyncEntry] {
        Array(filteredEntries.filter { !$0.isPinned }.reversed())
    }

    var pinnedEntries: [SyncEntry] {
        Array(filteredEntries.filter(\.isPinned).reversed())
    }

    var visibleHistory: [SyncEntry] {
        Array(history.prefix(visibleHistoryCount))
    }

    var hiddenHistory: [SyncEntry] {
        Array(hiddenEntries.filter { !$0.isPinned }.reversed())
    }

    var visibleHistoryItems: [HistoryListItem] {
        makeHistoryItems(visibleEntries: visibleHistory, hiddenEntries: hiddenHistory)
    }

    var canLoadMoreHistory: Bool {
        visibleHistoryCount < history.count
    }

    func count(for category: EntryCategoryFilter) -> Int {
        guard category != .all else { return entries.count }
        return entries.filter { $0.normalizedCategory == category.rawValue }.count
    }

    var quickCopyEntries: [SyncEntry] {
        var seenIDs = Set<Int>()
        var result: [SyncEntry] = []

        for entry in pinnedEntries + history {
            if quickCategory != .all && entry.normalizedCategory != quickCategory.rawValue {
                continue
            }
            guard !seenIDs.contains(entry.id) else { continue }
            seenIDs.insert(entry.id)
            result.append(entry)
        }

        return result
    }

    var isServerConfigured: Bool {
        !serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var latestRemoteText: SyncEntry? {
        entries.reversed().first { !$0.isImage }
    }

    var statusLine: String {
        if let message, !message.isEmpty {
            return message
        }
        if let latest {
            let mode = automaticRemoteUploadEnabled ? "自动远程" : "仅本机"
            return "\(mode) · 最新 \(latest.time.textSyncFormatted) · \(entries.count) 条"
        }
        if serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请先设置服务器地址"
        }
        return "暂无缓存"
    }

    func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        loadCachedEntries()
        await refresh(allowOverwriteLocalEdits: false, showMissingServerMessage: false)
        startClipboardMonitoring()
    }

    func loadCachedEntries() {
        do {
            entries = try localStore.visibleEntries(serverAddress: serverAddress)
            hiddenEntries = try localStore.hiddenEntries(serverAddress: serverAddress)
            trashEntries = try localStore.trashEntries(serverAddress: serverAddress)
            syncLatestDraft()
            normalizeVisibleCount()
        } catch {
            message = "本地缓存读取失败"
        }
    }

    func refresh(allowOverwriteLocalEdits: Bool = false, showMissingServerMessage: Bool = true) async {
        guard !serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            loadCachedEntries()
            if showMissingServerMessage {
                message = "请先设置服务器地址"
            }
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let remoteEntries = try await service.listEntries(serverAddress: serverAddress, includeDeleted: true)
            serverAddress = try ServerAddress.normalized(serverAddress)
            try localStore.merge(remoteEntries, serverAddress: serverAddress, preserveLocalEdits: !allowOverwriteLocalEdits)
            try localStore.saveServerAddress(serverAddress)
            entries = try localStore.visibleEntries(serverAddress: serverAddress)
            hiddenEntries = try localStore.hiddenEntries(serverAddress: serverAddress)
            trashEntries = try localStore.trashEntries(serverAddress: serverAddress)
            syncLatestDraft()
            normalizeVisibleCount()
            warmImageCache(for: entries)
            message = entries.isEmpty ? "服务器暂无内容" : "已同步最新内容"
        } catch {
            loadCachedEntries()
            message = error.localizedDescription
        }
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            message = "请输入要同步的文本"
            return
        }

        await postText(draft, successMessage: "文本已上传")
        if message == "文本已上传" {
            draft = ""
        }
    }

    func sendClipboardToRemote() async {
        let clipboardText = ClipboardClient.readTextLikeContent()
        if !clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await postText(clipboardText, successMessage: "已上传剪贴板文本")
        } else {
            await sendClipboardImage()
        }
    }

    func recordClipboardLocally() {
        do {
            if let entry = try createLocalClipboardEntry() {
                reloadLocalCollections()
                message = entry.isImage ? "已保存图片到本机历史" : "已保存文本到本机历史"
            } else {
                message = "剪贴板没有可记录内容"
            }
        } catch {
            message = "本机记录失败：\(error.localizedDescription)"
        }
    }

    func sendClipboardImage() async {
        guard !serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "请先设置服务器地址"
            return
        }

        guard let image = ClipboardClient.readImage(maxBytes: maxClipboardImageBytes) else {
            message = "剪贴板没有可上传图片，或图片超过 8MB"
            return
        }

        isSending = true
        defer { isSending = false }

        do {
            try await service.postImage(image.data, fileName: image.fileName, mimeType: image.mimeType, serverAddress: serverAddress)
            message = "已上传剪贴板图片"
            await refresh(allowOverwriteLocalEdits: false)
        } catch {
            message = error.localizedDescription
        }
    }

    func fetchLatestToClipboard() async {
        guard !serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "请先设置服务器地址"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let remoteEntries = try await service.listEntries(serverAddress: serverAddress, includeDeleted: true)
            serverAddress = try ServerAddress.normalized(serverAddress)
            if !remoteEntries.isEmpty {
                try localStore.merge(remoteEntries, serverAddress: serverAddress, preserveLocalEdits: true)
            }
            try localStore.saveServerAddress(serverAddress)
            entries = try localStore.visibleEntries(serverAddress: serverAddress)
            hiddenEntries = try localStore.hiddenEntries(serverAddress: serverAddress)
            trashEntries = try localStore.trashEntries(serverAddress: serverAddress)
            syncLatestDraft()
            normalizeVisibleCount()
            warmImageCache(for: entries)

            guard let newest = remoteEntries.last else {
                message = "服务器暂无内容"
                return
            }

            if newest.isImage {
                try await copyImage(newest)
                message = "已复制远程最新图片"
            } else {
                ClipboardClient.writeString(newest.content)
                message = "已复制远程最新文本"
            }
        } catch {
            loadCachedEntries()
            message = error.localizedDescription
        }
    }

    func fetchRemoteOnly() async {
        await refresh(allowOverwriteLocalEdits: false)
    }

    func copyLatestRemoteText() {
        guard let latestRemoteText else {
            message = "远程暂无可复制文本"
            return
        }
        ClipboardClient.writeString(latestRemoteText.content)
        message = "已复制远程文本"
    }

    func hideLocal(_ entry: SyncEntry) {
        do {
            try localStore.markHidden(id: entry.id, serverAddress: serverAddress, isHidden: true)
            entries = try localStore.visibleEntries(serverAddress: serverAddress)
            hiddenEntries = try localStore.hiddenEntries(serverAddress: serverAddress)
            trashEntries = try localStore.trashEntries(serverAddress: serverAddress)
            syncLatestDraft()
            normalizeVisibleCount()
            message = "已从本机历史隐藏"
        } catch {
            message = "本地隐藏失败"
        }
    }

    func restoreHidden(_ range: HiddenEntryRange) {
        do {
            let ids = hiddenEntries
                .map(\.id)
                .filter { range.startID...range.endID ~= $0 }
            try localStore.restoreHiddenEntries(ids: ids, serverAddress: serverAddress)
            entries = try localStore.visibleEntries(serverAddress: serverAddress)
            hiddenEntries = try localStore.hiddenEntries(serverAddress: serverAddress)
            trashEntries = try localStore.trashEntries(serverAddress: serverAddress)
            syncLatestDraft()
            normalizeVisibleCount()
            message = ids.count > 1 ? "已显示 \(ids.count) 条隐藏记录" : "已显示隐藏记录"
        } catch {
            message = "恢复隐藏记录失败"
        }
    }

    func togglePinned(_ entry: SyncEntry) {
        do {
            try localStore.markPinned(id: entry.id, serverAddress: serverAddress, isPinned: !entry.isPinned)
            entries = try localStore.visibleEntries(serverAddress: serverAddress)
            hiddenEntries = try localStore.hiddenEntries(serverAddress: serverAddress)
            trashEntries = try localStore.trashEntries(serverAddress: serverAddress)
            syncLatestDraft()
            normalizeVisibleCount()
            message = entry.isPinned ? "已取消置顶" : "已置顶"
        } catch {
            message = "置顶状态保存失败"
        }
    }

    func pasteFromClipboard() {
        let clipboardText = ClipboardClient.readTextLikeContent()
        if !clipboardText.isEmpty {
            draft = clipboardText
            message = "已从剪贴板粘贴"
        } else if ClipboardClient.readImage(maxBytes: maxClipboardImageBytes) != nil {
            message = "剪贴板是图片，可直接上传图片"
        } else {
            message = "剪贴板没有可用内容"
        }
    }

    func copyLatest() async {
        guard let latest else {
            message = "没有可复制的内容"
            return
        }
        if latest.isImage {
            await copy(latest)
            return
        }

        let content = latestDraft.isEmpty ? latest.content : latestDraft
        guard !content.isEmpty else {
            message = "没有可复制的文本"
            return
        }
        ClipboardClient.writeString(content)
        message = "已复制最新文本"
    }

    func copy(_ entry: SyncEntry) async {
        if entry.isImage {
            do {
                try await copyImage(entry)
                message = "已复制图片"
            } catch {
                message = "图片复制失败：\(error.localizedDescription)"
            }
            return
        }

        ClipboardClient.writeString(entry.content)
        message = "已复制文本"
    }

    func updateLatestDraft(_ content: String) {
        if latest?.isImage == true {
            latestDraft = ""
            return
        }

        latestDraft = content
        guard let latest else { return }

        do {
            try localStore.saveLocalContent(id: latest.id, serverAddress: serverAddress, content: content)
            entries = try localStore.visibleEntries(serverAddress: serverAddress)
            hiddenEntries = try localStore.hiddenEntries(serverAddress: serverAddress)
            trashEntries = try localStore.trashEntries(serverAddress: serverAddress)
        } catch {
            message = "本地编辑保存失败"
        }
    }

    func editLocal(_ entry: SyncEntry, content: String) {
        guard !entry.isImage else {
            message = "图片记录不能编辑为文本"
            return
        }

        do {
            try localStore.saveLocalContent(id: entry.id, serverAddress: serverAddress, content: content)
            entries = try localStore.visibleEntries(serverAddress: serverAddress)
            hiddenEntries = try localStore.hiddenEntries(serverAddress: serverAddress)
            trashEntries = try localStore.trashEntries(serverAddress: serverAddress)
            syncLatestDraft()
            message = "本地修改已保存"
        } catch {
            message = "本地编辑保存失败"
        }
    }

    func updateEntryFromCloud(_ entry: SyncEntry) async {
        guard !serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "请先设置服务器地址"
            return
        }

        do {
            let remoteEntries = try await service.listEntries(serverAddress: serverAddress, includeDeleted: true)
            guard let remoteEntry = remoteEntries.first(where: { $0.id == entry.id }) else {
                message = "云端没有找到这条记录"
                return
            }
            serverAddress = try ServerAddress.normalized(serverAddress)
            try localStore.replaceWithRemote(remoteEntry, serverAddress: serverAddress)
            entries = try localStore.visibleEntries(serverAddress: serverAddress)
            hiddenEntries = try localStore.hiddenEntries(serverAddress: serverAddress)
            trashEntries = try localStore.trashEntries(serverAddress: serverAddress)
            syncLatestDraft()
            normalizeVisibleCount()
            if remoteEntry.isImage {
                warmImageCache(for: [remoteEntry])
            }
            message = "已用云端更新"
        } catch {
            message = "更新失败：\(error.localizedDescription)"
        }
    }

    func loadMoreHistory() {
        visibleHistoryCount = min(visibleHistoryCount + pageSize, history.count)
    }

    func deleteRemote(_ entry: SyncEntry) async {
        if entry.isLocalOnly {
            deleteLocalOnly(entry)
            return
        }

        guard !serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "请先设置服务器地址"
            return
        }

        do {
            try await service.deleteEntry(entry, serverAddress: serverAddress)
            await refresh(allowOverwriteLocalEdits: false)
            message = "已删除到回收站"
        } catch {
            message = "删除失败：\(error.localizedDescription)"
        }
    }

    func restoreRemote(_ entry: SyncEntry) async {
        guard !serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "请先设置服务器地址"
            return
        }

        do {
            try await service.restoreEntry(entry, serverAddress: serverAddress)
            await refresh(allowOverwriteLocalEdits: false)
            message = "已从回收站恢复"
        } catch {
            message = "恢复失败：\(error.localizedDescription)"
        }
    }

    func permanentlyDeleteRemote(_ entry: SyncEntry) async {
        if entry.isLocalOnly {
            deleteLocalOnly(entry)
            return
        }

        guard !serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "请先设置服务器地址"
            return
        }

        do {
            try await service.deleteEntry(entry, serverAddress: serverAddress, permanently: true)
            await refresh(allowOverwriteLocalEdits: false)
            message = "已永久删除"
        } catch {
            message = "永久删除失败：\(error.localizedDescription)"
        }
    }

    func saveSettings() {
        saveSettings(
            appTitle: appTitle,
            serverAddress: serverAddress,
            automaticRemoteUploadEnabled: automaticRemoteUploadEnabled,
            hotKeyShortcut: hotKeyShortcut,
            quickPanelPlacement: quickPanelPlacement
        )
    }

    func saveSettings(
        appTitle: String,
        serverAddress: String,
        automaticRemoteUploadEnabled: Bool,
        hotKeyShortcut: HotKeyShortcut,
        quickPanelPlacement: QuickPanelPlacement
    ) {
        do {
            self.appTitle = appTitle
            self.serverAddress = serverAddress
            self.automaticRemoteUploadEnabled = automaticRemoteUploadEnabled
            self.hotKeyShortcut = hotKeyShortcut
            self.quickPanelPlacement = quickPanelPlacement

            try localStore.saveAppTitle(self.appTitle)
            try localStore.saveAutomaticRemoteUploadEnabled(self.automaticRemoteUploadEnabled)
            try localStore.saveHotKeyShortcut(self.hotKeyShortcut)
            try localStore.saveQuickPanelPlacement(self.quickPanelPlacement)
            self.appTitle = try localStore.appTitle()

            if !self.serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.serverAddress = try ServerAddress.normalized(self.serverAddress)
                try localStore.saveServerAddress(self.serverAddress)
            }

            message = "设置已保存"
            configureHotKey()
        } catch {
            message = "设置保存失败"
        }
    }

    func setAutomaticRemoteUploadEnabled(_ isEnabled: Bool) {
        automaticRemoteUploadEnabled = isEnabled
        do {
            try localStore.saveAutomaticRemoteUploadEnabled(isEnabled)
            message = isEnabled ? "已开启自动发送到远程" : "已关闭自动发送到远程"
        } catch {
            message = "开关保存失败"
        }
    }

    func resetLocalData() {
        do {
            try localStore.resetCachedEntries(serverAddress: serverAddress)
            entries = []
            hiddenEntries = []
            trashEntries = []
            latestDraft = ""
            visibleHistoryCount = pageSize
            ImageDiskCache.clear()
            message = "本地数据已重置"
        } catch {
            message = "本地数据重置失败"
        }
    }

    func testConnection() async {
        await testConnection(serverAddress: serverAddress)
    }

    func testConnection(serverAddress: String) async {
        self.serverAddress = serverAddress
        isTestingConnection = true
        connectionTestMessage = "正在测试连接..."
        didLastConnectionTestSucceed = false
        defer { isTestingConnection = false }

        do {
            self.serverAddress = try ServerAddress.normalized(self.serverAddress)
            let count = try await service.testConnection(serverAddress: self.serverAddress)
            try localStore.saveServerAddress(self.serverAddress)
            let successMessage = "连接成功，读取到 \(count) 条记录"
            connectionTestMessage = successMessage
            didLastConnectionTestSucceed = true
            message = successMessage
        } catch {
            let failureMessage = "连接失败：\(error.localizedDescription)"
            connectionTestMessage = failureMessage
            didLastConnectionTestSucceed = false
            message = failureMessage
        }
    }

    private func postText(_ content: String, successMessage: String) async {
        guard !serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "请先设置服务器地址"
            return
        }

        isSending = true
        defer { isSending = false }

        do {
            try await service.post(content, serverAddress: serverAddress)
            message = successMessage
            await refresh(allowOverwriteLocalEdits: false)
        } catch {
            message = error.localizedDescription
        }
    }

    func uploadEntryToRemote(_ entry: SyncEntry) async {
        guard !serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "请先设置服务器地址"
            return
        }

        isSending = true
        defer { isSending = false }

        do {
            if entry.isImage {
                guard let data = try await imageDataForUpload(entry) else {
                    message = "图片文件不可用"
                    return
                }
                try await service.postImage(data, fileName: entry.fileName ?? "clipboard.png", mimeType: entry.mimeType ?? "image/png", serverAddress: serverAddress)
            } else {
                try await service.post(entry.content, serverAddress: serverAddress)
            }

            if entry.isLocalOnly {
                try localStore.deleteLocalEntry(entry, serverAddress: serverAddress)
            }
            await refresh(allowOverwriteLocalEdits: false, showMissingServerMessage: false)
            message = "已发送到远程"
        } catch {
            message = "发送失败：\(error.localizedDescription)"
        }
    }

    private func startClipboardMonitoring() {
        guard clipboardMonitorTimer == nil else { return }
        lastClipboardChangeCount = ClipboardClient.changeCount
        clipboardMonitorTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.captureClipboardIfNeeded()
            }
        }
    }

    private func captureClipboardIfNeeded() async {
        let changeCount = ClipboardClient.changeCount
        guard changeCount != lastClipboardChangeCount else { return }
        lastClipboardChangeCount = changeCount

        guard !isSending else { return }

        let clipboardText = ClipboardClient.readTextLikeContent()
        if !clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let signature = "text:\(clipboardText)"
            guard signature != lastCapturedClipboardSignature else { return }
            lastCapturedClipboardSignature = signature
            do {
                let entry = try localStore.createLocalTextEntry(content: clipboardText, serverAddress: serverAddress)
                reloadLocalCollections()
                if automaticRemoteUploadEnabled {
                    await uploadEntryToRemote(entry)
                } else {
                    message = "已记录剪贴板文本到本机"
                }
            } catch {
                message = "剪贴板文本记录失败：\(error.localizedDescription)"
            }
            return
        }

        if let image = ClipboardClient.readImage(maxBytes: maxClipboardImageBytes) {
            let signature = "image:\(image.data.count):\(Data(image.data.prefix(96)).base64EncodedString())"
            guard signature != lastCapturedClipboardSignature else { return }
            lastCapturedClipboardSignature = signature

            do {
                let entry = try localStore.createLocalImageEntry(payload: image, serverAddress: serverAddress)
                reloadLocalCollections()
                if automaticRemoteUploadEnabled {
                    await uploadEntryToRemote(entry)
                } else {
                    message = "已记录剪贴板图片到本机"
                }
            } catch {
                message = "剪贴板图片记录失败：\(error.localizedDescription)"
            }
            return
        }

        let fallback = ClipboardClient.readUnsupportedTypeSummary()
        guard !fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let fallbackSignature = "unsupported:\(fallback)"
        guard fallbackSignature != lastCapturedClipboardSignature else { return }
        lastCapturedClipboardSignature = fallbackSignature
        do {
            _ = try localStore.createLocalTextEntry(content: fallback, serverAddress: serverAddress)
            reloadLocalCollections()
            if automaticRemoteUploadEnabled {
                await postText(fallback, successMessage: "已记录剪贴板类型并发送远程")
            } else {
                message = "已记录剪贴板类型到本机"
            }
        } catch {
            message = "剪贴板类型记录失败：\(error.localizedDescription)"
        }
    }

    private func normalizeVisibleCount() {
        visibleHistoryCount = min(max(visibleHistoryCount, pageSize), history.count)
    }

    private func syncLatestDraft() {
        latestDraft = latest?.isImage == true ? "" : latest?.content ?? ""
    }

    private func createLocalClipboardEntry() throws -> SyncEntry? {
        let clipboardText = ClipboardClient.readTextLikeContent()
        if !clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try localStore.createLocalTextEntry(content: clipboardText, serverAddress: serverAddress)
        }

        if let image = ClipboardClient.readImage(maxBytes: maxClipboardImageBytes) {
            return try localStore.createLocalImageEntry(payload: image, serverAddress: serverAddress)
        }

        let fallback = ClipboardClient.readUnsupportedTypeSummary()
        guard !fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return try localStore.createLocalTextEntry(content: fallback, serverAddress: serverAddress)
    }

    private func reloadLocalCollections() {
        do {
            entries = try localStore.visibleEntries(serverAddress: serverAddress)
            hiddenEntries = try localStore.hiddenEntries(serverAddress: serverAddress)
            trashEntries = try localStore.trashEntries(serverAddress: serverAddress)
            syncLatestDraft()
            normalizeVisibleCount()
        } catch {
            message = "本地缓存读取失败"
        }
    }

    private func configureHotKey() {
        GlobalHotKeyManager.shared.configure(shortcut: hotKeyShortcut) { [weak self] in
            guard let self else { return }
            QuickPanelController.shared.toggle(viewModel: self, placement: self.quickPanelPlacement)
        }
    }

    private func deleteLocalOnly(_ entry: SyncEntry) {
        do {
            try localStore.deleteLocalEntry(entry, serverAddress: serverAddress)
            reloadLocalCollections()
            message = "已删除本机记录"
        } catch {
            message = "本机删除失败"
        }
    }

    private func makeHistoryItems(visibleEntries: [SyncEntry], hiddenEntries: [SyncEntry]) -> [HistoryListItem] {
        guard !visibleEntries.isEmpty else {
            return hiddenRanges(from: hiddenEntries.map(\.id)).map(HistoryListItem.hiddenRange)
        }

        let visibleIDs = visibleEntries.map(\.id)
        let hiddenIDs = Set(hiddenEntries.map(\.id))
        var items: [HistoryListItem] = []

        if let firstID = visibleIDs.first {
            appendHiddenRange(
                ids: hiddenIDs.filter { $0 > firstID },
                to: &items
            )
        }

        for index in visibleEntries.indices {
            let entry = visibleEntries[index]
            items.append(.entry(entry))

            let lowerBound = index + 1 < visibleEntries.count ? visibleEntries[index + 1].id : Int.min
            appendHiddenRange(
                ids: hiddenIDs.filter { $0 < entry.id && $0 > lowerBound },
                to: &items
            )
        }

        return items
    }

    private func appendHiddenRange(ids: [Int], to items: inout [HistoryListItem]) {
        for range in hiddenRanges(from: ids) {
            items.append(.hiddenRange(range))
        }
    }

    private func hiddenRanges(from ids: [Int]) -> [HiddenEntryRange] {
        let sortedIDs = ids.sorted(by: >)
        guard let first = sortedIDs.first else { return [] }

        var ranges: [HiddenEntryRange] = []
        var startID = first
        var endID = first
        var count = 1

        for id in sortedIDs.dropFirst() {
            if id == endID - 1 {
                endID = id
                count += 1
            } else {
                ranges.append(HiddenEntryRange(startID: endID, endID: startID, count: count))
                startID = id
                endID = id
                count = 1
            }
        }

        ranges.append(HiddenEntryRange(startID: endID, endID: startID, count: count))
        return ranges
    }

    private func copyImage(_ entry: SyncEntry) async throws {
        if let data = ImageDiskCache.cachedData(for: entry, serverAddress: serverAddress, variant: "asset") {
            guard ClipboardClient.writeImage(data) else {
                throw TextSyncError.requestFailed(-1)
            }
            return
        }

        if entry.isLocalOnly {
            throw TextSyncError.requestFailed(-1)
        }

        guard let url = entry.resolvedAssetURL(serverAddress: serverAddress) else {
            throw TextSyncError.invalidServer
        }
        let data = try await service.data(from: url)
        guard ClipboardClient.writeImage(data) else {
            throw TextSyncError.requestFailed(-1)
        }
        try? ImageDiskCache.store(data, for: entry, serverAddress: serverAddress, variant: "asset")
        ImageDiskCache.prune()
    }

    private func imageDataForUpload(_ entry: SyncEntry) async throws -> Data? {
        if let data = ImageDiskCache.cachedData(for: entry, serverAddress: serverAddress, variant: "asset") {
            return data
        }
        guard !entry.isLocalOnly,
              let url = entry.resolvedAssetURL(serverAddress: serverAddress) else {
            return nil
        }
        let data = try await service.data(from: url)
        try? ImageDiskCache.store(data, for: entry, serverAddress: serverAddress, variant: "asset")
        ImageDiskCache.prune()
        return data
    }

    private func warmImageCache(for entries: [SyncEntry]) {
        let serverAddress = self.serverAddress
        let imageEntries = entries.reversed().filter(\.isImage).prefix(24)
        Task.detached(priority: .utility) {
            for entry in imageEntries {
                if ImageDiskCache.cachedData(for: entry, serverAddress: serverAddress, variant: "thumb") != nil {
                    continue
                }
                guard let url = entry.resolvedThumbnailURL(serverAddress: serverAddress) else { continue }
                do {
                    let (data, response) = try await URLSession.shared.data(from: url)
                    guard let httpResponse = response as? HTTPURLResponse,
                          (200..<300).contains(httpResponse.statusCode),
                          NSImage(data: data) != nil else {
                        continue
                    }
                    try? ImageDiskCache.store(data, for: entry, serverAddress: serverAddress, variant: "thumb")
                } catch {
                    continue
                }
            }
            ImageDiskCache.prune()
        }
    }
}

import CoreData
import Foundation
import SwiftUI
import UIKit

struct SyncEntry: Identifiable, Decodable, Equatable {
    let id: Int
    let time: Date
    let content: String
    let isPinned: Bool

    init(id: Int, time: Date, content: String, isPinned: Bool = false) {
        self.id = id
        self.time = time
        self.content = content
        self.isPinned = isPinned
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case time
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        time = try container.decode(Date.self, forKey: .time)
        content = try container.decode(String.self, forKey: .content)
        isPinned = false
    }
}

enum TextSyncError: LocalizedError {
    case invalidServer
    case requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .invalidServer:
            return "服务器地址无效"
        case .requestFailed(let code):
            return "请求失败，状态码 \(code)"
        }
    }
}

enum ServerAddress {
    static func normalized(_ input: String) throws -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") {
            value.removeLast()
        }

        guard !value.isEmpty else {
            throw TextSyncError.invalidServer
        }

        if !value.contains("://") {
            value = "https://\(value)"
        }

        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              components.host != nil else {
            throw TextSyncError.invalidServer
        }

        return value
    }

    static func isPlainHTTP(_ input: String) -> Bool {
        (try? normalized(input).lowercased().hasPrefix("http://")) ?? false
    }
}

final class TextSyncService {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func listEntries(serverAddress: String) async throws -> [SyncEntry] {
        let url = try endpoint("/api/list", serverAddress: serverAddress)
        let (data, response) = try await session.data(from: url)
        try validate(response)
        return try decoder.decode([SyncEntry].self, from: data)
    }

    func post(_ text: String, serverAddress: String) async throws {
        let url = try endpoint("/api/post", serverAddress: serverAddress)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(text.utf8)

        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    func testConnection(serverAddress: String) async throws -> Int {
        try await listEntries(serverAddress: serverAddress).count
    }

    private func endpoint(_ path: String, serverAddress: String) throws -> URL {
        let normalized = try ServerAddress.normalized(serverAddress)
        guard var components = URLComponents(string: normalized) else {
            throw TextSyncError.invalidServer
        }
        components.path = path
        components.query = nil
        guard let url = components.url else {
            throw TextSyncError.invalidServer
        }
        return url
    }

    private func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw TextSyncError.requestFailed(httpResponse.statusCode)
        }
    }
}

@MainActor
final class TextSyncLocalStore {
    static let defaultAppTitle = "文本中转"

    private let container: NSPersistentContainer

    init() {
        let model = NSManagedObjectModel()
        let entryEntity = NSEntityDescription()
        entryEntity.name = "CachedEntry"
        entryEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let id = NSAttributeDescription()
        id.name = "id"
        id.attributeType = .integer64AttributeType
        id.isOptional = false

        let time = NSAttributeDescription()
        time.name = "time"
        time.attributeType = .dateAttributeType
        time.isOptional = false

        let content = NSAttributeDescription()
        content.name = "content"
        content.attributeType = .stringAttributeType
        content.isOptional = false

        let serverAddress = NSAttributeDescription()
        serverAddress.name = "serverAddress"
        serverAddress.attributeType = .stringAttributeType
        serverAddress.isOptional = true

        let isDeleted = NSAttributeDescription()
        isDeleted.name = "isDeleted"
        isDeleted.attributeType = .booleanAttributeType
        isDeleted.isOptional = false
        isDeleted.defaultValue = false

        let isPinned = NSAttributeDescription()
        isPinned.name = "isPinned"
        isPinned.attributeType = .booleanAttributeType
        isPinned.isOptional = false
        isPinned.defaultValue = false

        entryEntity.properties = [id, time, content, serverAddress, isDeleted, isPinned]

        let settingEntity = NSEntityDescription()
        settingEntity.name = "AppSetting"
        settingEntity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        let key = NSAttributeDescription()
        key.name = "key"
        key.attributeType = .stringAttributeType
        key.isOptional = false

        let value = NSAttributeDescription()
        value.name = "value"
        value.attributeType = .stringAttributeType
        value.isOptional = false

        settingEntity.properties = [key, value]
        model.entities = [entryEntity, settingEntity]

        container = NSPersistentContainer(name: "TextSyncLocalStore", managedObjectModel: model)
        let description = container.persistentStoreDescriptions.first
        description?.shouldMigrateStoreAutomatically = true
        description?.shouldInferMappingModelAutomatically = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        var loadError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        container.loadPersistentStores { _, error in
            loadError = error
            semaphore.signal()
        }
        semaphore.wait()

        if let loadError {
            assertionFailure("Core Data store failed to load: \(loadError)")
        }
    }

    func visibleEntries(serverAddress: String) throws -> [SyncEntry] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CachedEntry")
        let serverKey = cacheServerKey(serverAddress)
        if serverKey.isEmpty {
            request.predicate = NSPredicate(format: "isDeleted == NO")
        } else {
            request.predicate = NSPredicate(format: "isDeleted == NO AND (serverAddress == %@ OR serverAddress == nil)", serverKey)
        }
        request.sortDescriptors = [NSSortDescriptor(key: "id", ascending: true)]
        return try container.viewContext.fetch(request).compactMap(makeEntry)
    }

    func merge(_ remoteEntries: [SyncEntry], serverAddress: String) throws {
        let serverKey = cacheServerKey(serverAddress)
        for entry in remoteEntries {
            let object = try cachedObject(id: entry.id, serverAddress: serverKey) ?? NSEntityDescription.insertNewObject(forEntityName: "CachedEntry", into: container.viewContext)
            object.setValue(Int64(entry.id), forKey: "id")
            object.setValue(entry.time, forKey: "time")
            object.setValue(entry.content, forKey: "content")
            object.setValue(serverKey, forKey: "serverAddress")
            if object.value(forKey: "isDeleted") == nil {
                object.setValue(false, forKey: "isDeleted")
            }
            if object.value(forKey: "isPinned") == nil {
                object.setValue(false, forKey: "isPinned")
            }
        }
        try saveIfNeeded()
    }

    func markDeleted(id: Int, serverAddress: String) throws {
        guard let object = try cachedObject(id: id, serverAddress: cacheServerKey(serverAddress)) else { return }
        object.setValue(true, forKey: "isDeleted")
        try saveIfNeeded()
    }

    func markPinned(id: Int, serverAddress: String, isPinned: Bool) throws {
        guard let object = try cachedObject(id: id, serverAddress: cacheServerKey(serverAddress)) else { return }
        object.setValue(isPinned, forKey: "isPinned")
        try saveIfNeeded()
    }

    func serverAddress() throws -> String {
        try settingValue(forKey: "serverAddress")
    }

    func appTitle() throws -> String {
        let title = try settingValue(forKey: "appTitle").trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? Self.defaultAppTitle : title
    }

    func saveServerAddress(_ address: String) throws {
        try saveSetting(key: "serverAddress", value: address.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func saveAppTitle(_ title: String) throws {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        try saveSetting(key: "appTitle", value: value.isEmpty ? Self.defaultAppTitle : value)
    }

    private func saveSetting(key: String, value: String) throws {
        let object = try settingObject(key: key) ?? NSEntityDescription.insertNewObject(forEntityName: "AppSetting", into: container.viewContext)
        object.setValue(key, forKey: "key")
        object.setValue(value, forKey: "value")
        try saveIfNeeded()
    }

    private func cachedObject(id: Int, serverAddress: String) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CachedEntry")
        if serverAddress.isEmpty {
            request.predicate = NSPredicate(format: "id == %lld", Int64(id))
        } else {
            request.predicate = NSPredicate(format: "id == %lld AND (serverAddress == %@ OR serverAddress == nil)", Int64(id), serverAddress)
        }
        request.fetchLimit = 1
        return try container.viewContext.fetch(request).first
    }

    private func cacheServerKey(_ address: String) -> String {
        if let normalized = try? ServerAddress.normalized(address) {
            return normalized
        }
        return address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func settingValue(forKey key: String) throws -> String {
        guard let object = try settingObject(key: key) else { return "" }
        return object.value(forKey: "value") as? String ?? ""
    }

    private func settingObject(key: String) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "AppSetting")
        request.predicate = NSPredicate(format: "key == %@", key)
        request.fetchLimit = 1
        return try container.viewContext.fetch(request).first
    }

    private func makeEntry(from object: NSManagedObject) -> SyncEntry? {
        guard let time = object.value(forKey: "time") as? Date,
              let content = object.value(forKey: "content") as? String else {
            return nil
        }
        let id = object.value(forKey: "id") as? Int64 ?? 0
        let isPinned = object.value(forKey: "isPinned") as? Bool ?? false
        return SyncEntry(id: Int(id), time: time, content: content, isPinned: isPinned)
    }

    private func saveIfNeeded() throws {
        if container.viewContext.hasChanges {
            try container.viewContext.save()
        }
    }
}

@MainActor
final class TextSyncViewModel: ObservableObject {
    private let pageSize = 10
    private let service = TextSyncService()
    private let localStore = TextSyncLocalStore()

    @Published var serverAddress = ""
    @Published var appTitle = TextSyncLocalStore.defaultAppTitle
    @Published var draft = ""
    @Published var entries: [SyncEntry] = []
    @Published var visibleHistoryCount = 10
    @Published var isLoading = false
    @Published var isSending = false
    @Published var isTestingConnection = false
    @Published var connectionTestMessage: String?
    @Published var didLastConnectionTestSucceed = false
    @Published var message: String?

    init() {
        do {
            serverAddress = try localStore.serverAddress()
            appTitle = try localStore.appTitle()
        } catch {
            serverAddress = ""
            appTitle = TextSyncLocalStore.defaultAppTitle
        }
    }

    var latest: SyncEntry? {
        entries.last
    }

    var history: [SyncEntry] {
        Array(entries.filter { !$0.isPinned }.reversed())
    }

    var pinnedEntries: [SyncEntry] {
        Array(entries.filter(\.isPinned).reversed())
    }

    var visibleHistory: [SyncEntry] {
        Array(history.prefix(visibleHistoryCount))
    }

    var canLoadMoreHistory: Bool {
        visibleHistoryCount < history.count
    }

    func loadCachedEntries() {
        do {
            entries = try localStore.visibleEntries(serverAddress: serverAddress)
            normalizeVisibleCount()
        } catch {
            message = "本地缓存读取失败"
        }
    }

    func refresh() async {
        guard !serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            loadCachedEntries()
            message = "请先设置服务器地址"
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let remoteEntries = try await service.listEntries(serverAddress: serverAddress)
            serverAddress = try ServerAddress.normalized(serverAddress)
            try localStore.merge(remoteEntries, serverAddress: serverAddress)
            try localStore.saveServerAddress(serverAddress)
            entries = try localStore.visibleEntries(serverAddress: serverAddress)
            normalizeVisibleCount()
            message = entries.isEmpty ? "服务器暂无文本" : "已同步最新文本"
        } catch {
            loadCachedEntries()
            message = error.localizedDescription
        }
    }

    func send() async {
        guard !serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "请先设置服务器地址"
            return
        }

        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            message = "请输入要同步的文本"
            return
        }

        isSending = true
        defer { isSending = false }

        do {
            try await service.post(draft, serverAddress: serverAddress)
            draft = ""
            message = "文本已上传"
            await refresh()
        } catch {
            message = error.localizedDescription
        }
    }

    func deleteLocal(_ entry: SyncEntry) {
        do {
            try localStore.markDeleted(id: entry.id, serverAddress: serverAddress)
            entries = try localStore.visibleEntries(serverAddress: serverAddress)
            normalizeVisibleCount()
            message = "已从本机历史隐藏"
        } catch {
            message = "本地删除失败"
        }
    }

    func togglePinned(_ entry: SyncEntry) {
        do {
            try localStore.markPinned(id: entry.id, serverAddress: serverAddress, isPinned: !entry.isPinned)
            entries = try localStore.visibleEntries(serverAddress: serverAddress)
            normalizeVisibleCount()
            message = entry.isPinned ? "已取消置顶" : "已置顶"
        } catch {
            message = "置顶状态保存失败"
        }
    }

    func pasteFromClipboard() {
        draft = UIPasteboard.general.string ?? ""
        message = draft.isEmpty ? "剪贴板没有可用文本" : "已从剪贴板粘贴"
    }

    func copyLatest() {
        guard let content = latest?.content, !content.isEmpty else {
            message = "没有可复制的文本"
            return
        }
        UIPasteboard.general.string = content
        message = "已复制最新文本"
    }

    func copy(_ entry: SyncEntry) {
        UIPasteboard.general.string = entry.content
        message = "已复制历史文本"
    }

    func loadMoreHistory() {
        visibleHistoryCount = min(visibleHistoryCount + pageSize, history.count)
    }

    func saveSettings() {
        do {
            try localStore.saveAppTitle(appTitle)
            appTitle = try localStore.appTitle()

            if !serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                serverAddress = try ServerAddress.normalized(serverAddress)
                try localStore.saveServerAddress(serverAddress)
            }

            message = "设置已保存"
        } catch {
            message = "设置保存失败"
        }
    }

    func testConnection() async {
        isTestingConnection = true
        connectionTestMessage = "正在测试连接..."
        didLastConnectionTestSucceed = false
        defer { isTestingConnection = false }

        do {
            serverAddress = try ServerAddress.normalized(serverAddress)
            let count = try await service.testConnection(serverAddress: serverAddress)
            try localStore.saveServerAddress(serverAddress)
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

    private func normalizeVisibleCount() {
        visibleHistoryCount = min(max(visibleHistoryCount, pageSize), history.count)
    }
}

struct ContentView: View {
    @StateObject private var viewModel = TextSyncViewModel()
    @State private var isSettingsPresented = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                List {
                    HeaderView(title: viewModel.appTitle)
                        .textSyncListRow()

                    LatestTextView(
                        entry: viewModel.latest,
                        isLoading: viewModel.isLoading,
                        copyAction: { viewModel.copyLatest() }
                    )
                    .textSyncListRow()

                    ComposerView(
                        draft: $viewModel.draft,
                        isSending: viewModel.isSending,
                        pasteAction: { viewModel.pasteFromClipboard() }
                    ) {
                        Task { await viewModel.send() }
                    }
                    .textSyncListRow()

                    HistorySection(
                        pinnedEntries: viewModel.pinnedEntries,
                        entries: viewModel.visibleHistory,
                        totalCount: viewModel.history.count,
                        canLoadMore: viewModel.canLoadMoreHistory,
                        copyAction: { viewModel.copy($0) },
                        pinAction: { viewModel.togglePinned($0) },
                        deleteAction: { viewModel.deleteLocal($0) },
                        loadMoreAction: { viewModel.loadMoreHistory() }
                    )
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable {
                    await viewModel.refresh()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        isSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("服务器设置")

                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                    .accessibilityLabel("刷新")
                }
            }
            .task {
                viewModel.loadCachedEntries()
                if viewModel.entries.isEmpty {
                    await viewModel.refresh()
                }
            }
            .sheet(isPresented: $isSettingsPresented) {
                SettingsView(
                    appTitle: $viewModel.appTitle,
                    serverAddress: $viewModel.serverAddress,
                    isTestingConnection: viewModel.isTestingConnection,
                    connectionTestMessage: viewModel.connectionTestMessage,
                    didLastConnectionTestSucceed: viewModel.didLastConnectionTestSucceed
                ) {
                    Task { await viewModel.testConnection() }
                } saveAction: {
                    viewModel.saveSettings()
                    isSettingsPresented = false
                    Task { await viewModel.refresh() }
                }
                .presentationDetents([.medium, .large])
            }
            .overlay(alignment: .bottom) {
                if let message = viewModel.message {
                    ToastView(message: message)
                        .task(id: message) {
                            try? await Task.sleep(nanoseconds: 2_400_000_000)
                            if viewModel.message == message {
                                withAnimation {
                                    viewModel.message = nil
                                }
                            }
                        }
                }
            }
        }
    }
}

private struct HeaderView: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "bolt.horizontal.circle.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.textSyncBrown)

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(TextSyncPanelBackground(tint: Color.textSyncCream))
    }
}

private struct LatestTextView: View {
    let entry: SyncEntry?
    let isLoading: Bool
    let copyAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最新文本")
                    .font(.headline)
                    .foregroundStyle(Color.textSyncBrown)

                Spacer()

                if let entry {
                    Text(entry.time.textSyncFormatted)
                        .font(.caption)
                        .foregroundStyle(Color.textSyncMuted)
                }
            }

            Text(displayText)
                .font(.body)
                .foregroundStyle(Color.textSyncBrown)
                .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
                .padding(14)
                .background(Color.textSyncPaper)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.textSyncLine, lineWidth: 1)
                )
                .textSelection(.enabled)

            Button(action: copyAction) {
                Label("复制最新文本", systemImage: "doc.on.doc.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(TextSyncPillButtonStyle(color: Color.textSyncTeal))
            .disabled(entry == nil)
        }
        .padding(16)
        .background(TextSyncPanelBackground(tint: Color.textSyncPanel))
    }

    private var displayText: String {
        if isLoading && entry == nil {
            return "正在同步..."
        }
        return entry?.content ?? "暂无数据"
    }
}

private struct ComposerView: View {
    @Binding var draft: String
    let isSending: Bool
    let pasteAction: () -> Void
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
                .frame(minHeight: 150)
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

                Button(action: sendAction) {
                    Label(isSending ? "上传中" : "上传", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TextSyncPillButtonStyle(color: Color.textSyncGreen))
                .disabled(isSending)
            }
        }
        .padding(16)
        .background(TextSyncPanelBackground(tint: Color.textSyncPanel))
    }
}

private struct HistorySection: View {
    let pinnedEntries: [SyncEntry]
    let entries: [SyncEntry]
    let totalCount: Int
    let canLoadMore: Bool
    let copyAction: (SyncEntry) -> Void
    let pinAction: (SyncEntry) -> Void
    let deleteAction: (SyncEntry) -> Void
    let loadMoreAction: () -> Void

    var body: some View {
        Section {
            HStack {
                Text("历史记录")
                    .font(.headline)
                    .foregroundStyle(Color.textSyncBrown)

                Spacer()

                if totalCount > 0 {
                    Text("\(entries.count)/\(totalCount)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.textSyncMuted)
                } else if !pinnedEntries.isEmpty {
                    Text("\(pinnedEntries.count) 个置顶")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.textSyncMuted)
                }
            }
            .textSyncListRow()

            if entries.isEmpty && pinnedEntries.isEmpty {
                Text("本机缓存暂无历史，点右上角刷新同步。")
                    .font(.callout)
                    .foregroundStyle(Color.textSyncMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.textSyncPaper)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .textSyncListRow()
            } else {
                ForEach(pinnedEntries) { entry in
                    historyButton(entry)
                }

                ForEach(entries) { entry in
                    historyButton(entry)
                }

                if canLoadMore {
                    Button(action: loadMoreAction) {
                        Label("加载更多", systemImage: "chevron.down.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TextSyncPillButtonStyle(color: Color.textSyncTeal))
                    .textSyncListRow()
                }
            }
        }
    }

    private func historyButton(_ entry: SyncEntry) -> some View {
        Button {
            copyAction(entry)
        } label: {
            HistoryRow(entry: entry)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteAction(entry)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                pinAction(entry)
            } label: {
                Label(entry.isPinned ? "取消置顶" : "置顶", systemImage: entry.isPinned ? "pin.slash" : "pin")
            }
            .tint(Color.textSyncTeal)
        }
        .textSyncListRow()
    }
}

private struct HistoryRow: View {
    let entry: SyncEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if entry.isPinned {
                    Label("#\(entry.id)", systemImage: "pin.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.textSyncTeal)
                } else {
                    Text("#\(entry.id)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.textSyncTeal)
                }

                Spacer()

                Text(entry.time.textSyncFormatted)
                    .font(.caption)
                    .foregroundStyle(Color.textSyncMuted)
            }

            Text(entry.content)
                .font(.callout)
                .foregroundStyle(Color.textSyncBrown)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
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

private struct SettingsView: View {
    @Binding var appTitle: String
    @Binding var serverAddress: String
    let isTestingConnection: Bool
    let connectionTestMessage: String?
    let didLastConnectionTestSucceed: Bool
    let testAction: () -> Void
    let saveAction: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("首页名称")
                    .font(.headline)
                    .foregroundStyle(Color.textSyncBrown)

                TextField("文本中转", text: $appTitle)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .frame(height: 46)
                    .background(Color.textSyncPaper)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.textSyncLine, lineWidth: 1)
                    )

                Text("服务器地址")
                    .font(.headline)
                    .foregroundStyle(Color.textSyncBrown)

                TextField("https://example.com", text: $serverAddress)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .frame(height: 46)
                    .background(Color.textSyncPaper)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.textSyncLine, lineWidth: 1)
                    )

                if ServerAddress.isPlainHTTP(serverAddress) {
                    Label("当前使用 HTTP，局域网或自签测试可以使用；公网建议 HTTPS。", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.textSyncWarning)
                }

                Text("可填写域名、IP、端口；未写协议时会默认使用 HTTPS。")
                    .font(.footnote)
                    .foregroundStyle(Color.textSyncMuted)

                Button(action: testAction) {
                    Label(isTestingConnection ? "测试中" : "测试连接", systemImage: "network")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TextSyncPillButtonStyle(color: Color.textSyncBrown))
                .disabled(isTestingConnection)

                if let connectionTestMessage {
                    Label(
                        connectionTestMessage,
                        systemImage: didLastConnectionTestSucceed ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(didLastConnectionTestSucceed ? Color.textSyncGreen : Color.textSyncWarning)
                }

                Button(action: saveAction) {
                    Label("保存并同步", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TextSyncPillButtonStyle(color: Color.textSyncTeal))

                Spacer()
            }
            .padding(18)
            .background(AppBackground())
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct ToastView: View {
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

private struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark ? darkColors : lightColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var lightColors: [Color] {
        [
            Color(red: 0.98, green: 0.97, blue: 0.92),
            Color(red: 0.89, green: 0.97, blue: 0.95),
            Color(red: 1.00, green: 0.94, blue: 0.86)
        ]
    }

    private var darkColors: [Color] {
        [
            Color(red: 0.11, green: 0.10, blue: 0.08),
            Color(red: 0.08, green: 0.16, blue: 0.15),
            Color(red: 0.16, green: 0.12, blue: 0.08)
        ]
    }
}

private struct TextSyncPanelBackground: View {
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(tint)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.textSyncPanelStroke, lineWidth: 1)
            )
            .shadow(color: Color.textSyncBrown.opacity(0.10), radius: 18, x: 0, y: 8)
    }
}

private struct TextSyncPillButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(Capsule().fill(color))
            .shadow(color: color.opacity(0.28), radius: 0, x: 0, y: configuration.isPressed ? 1 : 4)
            .offset(y: configuration.isPressed ? 2 : 0)
    }
}

private extension View {
    func textSyncListRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 9, leading: 18, bottom: 9, trailing: 18))
    }
}

private extension Date {
    static let textSyncFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()

    var textSyncFormatted: String {
        Date.textSyncFormatter.string(from: self)
    }
}

private extension Color {
    static let textSyncBrown = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.93, green: 0.84, blue: 0.70, alpha: 1)
            : UIColor(red: 0.44, green: 0.30, blue: 0.18, alpha: 1)
    })

    static let textSyncMuted = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.72, green: 0.66, blue: 0.56, alpha: 1)
            : UIColor(red: 0.54, green: 0.47, blue: 0.37, alpha: 1)
    })

    static let textSyncTeal = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.24, green: 0.86, blue: 0.78, alpha: 1)
            : UIColor(red: 0.10, green: 0.70, blue: 0.65, alpha: 1)
    })

    static let textSyncGreen = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.61, green: 0.84, blue: 0.36, alpha: 1)
            : UIColor(red: 0.39, green: 0.66, blue: 0.22, alpha: 1)
    })

    static let textSyncWarning = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.72, blue: 0.28, alpha: 1)
            : UIColor(red: 0.84, green: 0.52, blue: 0.10, alpha: 1)
    })

    static let textSyncCream = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.23, green: 0.18, blue: 0.12, alpha: 1)
            : UIColor(red: 1.00, green: 0.96, blue: 0.84, alpha: 1)
    })

    static let textSyncPaper = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.16, green: 0.15, blue: 0.12, alpha: 1)
            : UIColor(red: 1.00, green: 0.99, blue: 0.95, alpha: 1)
    })

    static let textSyncLine = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.36, green: 0.31, blue: 0.24, alpha: 1)
            : UIColor(red: 0.82, green: 0.77, blue: 0.68, alpha: 1)
    })

    static let textSyncPanel = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.13, green: 0.12, blue: 0.10, alpha: 0.92)
            : UIColor(white: 1.0, alpha: 0.82)
    })

    static let textSyncPanelStroke = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.40, green: 0.34, blue: 0.26, alpha: 0.70)
            : UIColor(white: 1.0, alpha: 0.75)
    })
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

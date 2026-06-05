import CoreData
import Foundation
import SwiftUI
import UIKit

struct DetectedContentAction: Identifiable, Equatable {
    enum Kind: String {
        case link
        case email
        case phone
    }

    let kind: Kind
    let value: String
    let url: URL

    var id: String {
        "\(kind.rawValue)-\(url.absoluteString)"
    }

    var systemImage: String {
        switch kind {
        case .link: return "safari"
        case .email: return "envelope.fill"
        case .phone: return "phone.fill"
        }
    }

    var category: String {
        kind.rawValue
    }

    var menuTitle: String {
        switch kind {
        case .link:
            return "打开 \(url.host ?? value)"
        case .email:
            return "发邮件给 \(value)"
        case .phone:
            return "拨打 \(value)"
        }
    }

    static func detect(in text: String) -> [DetectedContentAction] {
        guard !text.isEmpty else { return [] }

        var actions: [DetectedContentAction] = []
        var seen = Set<String>()
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.phoneNumber.rawValue) {
            for match in detector.matches(in: text, options: [], range: fullRange) {
                if let phoneNumber = match.phoneNumber,
                   let url = phoneURL(for: phoneNumber) {
                    append(kind: .phone, value: phoneNumber, url: url, to: &actions, seen: &seen)
                    continue
                }

                guard let url = match.url else { continue }
                if url.scheme?.lowercased() == "mailto" {
                    let rawEmail = String(url.absoluteString.dropFirst("mailto:".count))
                    let email = rawEmail.removingPercentEncoding ?? rawEmail
                    append(kind: .email, value: email, url: url, to: &actions, seen: &seen)
                } else {
                    append(kind: .link, value: url.absoluteString, url: url, to: &actions, seen: &seen)
                }
            }
        }

        for email in emails(in: text) {
            guard let url = URL(string: "mailto:\(email)") else { continue }
            append(kind: .email, value: email, url: url, to: &actions, seen: &seen)
        }

        return actions
    }

    static func primaryCategory(kind: String, content: String) -> String {
        if kind.lowercased() == "image" {
            return "image"
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "text" }

        if isWholeHTTPURL(trimmed) {
            return "link"
        }
        if isWholeEmail(trimmed) {
            return "email"
        }
        if isWholePhone(trimmed) {
            return "phone"
        }
        return "text"
    }

    private static func append(kind: Kind, value: String, url: URL, to actions: inout [DetectedContentAction], seen: inout Set<String>) {
        let key = "\(kind.rawValue)-\(value.lowercased())"
        guard !seen.contains(key) else { return }
        seen.insert(key)
        actions.append(DetectedContentAction(kind: kind, value: value, url: url))
    }

    private static func emails(in text: String) -> [String] {
        let pattern = #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func phoneURL(for phoneNumber: String) -> URL? {
        let allowed = Set("+0123456789")
        let normalized = phoneNumber.filter { allowed.contains($0) }
        guard normalized.count >= 5 else { return nil }
        return URL(string: "tel:\(normalized)")
    }

    private static func isWholeHTTPURL(_ text: String) -> Bool {
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return false
        }
        return url.absoluteString == text || url.absoluteString == text + "/"
    }

    private static func isWholeEmail(_ text: String) -> Bool {
        emails(in: text).contains { $0.caseInsensitiveCompare(text) == .orderedSame }
    }

    private static func isWholePhone(_ text: String) -> Bool {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue) else {
            return false
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        return matches.count == 1 && matches[0].range.location == 0 && matches[0].range.length == range.length
    }
}

struct SyncEntry: Identifiable, Decodable, Equatable {
    let id: Int
    let time: Date
    let content: String
    let kind: String
    let category: String
    let mimeType: String?
    let assetURL: String?
    let thumbnailURL: String?
    let fileName: String?
    let width: Int?
    let height: Int?
    let byteCount: Int?
    let deletedAt: Date?
    let isPinned: Bool
    let isLocallyEdited: Bool
    let isHidden: Bool

    init(
        id: Int,
        time: Date,
        content: String,
        kind: String = "text",
        category: String = "",
        mimeType: String? = nil,
        assetURL: String? = nil,
        thumbnailURL: String? = nil,
        fileName: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        byteCount: Int? = nil,
        deletedAt: Date? = nil,
        isPinned: Bool = false,
        isLocallyEdited: Bool = false,
        isHidden: Bool = false
    ) {
        self.id = id
        self.time = time
        self.content = content
        self.kind = kind.isEmpty ? "text" : kind
        self.category = category.isEmpty ? SyncEntry.defaultCategory(kind: kind, content: content) : category
        self.mimeType = mimeType
        self.assetURL = assetURL
        self.thumbnailURL = thumbnailURL
        self.fileName = fileName
        self.width = width
        self.height = height
        self.byteCount = byteCount
        self.deletedAt = deletedAt
        self.isPinned = isPinned
        self.isLocallyEdited = isLocallyEdited
        self.isHidden = isHidden
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case time
        case content
        case kind
        case category
        case mimeType = "mime_type"
        case assetURL = "asset_url"
        case thumbnailURL = "thumbnail_url"
        case fileName = "file_name"
        case width
        case height
        case byteCount = "byte_count"
        case deletedAt = "deleted_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        time = try container.decode(Date.self, forKey: .time)
        content = try container.decode(String.self, forKey: .content)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "text"
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? SyncEntry.defaultCategory(kind: kind, content: content)
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        assetURL = try container.decodeIfPresent(String.self, forKey: .assetURL)
        thumbnailURL = try container.decodeIfPresent(String.self, forKey: .thumbnailURL)
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
        width = try container.decodeIfPresent(Int.self, forKey: .width)
        height = try container.decodeIfPresent(Int.self, forKey: .height)
        byteCount = try container.decodeIfPresent(Int.self, forKey: .byteCount)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        isPinned = false
        isLocallyEdited = false
        isHidden = false
    }

    var isImage: Bool {
        kind == "image"
    }

    var isServerDeleted: Bool {
        deletedAt != nil
    }

    var normalizedCategory: String {
        category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var effectiveCategory: String {
        DetectedContentAction.primaryCategory(kind: kind, content: content)
    }

    var displayCategory: String {
        let normalized = normalizedCategory
        if normalized.isEmpty || normalized == "text" {
            return effectiveCategory
        }
        return normalized
    }

    var detectedActions: [DetectedContentAction] {
        DetectedContentAction.detect(in: content)
    }

    var detectedURLs: [URL] {
        detectedActions.filter { $0.kind == .link }.map(\.url)
    }

    var primaryAction: DetectedContentAction? {
        detectedActions.first { $0.category == displayCategory } ?? detectedActions.first
    }

    var imageDetailText: String {
        let size = width.flatMap { width in height.map { "\(width)×\($0)" } }
        let name = fileName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return [name, size].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " · ")
    }

    func resolvedThumbnailURL(serverAddress: String) -> URL? {
        resolvedURL(thumbnailURL ?? assetURL, serverAddress: serverAddress)
    }

    func resolvedAssetURL(serverAddress: String) -> URL? {
        resolvedURL(assetURL, serverAddress: serverAddress)
    }

    private func resolvedURL(_ rawValue: String?, serverAddress: String) -> URL? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        if let absoluteURL = URL(string: rawValue), absoluteURL.scheme != nil {
            return absoluteURL
        }
        guard let normalized = try? ServerAddress.normalized(serverAddress),
              let baseURL = URL(string: normalized) else {
            return nil
        }
        return URL(string: rawValue, relativeTo: baseURL)?.absoluteURL
    }

    private static func defaultCategory(kind: String, content: String) -> String {
        DetectedContentAction.primaryCategory(kind: kind, content: content)
    }
}

enum EntryCategoryFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case image
    case link
    case email
    case phone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .text: return "文本"
        case .image: return "图片"
        case .link: return "链接"
        case .email: return "邮箱"
        case .phone: return "电话"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .link: return "link"
        case .email: return "envelope"
        case .phone: return "phone"
        }
    }
}

struct HiddenEntryRange: Identifiable, Equatable {
    let startID: Int
    let endID: Int
    let count: Int

    var id: String {
        "\(startID)-\(endID)-\(count)"
    }

    var title: String {
        if startID == endID {
            return "已隐藏 #\(startID)"
        }
        return "已隐藏 #\(startID)-#\(endID)"
    }
}

enum HistoryListItem: Identifiable, Equatable {
    case entry(SyncEntry)
    case hiddenRange(HiddenEntryRange)

    var id: String {
        switch self {
        case .entry(let entry):
            return "entry-\(entry.id)"
        case .hiddenRange(let range):
            return "hidden-\(range.id)"
        }
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

    func listEntries(serverAddress: String, includeDeleted: Bool = false, category: EntryCategoryFilter = .all) async throws -> [SyncEntry] {
        var queryItems: [URLQueryItem] = []
        if includeDeleted {
            queryItems.append(URLQueryItem(name: "include_deleted", value: "1"))
        }
        if category != .all {
            queryItems.append(URLQueryItem(name: "category", value: category.rawValue))
        }
        let url = try endpoint("/api/list", serverAddress: serverAddress, queryItems: queryItems)
        let (data, response) = try await session.data(for: getRequest(url: url))
        try validate(response)
        return try decoder.decode([SyncEntry].self, from: data)
    }

    func trashEntries(serverAddress: String) async throws -> [SyncEntry] {
        let url = try endpoint("/api/trash", serverAddress: serverAddress)
        let (data, response) = try await session.data(for: getRequest(url: url))
        try validate(response)
        return try decoder.decode([SyncEntry].self, from: data)
    }

    func latestContent(serverAddress: String) async throws -> String {
        let url = try endpoint("/api/get", serverAddress: serverAddress)
        let (data, response) = try await session.data(for: getRequest(url: url))
        try validate(response)
        return String(decoding: data, as: UTF8.self)
    }

    func latestTextContent(serverAddress: String) async throws -> String {
        try await listEntries(serverAddress: serverAddress)
            .reversed()
            .first { !$0.isImage && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
            .content ?? ""
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

    func postImage(_ imageData: Data, fileName: String, mimeType: String, serverAddress: String) async throws {
        let url = try endpoint("/api/items", serverAddress: serverAddress)
        let boundary = "TextSyncBoundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(
            imageData: imageData,
            fileName: fileName,
            mimeType: mimeType,
            boundary: boundary
        )

        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    func data(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(for: getRequest(url: url))
        try validate(response)
        return data
    }

    func deleteEntry(_ entry: SyncEntry, serverAddress: String, permanently: Bool = false) async throws {
        let path = permanently ? "/api/items/\(entry.id)/permanent" : "/api/items/\(entry.id)"
        var request = URLRequest(url: try endpoint(path, serverAddress: serverAddress))
        request.httpMethod = "DELETE"
        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    func permanentlyDeleteTrash(serverAddress: String, category: EntryCategoryFilter = .all) async throws {
        var queryItems: [URLQueryItem] = []
        if category != .all {
            queryItems.append(URLQueryItem(name: "category", value: category.rawValue))
        }
        var request = URLRequest(url: try endpoint("/api/trash/permanent", serverAddress: serverAddress, queryItems: queryItems))
        request.httpMethod = "DELETE"
        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    func restoreEntry(_ entry: SyncEntry, serverAddress: String) async throws {
        var request = URLRequest(url: try endpoint("/api/items/\(entry.id)/restore", serverAddress: serverAddress))
        request.httpMethod = "POST"
        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    func testConnection(serverAddress: String) async throws -> Int {
        try await listEntries(serverAddress: serverAddress).count
    }

    private func endpoint(_ path: String, serverAddress: String, queryItems: [URLQueryItem] = []) throws -> URL {
        let normalized = try ServerAddress.normalized(serverAddress)
        guard var components = URLComponents(string: normalized) else {
            throw TextSyncError.invalidServer
        }
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw TextSyncError.invalidServer
        }
        return url
    }

    private func getRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        return request
    }

    private func multipartBody(imageData: Data, fileName: String, mimeType: String, boundary: String) -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8) ?? Data())
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"\(fileName)\"\r\n".data(using: .utf8) ?? Data())
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8) ?? Data())
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8) ?? Data())
        return body
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

        let kind = NSAttributeDescription()
        kind.name = "kind"
        kind.attributeType = .stringAttributeType
        kind.isOptional = true

        let category = NSAttributeDescription()
        category.name = "category"
        category.attributeType = .stringAttributeType
        category.isOptional = true

        let mimeType = NSAttributeDescription()
        mimeType.name = "mimeType"
        mimeType.attributeType = .stringAttributeType
        mimeType.isOptional = true

        let assetURL = NSAttributeDescription()
        assetURL.name = "assetURL"
        assetURL.attributeType = .stringAttributeType
        assetURL.isOptional = true

        let thumbnailURL = NSAttributeDescription()
        thumbnailURL.name = "thumbnailURL"
        thumbnailURL.attributeType = .stringAttributeType
        thumbnailURL.isOptional = true

        let fileName = NSAttributeDescription()
        fileName.name = "fileName"
        fileName.attributeType = .stringAttributeType
        fileName.isOptional = true

        let width = NSAttributeDescription()
        width.name = "width"
        width.attributeType = .integer64AttributeType
        width.isOptional = true

        let height = NSAttributeDescription()
        height.name = "height"
        height.attributeType = .integer64AttributeType
        height.isOptional = true

        let byteCount = NSAttributeDescription()
        byteCount.name = "byteCount"
        byteCount.attributeType = .integer64AttributeType
        byteCount.isOptional = true

        let serverDeletedAt = NSAttributeDescription()
        serverDeletedAt.name = "serverDeletedAt"
        serverDeletedAt.attributeType = .dateAttributeType
        serverDeletedAt.isOptional = true

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

        let isLocallyEdited = NSAttributeDescription()
        isLocallyEdited.name = "isLocallyEdited"
        isLocallyEdited.attributeType = .booleanAttributeType
        isLocallyEdited.isOptional = false
        isLocallyEdited.defaultValue = false

        entryEntity.properties = [
            id,
            time,
            content,
            kind,
            category,
            mimeType,
            assetURL,
            thumbnailURL,
            fileName,
            width,
            height,
            byteCount,
            serverDeletedAt,
            serverAddress,
            isDeleted,
            isPinned,
            isLocallyEdited
        ]

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
        try entries(serverAddress: serverAddress, includeHidden: false)
    }

    func hiddenEntries(serverAddress: String) throws -> [SyncEntry] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CachedEntry")
        let serverKey = cacheServerKey(serverAddress)
        if serverKey.isEmpty {
            request.predicate = NSPredicate(format: "isDeleted == YES AND serverDeletedAt == nil")
        } else {
            request.predicate = NSPredicate(format: "isDeleted == YES AND serverDeletedAt == nil AND (serverAddress == %@ OR serverAddress == nil)", serverKey)
        }
        request.sortDescriptors = [NSSortDescriptor(key: "id", ascending: true)]
        return try container.viewContext.fetch(request).compactMap(makeEntry)
    }

    func trashEntries(serverAddress: String) throws -> [SyncEntry] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CachedEntry")
        let serverKey = cacheServerKey(serverAddress)
        if serverKey.isEmpty {
            request.predicate = NSPredicate(format: "serverDeletedAt != nil")
        } else {
            request.predicate = NSPredicate(format: "serverDeletedAt != nil AND (serverAddress == %@ OR serverAddress == nil)", serverKey)
        }
        request.sortDescriptors = [NSSortDescriptor(key: "id", ascending: false)]
        return try container.viewContext.fetch(request).compactMap(makeEntry)
    }

    private func entries(serverAddress: String, includeHidden: Bool) throws -> [SyncEntry] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CachedEntry")
        let serverKey = cacheServerKey(serverAddress)
        if serverKey.isEmpty {
            request.predicate = includeHidden
                ? NSPredicate(format: "serverDeletedAt == nil")
                : NSPredicate(format: "isDeleted == NO AND serverDeletedAt == nil")
        } else {
            request.predicate = includeHidden
                ? NSPredicate(format: "serverDeletedAt == nil AND (serverAddress == %@ OR serverAddress == nil)", serverKey)
                : NSPredicate(format: "isDeleted == NO AND serverDeletedAt == nil AND (serverAddress == %@ OR serverAddress == nil)", serverKey)
        }
        request.sortDescriptors = [NSSortDescriptor(key: "id", ascending: true)]
        return try container.viewContext.fetch(request).compactMap(makeEntry)
    }

    func merge(_ remoteEntries: [SyncEntry], serverAddress: String, preserveLocalEdits: Bool) throws {
        let serverKey = cacheServerKey(serverAddress)
        let remoteIDs = Set(remoteEntries.map(\.id))
        for entry in remoteEntries {
            let object = try cachedObject(id: entry.id, serverAddress: serverKey) ?? NSEntityDescription.insertNewObject(forEntityName: "CachedEntry", into: container.viewContext)
            let shouldKeepLocalContent = preserveLocalEdits && (object.value(forKey: "isLocallyEdited") as? Bool ?? false)
            object.setValue(Int64(entry.id), forKey: "id")
            if !shouldKeepLocalContent {
                object.setValue(entry.time, forKey: "time")
                object.setValue(entry.content, forKey: "content")
                object.setValue(false, forKey: "isLocallyEdited")
            }
            updateMetadata(on: object, with: entry)
            object.setValue(serverKey, forKey: "serverAddress")
            if object.value(forKey: "isDeleted") == nil {
                object.setValue(false, forKey: "isDeleted")
            }
            if object.value(forKey: "isPinned") == nil {
                object.setValue(false, forKey: "isPinned")
            }
            if object.value(forKey: "isLocallyEdited") == nil {
                object.setValue(false, forKey: "isLocallyEdited")
            }
        }
        try pruneRemoteEntries(missingFrom: remoteIDs, serverAddress: serverKey)
        try saveIfNeeded()
    }

    private func pruneRemoteEntries(missingFrom remoteIDs: Set<Int>, serverAddress serverKey: String) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CachedEntry")
        if serverKey.isEmpty {
            request.predicate = NSPredicate(format: "serverAddress == nil")
        } else {
            request.predicate = NSPredicate(format: "serverAddress == %@ OR serverAddress == nil", serverKey)
        }

        let objects = try container.viewContext.fetch(request)
        for object in objects {
            let id = Int(object.value(forKey: "id") as? Int64 ?? -1)
            if !remoteIDs.contains(id) {
                container.viewContext.delete(object)
            }
        }
    }

    func markHidden(id: Int, serverAddress: String, isHidden: Bool) throws {
        guard let object = try cachedObject(id: id, serverAddress: cacheServerKey(serverAddress)) else { return }
        object.setValue(isHidden, forKey: "isDeleted")
        try saveIfNeeded()
    }

    func restoreHiddenEntries(ids: [Int], serverAddress: String) throws {
        for id in ids {
            try markHidden(id: id, serverAddress: serverAddress, isHidden: false)
        }
    }

    func resetCachedEntries(serverAddress: String) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CachedEntry")
        let serverKey = cacheServerKey(serverAddress)
        if !serverKey.isEmpty {
            request.predicate = NSPredicate(format: "serverAddress == %@ OR serverAddress == nil", serverKey)
        }

        let objects = try container.viewContext.fetch(request)
        for object in objects {
            container.viewContext.delete(object)
        }
        try saveIfNeeded()
    }

    func markPinned(id: Int, serverAddress: String, isPinned: Bool) throws {
        guard let object = try cachedObject(id: id, serverAddress: cacheServerKey(serverAddress)) else { return }
        object.setValue(isPinned, forKey: "isPinned")
        try saveIfNeeded()
    }

    func saveLocalContent(id: Int, serverAddress: String, content: String) throws {
        guard let object = try cachedObject(id: id, serverAddress: cacheServerKey(serverAddress)) else { return }
        object.setValue(content, forKey: "content")
        object.setValue(true, forKey: "isLocallyEdited")
        try saveIfNeeded()
    }

    func replaceWithRemote(_ entry: SyncEntry, serverAddress: String) throws {
        let serverKey = cacheServerKey(serverAddress)
        let object = try cachedObject(id: entry.id, serverAddress: serverKey) ?? NSEntityDescription.insertNewObject(forEntityName: "CachedEntry", into: container.viewContext)
        object.setValue(Int64(entry.id), forKey: "id")
        object.setValue(entry.time, forKey: "time")
        object.setValue(entry.content, forKey: "content")
        object.setValue(false, forKey: "isLocallyEdited")
        updateMetadata(on: object, with: entry)
        object.setValue(serverKey, forKey: "serverAddress")
        if object.value(forKey: "isDeleted") == nil {
            object.setValue(false, forKey: "isDeleted")
        }
        if object.value(forKey: "isPinned") == nil {
            object.setValue(false, forKey: "isPinned")
        }
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
        let isLocallyEdited = object.value(forKey: "isLocallyEdited") as? Bool ?? false
        let isHidden = object.value(forKey: "isDeleted") as? Bool ?? false
        return SyncEntry(
            id: Int(id),
            time: time,
            content: content,
            kind: object.value(forKey: "kind") as? String ?? "text",
            category: object.value(forKey: "category") as? String ?? "",
            mimeType: object.value(forKey: "mimeType") as? String,
            assetURL: object.value(forKey: "assetURL") as? String,
            thumbnailURL: object.value(forKey: "thumbnailURL") as? String,
            fileName: object.value(forKey: "fileName") as? String,
            width: (object.value(forKey: "width") as? Int64).map(Int.init),
            height: (object.value(forKey: "height") as? Int64).map(Int.init),
            byteCount: (object.value(forKey: "byteCount") as? Int64).map(Int.init),
            deletedAt: object.value(forKey: "serverDeletedAt") as? Date,
            isPinned: isPinned,
            isLocallyEdited: isLocallyEdited,
            isHidden: isHidden
        )
    }

    private func updateMetadata(on object: NSManagedObject, with entry: SyncEntry) {
        object.setValue(entry.kind, forKey: "kind")
        object.setValue(entry.category, forKey: "category")
        object.setValue(entry.mimeType, forKey: "mimeType")
        object.setValue(entry.assetURL, forKey: "assetURL")
        object.setValue(entry.thumbnailURL, forKey: "thumbnailURL")
        object.setValue(entry.fileName, forKey: "fileName")
        object.setValue(entry.width.map { Int64($0) }, forKey: "width")
        object.setValue(entry.height.map { Int64($0) }, forKey: "height")
        object.setValue(entry.byteCount.map { Int64($0) }, forKey: "byteCount")
        object.setValue(entry.deletedAt, forKey: "serverDeletedAt")
    }

    private func saveIfNeeded() throws {
        if container.viewContext.hasChanges {
            try container.viewContext.save()
        }
    }
}

@MainActor
final class TextSyncViewModel: ObservableObject {
    private struct ClipboardImagePayload {
        let data: Data
        let fileName: String
        let mimeType: String
    }

    private let pageSize = 10
    private let maxClipboardImageBytes = 8 * 1024 * 1024
    private let service = TextSyncService()
    private let localStore = TextSyncLocalStore()

    @Published var serverAddress = ""
    @Published var appTitle = TextSyncLocalStore.defaultAppTitle
    @Published var draft = ""
    @Published var latestDraft = ""
    @Published var entries: [SyncEntry] = []
    @Published var hiddenEntries: [SyncEntry] = []
    @Published var trashEntries: [SyncEntry] = []
    @Published var selectedCategory: EntryCategoryFilter = .all
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

    var filteredEntries: [SyncEntry] {
        guard selectedCategory != .all else { return entries }
        return entries.filter { $0.displayCategory == selectedCategory.rawValue }
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
        return entries.filter { $0.displayCategory == category.rawValue }.count
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

    func refresh(allowOverwriteLocalEdits: Bool = false) async {
        guard !serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            loadCachedEntries()
            message = "请先设置服务器地址"
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
            message = entries.isEmpty ? "服务器暂无内容" : "已同步最新内容"
        } catch {
            loadCachedEntries()
            message = error.localizedDescription
        }
    }

    func sendClipboardImage() async {
        guard !serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "请先设置服务器地址"
            return
        }

        guard let payload = clipboardImagePayload() else {
            message = "剪贴板没有可上传图片"
            return
        }

        isSending = true
        defer { isSending = false }

        do {
            try await service.postImage(
                payload.data,
                fileName: payload.fileName,
                mimeType: payload.mimeType,
                serverAddress: serverAddress
            )
            message = "图片已上传"
            await refresh()
        } catch {
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
        if let text = UIPasteboard.general.string, !text.isEmpty {
            draft = text
            message = "已从剪贴板粘贴"
        } else if UIPasteboard.general.image != nil {
            message = "剪贴板是图片，可直接上传图片"
        } else {
            message = "剪贴板没有可用内容"
        }
    }

    func copyLatest() async {
        guard let latest else {
            message = "没有可复制的文本"
            return
        }

        if latest.isImage {
            await copyImage(latest)
            return
        }

        let content = latestDraft.isEmpty ? latest.content : latestDraft
        guard !content.isEmpty else {
            message = "没有可复制的文本"
            return
        }
        UIPasteboard.general.string = content
        message = "已复制最新文本"
    }

    func copy(_ entry: SyncEntry) async {
        if entry.isImage {
            await copyImage(entry)
            return
        }

        UIPasteboard.general.string = entry.content
        message = "已复制历史文本"
    }

    func updateLatestDraft(_ content: String) {
        guard latest?.isImage != true else { return }
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
            let remoteEntries = try await service.listEntries(serverAddress: serverAddress)
            guard let remoteEntry = remoteEntries.first(where: { $0.id == entry.id }) else {
                message = "云端没有找到 #\(entry.id)"
                return
            }
            serverAddress = try ServerAddress.normalized(serverAddress)
            try localStore.replaceWithRemote(remoteEntry, serverAddress: serverAddress)
            entries = try localStore.visibleEntries(serverAddress: serverAddress)
            hiddenEntries = try localStore.hiddenEntries(serverAddress: serverAddress)
            trashEntries = try localStore.trashEntries(serverAddress: serverAddress)
            syncLatestDraft()
            normalizeVisibleCount()
            message = "已用云端更新 #\(entry.id)"
        } catch {
            message = "更新失败：\(error.localizedDescription)"
        }
    }

    func deleteRemote(_ entry: SyncEntry) async {
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

    func permanentlyDeleteAllTrashRemote() async {
        guard !serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "请先设置服务器地址"
            return
        }

        do {
            try await service.permanentlyDeleteTrash(serverAddress: serverAddress)
            await refresh(allowOverwriteLocalEdits: false)
            message = "已清空回收站"
        } catch {
            message = "清空回收站失败：\(error.localizedDescription)"
        }
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

    func resetLocalData() {
        do {
            try localStore.resetCachedEntries(serverAddress: serverAddress)
            entries = []
            hiddenEntries = []
            trashEntries = []
            latestDraft = ""
            visibleHistoryCount = pageSize
            message = "本地数据已重置"
        } catch {
            message = "本地数据重置失败"
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

    private func syncLatestDraft() {
        latestDraft = latest?.isImage == true ? "" : latest?.content ?? ""
    }

    private func clipboardImagePayload() -> ClipboardImagePayload? {
        guard let image = UIPasteboard.general.image else { return nil }
        if let pngData = image.pngData(), pngData.count <= maxClipboardImageBytes {
            return ClipboardImagePayload(
                data: pngData,
                fileName: "clipboard.png",
                mimeType: "image/png"
            )
        }
        if let jpegData = image.jpegData(compressionQuality: 0.86), jpegData.count <= maxClipboardImageBytes {
            return ClipboardImagePayload(
                data: jpegData,
                fileName: "clipboard.jpg",
                mimeType: "image/jpeg"
            )
        }
        return nil
    }

    private func copyImage(_ entry: SyncEntry) async {
        guard let url = entry.resolvedAssetURL(serverAddress: serverAddress) else {
            message = "图片地址无效"
            return
        }

        do {
            let data = try await service.data(from: url)
            guard let image = UIImage(data: data) else {
                message = "图片读取失败"
                return
            }
            UIPasteboard.general.image = image
            message = "已复制图片"
        } catch {
            message = "复制图片失败：\(error.localizedDescription)"
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
}

struct ContentView: View {
    @StateObject private var viewModel = TextSyncViewModel()
    @State private var isSettingsPresented = false
    @State private var isHelpPresented = false
    @State private var isTrashPresented = false
    @State private var isQuickPanelPresented = false
    @State private var editingEntry: SyncEntry?
    @State private var imagePreviewEntry: SyncEntry?
    @State private var editingText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                List {
                    HeaderView(title: viewModel.appTitle)
                        .textSyncListRow()

                    LatestTextView(
                        entry: viewModel.latest,
                        text: Binding(
                            get: { viewModel.latestDraft },
                            set: { viewModel.updateLatestDraft($0) }
                        ),
                        serverAddress: viewModel.serverAddress,
                        isLoading: viewModel.isLoading,
                        copyAction: { Task { await viewModel.copyLatest() } },
                        openImageAction: { entry in imagePreviewEntry = entry }
                    )
                    .textSyncListRow()

                    ComposerView(
                        draft: $viewModel.draft,
                        isSending: viewModel.isSending,
                        pasteAction: { viewModel.pasteFromClipboard() },
                        uploadImageAction: { Task { await viewModel.sendClipboardImage() } }
                    ) {
                        Task { await viewModel.send() }
                    }
                    .textSyncListRow()

                    CategoryFilterView(
                        selectedCategory: $viewModel.selectedCategory,
                        countProvider: { viewModel.count(for: $0) }
                    )
                    .textSyncListRow()

                    HistorySection(
                        pinnedEntries: viewModel.pinnedEntries,
                        items: viewModel.visibleHistoryItems,
                        totalCount: viewModel.history.count,
                        hiddenCount: viewModel.hiddenHistory.count,
                        latestID: viewModel.latest?.id,
                        serverAddress: viewModel.serverAddress,
                        canLoadMore: viewModel.canLoadMoreHistory,
                        copyAction: { entry in Task { await viewModel.copy(entry) } },
                        editAction: { entry in
                            editingText = entry.content
                            editingEntry = entry
                        },
                        updateFromCloudAction: { entry in
                            Task { await viewModel.updateEntryFromCloud(entry) }
                        },
                        pinAction: { viewModel.togglePinned($0) },
                        hideAction: { viewModel.hideLocal($0) },
                        deleteAction: { entry in
                            Task { await viewModel.deleteRemote(entry) }
                        },
                        openImageAction: { entry in imagePreviewEntry = entry },
                        restoreHiddenAction: { viewModel.restoreHidden($0) },
                        loadMoreAction: { viewModel.loadMoreHistory() }
                    )
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable {
                    await viewModel.refresh(allowOverwriteLocalEdits: false)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        isQuickPanelPresented = true
                    } label: {
                        Image(systemName: "rectangle.bottomthird.inset.filled")
                    }
                    .accessibilityLabel("半屏快捷面板")

                    Button {
                        isSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("服务器设置")

                    Button {
                        isHelpPresented = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("帮助")

                    Button {
                        isTrashPresented = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("回收站")
                }
            }
            .task {
                viewModel.loadCachedEntries()
                await viewModel.refresh(allowOverwriteLocalEdits: false)
                presentQuickPanelIfRequested()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                presentQuickPanelIfRequested()
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
                    Task { await viewModel.refresh(allowOverwriteLocalEdits: false) }
                } resetLocalDataAction: {
                    viewModel.resetLocalData()
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $isHelpPresented) {
                HelpView()
                    .presentationDetents([.large])
            }
            .sheet(isPresented: $isTrashPresented) {
                TrashView(
                    entries: viewModel.trashEntries,
                    serverAddress: viewModel.serverAddress,
                    restoreAction: { entry in
                        Task { await viewModel.restoreRemote(entry) }
                    },
                    permanentDeleteAction: { entry in
                        Task { await viewModel.permanentlyDeleteRemote(entry) }
                    },
                    permanentDeleteAllAction: {
                        Task { await viewModel.permanentlyDeleteAllTrashRemote() }
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $isQuickPanelPresented) {
                QuickPanelView(
                    title: viewModel.appTitle,
                    entries: Array(viewModel.entries.reversed().prefix(8)),
                    serverAddress: viewModel.serverAddress,
                    copyAction: { entry in Task { await viewModel.copy(entry) } },
                    openImageAction: { entry in
                        isQuickPanelPresented = false
                        imagePreviewEntry = entry
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $editingEntry) { entry in
                EditHistoryEntryView(
                    entry: entry,
                    text: $editingText
                ) {
                    viewModel.editLocal(entry, content: editingText)
                    editingEntry = nil
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $imagePreviewEntry) { entry in
                ImageDetailView(entry: entry, serverAddress: viewModel.serverAddress)
                    .presentationDetents([.large])
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

    private func presentQuickPanelIfRequested() {
        guard UserDefaults.standard.bool(forKey: OpenQuickPanelIntent.requestKey) else { return }
        UserDefaults.standard.set(false, forKey: OpenQuickPanelIntent.requestKey)
        isQuickPanelPresented = true
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
    @Binding var text: String
    let serverAddress: String
    let isLoading: Bool
    let copyAction: () -> Void
    let openImageAction: (SyncEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                ImagePreview(entry: entry, serverAddress: serverAddress, minHeight: 180)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        openImageAction(entry)
                    }
            } else {
                TextEditor(text: editableText)
                    .scrollContentBackground(.hidden)
                    .font(.body)
                    .foregroundStyle(Color.textSyncBrown)
                    .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
                    .padding(10)
                    .background(Color.textSyncPaper)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.textSyncLine, lineWidth: 1)
                    )
                    .disabled(entry == nil)
            }

            Button(action: copyAction) {
                Label(entry?.isImage == true ? "复制最新图片" : "复制最新文本", systemImage: entry?.isImage == true ? "photo.on.rectangle" : "doc.on.doc.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(TextSyncPillButtonStyle(color: Color.textSyncTeal))
            .disabled(entry == nil)
        }
        .padding(16)
        .background(TextSyncPanelBackground(tint: Color.textSyncPanel))
    }

    private var editableText: Binding<String> {
        Binding(
            get: {
                if entry == nil {
                    return displayText
                }
                return text
            },
            set: { text = $0 }
        )
    }

    private var displayText: String {
        if isLoading && entry == nil {
            return "正在同步..."
        }
        return "暂无数据"
    }
}

private struct ComposerView: View {
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

            Button(action: uploadImageAction) {
                Label(isSending ? "上传中" : "上传剪贴板图片", systemImage: "photo.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(TextSyncPillButtonStyle(color: Color.textSyncTeal))
            .disabled(isSending)
        }
        .padding(16)
        .background(TextSyncPanelBackground(tint: Color.textSyncPanel))
    }
}

private struct CategoryFilterView: View {
    @Binding var selectedCategory: EntryCategoryFilter
    let countProvider: (EntryCategoryFilter) -> Int
    private let columns = [
        GridItem(.adaptive(minimum: 138), spacing: 8)
    ]

    private var visibleCategories: [EntryCategoryFilter] {
        EntryCategoryFilter.allCases.filter { category in
            category == .all || countProvider(category) > 0 || selectedCategory == category
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("分类")
                .font(.headline)
                .foregroundStyle(Color.textSyncBrown)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(visibleCategories) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: category.systemImage)
                                .frame(width: 16)

                            Text(category.title)
                                .lineLimit(1)
                                .minimumScaleFactor(0.86)

                            Spacer(minLength: 4)

                            Text("\(countProvider(category))")
                                .font(.caption2.weight(.bold))
                                .lineLimit(1)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.white.opacity(selectedCategory == category ? 0.24 : 0.46)))
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(selectedCategory == category ? .white : Color.textSyncBrown)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(
                            Capsule().fill(selectedCategory == category ? Color.textSyncTeal : Color.textSyncPaper)
                        )
                        .overlay(
                            Capsule().stroke(Color.textSyncLine, lineWidth: selectedCategory == category ? 0 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(TextSyncPanelBackground(tint: Color.textSyncPanel))
    }
}

private struct HistorySection: View {
    let pinnedEntries: [SyncEntry]
    let items: [HistoryListItem]
    let totalCount: Int
    let hiddenCount: Int
    let latestID: Int?
    let serverAddress: String
    let canLoadMore: Bool
    let copyAction: (SyncEntry) -> Void
    let editAction: (SyncEntry) -> Void
    let updateFromCloudAction: (SyncEntry) -> Void
    let pinAction: (SyncEntry) -> Void
    let hideAction: (SyncEntry) -> Void
    let deleteAction: (SyncEntry) -> Void
    let openImageAction: (SyncEntry) -> Void
    let restoreHiddenAction: (HiddenEntryRange) -> Void
    let loadMoreAction: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
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
            .textSyncListRow()

            if items.isEmpty && pinnedEntries.isEmpty {
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

                ForEach(items) { item in
                    switch item {
                    case .entry(let entry):
                        historyButton(entry)
                    case .hiddenRange(let range):
                        HiddenRangeButton(range: range, restoreAction: restoreHiddenAction)
                            .textSyncListRow()
                    }
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

    private var entryCount: Int {
        items.reduce(0) { count, item in
            if case .entry = item {
                return count + 1
            }
            return count
        }
    }

    private func historyButton(_ entry: SyncEntry) -> some View {
        HistoryRow(entry: entry, isLatest: entry.id == latestID, serverAddress: serverAddress)
            .contentShape(Rectangle())
            .onTapGesture {
                if entry.isImage {
                    openImageAction(entry)
                } else if entry.displayCategory != EntryCategoryFilter.text.rawValue, let action = entry.primaryAction {
                    openURL(action.url)
                } else {
                    copyAction(entry)
                }
            }
            .contextMenu {
                let actions = Array(entry.detectedActions.prefix(6))

                Button {
                    copyAction(entry)
                } label: {
                    Label("复制", systemImage: "doc.on.doc.fill")
                }

                if entry.isImage {
                    Button {
                        openImageAction(entry)
                    } label: {
                        Label("查看原图", systemImage: "photo.fill")
                    }
                }

                ForEach(actions) { action in
                    Button {
                        openURL(action.url)
                    } label: {
                        Label(action.menuTitle, systemImage: action.systemImage)
                    }
                }

                if !entry.isImage {
                    Button {
                        editAction(entry)
                    } label: {
                        Label("编辑本地文本", systemImage: "pencil.circle.fill")
                    }
                }

                Button {
                    updateFromCloudAction(entry)
                } label: {
                    Label("更新", systemImage: "icloud.and.arrow.down.fill")
                }

                Button {
                    pinAction(entry)
                } label: {
                    Label(entry.isPinned ? "取消置顶" : "置顶", systemImage: entry.isPinned ? "pin.slash" : "pin.fill")
                }

                Button(role: .destructive) {
                    hideAction(entry)
                } label: {
                    Label("隐藏", systemImage: "eye.slash")
                }

                Button(role: .destructive) {
                    deleteAction(entry)
                } label: {
                    Label("删除到回收站", systemImage: "trash")
                }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "复制") {
                copyAction(entry)
            }
            .accessibilityAction(named: "编辑本地文本") {
                if !entry.isImage {
                    editAction(entry)
                }
            }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteAction(entry)
            } label: {
                Label("删除", systemImage: "trash")
            }

            Button(role: .destructive) {
                hideAction(entry)
            } label: {
                Label("隐藏", systemImage: "eye.slash")
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

private struct TrashView: View {
    let entries: [SyncEntry]
    let serverAddress: String
    let restoreAction: (SyncEntry) -> Void
    let permanentDeleteAction: (SyncEntry) -> Void
    let permanentDeleteAllAction: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isDeleteAllPresented = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

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
                } else {
                    List {
                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: 12) {
                                HistoryRow(entry: entry, isLatest: false, serverAddress: serverAddress)

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
                            .textSyncListRow()
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("回收站")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    if !entries.isEmpty {
                        Button(role: .destructive) {
                            isDeleteAllPresented = true
                        } label: {
                            Label("全部永久删除", systemImage: "trash.slash.fill")
                        }
                    }
                }
            }
            .alert("全部永久删除？", isPresented: $isDeleteAllPresented) {
                Button("取消", role: .cancel) {}
                Button("全部永久删除", role: .destructive) {
                    permanentDeleteAllAction()
                }
            } message: {
                Text("这会从远端回收站彻底删除所有内容，操作不可撤销。")
            }
        }
    }
}

private struct QuickPanelView: View {
    let title: String
    let entries: [SyncEntry]
    let serverAddress: String
    let copyAction: (SyncEntry) -> Void
    let openImageAction: (SyncEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                if entries.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "tray")
                            .font(.system(size: 36, weight: .semibold))
                        Text("暂无同步内容")
                            .font(.headline)
                    }
                    .foregroundStyle(Color.textSyncMuted)
                } else {
                    List(entries) { entry in
                        QuickPanelRow(entry: entry, serverAddress: serverAddress)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if entry.isImage {
                                    openImageAction(entry)
                                } else if entry.displayCategory != EntryCategoryFilter.text.rawValue, let action = entry.primaryAction {
                                    openURL(action.url)
                                } else {
                                    copyAction(entry)
                                }
                            }
                            .contextMenu {
                                Button {
                                    copyAction(entry)
                                } label: {
                                    Label("复制", systemImage: "doc.on.doc.fill")
                                }

                                if entry.isImage {
                                    Button {
                                        openImageAction(entry)
                                    } label: {
                                        Label("查看原图", systemImage: "photo.fill")
                                    }
                                }

                                ForEach(Array(entry.detectedActions.prefix(6))) { action in
                                    Button {
                                        openURL(action.url)
                                    } label: {
                                        Label(action.menuTitle, systemImage: action.systemImage)
                                    }
                                }
                            }
                            .textSyncListRow()
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct QuickPanelRow: View {
    let entry: SyncEntry
    let serverAddress: String

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(entry: entry)

            VStack(alignment: .leading, spacing: 5) {
                Text(rowTitle)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.textSyncBrown)
                    .lineLimit(2)

                Text(entry.time.textSyncFormatted)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.textSyncMuted)
            }

            Spacer()
        }
        .padding(12)
        .background(Color.textSyncPaper)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.textSyncLine, lineWidth: 1)
        )
    }

    private var rowTitle: String {
        if entry.isImage {
            return entry.imageDetailText.isEmpty ? "图片" : entry.imageDetailText
        }
        return entry.content
    }
}

private struct ImageDetailView: View {
    let entry: SyncEntry
    let serverAddress: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let url = entry.resolvedAssetURL(serverAddress: serverAddress) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .tint(.white)
                        case .success(let image):
                            ScrollView([.horizontal, .vertical]) {
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: UIScreen.main.bounds.width, minHeight: 260)
                                    .padding()
                            }
                        case .failure:
                            Label("原图加载失败", systemImage: "photo")
                                .foregroundStyle(.white)
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    Label("原图地址无效", systemImage: "photo")
                        .foregroundStyle(.white)
                }
            }
            .navigationTitle(entry.imageDetailText.isEmpty ? "原图" : entry.imageDetailText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    if let url = entry.resolvedAssetURL(serverAddress: serverAddress) {
                        Button {
                            openURL(url)
                        } label: {
                            Image(systemName: "safari")
                        }
                    }
                }
            }
        }
    }
}

private struct EditHistoryEntryView: View {
    let entry: SyncEntry
    @Binding var text: String
    let saveAction: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("#\(entry.id)", systemImage: "pencil.circle.fill")
                        .font(.headline)
                        .foregroundStyle(Color.textSyncBrown)

                    Spacer()

                    Text(entry.time.textSyncFormatted)
                        .font(.caption)
                        .foregroundStyle(Color.textSyncMuted)
                }

                Text("只修改本机缓存，不会上传或覆盖服务器内容。")
                    .font(.footnote)
                    .foregroundStyle(Color.textSyncMuted)

                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .font(.body)
                    .foregroundStyle(Color.textSyncBrown)
                    .frame(minHeight: 180)
                    .padding(10)
                    .background(Color.textSyncPaper)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.textSyncLine, lineWidth: 1)
                    )

                Button(action: saveAction) {
                    Label("保存本地修改", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TextSyncPillButtonStyle(color: Color.textSyncTeal))

                Spacer()
            }
            .padding(18)
            .background(AppBackground())
            .navigationTitle("编辑本地文本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: SyncEntry
    let isLatest: Bool
    let serverAddress: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                CategoryIcon(entry: entry)

                if entry.isPinned {
                    StatusIcon(systemName: "pin.fill", color: Color.textSyncTeal, label: "置顶")
                }

                if isLatest {
                    StatusIcon(systemName: "sparkles", color: Color.textSyncWarning, label: "最新")
                }

                if entry.isLocallyEdited {
                    StatusIcon(systemName: "pencil.circle.fill", color: Color.textSyncWarning, label: "本地修改")
                }

                Spacer(minLength: 8)

                Text(entry.time.textSyncFormatted)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSyncMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            if entry.isImage {
                ImagePreview(entry: entry, serverAddress: serverAddress, minHeight: 132)
            } else {
                Text(entry.content)
                    .font(.callout)
                    .foregroundStyle(Color.textSyncBrown)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

private struct ImagePreview: View {
    let entry: SyncEntry
    let serverAddress: String
    let minHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Color.textSyncPaper

                if let url = entry.resolvedThumbnailURL(serverAddress: serverAddress) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                        case .failure:
                            Label("图片加载失败", systemImage: "photo")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Color.textSyncMuted)
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    Label("图片地址无效", systemImage: "photo")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.textSyncMuted)
                }
            }
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.textSyncLine, lineWidth: 1)
            )

            if !entry.imageDetailText.isEmpty {
                Text(entry.imageDetailText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSyncMuted)
                    .lineLimit(1)
            }
        }
    }
}

private struct HiddenRangeButton: View {
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

private struct StatusIcon: View {
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

private struct CategoryIcon: View {
    let entry: SyncEntry

    var body: some View {
        let category = EntryCategoryFilter(rawValue: entry.displayCategory) ?? .text
        Label(category.title, systemImage: category.systemImage)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.textSyncBrown)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.textSyncPanel.opacity(0.78)))
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
    let resetLocalDataAction: () -> Void
    @State private var isResetConfirmationPresented = false

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

                Button {
                    isResetConfirmationPresented = true
                } label: {
                    Label("重置本地数据", systemImage: "arrow.counterclockwise.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TextSyncPillButtonStyle(color: Color.textSyncWarning))

                Spacer()
            }
            .padding(18)
            .background(AppBackground())
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .alert("重置本地数据？", isPresented: $isResetConfirmationPresented) {
                Button("取消", role: .cancel) {}
                Button("重置", role: .destructive) {
                    resetLocalDataAction()
                }
            } message: {
                Text("这会清空本机缓存、置顶、隐藏和本地修改记录，不会删除服务器上的文本，也会保留当前服务器地址。")
            }
        }
    }
}

private struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var updateStatus = "尚未检查更新"
    @State private var isCheckingUpdate = false
    @State private var latestReleaseURL = URL(string: "https://github.com/lixibi/iosTextSync/releases/tag/latest-ipa")!
    @State private var latestAssetURL: URL?

    private let projectURL = URL(string: "https://github.com/lixibi/iosTextSync")!
    private let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/lixibi/iosTextSync/releases/tags/latest-ipa")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    UpdateHelpCard(
                        currentVersion: currentVersionText,
                        status: updateStatus,
                        isChecking: isCheckingUpdate,
                        checkAction: { Task { await checkForUpdates() } },
                        openProjectAction: { openURL(projectURL) },
                        openLatestAction: { openURL(latestAssetURL ?? latestReleaseURL) }
                    )

                    HelpCard(
                        title: "文本中转是什么",
                        systemImage: "bolt.horizontal.circle.fill",
                        items: [
                            "把临时文本、链接、备忘和代码片段通过自己的服务器在多设备之间中转。",
                            "服务端可自部署，App 只保存你设置的服务器地址。",
                            "自动同步和下拉同步都会保留本地修改，不会悄悄覆盖。"
                        ]
                    )

                    HelpCard(
                        title: "常用操作",
                        systemImage: "hand.tap.fill",
                        items: [
                            "点击历史条目：快速复制。",
                            "长按历史条目：打开更多操作菜单。",
                            "左滑：置顶或取消置顶。",
                            "右滑：隐藏本机条目。"
                        ]
                    )

                    HelpCard(
                        title: "本地和云端",
                        systemImage: "icloud.fill",
                        items: [
                            "云图标表示这条内容与云端一致。",
                            "铅笔图标表示这条内容在本机修改过。",
                            "长按菜单里的“更新”会用云端内容覆盖这一条本地记录。",
                            "编辑本地文本不会上传到服务器。"
                        ]
                    )

                    HelpCard(
                        title: "隐藏和置顶",
                        systemImage: "pin.fill",
                        items: [
                            "隐藏只影响本机列表，不会删除服务器数据。",
                            "隐藏区间会用很淡的提示显示，并保留隐藏条数。",
                            "置顶条目不受普通历史显示条数影响。"
                        ]
                    )

                    HelpCard(
                        title: "快捷指令",
                        systemImage: "wand.and.stars",
                        items: [
                            "可以上传剪贴板文本，也可以获取远程最新文本并复制。",
                            "上传时建议在快捷指令里先使用“获取剪贴板”，再把结果传给 TextSync。",
                            "这样比让 App 自己读取剪贴板更稳定。"
                        ]
                    )
                }
                .padding(18)
            }
            .background(AppBackground())
            .navigationTitle("帮助")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var currentVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "未知"
        return "\(version) (\(build))"
    }

    @MainActor
    private func checkForUpdates() async {
        isCheckingUpdate = true
        updateStatus = "正在检查 GitHub 最新版本..."
        defer { isCheckingUpdate = false }

        do {
            let (data, response) = try await URLSession.shared.data(from: latestReleaseAPIURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                updateStatus = "检查失败：GitHub 返回异常"
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            latestReleaseURL = release.htmlURL
            latestAssetURL = release.assets.first { $0.name.lowercased().hasSuffix(".ipa") }?.browserDownloadURL

            let latest = release.parsedVersion
            if isNewerRelease(latestVersion: latest.version, latestBuild: latest.build) {
                let versionText = latest.version.map { version in
                    latest.build.map { "\(version) (\($0))" } ?? version
                } ?? release.tagName
                updateStatus = "发现新版本：\(versionText)"
            } else {
                updateStatus = "当前已是最新版本"
            }
        } catch {
            updateStatus = "检查失败：\(error.localizedDescription)"
        }
    }

    private func isNewerRelease(latestVersion: String?, latestBuild: String?) -> Bool {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let currentBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"

        if let latestVersion {
            let versionComparison = compareVersion(latestVersion, currentVersion)
            if versionComparison > 0 { return true }
            if versionComparison < 0 { return false }
        }

        guard let latestBuild = latestBuild.flatMap(Int.init),
              let currentBuild = Int(currentBuild) else {
            return false
        }
        return latestBuild > currentBuild
    }

    private func compareVersion(_ lhs: String, _ rhs: String) -> Int {
        let left = lhs.split(separator: ".").compactMap { Int($0) }
        let right = rhs.split(separator: ".").compactMap { Int($0) }
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l > r ? 1 : -1 }
        }
        return 0
    }
}

private struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        private enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let htmlURL: URL
    let body: String?
    let assets: [Asset]

    var parsedVersion: (version: String?, build: String?) {
        guard let body,
              let regex = try? NSRegularExpression(pattern: #"版本：\s*([^\s(]+)\s*\(([^)]+)\)"#) else {
            return (nil, nil)
        }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        guard let match = regex.firstMatch(in: body, options: [], range: range),
              let versionRange = Range(match.range(at: 1), in: body),
              let buildRange = Range(match.range(at: 2), in: body) else {
            return (nil, nil)
        }
        return (String(body[versionRange]), String(body[buildRange]))
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
        case assets
    }
}

private struct UpdateHelpCard: View {
    let currentVersion: String
    let status: String
    let isChecking: Bool
    let checkAction: () -> Void
    let openProjectAction: () -> Void
    let openLatestAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("项目与更新", systemImage: "arrow.down.circle.fill")
                .font(.headline)
                .foregroundStyle(Color.textSyncBrown)

            VStack(alignment: .leading, spacing: 6) {
                Text("当前版本：\(currentVersion)")
                Text(status)
            }
            .font(.footnote)
            .foregroundStyle(Color.textSyncMuted)

            HStack(spacing: 10) {
                Button(action: checkAction) {
                    Label(isChecking ? "检查中" : "检查更新", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TextSyncPillButtonStyle(color: Color.textSyncTeal))
                .disabled(isChecking)

                Button(action: openLatestAction) {
                    Label("最新版", systemImage: "square.and.arrow.down.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TextSyncPillButtonStyle(color: Color.textSyncGreen))
            }

            Button(action: openProjectAction) {
                Label("打开 GitHub 项目", systemImage: "link")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(TextSyncPillButtonStyle(color: Color.textSyncBrown))

            Text("iOS 不允许普通 App 静默自我安装；这里会打开 GitHub 最新 Release 或 IPA 下载入口，由你按当前安装方式完成更新。")
                .font(.caption)
                .foregroundStyle(Color.textSyncMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TextSyncPanelBackground(tint: Color.textSyncPanel))
    }
}

private struct HelpCard: View {
    let title: String
    let systemImage: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(Color.textSyncBrown)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Color.textSyncTeal.opacity(0.75))
                            .frame(width: 5, height: 5)
                            .padding(.top, 7)

                        Text(item)
                            .font(.footnote)
                            .foregroundStyle(Color.textSyncMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TextSyncPanelBackground(tint: Color.textSyncPanel))
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

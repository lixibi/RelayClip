import Foundation

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
    let isLocalOnly: Bool
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
        isLocalOnly: Bool = false,
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
        self.isLocalOnly = isLocalOnly
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
        isLocalOnly = false
        isHidden = false
    }

    var isImage: Bool {
        kind.lowercased() == "image"
    }

    var normalizedCategory: String {
        category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var imageDetailText: String {
        var parts: [String] = []
        if let width, let height {
            parts.append("\(width) x \(height)")
        }
        if let byteCount {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))
        }
        if let fileName, !fileName.isEmpty {
            parts.append(fileName)
        }
        return parts.isEmpty ? "图片" : parts.joined(separator: " · ")
    }

    var detectedActions: [DetectedContentAction] {
        guard !isImage else { return [] }
        return DetectedContentAction.detect(in: content)
    }

    func resolvedThumbnailURL(serverAddress: String) -> URL? {
        resolvedURL(from: thumbnailURL ?? assetURL, serverAddress: serverAddress)
    }

    func resolvedAssetURL(serverAddress: String) -> URL? {
        resolvedURL(from: assetURL, serverAddress: serverAddress)
    }

    private func resolvedURL(from rawValue: String?, serverAddress: String) -> URL? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        if let url = URL(string: rawValue), url.scheme != nil {
            return url
        }

        guard let normalizedServer = try? ServerAddress.normalized(serverAddress),
              var components = URLComponents(string: normalizedServer) else {
            return nil
        }

        components.path = rawValue.hasPrefix("/") ? rawValue : "/" + rawValue
        components.query = nil
        return components.url
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
        case .all:
            return "全部"
        case .text:
            return "文本"
        case .image:
            return "图片"
        case .link:
            return "链接"
        case .email:
            return "邮箱"
        case .phone:
            return "电话"
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .text:
            return "text.alignleft"
        case .image:
            return "photo"
        case .link:
            return "link"
        case .email:
            return "envelope"
        case .phone:
            return "phone"
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

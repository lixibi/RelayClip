import Foundation

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

    func listEntries(serverAddress: String, includeDeleted: Bool = false) async throws -> [SyncEntry] {
        let queryItems = includeDeleted ? [URLQueryItem(name: "include_deleted", value: "1")] : []
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

    func post(_ text: String, serverAddress: String) async throws {
        let url = try endpoint("/api/post", serverAddress: serverAddress)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(text.utf8)

        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    func postImage(_ data: Data, fileName: String, mimeType: String, serverAddress: String) async throws {
        let boundary = "TextSyncBoundary-\(UUID().uuidString)"
        let body = multipartBody(
            content: "图片 \(fileName)",
            imageData: data,
            fileName: fileName,
            mimeType: mimeType,
            boundary: boundary
        )
        let url = try endpoint("/api/items", serverAddress: serverAddress)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

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

    private func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw TextSyncError.requestFailed(httpResponse.statusCode)
        }
    }

    private func multipartBody(content: String, imageData: Data, fileName: String, mimeType: String, boundary: String) -> Data {
        var body = Data()
        append("--\(boundary)\r\n", to: &body)
        append("Content-Disposition: form-data; name=\"content\"\r\n\r\n", to: &body)
        append("\(content)\r\n", to: &body)
        append("--\(boundary)\r\n", to: &body)
        append("Content-Disposition: form-data; name=\"image\"; filename=\"\(fileName)\"\r\n", to: &body)
        append("Content-Type: \(mimeType)\r\n\r\n", to: &body)
        body.append(imageData)
        append("\r\n--\(boundary)--\r\n", to: &body)
        return body
    }

    private func append(_ string: String, to data: inout Data) {
        data.append(Data(string.utf8))
    }
}

import AppKit
import Foundation

enum ImageDiskCache {
    static func cachedImage(for entry: SyncEntry, serverAddress: String, variant: String) -> NSImage? {
        guard let data = cachedData(for: entry, serverAddress: serverAddress, variant: variant) else {
            return nil
        }
        return NSImage(data: data)
    }

    static func cachedData(for entry: SyncEntry, serverAddress: String, variant: String) -> Data? {
        guard let url = imageURL(for: entry, serverAddress: serverAddress, variant: variant) else {
            return nil
        }
        return try? Data(contentsOf: fileURL(for: url, variant: variant))
    }

    static func store(_ data: Data, for entry: SyncEntry, serverAddress: String, variant: String) throws {
        guard let url = imageURL(for: entry, serverAddress: serverAddress, variant: variant) else {
            return
        }
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try data.write(to: fileURL(for: url, variant: variant), options: .atomic)
    }

    static func prune(maximumBytes: Int = 120 * 1024 * 1024) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else {
            return
        }

        let records = files.compactMap { url -> (url: URL, date: Date, size: Int)? in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return (url, values?.contentModificationDate ?? .distantPast, values?.fileSize ?? 0)
        }
        var total = records.reduce(0) { $0 + $1.size }
        for record in records.sorted(by: { $0.date < $1.date }) where total > maximumBytes {
            try? fileManager.removeItem(at: record.url)
            total -= record.size
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: cacheDirectory)
    }

    private static func imageURL(for entry: SyncEntry, serverAddress: String, variant: String) -> URL? {
        variant == "asset"
            ? entry.resolvedAssetURL(serverAddress: serverAddress)
            : entry.resolvedThumbnailURL(serverAddress: serverAddress)
    }

    private static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TextSyncMacImageCache", isDirectory: true)
    }

    private static func fileURL(for remoteURL: URL, variant: String) -> URL {
        let key = "\(variant)-\(remoteURL.absoluteString)"
        let fileName = Data(key.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return cacheDirectory.appendingPathComponent(fileName)
    }
}

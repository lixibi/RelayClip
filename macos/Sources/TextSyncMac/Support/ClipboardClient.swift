import AppKit

struct ClipboardImagePayload {
    let data: Data
    let fileName: String
    let mimeType: String
}

enum ClipboardClient {
    static var changeCount: Int {
        NSPasteboard.general.changeCount
    }

    static func readString() -> String {
        NSPasteboard.general.string(forType: .string) ?? ""
    }

    static func readTextLikeContent() -> String {
        let pasteboard = NSPasteboard.general
        if let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }

        let urls = readURLs(from: pasteboard)
        if !urls.isEmpty {
            return urls.map(\.absoluteString).joined(separator: "\n")
        }

        if let html = pasteboard.string(forType: .html), !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return html
        }

        if let rtf = pasteboard.data(forType: .rtf),
           let attributed = try? NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil),
           !attributed.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return attributed.string
        }

        return ""
    }

    static func readUnsupportedTypeSummary() -> String {
        let typeNames = NSPasteboard.general.types?
            .map(\.rawValue)
            .filter { !$0.isEmpty }
            .sorted() ?? []
        guard !typeNames.isEmpty else { return "" }
        return "剪贴板内容暂不支持预览\n" + typeNames.joined(separator: "\n")
    }

    static func writeString(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func readImage(maxBytes: Int) -> ClipboardImagePayload? {
        let pasteboard = NSPasteboard.general
        if let pngData = pasteboard.data(forType: .png),
           !pngData.isEmpty,
           pngData.count <= maxBytes {
            return ClipboardImagePayload(data: pngData, fileName: "clipboard.png", mimeType: "image/png")
        }

        if let tiffData = pasteboard.data(forType: .tiff),
           let payload = imagePayload(from: tiffData, maxBytes: maxBytes) {
            return payload
        }

        if let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
           let payload = imagePayload(from: image, maxBytes: maxBytes) {
            return payload
        }

        return nil
    }

    static func writeImage(_ data: Data) -> Bool {
        guard let image = NSImage(data: data) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var didWrite = false
        if let pngData = pngData(from: image) {
            didWrite = pasteboard.setData(pngData, forType: .png)
        }
        if let tiffData = image.tiffRepresentation {
            didWrite = pasteboard.setData(tiffData, forType: .tiff) || didWrite
        }
        return didWrite
    }

    private static func imagePayload(from data: Data, maxBytes: Int) -> ClipboardImagePayload? {
        guard let image = NSImage(data: data) else { return nil }
        return imagePayload(from: image, maxBytes: maxBytes)
    }

    private static func imagePayload(from image: NSImage, maxBytes: Int) -> ClipboardImagePayload? {
        if let pngData = pngData(from: image), pngData.count <= maxBytes {
            return ClipboardImagePayload(data: pngData, fileName: "clipboard.png", mimeType: "image/png")
        }

        if let jpegData = bitmapRepresentation(from: image)?.representation(using: .jpeg, properties: [.compressionFactor: 0.86]),
           jpegData.count <= maxBytes {
            return ClipboardImagePayload(data: jpegData, fileName: "clipboard.jpg", mimeType: "image/jpeg")
        }

        return nil
    }

    private static func pngData(from image: NSImage) -> Data? {
        bitmapRepresentation(from: image)?.representation(using: .png, properties: [:])
    }

    private static func bitmapRepresentation(from image: NSImage) -> NSBitmapImageRep? {
        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData) {
            return bitmap
        }
        return nil
    }

    private static func readURLs(from pasteboard: NSPasteboard) -> [URL] {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            return urls
        }

        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !fileURLs.isEmpty {
            return fileURLs
        }

        if let filenames = pasteboard.propertyList(forType: .fileURL) as? [String] {
            return filenames.compactMap(URL.init(fileURLWithPath:))
        }

        return []
    }
}

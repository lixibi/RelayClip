import AppIntents
import Foundation
import UIKit

struct UploadClipboardTextIntent: AppIntent {
    static var title: LocalizedStringResource = "上传剪贴板文本"
    static var description = IntentDescription("将当前剪贴板文本上传到已保存的 TextSync 服务器。")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = await Self.clipboardText()

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .result(dialog: "剪贴板没有可上传的文本")
        }

        let serverAddress = try await MainActor.run {
            try TextSyncLocalStore().serverAddress()
        }

        guard !serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .result(dialog: "请先在 TextSync 中设置服务器地址")
        }

        try await TextSyncService().post(text, serverAddress: serverAddress)
        return .result(dialog: "已上传剪贴板文本")
    }

    private static func clipboardText() async -> String {
        for attempt in 0..<8 {
            let text = await MainActor.run {
                UIPasteboard.general.string ?? ""
            }
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attempt == 7 {
                return text
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return ""
    }
}

struct FetchRemoteTextIntent: AppIntent {
    static var title: LocalizedStringResource = "获取远程文本"
    static var description = IntentDescription("获取服务器上的最新文本并复制到剪贴板。")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let serverAddress = try await MainActor.run {
            try TextSyncLocalStore().serverAddress()
        }

        guard !serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .result(dialog: "请先在 TextSync 中设置服务器地址")
        }

        let entries = try await TextSyncService().listEntries(serverAddress: serverAddress)
        guard let latest = entries.last else {
            return .result(dialog: "服务器暂无文本")
        }

        try await MainActor.run {
            let store = TextSyncLocalStore()
            try store.merge(entries, serverAddress: serverAddress, preserveLocalEdits: true)
            UIPasteboard.general.string = latest.content
        }

        return .result(dialog: "已复制远程最新文本")
    }
}

struct TextSyncShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: UploadClipboardTextIntent(),
            phrases: [
                "用 \(.applicationName) 上传剪贴板",
                "\(.applicationName) 上传文本"
            ],
            shortTitle: "上传剪贴板",
            systemImageName: "paperplane.fill"
        )

        AppShortcut(
            intent: FetchRemoteTextIntent(),
            phrases: [
                "用 \(.applicationName) 获取远程文本",
                "\(.applicationName) 复制远程文本"
            ],
            shortTitle: "获取远程",
            systemImageName: "doc.on.doc.fill"
        )
    }
}

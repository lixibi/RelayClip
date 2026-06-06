import AppIntents
import Foundation
import UIKit

struct UploadClipboardTextIntent: AppIntent {
    static var title: LocalizedStringResource = "上传剪贴板文本"
    static var description = IntentDescription("将快捷指令传入的文本或当前剪贴板文本上传到已保存的 RelayClip 服务器。")
    static var openAppWhenRun = false

    @Parameter(title: "文本", description: "可从快捷指令的“获取剪贴板”动作传入。留空时会尝试直接读取当前剪贴板。")
    var text: String?

    init() {
        text = nil
    }

    init(text: String?) {
        self.text = text
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let content = await Self.resolvedText(from: text)

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .result(dialog: "没有可上传的文本。建议在快捷指令里先添加“获取剪贴板”，再把结果传给 RelayClip。")
        }

        let serverAddress = try await MainActor.run {
            try RelayClipLocalStore().serverAddress()
        }

        guard !serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .result(dialog: "请先在 RelayClip 中设置服务器地址")
        }

        try await RelayClipService().post(content, serverAddress: serverAddress)
        return .result(dialog: "已上传文本")
    }

    private static func resolvedText(from parameterText: String?) async -> String {
        let trimmedParameter = parameterText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedParameter.isEmpty {
            return parameterText ?? ""
        }
        return await clipboardText()
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
            try RelayClipLocalStore().serverAddress()
        }

        guard !serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .result(dialog: "请先在 RelayClip 中设置服务器地址")
        }

        let service = RelayClipService()
        let latestContent = try await service.latestTextContent(serverAddress: serverAddress)
        guard !latestContent.isEmpty else {
            return .result(dialog: "服务器暂无文本")
        }

        let entries = (try? await service.listEntries(serverAddress: serverAddress)) ?? []

        try await MainActor.run {
            let store = RelayClipLocalStore()
            if !entries.isEmpty {
                try store.merge(entries, serverAddress: serverAddress, preserveLocalEdits: true)
            }
            UIPasteboard.general.string = latestContent
        }

        return .result(dialog: "已复制远程最新文本")
    }
}

struct OpenQuickPanelIntent: AppIntent {
    static let requestKey = "RelayClipOpenQuickPanelRequested"
    static var title: LocalizedStringResource = "打开快捷面板"
    static var description = IntentDescription("打开 RelayClip，并显示半屏快捷面板。")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        UserDefaults.standard.set(true, forKey: Self.requestKey)
        return .result(dialog: "正在打开 RelayClip 快捷面板")
    }
}

struct RelayClipShortcuts: AppShortcutsProvider {
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

        AppShortcut(
            intent: OpenQuickPanelIntent(),
            phrases: [
                "打开 \(.applicationName) 快捷面板",
                "\(.applicationName) 半屏面板"
            ],
            shortTitle: "快捷面板",
            systemImageName: "rectangle.bottomthird.inset.filled"
        )
    }
}

import AppKit
import SwiftUI

struct SettingsView: View {
    @State private var appTitle: String
    @State private var serverAddress: String
    @State private var automaticRemoteUploadEnabled: Bool
    @State private var hotKeyShortcut: HotKeyShortcut
    @State private var quickPanelPlacement: QuickPanelPlacement
    let isTestingConnection: Bool
    let connectionTestMessage: String?
    let didLastConnectionTestSucceed: Bool
    let testAction: (String) -> Void
    let saveAction: (String, String, Bool, HotKeyShortcut, QuickPanelPlacement) -> Void
    let resetLocalDataAction: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isResetConfirmationPresented = false

    init(
        appTitle: String,
        serverAddress: String,
        automaticRemoteUploadEnabled: Bool,
        hotKeyShortcut: HotKeyShortcut,
        quickPanelPlacement: QuickPanelPlacement,
        isTestingConnection: Bool,
        connectionTestMessage: String?,
        didLastConnectionTestSucceed: Bool,
        testAction: @escaping (String) -> Void,
        saveAction: @escaping (String, String, Bool, HotKeyShortcut, QuickPanelPlacement) -> Void,
        resetLocalDataAction: @escaping () -> Void
    ) {
        _appTitle = State(initialValue: appTitle)
        _serverAddress = State(initialValue: serverAddress)
        _automaticRemoteUploadEnabled = State(initialValue: automaticRemoteUploadEnabled)
        _hotKeyShortcut = State(initialValue: hotKeyShortcut)
        _quickPanelPlacement = State(initialValue: quickPanelPlacement)
        self.isTestingConnection = isTestingConnection
        self.connectionTestMessage = connectionTestMessage
        self.didLastConnectionTestSucceed = didLastConnectionTestSucceed
        self.testAction = testAction
        self.saveAction = saveAction
        self.resetLocalDataAction = resetLocalDataAction
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("设置")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.textSyncBrown)

                    Spacer()

                    Button("关闭") {
                        dismiss()
                    }
                }

                Text("首页名称")
                    .font(.headline)
                    .foregroundStyle(Color.textSyncBrown)

                TextField("RelayClip", text: $appTitle)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .frame(height: 42)
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
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .frame(height: 42)
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

                Toggle(isOn: $automaticRemoteUploadEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("自动发送")
                            .font(.headline)
                            .foregroundStyle(Color.textSyncBrown)
                        Text("关闭时只记录本机，需要时手动发送。")
                            .font(.footnote)
                            .foregroundStyle(Color.textSyncMuted)
                    }
                }
                .toggleStyle(.switch)
                .padding(12)
                .background(Color.textSyncPaper)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.textSyncLine, lineWidth: 1)
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("快捷窗口")
                        .font(.headline)
                        .foregroundStyle(Color.textSyncBrown)

                    HStack(spacing: 10) {
                        HotKeyRecorderView(shortcut: $hotKeyShortcut)
                            .frame(height: 38)

                        Button {
                            hotKeyShortcut = .off
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(TextSyncIconButtonStyle(color: Color.textSyncMuted))
                        .help("关闭快捷键")
                    }

                    Picker("弹出位置", selection: $quickPanelPlacement) {
                        ForEach(QuickPanelPlacement.allCases) { placement in
                            Text(placement.title).tag(placement)
                        }
                    }
                }
                .padding(12)
                .background(Color.textSyncPaper)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.textSyncLine, lineWidth: 1)
                )

                Button {
                    testAction(serverAddress)
                } label: {
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

                Button {
                    saveAction(appTitle, serverAddress, automaticRemoteUploadEnabled, hotKeyShortcut, quickPanelPlacement)
                } label: {
                    Label("保存", systemImage: "checkmark.circle.fill")
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
            .padding(22)
            .frame(width: 450, height: 690)
        }
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

struct HotKeyRecorderView: NSViewRepresentable {
    @Binding var shortcut: HotKeyShortcut

    func makeNSView(context: Context) -> HotKeyRecorderNSView {
        let view = HotKeyRecorderNSView()
        view.onShortcutChange = { shortcut in
            self.shortcut = shortcut
        }
        view.shortcut = shortcut
        return view
    }

    func updateNSView(_ nsView: HotKeyRecorderNSView, context: Context) {
        nsView.shortcut = shortcut
    }
}

final class HotKeyRecorderNSView: NSView {
    var shortcut: HotKeyShortcut = .defaultValue {
        didSet { updateLabel() }
    }
    var onShortcutChange: ((HotKeyShortcut) -> Void)?

    private let label = NSTextField(labelWithString: "")
    private var isRecording = false {
        didSet { updateLabel() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.56).cgColor

        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        updateLabel()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            isRecording = false
            return
        }

        guard let shortcut = HotKeyShortcut(event: event) else {
            label.stringValue = "请按组合键"
            return
        }

        self.shortcut = shortcut
        isRecording = false
        onShortcutChange?(shortcut)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return true
    }

    private func updateLabel() {
        label.stringValue = isRecording ? "按下新的快捷键" : shortcut.title
        layer?.borderColor = isRecording ? NSColor.controlAccentColor.cgColor : NSColor.separatorColor.cgColor
    }
}

struct ServerSetupGuideView: View {
    @State private var serverAddress: String
    let isTestingConnection: Bool
    let connectionTestMessage: String?
    let didLastConnectionTestSucceed: Bool
    let testAction: (String) -> Void
    let saveAction: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    init(
        serverAddress: String,
        isTestingConnection: Bool,
        connectionTestMessage: String?,
        didLastConnectionTestSucceed: Bool,
        testAction: @escaping (String) -> Void,
        saveAction: @escaping (String) -> Void
    ) {
        _serverAddress = State(initialValue: serverAddress)
        self.isTestingConnection = isTestingConnection
        self.connectionTestMessage = connectionTestMessage
        self.didLastConnectionTestSucceed = didLastConnectionTestSucceed
        self.testAction = testAction
        self.saveAction = saveAction
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("连接 RelayClip", systemImage: "bolt.horizontal.circle.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.textSyncBrown)

                    Spacer()

                    Button("稍后") {
                        dismiss()
                    }
                }

                TextField("https://your-domain.com", text: $serverAddress)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(Color.textSyncPaper)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.textSyncLine, lineWidth: 1)
                    )

                HStack(spacing: 10) {
                    Button {
                        testAction(serverAddress)
                    } label: {
                        Label(isTestingConnection ? "测试中" : "测试", systemImage: "network")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TextSyncPillButtonStyle(color: Color.textSyncBrown))
                    .disabled(isTestingConnection)

                    Button {
                        saveAction(serverAddress)
                        dismiss()
                    } label: {
                        Label("保存", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TextSyncPillButtonStyle(color: Color.textSyncTeal))
                }

                if let connectionTestMessage {
                    Label(
                        connectionTestMessage,
                        systemImage: didLastConnectionTestSucceed ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(didLastConnectionTestSucceed ? Color.textSyncGreen : Color.textSyncWarning)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("自部署")
                        .font(.headline)
                        .foregroundStyle(Color.textSyncBrown)

                    Text("Docker 镜像：ghcr.io/lixibi/relayclip-server:latest")
                        .font(.footnote)
                        .foregroundStyle(Color.textSyncMuted)

                    Text("运行服务端后，把浏览器能打开的地址填到这里；网页端也在同一个地址。")
                        .font(.footnote)
                        .foregroundStyle(Color.textSyncMuted)
                }
                .padding(12)
                .background(Color.textSyncPaper)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.textSyncLine, lineWidth: 1)
                )
            }
            .padding(22)
            .frame(width: 460, height: 360)
        }
    }
}

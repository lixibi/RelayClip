import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var updateStatus = "可手动检查 GitHub Release。"
    @State private var latestReleaseURL = URL(string: "https://github.com/lixibi/RelayClip/releases/latest")!

    private let projectURL = URL(string: "https://github.com/lixibi/RelayClip")!
    private let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/lixibi/RelayClip/releases/latest")!

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("帮助")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Color.textSyncBrown)

                        Spacer()

                        Button("关闭") {
                            dismiss()
                        }
                    }

                    HelpCard(
                        title: "RelayClip 是什么",
                        systemImage: "bolt.horizontal.circle.fill",
                        items: [
                            "把剪贴板、临时文本、链接、备忘、代码片段和图片通过自己的服务器在多设备之间共享。",
                            "服务端可自部署，App 只保存你设置的服务器地址。",
                            "自动同步和手动同步都会保留本地修改，不会悄悄覆盖。"
                        ]
                    )

                    HelpCard(
                        title: "菜单栏操作",
                        systemImage: "menubar.rectangle",
                        items: [
                            "菜单栏保留快捷复制、分类筛选、浮动、+ 和设置入口。",
                            "点击列表项即可复制，图片会尽量显示缩略图。",
                            "设置里的快捷键可弹出浮动窗口，图钉可让它保持在前面。"
                        ]
                    )

                    HelpCard(
                        title: "本地和云端",
                        systemImage: "externaldrive.fill.badge.checkmark",
                        items: [
                            "默认只记录本机历史，需要时手动发送。",
                            "打开自动发送后，新剪贴板会先写入本机，再发送到服务器。",
                            "历史列表里的纸飞机图标可强制发送单条记录。",
                            "同步按钮负责刷新远程列表。"
                        ]
                    )

                    HelpCard(
                        title: "隐藏和置顶",
                        systemImage: "pin.fill",
                        items: [
                            "隐藏只影响本机列表，不会删除服务器数据。",
                            "隐藏区间会用很淡的提示显示，并保留隐藏条数。",
                            "置顶条目会优先显示在菜单栏快捷复制列表里。"
                        ]
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Label("GitHub 和更新", systemImage: "arrow.down.circle.fill")
                            .font(.headline)
                            .foregroundStyle(Color.textSyncBrown)

                        Text(updateStatus)
                            .font(.footnote)
                            .foregroundStyle(Color.textSyncMuted)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(spacing: 10) {
                            Button {
                                openURL(projectURL)
                            } label: {
                                Label("打开项目", systemImage: "link")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(TextSyncPillButtonStyle(color: Color.textSyncBrown))

                            Button {
                                Task { await checkLatestRelease() }
                            } label: {
                                Label("检查更新", systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(TextSyncPillButtonStyle(color: Color.textSyncTeal))

                            Button {
                                openURL(latestReleaseURL)
                            } label: {
                                Label("下载最新版", systemImage: "square.and.arrow.down")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(TextSyncPillButtonStyle(color: Color.textSyncGreen))
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(TextSyncPanelBackground(tint: Color.textSyncPanel))
                }
                .padding(22)
            }
            .frame(width: 480, height: 560)
        }
    }

    @MainActor
    private func checkLatestRelease() async {
        updateStatus = "正在检查 GitHub 最新版本..."
        do {
            let (data, response) = try await URLSession.shared.data(from: latestReleaseAPIURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                updateStatus = "检查失败：GitHub 返回异常，可直接打开下载入口。"
                return
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            if let url = URL(string: release.htmlURL) {
                latestReleaseURL = url
            }

            let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "本地开发版"
            updateStatus = "当前版本：\(currentVersion)。GitHub 最新版本：\(release.tagName)。"
        } catch {
            updateStatus = "检查失败：\(error.localizedDescription)"
        }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
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

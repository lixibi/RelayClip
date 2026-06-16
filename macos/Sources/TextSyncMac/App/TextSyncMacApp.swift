import AppKit
import SwiftUI

enum WindowID {
    static let main = "main"
}

@main
struct TextSyncMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = TextSyncViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(viewModel: viewModel)
                .task {
                    await viewModel.bootstrap()
                }
        } label: {
            Label("RelayClip", systemImage: "bolt.horizontal.circle.fill")
        }
        .menuBarExtraStyle(.window)

        Window("RelayClip", id: WindowID.main) {
            MainWindowView(viewModel: viewModel)
                .frame(minWidth: 500, idealWidth: 560, minHeight: 680, idealHeight: 760)
                .task {
                    await viewModel.bootstrap()
                }
        }
        .defaultSize(width: 560, height: 760)
    }
}

import SwiftUI

struct MainWindowView: View {
    @ObservedObject var viewModel: TextSyncViewModel
    @State private var isSettingsPresented = false
    @State private var isHelpPresented = false
    @State private var isTrashPresented = false
    @State private var isSetupGuidePresented = false
    @State private var didOfferSetupGuide = false
    @State private var editingEntry: SyncEntry?
    @State private var editingText = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            AppBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HeaderView(title: viewModel.appTitle)

                    LatestTextView(
                        entry: viewModel.latest,
                        serverAddress: viewModel.serverAddress,
                        text: Binding(
                            get: { viewModel.latestDraft },
                            set: { viewModel.updateLatestDraft($0) }
                        ),
                        isLoading: viewModel.isLoading,
                        copyAction: { Task { await viewModel.copyLatest() } }
                    )

                    ComposerView(
                        draft: $viewModel.draft,
                        isSending: viewModel.isSending,
                        pasteAction: { viewModel.pasteFromClipboard() },
                        uploadImageAction: { Task { await viewModel.sendClipboardImage() } }
                    ) {
                        Task { await viewModel.send() }
                    }

	                    SyncModePanel(
	                        recordLocalAction: { viewModel.recordClipboardLocally() },
	                        sendClipboardAction: { Task { await viewModel.sendClipboardToRemote() } },
	                        syncRemoteAction: { Task { await viewModel.refresh() } }
	                    )

                    CategoryFilterView(
                        selectedCategory: $viewModel.selectedCategory,
                        countProvider: { viewModel.count(for: $0) }
                    )

                    HistorySection(
                        pinnedEntries: viewModel.pinnedEntries,
                        items: viewModel.visibleHistoryItems,
                        serverAddress: viewModel.serverAddress,
                        totalCount: viewModel.history.count,
                        hiddenCount: viewModel.hiddenHistory.count,
                        latestID: viewModel.latest?.id,
                        canLoadMore: viewModel.canLoadMoreHistory,
                        copyAction: { entry in Task { await viewModel.copy(entry) } },
                        editAction: { entry in
                            editingText = entry.content
                            editingEntry = entry
                        },
                        updateFromCloudAction: { entry in
                            Task { await viewModel.updateEntryFromCloud(entry) }
                        },
                        uploadToRemoteAction: { entry in
                            Task { await viewModel.uploadEntryToRemote(entry) }
                        },
                        pinAction: { viewModel.togglePinned($0) },
                        hideAction: { viewModel.hideLocal($0) },
                        deleteAction: { entry in
                            Task { await viewModel.deleteRemote(entry) }
                        },
                        restoreHiddenAction: { viewModel.restoreHidden($0) },
                        loadMoreAction: { viewModel.loadMoreHistory() }
                    )
                }
                .padding(22)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }

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
	        .toolbar {
	            ToolbarItemGroup {
	                Button {
	                    Task { await viewModel.refresh() }
	                } label: {
	                    Label("同步", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
                .keyboardShortcut("r", modifiers: [.command])

                Button {
                    isSettingsPresented = true
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: [.command])

                Button {
                    isHelpPresented = true
                } label: {
                    Label("帮助", systemImage: "questionmark.circle")
                }

                Button {
                    isTrashPresented = true
                } label: {
                    Label("回收站", systemImage: "trash")
                }
            }
        }
	        .sheet(isPresented: $isSettingsPresented) {
            SettingsView(
	                appTitle: viewModel.appTitle,
	                serverAddress: viewModel.serverAddress,
	                automaticRemoteUploadEnabled: viewModel.automaticRemoteUploadEnabled,
	                hotKeyShortcut: viewModel.hotKeyShortcut,
	                quickPanelPlacement: viewModel.quickPanelPlacement,
	                isTestingConnection: viewModel.isTestingConnection,
	                connectionTestMessage: viewModel.connectionTestMessage,
	                didLastConnectionTestSucceed: viewModel.didLastConnectionTestSucceed
            ) { serverAddress in
                Task { await viewModel.testConnection(serverAddress: serverAddress) }
	            } saveAction: { appTitle, serverAddress, automaticRemoteUploadEnabled, hotKeyShortcut, quickPanelPlacement in
	                viewModel.saveSettings(
	                    appTitle: appTitle,
	                    serverAddress: serverAddress,
	                    automaticRemoteUploadEnabled: automaticRemoteUploadEnabled,
	                    hotKeyShortcut: hotKeyShortcut,
	                    quickPanelPlacement: quickPanelPlacement
	                )
                isSettingsPresented = false
                Task { await viewModel.refresh(allowOverwriteLocalEdits: false) }
            } resetLocalDataAction: {
                viewModel.resetLocalData()
            }
        }
	        .sheet(isPresented: $isHelpPresented) {
	            HelpView()
	        }
	        .sheet(isPresented: $isSetupGuidePresented) {
	            ServerSetupGuideView(
	                serverAddress: viewModel.serverAddress,
	                isTestingConnection: viewModel.isTestingConnection,
	                connectionTestMessage: viewModel.connectionTestMessage,
	                didLastConnectionTestSucceed: viewModel.didLastConnectionTestSucceed
	            ) { serverAddress in
	                Task { await viewModel.testConnection(serverAddress: serverAddress) }
	            } saveAction: { serverAddress in
	                viewModel.saveSettings(
	                    appTitle: viewModel.appTitle,
	                    serverAddress: serverAddress,
	                    automaticRemoteUploadEnabled: viewModel.automaticRemoteUploadEnabled,
	                    hotKeyShortcut: viewModel.hotKeyShortcut,
	                    quickPanelPlacement: viewModel.quickPanelPlacement
	                )
	                Task { await viewModel.refresh(allowOverwriteLocalEdits: false) }
	            }
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
                }
            )
        }
	        .sheet(item: $editingEntry) { entry in
            EditHistoryEntryView(
                entry: entry,
                text: $editingText
            ) {
                viewModel.editLocal(entry, content: editingText)
                editingEntry = nil
	        }
	        .task {
	            guard !didOfferSetupGuide, !viewModel.isServerConfigured else { return }
	            didOfferSetupGuide = true
	            isSetupGuidePresented = true
	        }
	    }
	}
}

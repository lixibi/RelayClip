import SwiftUI

struct EditHistoryEntryView: View {
    let entry: SyncEntry
    @Binding var text: String
    let saveAction: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppBackground()

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("编辑本地文本", systemImage: "pencil.circle.fill")
                        .font(.headline)
                        .foregroundStyle(Color.textSyncBrown)

                    Spacer()

                    Text(entry.time.textSyncFormatted)
                        .font(.caption)
                        .foregroundStyle(Color.textSyncMuted)
                }

                Text("只修改本机缓存，不会上传或覆盖服务器内容。")
                    .font(.footnote)
                    .foregroundStyle(Color.textSyncMuted)

                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .font(.body)
                    .foregroundStyle(Color.textSyncBrown)
                    .frame(minHeight: 210)
                    .padding(10)
                    .background(Color.textSyncPaper)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.textSyncLine, lineWidth: 1)
                    )

                HStack(spacing: 10) {
                    Button {
                        dismiss()
                    } label: {
                        Label("取消", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TextSyncPillButtonStyle(color: Color.textSyncBrown))

                    Button(action: saveAction) {
                        Label("保存本地修改", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TextSyncPillButtonStyle(color: Color.textSyncTeal))
                }
            }
            .padding(22)
            .frame(width: 470, height: 430)
        }
    }
}

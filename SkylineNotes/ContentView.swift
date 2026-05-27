import SwiftUI

struct ContentView: View {
    @State private var noteText = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Quick note")
                    .font(.headline)

                TextEditor(text: $noteText)
                    .frame(minHeight: 180)
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack {
                    Label("\(noteText.count)", systemImage: "textformat.size")
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Clear") {
                        noteText = ""
                    }
                    .buttonStyle(.bordered)
                    .disabled(noteText.isEmpty)
                }
            }
            .padding()
            .navigationTitle("Skyline Notes")
        }
    }
}

#Preview {
    ContentView()
}

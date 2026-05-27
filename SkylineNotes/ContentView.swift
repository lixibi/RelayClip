import SwiftUI

struct ContentView: View {
    @State private var noteText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.94, green: 0.97, blue: 1.0),
                        Color(red: 0.98, green: 0.96, blue: 0.92)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Today", systemImage: "sun.max.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)

                        Text("Capture a thought before it disappears.")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.primary)

                        Text("A small note pad for quick ideas, reminders, and tiny plans.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 10)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Quick note")
                            .font(.headline)

                        TextEditor(text: $noteText)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 220)
                            .padding(12)
                            .background(.white.opacity(0.82))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.9), lineWidth: 1)
                            )
                    }

                    HStack(spacing: 12) {
                        Label("\(noteText.count) chars", systemImage: "textformat.size")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            noteText = ""
                        } label: {
                            Label("Clear", systemImage: "xmark.circle")
                        }
                        .buttonStyle(.bordered)
                        .disabled(noteText.isEmpty)
                    }
                }
                .padding()
            }
            .navigationTitle("Skyline Notes")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

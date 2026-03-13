import SwiftUI

struct StylistView: View {
    @State private var draftText = ""
    @State private var messages: [String] = [
        "Ask the stylist for fit and combination ideas."
    ]

    var body: some View {
        NavigationStack {
            VStack {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages, id: \.self) { message in
                            Text(message)
                                .padding(12)
                                .background(PluckTheme.card)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()
                HStack {
                    TextField("Type message...", text: $draftText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        send()
                    } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .navigationTitle("Stylist")
        }
    }

    private func send() {
        let msg = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty else { return }
        messages.append(msg)
        messages.append("I’m preparing outfit suggestions...")
        draftText = ""
    }
}

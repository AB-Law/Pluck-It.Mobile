import SwiftUI

private enum StylistBubbleRole {
    case assistant
    case user
}

private struct StylistBubble: Identifiable {
    var id = UUID()
    var role: StylistBubbleRole
    var text: String
    var streaming: Bool = false
}

struct StylistView: View {
    @EnvironmentObject private var appServices: AppServices
    @State private var draftText = ""
    @State private var messages: [StylistBubble] = [
        StylistBubble(role: .assistant, text: "Ask the stylist for fit and combination ideas.")
    ]
    @State private var chatHistory: [StylistMessage] = []
    @State private var sending = false
    @State private var activeAssistantIndex: Int?
    @State private var streamTask: Task<Void, Never>?
    @State private var lastError: String?
    @State private var receivedAnyEvent = false

    var body: some View {
        NavigationStack {
            VStack {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            HStack {
                                if message.role == .assistant {
                                    Spacer()
                                }
                                Text(message.text + (message.streaming ? "…" : ""))
                                    .padding(12)
                                    .background(message.role == .user ? Color(red: 0.0, green: 0.48, blue: 1.0) : Color(red: 0.28, green: 0.28, blue: 0.30))
                                    .foregroundStyle(message.role == .user ? .white : .white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: message.role == .user ? .trailing : .leading
                                    )
                                if message.role == .user {
                                    Spacer()
                                }
                            }
                        }
                        if let lastError {
                            Text(lastError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()
                HStack {
                    TextField("Type message...", text: $draftText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .disabled(sending)
                        .onSubmit {
                            send()
                        }
                    Button {
                        send()
                    } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                }
                .padding()
            }
            .navigationTitle("Stylist")
        }
    }

    private func send() {
        let msg = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty, !sending else { return }

        print("🛰 StylistView send tapped: \(msg)")

        draftText = ""
        lastError = nil
        sending = true
        receivedAnyEvent = false

        let userMessage = StylistBubble(role: .user, text: msg)
        messages.append(userMessage)
        chatHistory.append(StylistMessage(role: .user, content: msg))

        let assistantIndex = messages.count
        messages.append(StylistBubble(role: .assistant, text: "", streaming: true))
        activeAssistantIndex = assistantIndex

        streamTask?.cancel()
        streamTask = Task {
            do {
                for try await event in appServices.stylistService.streamChat(
                    message: msg,
                    recentMessages: chatHistory,
                    selectedItemIds: nil
                ) {
                    await MainActor.run {
                        handle(event)
                    }
                }
                await MainActor.run {
                    finalizeStream()
                }
            } catch {
                if error is CancellationError {
                    return
                }
                await MainActor.run {
                    finalizeStream(with: "Stylist request failed: \(error)")
                }
            }
        }
    }

    private func handle(_ event: StylistChatEvent) {
        receivedAnyEvent = true
        switch event {
        case let .token(content, _, _, _, _, _):
            guard let index = activeAssistantIndex else { return }
            guard messages.indices.contains(index) else { return }
            if messages[index].text.isEmpty {
                messages[index].text = content
            } else {
                messages[index].text += content
            }
        case let .toolUse(name, _, _, _, _, _):
            guard let index = activeAssistantIndex, messages.indices.contains(index) else { return }
            if messages[index].text.isEmpty {
                messages[index].text = "\(name)..."
            }
        case let .toolResult(name, _, _, _, _, _, _):
            guard let index = activeAssistantIndex, messages.indices.contains(index) else { return }
            if messages[index].text.isEmpty {
                messages[index].text = "\(name) completed."
            }
        case let .memoryUpdate(updated, _, _, _, _, _):
            if updated {
                messages.append(StylistBubble(role: .assistant, text: "Memory updated."))
            }
        case let .error(content, _, _, _, _, _):
            finalizeStream(with: content)
        case .done:
            finalizeStream()
        case let .unknown(type, _, _, _, _, _):
            finalizeStream(with: "Stylist sent unknown event: \(type)")
        }
    }

    private func finalizeStream(with errorText: String? = nil) {
        sending = false
        let normalizedErrorText: String? = {
            if errorText == nil, !receivedAnyEvent {
                return "Stylist did not return any stream events."
            }
            return errorText
        }()
        guard let index = activeAssistantIndex, messages.indices.contains(index) else {
            activeAssistantIndex = nil
            if let normalizedErrorText {
                messages.append(StylistBubble(role: .assistant, text: normalizedErrorText))
                lastError = normalizedErrorText
            }
            return
        }

        messages[index].streaming = false
        if let normalizedErrorText {
            if messages[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages[index].text = normalizedErrorText
            } else {
                messages[index].text += "\n\(normalizedErrorText)"
            }
            lastError = normalizedErrorText
        }
        if !messages[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chatHistory.append(StylistMessage(role: .assistant, content: messages[index].text))
            if chatHistory.count > 14 {
                chatHistory = Array(chatHistory.suffix(14))
            }
        }
        activeAssistantIndex = nil
        streamTask = nil
    }
}

import SwiftUI

private enum StylistBubbleRole {
    case assistant
    case user
}

private enum StylistTool: String {
    case searchWardrobe = "search_wardrobe"
    case searchScrapedItems = "search_scraped_items"
    case getWardrobeSummary = "get_wardrobe_summary"
    case getWeather = "get_weather"
    case getUserProfile = "get_user_profile"
    case analyzeWardrobeGaps = "analyze_wardrobe_gaps"

    var displayLabel: String {
        switch self {
        case .searchWardrobe:
            return "Searching wardrobe…"
        case .searchScrapedItems:
            return "Discovering items…"
        case .getWardrobeSummary:
            return "Reading wardrobe…"
        case .getWeather:
            return "Checking weather…"
        case .getUserProfile:
            return "Loading profile…"
        case .analyzeWardrobeGaps:
            return "Analysing gaps…"
        }
    }

    static func displayLabel(for name: String) -> String {
        StylistTool(rawValue: name)?.displayLabel ?? "Working…"
    }
}

private struct StylistBubble: Identifiable {
    var id = UUID()
    var role: StylistBubbleRole
    var text: String
    var streaming: Bool = false
    let createdAt: Date = Date()
}

struct StylistView: View {
    @EnvironmentObject private var appServices: AppServices
    @State private var draftText = ""
    @State private var messages: [StylistBubble] = [
        StylistBubble(
            role: .assistant,
            text: "Ask the stylist for fit and combination ideas."
        )
    ]
    @State private var chatHistory: [StylistMessage] = []
    @State private var sending = false
    @State private var activeAssistantIndex: Int?
    @State private var streamTask: Task<Void, Never>?
    @State private var activeToolName: String?
    @State private var lastError: String?
    @State private var receivedAnyEvent = false
    @State private var didTrySendWhileOffline = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                messageArea

                Divider()
                    .overlay(PluckTheme.border)

                inputBar
            }
            .background(PluckTheme.background)
            .navigationTitle("Stylist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if sending {
                        ProgressView()
                    }
                }
            }
            .shellToolbar()
            .onAppear {
                if chatHistory.isEmpty {
                    chatHistory = []
                }
            }
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: PluckTheme.Spacing.xs) {
                statusBadge
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Stylist")
                        .font(.headline)
                        .foregroundStyle(PluckTheme.primaryText)
                    Text("Online · v3.0")
                        .font(.caption2)
                        .foregroundStyle(PluckTheme.secondaryText)
                }
            }

            Spacer()

            if let errorText = lastError, !sending {
                Text(errorText)
                    .font(.caption2)
                    .foregroundStyle(PluckTheme.danger)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, PluckTheme.Spacing.md)
        .padding(.vertical, PluckTheme.Spacing.sm)
    }

    private var statusBadge: some View {
        Circle()
            .fill(appServices.networkMonitor.isOnline ? Color.green : PluckTheme.danger)
            .animation(.snappy(duration: 0.18), value: appServices.networkMonitor.isOnline)
    }

    private var messageArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: PluckTheme.Spacing.md) {
                    ForEach(messages) { message in
                        messageBubble(for: message)
                    }

                    if sending, let activeToolName {
                        thinkingRow(toolLabel: StylistTool.displayLabel(for: activeToolName))
                    } else if sending {
                        thinkingRow(toolLabel: nil)
                    }

                    Color.clear
                        .frame(height: 2)
                        .id("chat-bottom")
                }
                .padding(PluckTheme.Spacing.md)
            }
            .onChange(of: messages.count) {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("chat-bottom", anchor: .bottom)
                }
            }
            .onChange(of: sending) {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("chat-bottom", anchor: .bottom)
                }
            }
            .onAppear {
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: PluckTheme.Spacing.xs) {
            HStack(spacing: PluckTheme.Spacing.sm) {
                TextField("Ask your stylist…", text: $draftText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, PluckTheme.Spacing.sm)
                    .padding(.vertical, 12)
                    .background(PluckTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
                    .disabled(sending)
                    .onSubmit {
                        send()
                    }

                Button {
                    send()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .padding(10)
                        .background(PluckTheme.accent)
                        .foregroundStyle(.white)
                        .clipShape(Circle())
                }
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
            }
            .padding(.horizontal, PluckTheme.Spacing.md)
            .padding(.top, PluckTheme.Spacing.sm)

            Text("AI can make mistakes. Review all outfit suggestions.")
                .font(.caption2)
                .foregroundStyle(PluckTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, PluckTheme.Spacing.md)
                .padding(.bottom, PluckTheme.Spacing.sm)
        }
        .background(PluckTheme.background)
    }

    @ViewBuilder
    private func messageBubble(for message: StylistBubble) -> some View {
        let isUser = message.role == .user
        HStack(alignment: .top, spacing: PluckTheme.Spacing.sm) {
            if isUser {
                Spacer(minLength: PluckTheme.Spacing.xl)
            } else {
                assistantAvatar
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(Self.timeFormatter.string(from: message.createdAt))
                    .font(.caption2)
                    .foregroundStyle(PluckTheme.secondaryText)

                bubbleContent(for: message)
                    .frame(maxWidth: 320, alignment: isUser ? .trailing : .leading)
            }

            if !isUser {
                Spacer(minLength: PluckTheme.Spacing.xl)
            } else {
                userAvatar
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private var assistantAvatar: some View {
        Circle()
            .fill(PluckTheme.assistantBubble)
            .frame(width: 28, height: 28)
            .overlay {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(PluckTheme.primaryText)
            }
    }

    private var userAvatar: some View {
        Circle()
            .fill(PluckTheme.userBubble)
            .frame(width: 28, height: 28)
            .overlay {
                Image(systemName: "person.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
            }
    }

    @ViewBuilder
    private func bubbleContent(for message: StylistBubble) -> some View {
        HStack(alignment: .bottom, spacing: 4) {
            if message.role == .assistant {
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(message.text)
                    .font(.caption)
                    .foregroundStyle(message.role == .user ? .white : PluckTheme.primaryText)
                    .multilineTextAlignment(message.role == .user ? .leading : .leading)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                if message.streaming {
                    Text("_")
                        .font(.caption)
                        .foregroundStyle(PluckTheme.secondaryText)
                        .lineLimit(1)
                        .opacity(0.001)
                        .overlay(alignment: .leading) {
                            CursorDot()
                        }
                }
            }

            if message.role == .user {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, PluckTheme.Spacing.md)
        .padding(.vertical, PluckTheme.Spacing.sm)
        .background(message.role == .user ? PluckTheme.userBubble : PluckTheme.assistantBubble)
        .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
    }

    @ViewBuilder
    private func thinkingRow(toolLabel: String?) -> some View {
        HStack(alignment: .top, spacing: PluckTheme.Spacing.sm) {
            assistantAvatar

            VStack(alignment: .leading, spacing: 6) {
                Text("Now")
                    .font(.caption2)
                    .foregroundStyle(PluckTheme.secondaryText)

                if let toolLabel {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.5)
                            .tint(PluckTheme.primaryText)

                        Text(toolLabel)
                            .font(.caption)
                            .foregroundStyle(PluckTheme.secondaryText)
                    }
                    .padding(10)
                    .background(PluckTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
                } else {
                    HStack(spacing: 6) {
                        TypingDot().animation(
                            .easeInOut(duration: 0.45)
                                .repeatForever(), value: sending
                        )
                        TypingDot(delay: 0.15)
                            .animation(
                                .easeInOut(duration: 0.45)
                                    .repeatForever(), value: sending
                            )
                        TypingDot(delay: 0.3)
                            .animation(
                                .easeInOut(duration: 0.45)
                                    .repeatForever(), value: sending
                            )
                    }
                    .padding(10)
                    .background(PluckTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    private func send() {
        let messageText = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty, !sending else { return }

        draftText = ""
        lastError = nil
        sending = true
        receivedAnyEvent = false
        didTrySendWhileOffline = false

        let userMessage = StylistBubble(role: .user, text: messageText)
        messages.append(userMessage)
        chatHistory.append(StylistMessage(role: .user, content: messageText))

        if !appServices.networkMonitor.isOnline {
            finalizeStream(with: "You're offline. Your message was queued and will send when you reconnect.")
            didTrySendWhileOffline = true
            return
        }

        let assistantIndex = messages.count
        messages.append(StylistBubble(role: .assistant, text: "", streaming: true))
        activeAssistantIndex = assistantIndex
        activeToolName = nil

        streamTask?.cancel()
        streamTask = Task {
            do {
                for try await event in appServices.stylistService.streamChat(
                    message: messageText,
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
            activeToolName = nil
            guard let index = activeAssistantIndex, messages.indices.contains(index) else { return }
            if messages[index].text.isEmpty {
                messages[index].text = content
            } else {
                messages[index].text += content
            }

        case let .toolUse(name, _, _, _, _, _):
            activeToolName = name
            guard let index = activeAssistantIndex, messages.indices.contains(index) else { return }
            if messages[index].text.isEmpty {
                messages[index].text = ""
            }

        case let .toolResult(name, summary, _, _, _, _, _):
            activeToolName = nil
            guard let index = activeAssistantIndex, messages.indices.contains(index) else { return }
            let resultText = messages[index].text.isEmpty
                ? (summary ?? "\(name) completed.")
                : messages[index].text
            messages[index].text = resultText

        case let .memoryUpdate(updated, _, _, _, _, _):
            if updated {
                messages.append(
                    StylistBubble(
                        role: .assistant,
                        text: "Memory updated."
                    )
                )
            }

        case let .error(content, _, _, _, _, _):
            finalizeStream(with: content)

        case .done(_, _, _, _, _):
            finalizeStream()

        case let .unknown(type, _, _, _, _, _):
            finalizeStream(with: "Stylist sent unknown event: \(type)")
        }
    }

    private func finalizeStream(with errorText: String? = nil) {
        sending = false
        activeToolName = nil

        let normalizedErrorText: String? = {
            if errorText == nil, !receivedAnyEvent {
                return didTrySendWhileOffline
                    ? "Offline mode: your request could not be sent yet."
                    : "Stylist did not return any stream events."
            }
            return errorText
        }()

        guard let index = activeAssistantIndex, messages.indices.contains(index) else {
            activeAssistantIndex = nil
            if let normalizedErrorText {
                messages.append(StylistBubble(role: .assistant, text: normalizedErrorText))
                lastError = normalizedErrorText
            }
            streamTask = nil
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

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct TypingDot: View {
    private let delay: Double
    @State private var animate = false

    init(delay: Double = 0) {
        self.delay = delay
    }

    var body: some View {
        Circle()
            .fill(PluckTheme.secondaryText)
            .frame(width: 6, height: 6)
            .opacity(animate ? 1 : 0.2)
            .scaleEffect(animate ? 1.2 : 0.8)
            .animation(
                .easeInOut(duration: 0.4)
                    .repeatForever(autoreverses: true)
                    .delay(delay),
                value: animate
            )
            .onAppear {
                animate = true
            }
    }
}

private struct CursorDot: View {
    @State private var show = false

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(PluckTheme.secondaryText)
            .frame(width: 8, height: 12)
            .opacity(show ? 0.8 : 0)
            .offset(y: show ? 0 : -2)
            .animation(
                .easeInOut(duration: 0.4).repeatForever(autoreverses: true),
                value: show
            )
            .onAppear {
                show = true
            }
    }
}

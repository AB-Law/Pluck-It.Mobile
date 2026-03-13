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

private struct FitRationale {
    let summary: String
    let tags: [String]
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
    private let quickSuggestions = [
        "Suggest a night out fit",
        "What goes with my leather jacket?",
        "Need a travel-ready outfit",
        "Fresh capsule wardrobe ideas",
    ]

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
                    } else if let shareText = shareableTranscript, !shareText.isEmpty {
                        ShareLink(
                            item: shareText,
                            subject: Text("Stylist chat")
                        ) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(PluckTheme.accent)
                        }
                    } else {
                        EmptyView()
                    }
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button("New Topic") {
                        pluckImpactFeedback(.light)
                        resetConversation()
                    }
                }
            }
            .overlay(alignment: .top) {
                if sending && activeToolName == nil {
                    HStack {
                        typingBanner
                            .padding(.horizontal, PluckTheme.Spacing.md)
                            .padding(.top, 4)
                        Spacer()
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
                    Text("AI STYLIST")
                        .font(.title3.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(PluckTheme.primaryText)
                    Text("SYSTEM: ONLINE")
                        .font(.caption)
                        .foregroundStyle(PluckTheme.secondaryText)
                        .padding(.top, 1)
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
        .padding(.vertical, PluckTheme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .fill(PluckTheme.card)
                .overlay(
                    Rectangle()
                        .frame(height: 0.6)
                        .foregroundStyle(PluckTheme.border),
                    alignment: .bottom
                )
        )
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
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        messageBubble(for: message)
                            .pluckReveal(delay: min(Double(index) * 0.03, 0.24))
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
            if !quickSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PluckTheme.Spacing.sm) {
                        ForEach(quickSuggestions, id: \.self) { suggestion in
                            Button {
                                pluckImpactFeedback(.light)
                                sendQuickSuggestion(suggestion)
                            } label: {
                                Text(suggestion)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(PluckTheme.secondaryText)
                                    .lineLimit(1)
                                    .padding(.horizontal, PluckTheme.Spacing.sm)
                                    .padding(.vertical, PluckTheme.Spacing.xxs)
                                    .background(PluckTheme.card)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: PluckTheme.Radius.small)
                                            .stroke(PluckTheme.border, lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
                            }
                            .disabled(sending)
                        }
                    }
                }
            }

            HStack(spacing: PluckTheme.Spacing.sm) {
                TextField("Ask your stylist…", text: $draftText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, PluckTheme.Spacing.sm)
                    .padding(.vertical, 12)
                    .background(PluckTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
                    .disabled(sending)
                    .onSubmit {
                        pluckImpactFeedback(.light)
                        send()
                    }

                Button {
                    pluckImpactFeedback(.light)
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

            VStack(alignment: .leading, spacing: 8) {
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

                if message.role == .assistant, let rationale = styleRationale(for: message.text) {
                    fitRationaleCard(for: rationale)
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

    private var typingBanner: some View {
        Text("Stylist is generating your next fit...")
            .font(.caption2)
            .foregroundStyle(PluckTheme.accent)
            .padding(.horizontal, PluckTheme.Spacing.md)
            .padding(.vertical, 8)
            .background(PluckTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
    }

    @ViewBuilder
    private func fitRationaleCard(for rationale: FitRationale) -> some View {
        VStack(alignment: .leading, spacing: PluckTheme.Spacing.xs) {
            Text("Style Rationale")
                .font(.caption2.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(PluckTheme.accent)
            Text(rationale.summary)
                .font(.caption)
                .foregroundStyle(PluckTheme.secondaryText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            HStack(spacing: 6) {
                ForEach(rationale.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(PluckTheme.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(PluckTheme.background.opacity(0.5))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(PluckTheme.border, lineWidth: 1))
                }
            }
        }
        .padding(PluckTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: PluckTheme.Radius.small)
                .fill(PluckTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PluckTheme.Radius.small)
                .stroke(PluckTheme.accent.opacity(0.35), lineWidth: 1)
        )
        .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
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

    private var shareableTranscript: String? {
        guard !messages.isEmpty else { return nil }
        return messages
            .compactMap { message in
                let sender = message.role == .user ? "You" : "Stylist"
                return "\(sender): \(message.text)"
            }
            .joined(separator: "\n")
    }

    private func styleRationale(for text: String) -> FitRationale? {
        let styleKeywords = ["modern", "minimal", "minimalist", "editorial", "streetwear", "vintage", "casual", "formal"]
        let lines = text
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard let startIndex = lines.firstIndex(where: { line in
            let lowercaseLine = line.lowercased()
            return lowercaseLine.hasPrefix("style rationale") || lowercaseLine.hasPrefix("rationale")
        }) else {
            return nil
        }

        let rationaleLine = lines.dropFirst(startIndex).joined(separator: " ")
        guard let colonRange = rationaleLine.range(of: ":") else {
            return nil
        }

        let rationaleText = String(rationaleLine[colonRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rationaleText.isEmpty else { return nil }

        var detectedTags = styleKeywords
            .filter { text.lowercased().contains($0) }
            .map { $0.capitalized }
            .prefix(3)
        if detectedTags.isEmpty {
            detectedTags = ["Modern", "Minimalist", "Editorial"]
        }

        return FitRationale(summary: String(rationaleText), tags: Array(detectedTags))
    }

    private func sendQuickSuggestion(_ suggestion: String) {
        guard !sending else { return }
        draftText = suggestion
        send()
    }

    private func resetConversation() {
        withAnimation(.easeInOut(duration: 0.2)) {
            messages = [
                StylistBubble(
                    role: .assistant,
                    text: "Ask the stylist for fit and combination ideas."
                )
            ]
            chatHistory = []
            lastError = nil
            activeAssistantIndex = nil
            draftText = ""
            streamTask?.cancel()
            streamTask = nil
            sending = false
            activeToolName = nil
        }
    }
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

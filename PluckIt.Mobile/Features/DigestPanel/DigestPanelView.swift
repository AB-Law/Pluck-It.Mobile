import SwiftUI

struct DigestPanelView: View {
    @EnvironmentObject private var appServices: AppServices
    @Environment(\.dismiss) private var dismiss

    @State private var digest: WardrobeDigest?
    @State private var loading = false
    @State private var errorText: String?
    @State private var rationaleOpen: [Bool] = []
    @State private var feedbackSent: [String?] = []  // "up" | "down" | nil per suggestion

    var body: some View {
        NavigationStack {
            Group {
                if loading && digest == nil {
                    stateLoading
                } else if let errorText, digest == nil {
                    stateError(errorText)
                } else if let digest {
                    digestContent(digest)
                } else {
                    stateEmpty
                }
            }
            .navigationTitle("Weekly Digest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        pluckImpactFeedback(.light)
                        dismiss()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .task { await load() }
        }
    }

    private func digestContent(_ digest: WardrobeDigest) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PluckTheme.Spacing.md) {
                metaSection(digest)
                Divider()
                    .padding(.horizontal, PluckTheme.Spacing.xxs)

                if digest.suggestions.isEmpty {
                    Text("No suggestions in this digest yet.")
                        .font(.caption)
                        .foregroundStyle(PluckTheme.secondaryText)
                        .padding(.horizontal, PluckTheme.Spacing.md)
                        .pluckReveal()
                } else {
                    VStack(spacing: PluckTheme.Spacing.sm) {
                        ForEach(Array(digest.suggestions.enumerated()), id: \.offset) { idx, suggestion in
                            suggestionCard(suggestion: suggestion, index: idx, digestId: digest.id)
                                .pluckReveal(delay: min(Double(idx) * 0.03, 0.28))
                        }
                    }
                    .padding(.horizontal, PluckTheme.Spacing.md)
                }

                Spacer(minLength: PluckTheme.Spacing.xl)
            }
            .padding(.vertical, PluckTheme.Spacing.sm)
        }
        .background(PluckTheme.background)
    }

    private func metaSection(_ digest: WardrobeDigest) -> some View {
        VStack(alignment: .leading, spacing: PluckTheme.Spacing.xs) {
            if let generatedAt = digest.generatedAt {
                Text("Generated \(formatDate(generatedAt))")
                    .font(.caption)
                    .foregroundStyle(PluckTheme.secondaryText)
            }
            HStack(spacing: PluckTheme.Spacing.md) {
                if let total = digest.totalItems {
                    Label("\(total) items", systemImage: "tshirt")
                        .font(.caption2)
                        .foregroundStyle(PluckTheme.mutedText)
                }
                if let withWears = digest.itemsWithWearHistory {
                    Label("\(withWears) with wear data", systemImage: "chart.bar")
                        .font(.caption2)
                        .foregroundStyle(PluckTheme.mutedText)
                }
                if let zone = digest.climateZone {
                    Label(zone, systemImage: "location")
                        .font(.caption2)
                        .foregroundStyle(PluckTheme.mutedText)
                }
            }
            Text("AI-curated purchase suggestions based on your wardrobe.")
                .font(.caption)
                .foregroundStyle(PluckTheme.secondaryText)
        }
        .padding(.horizontal, PluckTheme.Spacing.md)
    }

    private func suggestionCard(suggestion: DigestSuggestion, index: Int, digestId: String) -> some View {
        let voted = index < feedbackSent.count ? feedbackSent[index] : nil

        return VStack(alignment: .leading, spacing: PluckTheme.Spacing.sm) {
            Text(suggestion.item)
                .font(.subheadline)
                .foregroundStyle(PluckTheme.primaryText)

            if let rationale = suggestion.rationale, !rationale.isEmpty {
                Button {
                    let isOpen = index < rationaleOpen.count ? rationaleOpen[index] : false
                    if index < rationaleOpen.count {
                        pluckImpactFeedback(.light)
                        rationaleOpen[index] = !isOpen
                    }
                } label: {
                    HStack {
                        Text("Why this?")
                            .font(.caption)
                            .foregroundStyle(PluckTheme.info)
                        Image(systemName: (index < rationaleOpen.count && rationaleOpen[index]) ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(PluckTheme.info)
                    }
                }
                .buttonStyle(.plain)

                if index < rationaleOpen.count && rationaleOpen[index] {
                    Text(rationale)
                        .font(.caption)
                        .foregroundStyle(PluckTheme.secondaryText)
                        .transition(.opacity)
                }
            }

            HStack(spacing: PluckTheme.Spacing.sm) {
                Button {
                    pluckImpactFeedback(.light)
                    Task { await sendFeedback(digestId: digestId, index: index, suggestion: suggestion, signal: "up") }
                } label: {
                    Label("Good pick", systemImage: voted == "up" ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(.caption)
                        .foregroundStyle(voted == "up" ? PluckTheme.success : PluckTheme.secondaryText)
                }
                .buttonStyle(.bordered)
                .disabled(voted != nil)

                Button {
                    pluckImpactFeedback(.light)
                    Task { await sendFeedback(digestId: digestId, index: index, suggestion: suggestion, signal: "down") }
                } label: {
                    Label("Not for me", systemImage: voted == "down" ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        .font(.caption)
                        .foregroundStyle(voted == "down" ? PluckTheme.danger : PluckTheme.secondaryText)
                }
                .buttonStyle(.bordered)
                .disabled(voted != nil)
            }
        }
        .padding(PluckTheme.Spacing.md)
        .background(PluckTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
        .overlay(
            RoundedRectangle(cornerRadius: PluckTheme.Radius.small)
                .stroke(PluckTheme.border, lineWidth: 0.7)
        )
    }

    private var stateLoading: some View {
        VStack(spacing: PluckTheme.Spacing.sm) {
            ProgressView("Loading digest")
                .foregroundStyle(PluckTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stateEmpty: some View {
        VStack(spacing: PluckTheme.Spacing.sm) {
            Image(systemName: "chart.bar")
                .font(.largeTitle)
                .foregroundStyle(PluckTheme.mutedText)
            Text("No digest yet")
                .font(.headline)
                .foregroundStyle(PluckTheme.primaryText)
            Text("Add items to your wardrobe and check back next Monday.")
                .font(.caption)
                .foregroundStyle(PluckTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(PluckTheme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stateError(_ message: String) -> some View {
        VStack(spacing: PluckTheme.Spacing.sm) {
            Text("Could not load digest")
                .font(.headline)
                .foregroundStyle(PluckTheme.danger)
            Text(message)
                .font(.caption)
                .foregroundStyle(PluckTheme.secondaryText)
                .multilineTextAlignment(.center)
            Button("Retry") {
                pluckImpactFeedback(.light)
                Task { await load() }
            }
                .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        loading = true
        errorText = nil
        defer { loading = false }
        do {
            let result = try await appServices.digestService.fetchLatest()
            digest = result
            guard let result else { return }
            rationaleOpen = Array(repeating: false, count: result.suggestions.count)
            feedbackSent = Array(repeating: nil, count: result.suggestions.count)
            // Restore prior feedback
            if let prior = try? await appServices.digestService.fetchFeedback(digestId: result.id) {
                for item in prior {
                    if item.suggestionIndex < feedbackSent.count {
                        feedbackSent[item.suggestionIndex] = item.signal
                    }
                }
            }
        } catch {
            if !(error is CancellationError) {
                let urlError = error as? URLError
                if urlError?.code != .cancelled {
                    errorText = error.localizedDescription
                }
            }
        }
    }

    private func sendFeedback(digestId: String, index: Int, suggestion: DigestSuggestion, signal: String) async {
        guard index < feedbackSent.count else { return }
        feedbackSent[index] = signal
        let body = DigestFeedbackRequest(
            digestId: digestId,
            suggestionIndex: index,
            suggestionDescription: suggestion.item,
            signal: signal
        )
        try? await appServices.digestService.sendFeedback(body)
    }

    private func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) {
            let display = DateFormatter()
            display.dateStyle = .medium
            return display.string(from: date)
        }
        return iso
    }
}

import SwiftUI

struct VaultView: View {
    @EnvironmentObject private var appServices: AppServices
    @State private var insights: VaultInsightsResponse?
    @State private var loading = false
    @State private var errorText: String?
    @State private var loadTask: Task<Void, Never>?

    private var hasData: Bool {
        insights != nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading && !hasData {
                    stateLoadingView()
                } else if let errorText {
                    stateErrorView(errorText: errorText)
                } else if let insights {
                    ScrollView {
                        VStack(alignment: .leading, spacing: PluckTheme.Spacing.md) {
                            statsCards(for: insights)
                            insightsPanel(for: insights)
                            Divider()
                                .padding(.horizontal, PluckTheme.Spacing.xxs)
                            Text("CPW signals")
                                .font(.subheadline)
                                .foregroundStyle(PluckTheme.secondaryText)
                                .textCase(.uppercase)
                                .padding(.horizontal, PluckTheme.Spacing.md)
                            cpwSignalsList(for: insights)
                            Spacer(minLength: PluckTheme.Spacing.md)
                        }
                        .padding(.vertical, PluckTheme.Spacing.sm)
                    }
                } else {
                    Text("No vault insight payload yet")
                        .foregroundStyle(PluckTheme.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        scheduleLoad()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(PluckTheme.primaryText)
                    }
                }
            }
            .task {
                scheduleLoad()
            }
            .refreshable {
                loadTask?.cancel()
                await loadInsights()
            }
            .shellToolbar()
        }
    }

    private func statsCards(for insights: VaultInsightsResponse) -> some View {
        HStack(alignment: .top, spacing: PluckTheme.Spacing.sm) {
            VaultStatCard(
                title: "Total archive items",
                value: formattedInt(insights.totalItems),
                accent: PluckTheme.accent
            )

            VaultStatCard(
                title: "Average CPW",
                value: formattedCurrency(insights.cpw),
                accent: PluckTheme.success
            )

            VaultStatCard(
                title: "Est. value",
                value: formattedCurrency(insights.totalMarketValue),
                accent: PluckTheme.info
            )
        }
        .padding(.horizontal, PluckTheme.Spacing.md)
    }

    private func insightsPanel(for insights: VaultInsightsResponse) -> some View {
        VStack(alignment: .leading, spacing: PluckTheme.Spacing.sm) {
            Text("Smart Insights")
                .font(.subheadline)
                .foregroundStyle(PluckTheme.secondaryText)

            RoundedRectangle(cornerRadius: PluckTheme.Radius.small)
                .fill(PluckTheme.card)
                .overlay {
                    VStack(alignment: .leading, spacing: PluckTheme.Spacing.sm) {
                        if let count = insights.totalItems, count > 0 {
                            LabeledMetric(
                                title: "Portfolio density",
                                value: "\(count) tracked entries",
                                accent: .secondary
                            )

                            LabeledMetric(
                                title: "Average item frequency",
                                value: "\(insights.averageItemCount ?? 0) wears",
                                accent: .secondary
                            )

                            if let avg = insights.cpw {
                                LabeledMetric(
                                    title: "Cost-per-wear trend",
                                    value: formattedCurrency(avg),
                                    accent: .secondary
                                )
                            }
                        } else {
                            Text("Add wear data to unlock behavioral insights.")
                                .font(.caption)
                                .foregroundStyle(PluckTheme.secondaryText)
                        }
                    }
                    .padding(PluckTheme.Spacing.md)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: PluckTheme.Radius.small)
                        .strokeBorder(PluckTheme.border, lineWidth: 1)
                )
        }
        .padding(.horizontal, PluckTheme.Spacing.md)
    }

    @ViewBuilder
    private func cpwSignalsList(for insights: VaultInsightsResponse) -> some View {
        let rows = insights.cpwItems ?? []
        let sorted = rows.compactMap { row -> (String, Double)? in
            guard let key = row.key, let value = row.value else { return nil }
            return (key, value)
        }

    if sorted.isEmpty {
        VStack {
            Text("CPW signals are not available yet.")
                .font(.caption)
                .foregroundStyle(PluckTheme.secondaryText)
                .padding(.horizontal, PluckTheme.Spacing.md)
        }
    } else {
        VStack(spacing: PluckTheme.Spacing.xs) {
            ForEach(Array(sorted.prefix(10).indices), id: \.self) { idx in
                let pair = sorted[idx]
                HStack {
                    Text("\(idx + 1). \(pair.0)")
                        .font(.caption)
                        .foregroundStyle(PluckTheme.secondaryText)
                        .lineLimit(1)

                    Spacer()

                    Text(formattedCurrency(pair.1))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(PluckTheme.primaryText)
                        .padding(.horizontal, PluckTheme.Spacing.sm)
                        .padding(.vertical, 4)
                        .background(PluckTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
                }
                .padding(.horizontal, PluckTheme.Spacing.md)
                .padding(.vertical, PluckTheme.Spacing.xs)
            }
        }
        }
    }

    private func stateLoadingView() -> some View {
        VStack(spacing: PluckTheme.Spacing.sm) {
            ProgressView("Loading vault")
                .foregroundStyle(PluckTheme.secondaryText)

            VStack(spacing: PluckTheme.Spacing.sm) {
                HStack {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: PluckTheme.Radius.small)
                            .fill(PluckTheme.card)
                            .frame(height: 84)
                            .overlay(ProgressView().tint(PluckTheme.primaryText))
                    }
                }
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: PluckTheme.Radius.small)
                        .fill(PluckTheme.card)
                        .frame(height: 58)
                        .overlay(ProgressView().tint(PluckTheme.primaryText))
                }
            }
            .padding(.horizontal, PluckTheme.Spacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stateErrorView(errorText: String) -> some View {
        VStack(spacing: PluckTheme.Spacing.sm) {
            Text("Vault request failed")
                .foregroundStyle(PluckTheme.danger)
                .font(.headline)
            Text(errorText)
                .foregroundStyle(PluckTheme.secondaryText)
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding(.horizontal, PluckTheme.Spacing.md)

            Button("Retry") {
                scheduleLoad()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formattedInt(_ value: Int?) -> String {
        let fallback = "0"
        guard let value else { return fallback }
        return NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }

    private func formattedCurrency(_ value: Double?) -> String {
        guard let value else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "—"
    }

    private func scheduleLoad() {
        loadTask?.cancel()
        loadTask = Task { await loadInsights() }
    }

    private func loadInsights() async {
        loading = true
        do {
            insights = try await appServices.vaultInsightsService.fetchInsights()
            errorText = nil
        } catch {
            if !Task.isCancelled && !(error is CancellationError) {
                let urlError = error as? URLError
                if urlError?.code != .cancelled {
                    errorText = String(describing: error)
                }
            }
        }
        loading = false
    }
}

private struct VaultStatCard: View {
    let title: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: PluckTheme.Spacing.xs) {
            Text(title)
                .font(.caption)
                .foregroundStyle(PluckTheme.secondaryText)
            Text(value)
                .font(.headline)
                .foregroundStyle(PluckTheme.primaryText)
            Rectangle()
                .fill(accent)
                .frame(height: 2)
                .opacity(0.75)
                .clipShape(RoundedRectangle(cornerRadius: 1))
        }
        .padding(PluckTheme.Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(PluckTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
    }
}

private struct LabeledMetric: View {
    let title: String
    let value: String
    let accent: Color

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(PluckTheme.secondaryText)
                    .textCase(.uppercase)
                Text(value)
                    .foregroundStyle(PluckTheme.primaryText)
                    .font(.subheadline)
            }
            Spacer()
            Circle()
                .fill(accent)
                .frame(width: 8, height: 8)
        }
    }
}

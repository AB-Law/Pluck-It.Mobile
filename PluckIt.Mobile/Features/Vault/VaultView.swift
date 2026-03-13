import SwiftUI

struct VaultView: View {
    @EnvironmentObject private var appServices: AppServices
    @State private var insights: VaultInsightsResponse?
    @State private var loading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Group {
                if loading && insights == nil {
                    ProgressView("Loading vault")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorText {
                    VStack(spacing: 12) {
                        Text("Vault request failed")
                            .foregroundStyle(.red)
                        Text(errorText)
                            .foregroundStyle(PluckTheme.muted)
                            .font(.caption)
                        Button("Retry") {
                            Task { await loadInsights() }
                        }
                    }
                    .padding()
                } else if let insights {
                    List {
                        Section("Summary") {
                            Text("Total Items: \(insights.totalItems ?? 0)")
                            Text("CPW: \(insights.cpw.map { String(format: "%.2f", $0) } ?? "—")")
                            Text("Average: \(insights.averageItemCount ?? 0)")
                            Text("Market value: \(insights.totalMarketValue.map { String(format: "%.2f", $0) } ?? "—")")
                        }
                        if let items = insights.cpwItems {
                            Section("Signals") {
                                ForEach(items.compactMap { $0.key }, id: \.self) { key in
                                    if let item = items.first(where: { $0.key == key }) {
                                        HStack {
                                            Text(key)
                                            Spacer()
                                            Text(item.value.map { String(format: "%.2f", $0) } ?? "—")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                } else {
                    Text("No vault insight payload yet")
                        .foregroundStyle(PluckTheme.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Vault")
            .task { await loadInsights() }
            .refreshable { await loadInsights() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await loadInsights() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }

    private func loadInsights() async {
        loading = true
        errorText = nil
        do {
            insights = try await appServices.vaultInsightsService.fetchInsights()
        } catch {
            errorText = String(describing: error)
        }
        loading = false
    }
}

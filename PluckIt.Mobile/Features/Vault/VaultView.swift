import SwiftUI

struct VaultView: View {
    @EnvironmentObject private var appServices: AppServices

    // Insights
    @State private var insights: VaultInsightsResponse?
    @State private var insightsLoading = false
    @State private var insightsError: String?
    @State private var insightsTask: Task<Void, Never>?

    // Items
    @State private var items: [ClothingItem] = []
    @State private var itemsLoading = false
    @State private var itemsLoadingMore = false
    @State private var itemsTask: Task<Void, Never>?
    @State private var itemsNextToken: String?
    @State private var itemsGeneration = 0

    // Filtering
    @State private var filters = VaultFilters()
    @State private var isFilterPresented = false

    // Item drawer
    @State private var selectedItem: ClothingItem?

    private var hasInsightData: Bool { insights != nil }
    private var hasActiveFilter: Bool { !filters.isDefault }

    var body: some View {
        NavigationStack {
            Group {
                if insightsLoading && !hasInsightData && items.isEmpty {
                    stateLoadingView()
                } else if let err = insightsError, !hasInsightData {
                    stateErrorView(errorText: err)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: PluckTheme.Spacing.md) {
                            if let insights {
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
                                Divider()
                                    .padding(.horizontal, PluckTheme.Spacing.xxs)
                            }

                            itemsSection
                            Spacer(minLength: PluckTheme.Spacing.md)
                        }
                        .padding(.vertical, PluckTheme.Spacing.sm)
                    }
                }
            }
            .navigationTitle("Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        isFilterPresented = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .foregroundStyle(PluckTheme.primaryText)
                            if hasActiveFilter {
                                Circle()
                                    .fill(PluckTheme.accent)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 4, y: -4)
                            }
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        scheduleInsightsLoad()
                        startItemsLoad(refresh: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(PluckTheme.primaryText)
                    }
                }
            }
            .task {
                scheduleInsightsLoad()
                startItemsLoad(refresh: true)
            }
            .refreshable {
                insightsTask?.cancel()
                await loadInsights()
                await awaitItemsLoad(refresh: true)
            }
            .shellToolbar()
            .sheet(isPresented: $isFilterPresented) {
                VaultFilterSidebarView(filters: $filters) {
                    startItemsLoad(refresh: true)
                }
            }
            .sheet(item: $selectedItem) { item in
                VaultItemDrawerView(item: item) { updated in
                    syncItem(updated)
                }
                .environmentObject(appServices)
            }
        }
    }

    // MARK: - Items Section

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: PluckTheme.Spacing.sm) {
            HStack {
                Text("Archive")
                    .font(.subheadline)
                    .foregroundStyle(PluckTheme.secondaryText)
                    .textCase(.uppercase)
                if hasActiveFilter {
                    Text("• Filtered")
                        .font(.caption2)
                        .foregroundStyle(PluckTheme.accent)
                }
            }
            .padding(.horizontal, PluckTheme.Spacing.md)

            if itemsLoading && items.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("Loading items")
                        .foregroundStyle(PluckTheme.secondaryText)
                    Spacer()
                }
                .padding(PluckTheme.Spacing.md)
            } else if items.isEmpty {
                Text("No items match the current filters.")
                    .font(.caption)
                    .foregroundStyle(PluckTheme.secondaryText)
                    .padding(.horizontal, PluckTheme.Spacing.md)
            } else {
                VStack(spacing: PluckTheme.Spacing.xs) {
                    ForEach(items) { item in
                        vaultItemRow(for: item)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedItem = item }
                    }

                    if itemsNextToken != nil {
                        if itemsLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView("Loading more")
                                    .foregroundStyle(PluckTheme.secondaryText)
                                Spacer()
                            }
                            .padding(.vertical, PluckTheme.Spacing.sm)
                        } else {
                            Button("Load more") {
                                startItemsLoad(refresh: false)
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(PluckTheme.info)
                            .padding(.vertical, PluckTheme.Spacing.sm)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func vaultItemRow(for item: ClothingItem) -> some View {
        HStack(spacing: PluckTheme.Spacing.sm) {
            AsyncImage(url: normalizedImageURL(item.imageUrl)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    Rectangle().fill(PluckTheme.card)
                        .overlay(Image(systemName: "tshirt").foregroundStyle(PluckTheme.secondaryText))
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))

            VStack(alignment: .leading, spacing: 4) {
                Text([item.brand, item.category].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(PluckTheme.primaryText)
                    .lineLimit(1)
                HStack(spacing: PluckTheme.Spacing.xs) {
                    if let wears = item.wearCount {
                        Text("\(wears) wear\(wears == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(PluckTheme.secondaryText)
                    }
                    if let price = item.price?.amount, price > 0,
                       let wears = item.wearCount, wears > 0 {
                        let cpw = price / Double(wears)
                        Text("CPW: \(formattedCurrency(cpw))")
                            .font(.caption2)
                            .foregroundStyle(PluckTheme.mutedText)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(PluckTheme.mutedText)
        }
        .padding(.horizontal, PluckTheme.Spacing.md)
        .padding(.vertical, PluckTheme.Spacing.xs)
    }

    private func syncItem(_ updated: ClothingItem) {
        if let idx = items.firstIndex(where: { $0.id == updated.id }) {
            items[idx] = updated
        }
        if selectedItem?.id == updated.id {
            selectedItem = updated
        }
    }

    // MARK: - Stats / Insights (unchanged layout)

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
            Text("CPW signals are not available yet.")
                .font(.caption)
                .foregroundStyle(PluckTheme.secondaryText)
                .padding(.horizontal, PluckTheme.Spacing.md)
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

    // MARK: - State views

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
            Button("Retry") { scheduleInsightsLoad() }
                .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Load Insights

    private func scheduleInsightsLoad() {
        insightsTask?.cancel()
        insightsTask = Task { await loadInsights() }
    }

    private func loadInsights() async {
        insightsLoading = true
        do {
            insights = try await appServices.vaultInsightsService.fetchInsights()
            insightsError = nil
        } catch {
            if !Task.isCancelled && !(error is CancellationError) {
                let urlError = error as? URLError
                if urlError?.code != .cancelled {
                    insightsError = String(describing: error)
                }
            }
        }
        insightsLoading = false
    }

    // MARK: - Load Items

    private func startItemsLoad(refresh: Bool) {
        if itemsLoading && !refresh || (!refresh && itemsNextToken == nil) { return }
        itemsGeneration += 1
        let gen = itemsGeneration
        itemsTask?.cancel()
        itemsLoading = true
        itemsLoadingMore = !refresh
        let token = refresh ? nil : itemsNextToken
        if refresh {
            itemsNextToken = nil
            items = []
        }
        itemsTask = Task { await runItemsLoad(token: token, generation: gen) }
    }

    private func awaitItemsLoad(refresh: Bool) async {
        startItemsLoad(refresh: refresh)
        if let t = itemsTask { await t.value }
    }

    private func runItemsLoad(token: String?, generation: Int) async {
        defer {
            if generation == itemsGeneration {
                itemsLoading = false
                itemsLoadingMore = false
                itemsTask = nil
            }
        }

        // Apply smart group client-side filtering after fetching (brand/condition/price server-side)
        let priceMin: Double? = filters.priceMin > 0 ? filters.priceMin : nil
        let priceMax: Double? = filters.priceMax < 5000 ? filters.priceMax : nil
        let minWears: Int? = filters.minWears > 0 ? filters.minWears : nil
        let brand: String? = filters.brand.isEmpty ? nil : filters.brand
        let condition: String? = filters.condition.isEmpty ? nil : filters.condition

        do {
            let response = try await appServices.wardrobeService.fetchItems(
                pageSize: 30,
                continuationToken: token,
                brand: brand,
                condition: condition,
                priceMin: priceMin,
                priceMax: priceMax,
                minWears: minWears
            )
            guard generation == itemsGeneration else { return }
            var fetchedItems = response.items
            // Client-side group filtering
            switch filters.group {
            case .all:
                break
            case .favorites:
                fetchedItems = fetchedItems.filter { item in
                    item.tags?.contains("favorite") == true ||
                    item.aestheticTags?.contains("favorite") == true
                }
            case .recentlyWorn:
                fetchedItems = fetchedItems.filter { $0.lastWornAt != nil || (($0.wearCount ?? 0) > 0) }
            }

            if token == nil {
                items = fetchedItems
            } else {
                items += fetchedItems
            }
            itemsNextToken = response.nextContinuationToken
        } catch {
            // silently ignore cancellations
        }
    }

    // MARK: - Helpers

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

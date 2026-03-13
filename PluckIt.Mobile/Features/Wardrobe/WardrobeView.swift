import SwiftUI

struct WardrobeView: View {
    @EnvironmentObject private var appServices: AppServices
    @State private var items: [ClothingItem] = []
    @State private var loading = false
    @State private var loadingMore = false
    @State private var loadingTask: Task<Void, Never>?
    @State private var loadingGeneration = 0
    @State private var errorText: String?
    @State private var nextToken: String?
    @State private var selectedItem: ClothingItem?
    @State private var searchText = ""
    @State private var sortMode: WardrobeSortMode = .newest

    private enum WardrobeSortMode: String, CaseIterable {
        case newest = "Newest"
        case oldest = "Oldest"
        case mostWorn = "Most Worn"
        case leastWorn = "Least Worn"
        case priceHigh = "Price: High–Low"
        case priceLow = "Price: Low–High"

        var sortField: String {
            switch self {
            case .newest, .oldest: return "dateAdded"
            case .mostWorn, .leastWorn: return "wearCount"
            case .priceHigh, .priceLow: return "price.amount"
            }
        }

        var sortDir: String {
            switch self {
            case .newest, .mostWorn, .priceHigh: return "desc"
            case .oldest, .leastWorn, .priceLow: return "asc"
            }
        }
    }

    private var isDataLoading: Bool {
        loading && items.isEmpty
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleItems: [ClothingItem] { items }

    private var loadMoreStateText: String {
        loadingMore ? "Loading more…" : "Load more"
    }

    var body: some View {
        NavigationStack {
            Group {
                if isDataLoading {
                    stateLoadingView()
                } else if let errorText {
                    stateErrorView(errorText: errorText, retryLabel: "Retry wardrobe")
                } else if items.isEmpty {
                    VStack(spacing: PluckTheme.Spacing.sm) {
                        Image(systemName: "tshirt")
                            .font(.system(size: 38))
                            .foregroundStyle(PluckTheme.mutedText)
                        Text("No wardrobe items yet")
                            .font(.headline)
                            .foregroundStyle(PluckTheme.primaryText)
                        Text("Sync your wardrobe and items will appear here.")
                            .foregroundStyle(PluckTheme.secondaryText)
                        Button("Refresh") {
                            startLoad(refresh: true)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(PluckTheme.accent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        HStack(spacing: PluckTheme.Spacing.sm) {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(PluckTheme.secondaryText)
                                TextField("Search wardrobe", text: $searchText)
                                    .foregroundStyle(PluckTheme.primaryText)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .submitLabel(.search)
                                    .onSubmit { startLoad(refresh: true) }
                            }
                            .padding(10)
                            .background(PluckTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))

                            Menu {
                                ForEach(WardrobeSortMode.allCases, id: \.self) { mode in
                                    Button(mode.rawValue) {
                                        sortMode = mode
                                        startLoad(refresh: true)
                                    }
                                }
                            } label: {
                                Label("Sort", systemImage: "arrow.up.arrow.down")
                                    .labelStyle(.iconOnly)
                                    .frame(width: PluckTheme.Control.rowHeight, height: PluckTheme.Control.rowHeight)
                                    .background(PluckTheme.card)
                                    .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
                                    .foregroundStyle(PluckTheme.primaryText)
                            }
                        }
                        .padding(.horizontal, PluckTheme.Spacing.md)
                        .padding(.top, PluckTheme.Spacing.md)

                        List {
                            Section(
                                header: Text("\(visibleItems.count) ITEM\(visibleItems.count == 1 ? "" : "S")")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(PluckTheme.secondaryText)
                                    .textCase(.uppercase)
                            ) {
                                ForEach(visibleItems) { item in
                                    WardrobeCardView(item: item)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            selectedItem = item
                                        }
                                }

                                if nextToken != nil {
                                    HStack {
                                        Spacer()
                                        if loadingMore {
                                            ProgressView(loadMoreStateText)
                                                .foregroundStyle(PluckTheme.secondaryText)
                                        } else {
                                            Button(loadMoreStateText) {
                                                startLoad(refresh: false)
                                            }
                                            .foregroundStyle(PluckTheme.info)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("Wardrobe")
            .navigationBarTitleDisplayMode(.inline)
            .background(PluckTheme.background)
            .task {
                if items.isEmpty {
                    await awaitCompletionOfLoad(refresh: true)
                }
            }
            .refreshable {
                await awaitCompletionOfLoad(refresh: true)
            }
            .shellToolbar()
            .sheet(item: $selectedItem) { item in
                WardrobeItemReviewModal(item: item) { updated in
                    syncUpdatedItem(updated)
                }
            }
        }
    }

    private func awaitCompletionOfLoad(refresh: Bool) async {
        startLoad(refresh: refresh)
        if let task = loadingTask {
            await task.value
        }
    }

    private func startLoad(refresh: Bool) {
        if loading && !refresh || (!refresh && nextToken == nil) {
            return
        }

        loadingGeneration += 1
        let generation = loadingGeneration
        loadingTask?.cancel()
        loading = true
        loadingMore = !refresh

        let requestContinuationToken = refresh ? nil : nextToken
        if refresh {
            nextToken = nil
            items = []
            errorText = nil
        }

        loadingTask = Task {
            await runLoad(
                refresh: refresh,
                continuationToken: requestContinuationToken,
                generation: generation
            )
        }
    }

    private func runLoad(refresh: Bool = false, continuationToken: String?, generation: Int) async {
        defer {
            if generation == loadingGeneration {
                loading = false
                loadingMore = false
                loadingTask = nil
            }
        }

        let currentSort = sortMode
        let currentQuery = query.isEmpty ? nil : query

        do {
            let response = try await appServices.wardrobeService.fetchItems(
                pageSize: 30,
                continuationToken: continuationToken,
                sortField: currentSort.sortField,
                sortDir: currentSort.sortDir,
                query: currentQuery
            )
            guard generation == loadingGeneration else { return }
            if refresh {
                items = response.items
            } else {
                items += response.items
            }
            nextToken = response.nextContinuationToken
            errorText = nil
        } catch {
            guard !isCancellationError(error) else { return }
            guard generation == loadingGeneration else { return }
            errorText = "Data could not be loaded: \(error)"
        }
    }

    private func syncUpdatedItem(_ updated: ClothingItem) {
        if let index = items.firstIndex(where: { $0.id == updated.id }) {
            items[index] = updated
        }
        selectedItem = updated
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        return (error as? URLError)?.code == .cancelled
    }

    private func stateLoadingView() -> some View {
        VStack(spacing: PluckTheme.Spacing.sm) {
            ProgressView("Loading wardrobe")
                .foregroundStyle(PluckTheme.secondaryText)
            HStack(spacing: PluckTheme.Spacing.sm) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: PluckTheme.Radius.small)
                        .fill(PluckTheme.card)
                        .frame(height: 96)
                        .overlay(
                            ProgressView()
                                .tint(PluckTheme.primaryText)
                        )
                        .padding(.horizontal, PluckTheme.Spacing.xxs)
                }
            }
            .padding(.horizontal, PluckTheme.Spacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stateErrorView(errorText: String, retryLabel: String) -> some View {
        VStack(spacing: PluckTheme.Spacing.sm) {
            Text("Wardrobe unavailable")
                .font(.headline.weight(.semibold))
                .foregroundStyle(PluckTheme.danger)
            Text(errorText)
                .font(.caption)
                .foregroundStyle(PluckTheme.mutedText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, PluckTheme.Spacing.lg)
            Button(retryLabel) {
                startLoad(refresh: true)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

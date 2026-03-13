import SwiftUI

struct WardrobeView: View {
    @EnvironmentObject private var appServices: AppServices
    @State private var items: [ClothingItem] = []
    @State private var loading = false
    @State private var loadingMore = false
    @State private var errorText: String?
    @State private var nextToken: String?
    @State private var selectedItem: ClothingItem?
    @State private var searchText = ""
    @State private var sortMode: WardrobeSortMode = .newest

    private enum WardrobeSortMode: String, CaseIterable {
        case newest = "Newest"
        case brandAZ = "Brand A-Z"
        case brandZA = "Brand Z-A"
        case mostWorn = "Most Worn"
        case leastWorn = "Least Worn"
    }

    private var isDataLoading: Bool {
        loading && items.isEmpty
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleItems: [ClothingItem] {
        let baseItems: [ClothingItem]
        if query.isEmpty {
            baseItems = items
        } else {
            baseItems = items.filter { item in
                item.searchableText().lowercased().contains(query.lowercased())
            }
        }

        let sorted = baseItems.sorted { lhs, rhs in
            switch sortMode {
            case .newest:
                return lhs.brand?.localizedCaseInsensitiveCompare(rhs.brand ?? "") == .orderedAscending
            case .brandAZ:
                return lhs.brand ?? "" < rhs.brand ?? ""
            case .brandZA:
                return lhs.brand ?? "" > rhs.brand ?? ""
            case .mostWorn:
                return (lhs.wearCount ?? 0) > (rhs.wearCount ?? 0)
            case .leastWorn:
                return (lhs.wearCount ?? 0) < (rhs.wearCount ?? 0)
            }
        }
        return sorted
    }

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
                            Task { await refresh() }
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
                            }
                            .padding(10)
                            .background(PluckTheme.card)
                            .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))

                            Menu {
                                ForEach(WardrobeSortMode.allCases, id: \.self) { mode in
                                    Button(mode.rawValue) {
                                        sortMode = mode
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
                                                Task { await loadItems(refresh: false) }
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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(PluckTheme.primaryText)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Label("Sort", systemImage: "line.3.horizontal.decrease")
                    }
                }
            }
            .task {
                if items.isEmpty {
                    await loadItems(refresh: true)
                }
            }
            .refreshable {
                await refresh()
            }
            .sheet(item: $selectedItem) { item in
                WardrobeItemReviewModal(item: item)
            }
        }
    }

    private func refresh() async {
        await loadItems(refresh: true)
    }

    private func loadItems(refresh: Bool = false) async {
        guard !loading else { return }
        loading = true
        loadingMore = !refresh
        if refresh {
            nextToken = nil
            items = []
        }
        do {
            let response = try await appServices.wardrobeService.fetchItems(
                page: 1,
                pageSize: 30,
                continuationToken: nextToken,
                search: query.isEmpty ? nil : query
            )
            if refresh {
                items = response.items
            } else {
                items += response.items
            }
            nextToken = response.nextContinuationToken
            errorText = nil
        } catch {
            errorText = "Data could not be loaded: \(error)"
        }
        loadingMore = false
        loading = false
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
                Task { await loadItems(refresh: true) }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

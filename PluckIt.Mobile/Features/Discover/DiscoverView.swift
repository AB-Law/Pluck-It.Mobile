import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var appServices: AppServices
    @State private var sources: [ScraperSource] = []
    @State private var feedItems: [ScrapedItem] = []
    @State private var continuationToken: String?
    @State private var loading = false
    @State private var loadingMore = false
    @State private var feedLoadTask: Task<Void, Never>?
    @State private var errorText: String?
    @State private var searchText = ""
    @State private var activeSourceId: String?
    @State private var sortMode: DiscoverSortMode = .top
    @State private var timeRange: DiscoverTimeRange = .all

    private enum DiscoverSortMode: String, CaseIterable {
        case top = "Top"
        case recent = "Recent"

        var apiValue: String {
            switch self {
            case .top:
                return "score"
            case .recent:
                return "recent"
            }
        }
    }

    private enum DiscoverTimeRange: String, CaseIterable {
        case oneHour = "1h"
        case oneDay = "1d"
        case sevenDays = "7d"
        case thirtyDays = "30d"
        case all = "all"

        var label: String {
            switch self {
            case .oneHour:
                return "1h"
            case .oneDay:
                return "1d"
            case .sevenDays:
                return "7d"
            case .thirtyDays:
                return "30d"
            case .all:
                return "All"
            }
        }

        var apiValue: String {
            switch self {
            case .oneHour:
                return "1h"
            case .oneDay:
                return "1d"
            case .sevenDays:
                return "7d"
            case .thirtyDays:
                return "30d"
            case .all:
                return "all"
            }
        }
    }

    private var isInitialLoading: Bool {
        loading && feedItems.isEmpty
    }

    private var normalizedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sourceLabel: String {
        guard let sourceId = activeSourceId,
              !sourceId.isEmpty,
              let source = sources.first(where: { $0.id == sourceId }) else {
            return "All Sources"
        }
        return source.name
    }

    private var visibleItems: [ScrapedItem] {
        let baseItems: [ScrapedItem]
        if let activeSourceId = activeSourceId, !activeSourceId.isEmpty {
            baseItems = feedItems.filter {
                if let sourceId = $0.sourceId, !sourceId.isEmpty {
                    return sourceId == activeSourceId
                }
                return $0.source?.id == activeSourceId
            }
        } else {
            baseItems = feedItems
        }

        let query = normalizedSearch.lowercased()
        if query.isEmpty {
            return baseItems
        }

        return baseItems.filter { item in
            let title = item.title?.lowercased() ?? ""
            let brand = item.brand?.lowercased() ?? ""
            let sourceName = item.resolvedSourceName(from: sources).lowercased()
            let tagMatch = item.tags?.contains { $0.lowercased().contains(query) } == true
            return title.contains(query) || brand.contains(query) || sourceName.contains(query) || tagMatch
        }
    }

    private var activeTimeRangeNotice: String? {
        guard timeRange != .all else { return nil }
        return "Showing the last \(timeRange.label)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: PluckTheme.Spacing.md) {
                    controlsHeader

                    if let errorText {
                        VStack(spacing: PluckTheme.Spacing.xs) {
                            Text(errorText)
                                .font(.caption)
                                .foregroundStyle(PluckTheme.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, PluckTheme.Spacing.lg)
                            Button("Retry") {
                                restartFeedLoad()
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if isInitialLoading {
                        stateLoading()
                    } else if visibleItems.isEmpty {
                        stateEmpty()
                    } else {
                        VStack(spacing: PluckTheme.Spacing.sm) {
                            ForEach(visibleItems) { item in
                                discoverCard(for: item)
                            }

                            if let _ = continuationToken {
                                if loadingMore {
                                    HStack {
                                        Spacer()
                                        ProgressView("Loading more")
                                            .foregroundStyle(PluckTheme.secondaryText)
                                        Spacer()
                                    }
                                    .padding(.vertical, PluckTheme.Spacing.md)
                                } else {
                                    Button("Load more") {
                                        Task { await loadFeed(refresh: false) }
                                    }
                                    .buttonStyle(.bordered)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .foregroundStyle(PluckTheme.info)
                                    .padding(.vertical, PluckTheme.Spacing.md)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, PluckTheme.Spacing.md)
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(sourceLabel) {
                        Task { await loadSources() }
                    }
                    .font(.caption2)
                }
            }
            .task {
                await loadSources()
                restartFeedLoad()
            }
            .refreshable {
                feedLoadTask?.cancel()
                loading = false
                await loadFeed(refresh: true)
            }
            .shellToolbar()
        }
    }

    private var controlsHeader: some View {
        VStack(spacing: PluckTheme.Spacing.sm) {
            HStack(spacing: PluckTheme.Spacing.sm) {
                HStack(spacing: PluckTheme.Spacing.xs) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(PluckTheme.secondaryText)
                    TextField("Search styles, brands, tags", text: $searchText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .onSubmit {
                            restartFeedLoad()
                        }
                }
                .padding(10)
                .background(PluckTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))

                Menu {
                    ForEach(DiscoverSortMode.allCases, id: \.self) { mode in
                        Button(mode.rawValue) {
                            sortMode = mode
                            restartFeedLoad()
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.subheadline)
                        .foregroundStyle(PluckTheme.primaryText)
                        .frame(width: PluckTheme.Control.rowHeight, height: PluckTheme.Control.rowHeight)
                        .background(PluckTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
                }
            }

            if !sources.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PluckTheme.Spacing.sm) {
                        sourceChip(label: "All", active: activeSourceId == nil) {
                            activeSourceId = nil
                            restartFeedLoad()
                        }

                        ForEach(sources) { source in
                            sourceChip(label: source.name, active: activeSourceId == source.id) {
                                activeSourceId = source.id
                                restartFeedLoad()
                            }
                        }
                    }
                    .padding(.vertical, PluckTheme.Spacing.xs)
                }
            }

            if activeSourceId != nil || timeRange != .all || !normalizedSearch.isEmpty {
                HStack {
                    Label("Filters", systemImage: "line.3.horizontal.decrease")
                        .font(.caption)
                        .foregroundStyle(PluckTheme.secondaryText)

                    Text("Active")
                        .font(.caption2)
                        .foregroundStyle(PluckTheme.secondaryText)

                    Spacer()

                    Button("Clear") {
                        activeSourceId = nil
                        timeRange = .all
                        searchText = ""
                        restartFeedLoad()
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(PluckTheme.info)
                }
            }

            HStack(spacing: PluckTheme.Spacing.xs) {
                Text("Range")
                    .font(.caption)
                    .foregroundStyle(PluckTheme.secondaryText)

                ForEach(DiscoverTimeRange.allCases, id: \.self) { option in
                    Button(option.label) {
                        timeRange = option
                        restartFeedLoad()
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(timeRange == option ? PluckTheme.info : PluckTheme.secondaryText)
                    .padding(.horizontal, PluckTheme.Spacing.xs)
                    .padding(.vertical, 6)
                    .background(timeRange == option ? PluckTheme.card : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
                }
            }
            .padding(.horizontal, PluckTheme.Spacing.xxs)
        }
        .padding(.vertical, PluckTheme.Spacing.sm)
    }

    @ViewBuilder
    private func discoverCard(for item: ScrapedItem) -> some View {
        VStack(alignment: .leading, spacing: PluckTheme.Spacing.sm) {
            if let imageURL = normalizedImageURL(item.imageUrl) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(PluckTheme.card)
                            .overlay {
                                ProgressView()
                                    .tint(PluckTheme.primaryText)
                            }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Rectangle()
                            .fill(PluckTheme.card)
                            .overlay {
                                VStack(spacing: PluckTheme.Spacing.xs) {
                                    Image(systemName: "photo")
                                    Text("No image")
                                        .font(.caption2)
                                }
                                .foregroundStyle(PluckTheme.secondaryText)
                            }
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(height: 186)
                .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
            } else {
                Rectangle()
                    .fill(PluckTheme.card)
                    .frame(height: 186)
                    .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
                    .overlay {
                        VStack(spacing: PluckTheme.Spacing.xs) {
                            Image(systemName: "photo")
                            Text("No image")
                                .font(.caption2)
                        }
                        .foregroundStyle(PluckTheme.secondaryText)
                    }
            }

            Text(item.title ?? "Untitled")
                .font(.headline)
                .foregroundStyle(PluckTheme.primaryText)
                .lineLimit(2)

            Text(item.resolvedSourceName(from: sources))
                .font(.caption)
                .foregroundStyle(PluckTheme.secondaryText)

            if let brand = item.brand, !brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(brand)
                    .font(.caption2)
                    .foregroundStyle(PluckTheme.mutedText)
            }

            HStack {
                if let tags = item.tags, !tags.isEmpty {
                    Text(tags.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(PluckTheme.mutedText)
                        .lineLimit(1)
                }

                Spacer()

                Text(item.displayPriceText ?? item.priceText ?? "—")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PluckTheme.info)
            }

            if let message = activeTimeRangeNotice {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(PluckTheme.secondaryText)
            }
        }
        .padding(PluckTheme.Spacing.md)
        .background(PluckTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
    }

    private func sourceChip(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(active ? .semibold : .regular)
                .foregroundStyle(active ? PluckTheme.background : PluckTheme.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(active ? PluckTheme.accent : PluckTheme.card)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func stateLoading() -> some View {
        VStack(spacing: PluckTheme.Spacing.md) {
            ProgressView("Loading discover")
                .foregroundStyle(PluckTheme.secondaryText)

            HStack(spacing: PluckTheme.Spacing.sm) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: PluckTheme.Radius.small)
                        .fill(PluckTheme.card)
                        .frame(height: 186)
                        .overlay(ProgressView().tint(PluckTheme.primaryText))
                }
            }
            .padding(.horizontal, PluckTheme.Spacing.xs)
        }
        .padding(.top, PluckTheme.Spacing.md)
    }

    @ViewBuilder
    private func stateEmpty() -> some View {
        VStack(spacing: PluckTheme.Spacing.sm) {
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(PluckTheme.mutedText)
            Text("No items found")
                .foregroundStyle(PluckTheme.primaryText)
                .font(.headline)

            if !sources.isEmpty, activeSourceId != nil {
                Text("Try a different source or clear filters.")
                    .foregroundStyle(PluckTheme.secondaryText)
                    .font(.caption)
            } else if !normalizedSearch.isEmpty {
                Text("Try a different search term.")
                    .foregroundStyle(PluckTheme.secondaryText)
                    .font(.caption)
            } else {
                Text("Try refreshing the feed.")
                    .foregroundStyle(PluckTheme.secondaryText)
                    .font(.caption)
            }
        }
        .padding(.top, PluckTheme.Spacing.lg)
        .padding(.bottom, PluckTheme.Spacing.xl)
        .frame(maxWidth: .infinity)
    }

    private func loadSources() async {
        do {
            sources = try await appServices.discoverService.fetchSources()
        } catch {
            sources = []
        }
    }

    private func restartFeedLoad() {
        feedLoadTask?.cancel()
        loading = false
        feedLoadTask = Task { await loadFeed(refresh: true) }
    }

    private func loadFeed(refresh: Bool = true) async {
        guard !loading else { return }

        if refresh {
            continuationToken = nil
            errorText = nil
            feedItems = []
        }

        loading = true
        loadingMore = !refresh

        var request = DiscoverFeedQuery()
        request.pageSize = 24
        request.sortBy = sortMode.apiValue
        request.timeRange = timeRange.apiValue
        if !normalizedSearch.isEmpty {
            request.query = normalizedSearch
        }
        request.sourceIds = activeSourceId.flatMap { sourceId in
            let trimmed = sourceId.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : [trimmed]
        }
        if !refresh, let continuationToken {
            request.continuationToken = continuationToken
        }

        do {
            let response = try await appServices.discoverService.fetchFeed(request)
            if refresh {
                feedItems = response.items
            } else {
                feedItems += response.items
            }
            continuationToken = response.nextContinuationToken
            errorText = nil
        } catch {
            if !isCancelledError(error) {
                errorText = String(describing: error)
                if refresh {
                    continuationToken = nil
                }
            }
        }

        loadingMore = false
        loading = false
    }

    private func isCancelledError(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError { return urlError.code == .cancelled }
        return false
    }
}

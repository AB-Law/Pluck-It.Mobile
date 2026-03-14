import SwiftUI
import Combine
import UniformTypeIdentifiers
import AppKit

/// Shared desktop card container used by authenticated feature screens.
private struct MacFeatureScreen<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MacWindowChrome(
                title: "PLUCK_IT_ARENA"
            ) {
                HStack(spacing: 10) {
                    MacStatusChip(label: "Online", tone: .success)
                    MacStatusChip(label: "SYNCED", tone: .info)
                }
            }

            HStack(spacing: PluckTheme.Spacing.sm) {
                Text(title)
                    .font(PluckTheme.Typography.terminalHeadline)
                    .foregroundStyle(PluckTheme.primaryText)
                Spacer()
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(PluckTheme.secondaryText)
            }
            .padding(.horizontal, PluckTheme.Spacing.md)
            .padding(.top, PluckTheme.Spacing.md)
            .padding(.bottom, PluckTheme.Spacing.xs)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(PluckTheme.Spacing.md)
        }
    }
}

private struct MacFeatureCard: View {
    let title: String
    let content: AnyView

    init(_ title: String, @ViewBuilder content: () -> some View) {
        self.title = title
        self.content = AnyView(content())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PluckTheme.Spacing.sm) {
            Text(title.uppercased())
                .font(PluckTheme.Typography.terminalLabel)
                .foregroundStyle(PluckTheme.terminalMuter)
            Divider()
                .background(PluckTheme.terminalBorder)
            content
        }
        .padding(PluckTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: PluckTheme.Radius.medium)
                .fill(PluckTheme.terminalPanelSubtle.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: PluckTheme.Radius.medium)
                        .stroke(PluckTheme.terminalBorder, lineWidth: 1)
                )
        )
    }
}

// MARK: - Wardrobe

struct MacWardrobeView: View {
    @EnvironmentObject private var appServices: AppServices
    @State private var items: [ClothingItem] = []
    @State private var selectedItemID: String?
    @State private var searchText = ""
    @State private var categoryFilter = "All"
    @State private var sortMode = "Newest"
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var showingImporter = false
    @State private var uploadQueue: [UploadQueueItem] = []
    @State private var drafts: [WardrobeUploadDraft] = []
    @State private var isUploadSheetPresented = false
    @State private var isDropTargeted = false
    @State private var includeWishlistedOnly = false
    @State private var draftStateFilter = "All"

    private let sortOptions: [(String, String?, String?)] = [
        ("Newest", "dateAdded", "desc"),
        ("Oldest", "dateAdded", "asc"),
        ("Most worn", "wearCount", "desc"),
        ("Least worn", "wearCount", "asc")
    ]

    private var selectedItem: ClothingItem? {
        items.first(where: { $0.id == selectedItemID })
    }

    private var categories: [String] {
        let names = items.compactMap { $0.category?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return ["All"] + Array(Set(names)).sorted()
    }

    private var filteredItems: [ClothingItem] {
        items.filter { item in
            let matchesCategory = categoryFilter == "All" || item.category == categoryFilter
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let matchesQuery = query.isEmpty ? true : item.searchableText().contains(query)
            let matchesWishlisted = includeWishlistedOnly ? item.isWishlisted : true
            return matchesCategory && matchesQuery && matchesWishlisted
        }
    }

    var body: some View {
        MacFeatureScreen(title: "Wardrobe", subtitle: "Upload, inspect, and queue your fashion archive.") {
            VStack(spacing: PluckTheme.Spacing.md) {
                MacFeatureCard("Wardrobe controls") {
                    HStack(spacing: PluckTheme.Spacing.md) {
                        TextField("Search wardrobe", text: $searchText)
                            .textFieldStyle(.roundedBorder)

                        Picker("Sort", selection: $sortMode) {
                            ForEach(sortOptions.map(\.0), id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 140)

                        Picker("Category", selection: $categoryFilter) {
                            ForEach(categories, id: \.self) { category in
                                Text(category).tag(category)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 160)

                        Toggle("Watchlist Only", isOn: $includeWishlistedOnly)
                            .toggleStyle(.switch)
                            .frame(width: 155)

                        Button {
                            Task { await loadItems() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            showingImporter = true
                        } label: {
                            Label("Upload", systemImage: "tray.and.arrow.up")
                                .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(PluckTheme.accent)
                        .foregroundStyle(.black)
                    }
                }

                if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(PluckTheme.danger)
                }

                HStack(alignment: .top, spacing: PluckTheme.Spacing.md) {
                    VStack(spacing: PluckTheme.Spacing.sm) {
                        MacFeatureCard("Extraction Hub") {
                            VStack(spacing: PluckTheme.Spacing.sm) {
                                HStack {
                                    Text("Upload queue")
                                        .font(.caption)
                                        .foregroundStyle(PluckTheme.secondaryText)
                                    Spacer()
                                    Text("Queued \(uploadQueue.count)")
                                        .font(.caption2)
                                        .foregroundStyle(PluckTheme.terminalMuter)
                                }

                                ForEach(uploadQueue) { item in
                                    HStack {
                                        Text(item.id.uuidString.prefix(7))
                                            .font(.caption)
                                            .foregroundStyle(PluckTheme.secondaryText)
                                        Spacer()
                                        stateBadge(for: item.state)
                                    }
                                }
                                if uploadQueue.isEmpty {
                                    Text("No active upload jobs.")
                                        .font(.caption)
                                        .foregroundStyle(PluckTheme.terminalMuter)
                                }

                                Divider()

                                Button("Review Drafts / Queue") {
                                    isUploadSheetPresented = true
                                }
                                .buttonStyle(.bordered)
                                .tint(PluckTheme.accent)

                                ScrollView {
                                    if isLoading {
                                        ProgressView("Loading wardrobe")
                                            .padding(.horizontal, PluckTheme.Spacing.sm)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    } else if filteredItems.isEmpty {
                                        ContentUnavailableView(
                                            "No wardrobe items",
                                            systemImage: "tshirt"
                                        )
                                    } else {
                                        LazyVStack(spacing: PluckTheme.Spacing.xs) {
                                            ForEach(filteredItems) { item in
                                                WardrobeGridCard(
                                                    item: item,
                                                    isSelected: item.id == selectedItemID
                                                )
                                                .contentShape(Rectangle())
                                                .onTapGesture {
                                                    selectedItemID = item.id
                                                }
                                            }
                                        }
                                    }
                                }
                                .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
                                    handleDrop(providers: providers)
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: PluckTheme.Radius.medium)
                                        .stroke(
                                            isDropTargeted ? PluckTheme.accent : .clear,
                                            style: .init(lineWidth: 2, dash: [8])
                                        )
                                )
                                .frame(minWidth: 340, maxWidth: 520)
                                .frame(maxHeight: .infinity)
                            }
                        }
                    }

                    MacWardrobeItemPanel(
                        item: selectedItem,
                        onDelete: { item in
                            Task { await delete(item) }
                        },
                        onLogWear: { item in
                            Task { await logWear(item) }
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await loadItems()
            await loadDrafts()
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            guard case let .success(urls) = result else { return }
            Task { await enqueueUploads(urls: urls) }
        }
        .sheet(isPresented: $isUploadSheetPresented) {
            MacUploadQueueSheet(
                queue: uploadQueue,
                drafts: drafts,
                onRefreshDrafts: { await loadDrafts() },
                onAcceptDraft: { draft in
                    try await appServices.wardrobeService.acceptDraft(draft.id)
                },
                onRejectDraft: { draft in
                    try await appServices.wardrobeService.rejectDraft(draft.id)
                },
                onRetryDraft: { draft in
                    try await appServices.wardrobeService.retryDraft(draft.id)
                }
            )
        }
        .onChange(of: searchText) { _, _ in
            Task { await loadItems() }
        }
        .onChange(of: categoryFilter) { _, _ in
            Task { await loadItems() }
        }
        .onChange(of: sortMode) { _, _ in
            Task { await loadItems() }
        }
        .onChange(of: includeWishlistedOnly) { _, _ in
            Task { await loadItems() }
        }
    }

    private func stateBadge(for state: UploadState) -> some View {
        let text: String
        let tone: MacStatusChip.ChipTone
        switch state {
        case .queued:
            text = "Queued"
            tone = .muted
        case .uploading:
            text = "Uploading"
            tone = .info
        case .processing:
            text = "Processing"
            tone = .warning
        case .ready:
            text = "Ready"
            tone = .success
        case let .failed(reason):
            text = "Failed"
            return MacStatusChip(label: "\(text): \(reason ?? "error")", tone: .warning)
        }
        return MacStatusChip(label: text, tone: tone)
    }

    private func loadItems() async {
        guard let config = sortOptions.first(where: { $0.0 == sortMode }) else { return }

        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            let response = try await appServices.wardrobeService.fetchItems(
                sortField: config.1,
                sortDir: config.2,
                includeWishlisted: includeWishlistedOnly ? true : nil,
                query: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : searchText
            )
            items = response.items
            if selectedItemID == nil {
                selectedItemID = items.first?.id
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func loadDrafts() async {
        do {
            drafts = try await appServices.wardrobeService.fetchDrafts()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func enqueueUploads(urls: [URL]) async {
        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            let queueItem = UploadQueueItem(imageData: data)
            uploadQueue.append(queueItem)
            do {
                _ = try await appServices.wardrobeService.uploadForDraft(imageData: data)
            } catch {
                if let index = uploadQueue.firstIndex(where: { $0.id == queueItem.id }) {
                    uploadQueue[index].state = .failed(error.localizedDescription)
                }
            }
        }
        await loadItems()
        await loadDrafts()
        isUploadSheetPresented = true
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { await enqueueUploads(urls: [url]) }
            }
        }
        return !providers.isEmpty
    }

    private func delete(_ item: ClothingItem) async {
        do {
            try await appServices.wardrobeService.delete(item.id)
            await loadItems()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func logWear(_ item: ClothingItem) async {
        do {
            try await appServices.wardrobeService.logWear(item.id)
            await loadItems()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct WardrobeGridCard: View {
    let item: ClothingItem
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .center, spacing: PluckTheme.Spacing.sm) {
            CachedAsyncImage(url: normalizedImageURL(item.imageUrl)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable()
                        .scaledToFill()
                default:
                    ZStack {
                        Rectangle()
                            .fill(PluckTheme.card)
                        Image(systemName: "photo")
                            .foregroundStyle(PluckTheme.terminalMuter)
                    }
                }
            }
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.xSmall))

            VStack(alignment: .leading, spacing: 2) {
                Text(fallbackText(item.brand))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PluckTheme.primaryText)
                Text(fallbackText(item.category))
                    .font(.caption)
                    .foregroundStyle(PluckTheme.secondaryText)
                Text(item.draftStatus ?? "saved")
                    .font(.caption2)
                    .foregroundStyle(PluckTheme.terminalInfo)
            }

            Spacer()
            if let wearCount = item.wearCount {
                Text("\(wearCount) wears")
                    .font(.caption2)
                    .foregroundStyle(PluckTheme.secondaryText)
            }
        }
        .padding(PluckTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: PluckTheme.Radius.medium)
                .fill(isSelected ? PluckTheme.accent.opacity(0.16) : PluckTheme.terminalPanelSubtle.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: PluckTheme.Radius.medium)
                        .stroke(
                            isSelected ? PluckTheme.accent : PluckTheme.terminalBorder,
                            lineWidth: isSelected ? 1.4 : 1
                        )
                )
        )
        .overlay(alignment: .topLeading) {
            if isSelected {
                RoundedRectangle(cornerRadius: PluckTheme.Radius.medium)
                    .stroke(PluckTheme.accent.opacity(0.6), lineWidth: 1)
            }
        }
    }
}

private struct MacWardrobeItemPanel: View {
    let item: ClothingItem?
    let onDelete: (ClothingItem) -> Void
    let onLogWear: (ClothingItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PluckTheme.Spacing.md) {
            if let item {
                VStack(alignment: .leading, spacing: PluckTheme.Spacing.md) {
                    CachedAsyncImage(url: normalizedImageURL(item.imageUrl)) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable()
                                .scaledToFit()
                        default:
                            RoundedRectangle(cornerRadius: 18)
                                .fill(PluckTheme.card)
                                .overlay(
                                    Image(systemName: "photo")
                                        .foregroundStyle(PluckTheme.terminalMuter)
                                )
                                .frame(height: 240)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .background(PluckTheme.card.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fallbackText(item.brand).isEmpty ? "Unknown brand" : fallbackText(item.brand))
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(PluckTheme.primaryText)
                                .lineLimit(1)
                            if let category = item.category, !category.isEmpty {
                                Text(category)
                                    .font(.subheadline)
                                    .foregroundStyle(PluckTheme.secondaryText)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        MacStatusChip(label: item.draftStatus ?? "Saved", tone: .info)
                    }

                    Divider()

                    HStack {
                        detailPill("Wear count", String(item.wearCount ?? 0))
                        detailPill("Condition", fallbackText(item.condition))
                        detailPill("Color", fallbackText(item.colours?.first?.name ?? item.colours?.first?.hex))
                    }

                    Text("Notes")
                        .font(.caption)
                        .foregroundStyle(PluckTheme.secondaryText)
                    Text(fallbackText(item.notes))
                        .font(.body)
                        .foregroundStyle(PluckTheme.primaryText)

                    HStack {
                        Button("Log wear") {
                            onLogWear(item)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Delete", role: .destructive) {
                            onDelete(item)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(PluckTheme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(PluckTheme.terminalPanel.opacity(0.5))
                )
            } else {
                ContentUnavailableView("Select an item", systemImage: "square.grid.2x2")
                    .padding(PluckTheme.Spacing.md)
            }
        }
        .padding(PluckTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: PluckTheme.Radius.large)
                .fill(PluckTheme.card.opacity(0.5))
        )
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2)
                .foregroundStyle(PluckTheme.secondaryText)
            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(PluckTheme.primaryText)
                .lineLimit(2)
        }
    }

    private func detailPill(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.caption2)
                .foregroundStyle(PluckTheme.secondaryText)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PluckTheme.primaryText)
                .lineLimit(1)
        }
        .padding(PluckTheme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(PluckTheme.terminalPanelSubtle.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(PluckTheme.terminalBorder, lineWidth: 1)
                )
        )
    }
}

private struct MacUploadQueueSheet: View {
    let queue: [UploadQueueItem]
    let drafts: [WardrobeUploadDraft]
    let onRefreshDrafts: () async -> Void
    let onAcceptDraft: (WardrobeUploadDraft) async throws -> Void
    let onRejectDraft: (WardrobeUploadDraft) async throws -> Void
    let onRetryDraft: (WardrobeUploadDraft) async throws -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !queue.isEmpty {
                    Section("Recent uploads") {
                        ForEach(queue) { item in
                            Text(item.id.uuidString)
                                .font(.caption.monospaced())
                        }
                    }
                }

                Section("Backend drafts") {
                    ForEach(drafts) { draft in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(draft.item?.brand ?? draft.item?.category ?? draft.id)
                                .foregroundStyle(PluckTheme.primaryText)
                            Text(draft.status)
                                .font(.caption)
                                .foregroundStyle(PluckTheme.secondaryText)

                            HStack {
                                Button("Accept") {
                                    Task {
                                        try? await onAcceptDraft(draft)
                                        await onRefreshDrafts()
                                    }
                                }
                                Button("Reject", role: .destructive) {
                                    Task {
                                        try? await onRejectDraft(draft)
                                        await onRefreshDrafts()
                                    }
                                }
                                Button("Retry") {
                                    Task {
                                        try? await onRetryDraft(draft)
                                        await onRefreshDrafts()
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .navigationTitle("Upload Queue")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .automatic) {
                    Button("Refresh") {
                        Task { await onRefreshDrafts() }
                    }
                }
            }
            .frame(minWidth: 780, minHeight: 480)
        }
    }
}

// MARK: - Vault

struct MacVaultView: View {
    @EnvironmentObject private var appServices: AppServices
    @State private var insights: VaultInsightsResponse?
    @State private var wardrobeItems: [ClothingItem] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var selectedItemId: String?
    @State private var windowDays = 90
    @State private var targetCpw = 120

    private var selectedIntel: CpwIntelItem? {
        insights?.cpwIntel?.first(where: { $0.itemId == selectedItemId })
    }

    private var cpwItems: [CpwIntelItem] {
        insights?.cpwIntel ?? []
    }

    private var wardrobeMap: [String: ClothingItem] {
        Dictionary(uniqueKeysWithValues: wardrobeItems.compactMap { item in
            item.id.isEmpty ? nil : (item.id, item)
        })
    }

    var body: some View {
        MacFeatureScreen(title: "Vault", subtitle: "Analytics, cost-per-wear, and decision signals.") {
            VStack(alignment: .leading, spacing: PluckTheme.Spacing.md) {
                // Filter bar
                HStack(spacing: PluckTheme.Spacing.md) {
                    Label("Window: \(windowDays)d", systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(PluckTheme.secondaryText)
                    Stepper("", value: $windowDays, in: 7...365, step: 7)
                        .labelsHidden()
                        .frame(width: 60)

                    Divider().frame(height: 20)

                    Label("Target CPW: \(targetCpw)", systemImage: "target")
                        .font(.caption)
                        .foregroundStyle(PluckTheme.secondaryText)
                    Stepper("", value: $targetCpw, in: 20...300, step: 10)
                        .labelsHidden()
                        .frame(width: 60)

                    Spacer()

                    if let errorText {
                        Text(errorText)
                            .font(.caption2)
                            .foregroundStyle(PluckTheme.danger)
                            .lineLimit(1)
                    }

                    Button {
                        Task { await loadAll() }
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PluckTheme.accent)
                    .foregroundStyle(.black)
                }
                .padding(.horizontal, PluckTheme.Spacing.sm)
                .padding(.vertical, PluckTheme.Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: PluckTheme.Radius.medium)
                        .fill(PluckTheme.terminalPanelSubtle.opacity(0.6))
                        .overlay(
                            RoundedRectangle(cornerRadius: PluckTheme.Radius.medium)
                                .stroke(PluckTheme.terminalBorder, lineWidth: 1)
                        )
                )

                if isLoading {
                    ProgressView("Loading vault insights")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let insights {
                    // Stat cards row
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
                        MacStatCard(
                            title: "Top color",
                            value: insights.behavioralInsights?.topColorWearShare?.color ?? "Unavailable",
                            tone: PluckTheme.terminalInfo,
                            delay: 0.05
                        )
                        MacStatCard(
                            title: "Unworn 90d",
                            value: percentage(insights.behavioralInsights?.unworn90dPct ?? 0),
                            tone: PluckTheme.terminalSuccess,
                            delay: 0.10
                        )
                        MacStatCard(
                            title: "CPW alerts",
                            value: "\(cpwItems.count)",
                            tone: PluckTheme.accent,
                            delay: 0.15
                        )
                        MacStatCard(
                            title: "Most Expensive Unworn",
                            value: currencyValue(
                                insights.behavioralInsights?.mostExpensiveUnworn?.amount,
                                currency: insights.behavioralInsights?.mostExpensiveUnworn?.currency
                            ),
                            tone: PluckTheme.terminalWarning,
                            delay: 0.18
                        )
                    }

                    // CPW item grid
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
                            ForEach(cpwItems, id: \.itemId) { item in
                                CpwInsightCard(
                                    item: item,
                                    clothingItem: wardrobeMap[item.itemId ?? ""],
                                    isSelected: item.itemId == selectedItemId
                                ) {
                                    selectedItemId = item.itemId
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("No vault insights", systemImage: "chart.bar.xaxis")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task { await loadAll() }
    }

    private func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        do {
            insights = try await appServices.vaultInsightsService.fetchInsights(windowDays: windowDays, targetCpw: targetCpw)
        } catch {
            errorText = error.localizedDescription
        }
        // Wardrobe items are used only for images; failure is non-critical
        if let result = try? await appServices.wardrobeService.fetchItems(sortField: nil, sortDir: nil, includeWishlisted: nil, query: nil) {
            wardrobeItems = result.items
        }
    }

    private func percentage(_ value: Double) -> String {
        String(format: "%.0f%%", max(0, min(100, value)) * 100)
    }

    private func currencyValue(_ value: Double?, currency: String?) -> String {
        guard let value else { return "Unavailable" }
        return "\(currency ?? "USD") \(String(format: "%.2f", value))"
    }
}

private struct CpwInsightCard: View {
    let item: CpwIntelItem
    let clothingItem: ClothingItem?
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: PluckTheme.Spacing.sm) {
                // Thumbnail
                CachedAsyncImage(url: normalizedImageURL(clothingItem?.imageUrl)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                            .scaledToFill()
                    default:
                        Rectangle()
                            .fill(PluckTheme.card)
                            .overlay(
                                Image(systemName: "tshirt")
                                    .foregroundStyle(PluckTheme.terminalMuter)
                            )
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(clothingItem?.brand ?? fallbackText(item.itemId))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(PluckTheme.primaryText)
                                .lineLimit(1)
                            if let category = clothingItem?.category {
                                Text(category)
                                    .font(.caption2)
                                    .foregroundStyle(PluckTheme.secondaryText)
                            }
                        }
                        Spacer()
                        if item.breakEvenReached == true {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundStyle(PluckTheme.terminalSuccess)
                        }
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.2f", item.cpw ?? 0))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(PluckTheme.primaryText)
                        Text("CPW")
                            .font(.caption2)
                            .foregroundStyle(PluckTheme.terminalMuter)
                        if let badge = item.badge {
                            Spacer()
                            Text(badge)
                                .font(.caption2)
                                .foregroundStyle(PluckTheme.accent)
                        }
                    }
                }
            }
            .padding(PluckTheme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: PluckTheme.Radius.medium)
                    .fill(isSelected ? PluckTheme.accent.opacity(0.2) : PluckTheme.card.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: PluckTheme.Radius.medium)
                            .stroke(isSelected ? PluckTheme.accent : PluckTheme.terminalBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Collections

struct MacCollectionsView: View {
    @EnvironmentObject private var appServices: AppServices
    @State private var collections: [Collection] = []
    @State private var selectedCollectionID: String?
    @State private var newName = ""
    @State private var newDescription = ""
    @State private var isPublic = false
    @State private var errorText: String?
    @State private var query = ""
    @State private var selectedCopyText = "Copied"

    private var selectedCollection: Collection? {
        collections.first(where: { $0.id == selectedCollectionID })
    }

    var body: some View {
        MacFeatureScreen(title: "Collections", subtitle: "Build, review, and manage wardrobe collections.") {
            HStack(spacing: PluckTheme.Spacing.md) {
                MacFeatureCard("Collections explorer") {
                    VStack(alignment: .leading, spacing: PluckTheme.Spacing.sm) {
                        TextField("Search collections", text: $query)
                            .textFieldStyle(.roundedBorder)

                        List(collections, selection: $selectedCollectionID) { collection in
                            MacCollectionRow(collection: collection, isSelected: collection.id == selectedCollectionID)
                                .tag(collection.id)
                        }
                        .overlay {
                            if collections.isEmpty {
                                ContentUnavailableView("No collections", systemImage: "folder")
                            }
                        }

                        VStack(alignment: .leading, spacing: PluckTheme.Spacing.sm) {
                            Text("Create collection")
                                .font(.caption)
                                .foregroundStyle(PluckTheme.secondaryText)

                            TextField("Collection name", text: $newName)
                                .textFieldStyle(.roundedBorder)
                            TextField("Description", text: $newDescription)
                                .textFieldStyle(.roundedBorder)
                            Toggle("Public", isOn: $isPublic)
                            HStack {
                                Button("Create") {
                                    Task { await createCollection() }
                                }
                                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                Button("Refresh") {
                                    Task { await loadCollections() }
                                }
                            }
                        }
                        .padding(.top, PluckTheme.Spacing.xs)
                    }
                }
                .frame(minWidth: 320, maxWidth: 360)

                VStack(spacing: PluckTheme.Spacing.sm) {
                    if let errorText {
                        Text(errorText)
                            .foregroundStyle(PluckTheme.danger)
                    }

                    if let selectedCollection {
                        MacFeatureCard(selectedCollection.name) {
                            VStack(alignment: .leading, spacing: PluckTheme.Spacing.md) {
                                Text(selectedCollection.description ?? "No description")
                                    .foregroundStyle(PluckTheme.secondaryText)

                                HStack(spacing: PluckTheme.Spacing.md) {
                                    VStack(alignment: .leading) {
                                        Text(selectedCollection.isPublic ? "Public" : "Private")
                                            .font(.caption)
                                            .foregroundStyle(selectedCollection.isPublic ? PluckTheme.terminalInfo : PluckTheme.terminalMuter)
                                        Text("Members: \((selectedCollection.memberUserIds?.count ?? 0))")
                                            .font(.caption2)
                                            .foregroundStyle(PluckTheme.secondaryText)
                                    }
                                    Divider()
                                        .frame(height: 30)
                                    VStack(alignment: .leading) {
                                        Text("Items")
                                            .font(.caption)
                                            .foregroundStyle(PluckTheme.secondaryText)
                                        Text("\(selectedCollection.clothingItemIds?.count ?? selectedCollection.itemIds?.count ?? 0)")
                                            .font(.title3.weight(.semibold))
                                            .foregroundStyle(PluckTheme.primaryText)
                                    }
                                }

                                HStack {
                                    Button("Copy Link") {
                                        copyCollectionLink()
                                    }
                                    Button("Delete", role: .destructive) {
                                        Task {
                                            if let collectionID = selectedCollectionID,
                                               let selectedCollection = collections.first(where: { $0.id == collectionID }) {
                                                await deleteCollection(selectedCollection)
                                            }
                                        }
                                    }
                                }
                                .buttonStyle(.bordered)

                                if let ids = selectedCollection.clothingItemIds, !ids.isEmpty {
                                    VStack(alignment: .leading, spacing: PluckTheme.Spacing.sm) {
                                        Text("Item IDs")
                                            .font(.caption)
                                            .foregroundStyle(PluckTheme.secondaryText)
                                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)]) {
                                            ForEach(ids, id: \.self) { itemId in
                                                Text(itemId)
                                                    .font(.caption2)
                                                    .foregroundStyle(PluckTheme.primaryText)
                                                    .padding(8)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 8)
                                                            .fill(PluckTheme.card)
                                                    )
                                            }
                                        }
                                    }
                                }

                                Text(selectedCopyText)
                                    .font(.caption2)
                                    .foregroundStyle(selectedCopyText == "Copied" ? PluckTheme.success : PluckTheme.secondaryText)
                            }
                        }
                    } else {
                        ContentUnavailableView("Select a collection", systemImage: "square.grid.2x2")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .task { await loadCollections() }
        .onChange(of: query) { _, _ in
            Task { await loadCollections(query: query) }
        }
        .onAppear {
            selectedCopyText = "Copy status"
        }
    }

    private func loadCollections(query: String? = nil) async {
        do {
            collections = try await appServices.collectionService.fetchCollections(query: query)
            if selectedCollectionID == nil {
                selectedCollectionID = collections.first?.id
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func createCollection() async {
        do {
            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            _ = try await appServices.collectionService.createCollection(
                CreateCollectionRequest(name: trimmed, isPublic: isPublic, description: newDescription.isEmpty ? nil : newDescription)
            )
            newName = ""
            newDescription = ""
            isPublic = false
            await loadCollections()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func deleteCollection(_ collection: Collection) async {
        do {
            try await appServices.collectionService.deleteCollection(collection.id)
            await loadCollections()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func copyCollectionLink() {
        guard let selected = selectedCollection else { return }
        let link = "pluckit://collections/\(selected.id)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
        selectedCopyText = "Copied \(link)"
    }
}

private struct MacCollectionRow: View {
    let collection: Collection
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(collection.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? PluckTheme.accent : PluckTheme.primaryText)
                Text(collection.isPublic ? "Public" : "Private")
                    .font(.caption)
                    .foregroundStyle(collection.isPublic ? PluckTheme.terminalInfo : PluckTheme.terminalMuter)
            }
            Spacer()
            Text("\((collection.clothingItemIds?.count ?? collection.itemIds?.count ?? 0))")
                .font(.caption2)
                .foregroundStyle(PluckTheme.secondaryText)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Discover

struct MacDiscoverView: View {
    @EnvironmentObject private var appServices: AppServices
    @State private var items: [ScrapedItem] = []
    @State private var sources: [ScraperSource] = []
    @State private var selectedItemID: String?
    @State private var errorText: String?
    @State private var selectedSourceIDs: Set<String> = []
    @State private var sortBy = "score"
    @State private var timeRange = "all"
    @State private var query = ""
    @State private var isLoading = false

    private var sortOptions = ["score": "Top", "date": "Recent", "freshness": "Fresh"]
    private var timeOptions = ["1h", "6h", "1d", "7d", "30d", "all"]

    private var selectedItem: ScrapedItem? {
        items.first(where: { $0.id == selectedItemID })
    }

    var body: some View {
        MacFeatureScreen(title: "Discover", subtitle: "Explore global fashion feeds and signal your preferences.") {
            HStack(alignment: .top, spacing: PluckTheme.Spacing.md) {
                MacFeatureCard("Source Controls") {
                    VStack(alignment: .leading, spacing: PluckTheme.Spacing.sm) {
                        TextField("Search discover", text: $query)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { Task { await load() } }

                        Picker("Sort", selection: $sortBy) {
                            ForEach(Array(sortOptions.keys), id: \.self) { key in
                                Text(sortOptions[key] ?? key).tag(key)
                            }
                        }
                        .pickerStyle(.segmented)

                        Picker("Time Range", selection: $timeRange) {
                            ForEach(timeOptions, id: \.self) { option in
                                Text(option).tag(option)
                            }
                        }
                        .pickerStyle(.menu)

                        Divider()

                        Text("Sources")
                            .font(.caption)
                            .foregroundStyle(PluckTheme.secondaryText)

                        if sources.isEmpty {
                            Text("No sources loaded")
                                .font(.caption)
                                .foregroundStyle(PluckTheme.terminalMuter)
                        } else {
                            FlowLayout(spacing: 6) {
                                ForEach(sources) { source in
                                    let isActive = selectedSourceIDs.contains(source.id)
                                    Button {
                                        if isActive {
                                            selectedSourceIDs.remove(source.id)
                                        } else {
                                            selectedSourceIDs.insert(source.id)
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(isActive ? PluckTheme.accent : PluckTheme.terminalMuter)
                                                .frame(width: 6, height: 6)
                                            Text(source.name)
                                                .font(.caption2)
                                                .foregroundStyle(isActive ? PluckTheme.accent : PluckTheme.secondaryText)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 999)
                                                .fill(isActive ? PluckTheme.accent.opacity(0.15) : PluckTheme.terminalPanelSubtle.opacity(0.5))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 999)
                                                        .stroke(isActive ? PluckTheme.accent.opacity(0.6) : PluckTheme.terminalBorder, lineWidth: 1)
                                                )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Button("Reload feed") {
                            Task { await load() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(PluckTheme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(width: 280)

                VStack(spacing: PluckTheme.Spacing.md) {
                    if let errorText {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(PluckTheme.danger)
                    }

                    ScrollView {
                        if isLoading {
                            ProgressView("Loading discover feed")
                                .padding()
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                                ForEach(items) { item in
                                    MacDiscoverCard(
                                        item: item,
                                        isSelected: item.id == selectedItemID,
                                        availableSources: sources
                                    ) {
                                        selectedItemID = item.id
                                    }
                                }
                            }
                        }
                    }

                    if let selectedItem {
                        MacFeatureCard("Selected item") {
                            VStack(alignment: .leading, spacing: PluckTheme.Spacing.sm) {
                                Text(fallbackText(selectedItem.title))
                                    .font(.headline)
                                Text(fallbackText(selectedItem.brand))
                                    .foregroundStyle(PluckTheme.secondaryText)
                                Text(selectedItem.resolvedSourceName(from: sources))
                                    .font(.caption)
                                    .foregroundStyle(PluckTheme.terminalInfo)
                                Text(selectedItem.displayPriceText ?? selectedItem.priceText ?? fallbackText(nil))
                                    .foregroundStyle(PluckTheme.accent)
                                Text(selectedItem.commentText ?? "")
                                    .font(.caption2)
                                    .foregroundStyle(PluckTheme.secondaryText)

                                HStack {
                                    if let urlString = selectedItem.productUrl ?? selectedItem.detailUrl,
                                       let url = URL(string: urlString) {
                                        Button("Open Link") {
                                            NSWorkspace.shared.open(url)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(PluckTheme.accent)
                                    }
                                    if let itemID = selectedItem.id.isEmpty ? nil : selectedItem.id as String? {
                                        Button("Copy ID") {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(itemID, forType: .string)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .onAppear {
            Task {
                await load()
            }
        }
        .onChange(of: selectedSourceIDs) { _, _ in
            Task { await load() }
        }
        .onChange(of: sortBy) { _, _ in
            Task { await load() }
        }
        .onChange(of: timeRange) { _, _ in
            Task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            sources = try await appServices.discoverService.fetchSources()
            let queryModel = DiscoverFeedQuery(
                pageSize: 30,
                query: query.isEmpty ? nil : query,
                sortBy: sortBy,
                sourceIds: selectedSourceIDs.isEmpty ? nil : Array(selectedSourceIDs),
                timeRange: timeRange == "all" ? nil : timeRange
            )
            let response = try await appServices.discoverService.fetchFeed(queryModel)
            items = response.items
            if selectedItemID == nil {
                selectedItemID = items.first?.id
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct MacDiscoverCard: View {
    let item: ScrapedItem
    let isSelected: Bool
    let availableSources: [ScraperSource]
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                CachedAsyncImage(url: normalizedImageURL(item.imageUrl)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                            .scaledToFill()
                    default:
                        Rectangle()
                            .fill(PluckTheme.card)
                            .overlay(Image(systemName: "photo").foregroundStyle(PluckTheme.terminalMuter))
                    }
                }
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))

                Text(fallbackText(item.title))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PluckTheme.primaryText)
                    .lineLimit(2)

                HStack {
                    Text(item.priceText ?? fallbackText(item.displayPriceText))
                        .font(.caption2)
                        .foregroundStyle(PluckTheme.accent)
                    Spacer()
                    Text(item.resolvedSourceName(from: availableSources))
                        .font(.caption2)
                        .foregroundStyle(PluckTheme.secondaryText)
                }
                if let score = item.scoreSignal {
                    Text("Signal: \(score)")
                        .font(.caption2)
                        .foregroundStyle(PluckTheme.terminalMuter)
                }
            }
            .padding(PluckTheme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: PluckTheme.Radius.medium)
                    .fill(isSelected ? PluckTheme.accent.opacity(0.25) : PluckTheme.card.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: PluckTheme.Radius.medium)
                            .stroke(isSelected ? PluckTheme.accent : PluckTheme.terminalBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Stylist

struct MacStylistView: View {
    @EnvironmentObject private var appServices: AppServices
    @State private var prompt = ""
    @State private var messages: [StylistMessageBubble] = [
        StylistMessageBubble(role: .assistant, text: "Ask the stylist for fit and combination ideas.", streaming: false)
    ]
    @State private var transcript = [StylistMessage]()
    @State private var isSending = false
    @State private var errorText: String?
    @State private var activeAssistantIndex: Int?
    @State private var streamTask: Task<Void, Error>?
    @State private var activeToolName: String?
    @State private var receivedAnyEvent = false
    @State private var pendingMessages: [String] = []
    @State private var isNetworkOnline = true
    private let quickSuggestions = [
        "Suggest a night out fit",
        "What goes with my leather jacket?",
        "Need a travel-ready outfit",
        "Fresh capsule wardrobe ideas"
    ]

    var body: some View {
        MacFeatureScreen(title: "Stylist", subtitle: "AI conversation for fit and pairing intelligence.") {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("AI STYLIST")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(PluckTheme.primaryText)
                        Text(isNetworkOnline ? "SYSTEM: ONLINE" : "SYSTEM: OFFLINE")
                            .font(.caption)
                            .foregroundStyle(isNetworkOnline ? PluckTheme.terminalSuccess : PluckTheme.danger)
                    }
                    Spacer()
                    if let errorText {
                        Text(errorText)
                            .font(.caption2)
                            .foregroundStyle(PluckTheme.danger)
                            .lineLimit(1)
                    }
                }
                .padding(PluckTheme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: PluckTheme.Radius.small)
                        .fill(PluckTheme.terminalPanelSubtle)
                        .overlay(
                            Rectangle()
                                .frame(height: 1)
                                .foregroundStyle(PluckTheme.border),
                            alignment: .bottom
                        )
                )

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: PluckTheme.Spacing.sm) {
                            ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                                if !message.isPlaceholder {
                                    StylistBubbleRow(message: message)
                                        .id(message.id)
                                        .onAppear { } 
                                }
                            }

                            if isSending, let tool = activeToolName {
                                HStack(alignment: .top, spacing: PluckTheme.Spacing.sm) {
                                    assistantMiniAvatar
                                    VStack(alignment: .leading, spacing: PluckTheme.Spacing.xs) {
                                        Text("Assistant is processing…")
                                            .font(.caption)
                                            .foregroundStyle(PluckTheme.secondaryText)
                                        HStack {
                                            ProgressView()
                                            Text(tool)
                                                .font(.caption)
                                                .foregroundStyle(PluckTheme.secondaryText)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(PluckTheme.Spacing.sm)
                                .background(
                                    RoundedRectangle(cornerRadius: PluckTheme.Radius.medium)
                                        .fill(PluckTheme.card.opacity(0.4))
                                )
                                .id("assistantThinking")
                            } else if isSending {
                                thinkingRow
                            }
                        }
                        .padding(PluckTheme.Spacing.md)
                    }
                    .onChange(of: messages.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(messages.last?.id, anchor: .bottom)
                        }
                    }
                    .onChange(of: isSending) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("assistantThinking", anchor: .bottom)
                        }
                    }
                }

                Divider()

                if !quickSuggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: PluckTheme.Spacing.sm) {
                            ForEach(quickSuggestions, id: \.self) { suggestion in
                                Button(suggestion) {
                                    sendQuickSuggestion(suggestion)
                                }
                                .buttonStyle(.bordered)
                                .disabled(isSending)
                            }
                        }
                        .padding(.horizontal, PluckTheme.Spacing.md)
                        .padding(.top, PluckTheme.Spacing.sm)
                    }
                }

                HStack(spacing: PluckTheme.Spacing.sm) {
                    TextField("Ask your stylist...", text: $prompt, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { send() }

                    Button {
                        send()
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .padding(10)
                            .background(PluckTheme.accent)
                            .foregroundStyle(.black)
                            .clipShape(Circle())
                    }
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }
                .padding(PluckTheme.Spacing.md)

                Text("AI can make mistakes. Review all outfit suggestions.")
                    .font(.caption2)
                    .foregroundStyle(PluckTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, PluckTheme.Spacing.sm)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            isNetworkOnline = appServices.networkMonitor.isOnline
        }
        .onReceive(appServices.networkMonitor.$isOnline.removeDuplicates()) { isOnline in
            isNetworkOnline = isOnline
            if isOnline { resendPendingMessages() }
        }
    }

    private var assistantMiniAvatar: some View {
        Circle()
            .fill(PluckTheme.assistantBubble)
            .frame(width: 24, height: 24)
            .overlay(
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(.white)
            )
    }

    private var thinkingRow: some View {
        HStack {
            assistantMiniAvatar
            HStack {
                TypingDot()
                TypingDot(delay: 0.15)
                TypingDot(delay: 0.25)
            }
            Spacer()
        }
        .padding(PluckTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: PluckTheme.Radius.medium)
                .fill(PluckTheme.card.opacity(0.4))
        )
        .id("assistantThinking")
    }

    private func send() {
        let messageText = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !messageText.isEmpty, !isSending else { return }
        prompt = ""
        errorText = nil
        receivedAnyEvent = false

        let userMessage = StylistMessageBubble(role: .user, text: messageText)
        messages.append(userMessage)
        transcript.append(StylistMessage(role: .user, content: messageText))

        if !appServices.networkMonitor.isOnline {
            pendingMessages.append(messageText)
            finalizeStream(with: "You're offline. Your message was queued and will send when you reconnect.")
            return
        }
        startStreaming(for: messageText, shouldRequeueOnFailure: false)
    }

    private func resendPendingMessages() {
        guard appServices.networkMonitor.isOnline else { return }
        Task { @MainActor in
            guard !isSending else { return }
            guard !pendingMessages.isEmpty else { return }
            isSending = true
            defer { isSending = false }
            while !pendingMessages.isEmpty {
                let messageText = pendingMessages.removeFirst()
                let success = await sendQueuedMessage(messageText)
                if !success { break }
            }
        }
    }

    private func sendQueuedMessage(_ messageText: String) async -> Bool {
        do {
            try await sendStreaming(message: messageText, shouldRequeueOnFailure: true)
            return true
        } catch {
            if error is CancellationError {
                return false
            }
            await MainActor.run {
                finalizeStream(with: "Stylist request failed: \(error)")
            }
            return false
        }
    }

    private func sendQuickSuggestion(_ suggestion: String) {
        guard !isSending else { return }
        prompt = suggestion
        send()
    }

    private func startStreaming(for messageText: String, shouldRequeueOnFailure: Bool) {
        streamTask?.cancel()
        streamTask = Task { @MainActor in
            do {
                try await sendStreaming(message: messageText, shouldRequeueOnFailure: shouldRequeueOnFailure)
            } catch is CancellationError {
                return
            } catch {
                finalizeStream(with: "Stylist request failed: \(error)")
            }
        }
    }

    private func sendStreaming(message: String, shouldRequeueOnFailure: Bool) async throws {
        await MainActor.run {
            isSending = true
            let assistantIndex = messages.count
            messages.append(StylistMessageBubble(role: .assistant, text: "", streaming: true))
            activeAssistantIndex = assistantIndex
            activeToolName = nil
        }

        do {
            for try await event in appServices.stylistService.streamChat(
                message: message,
                recentMessages: transcript,
                selectedItemIds: nil
            ) {
                await MainActor.run { handle(event) }
            }
            await MainActor.run { finalizeStream() }
        } catch {
            if !(error is CancellationError), shouldRequeueOnFailure {
                await MainActor.run { pendingMessages.append(message) }
            }
            throw error
        }
    }

    private func handle(_ event: StylistChatEvent) {
        receivedAnyEvent = true
        switch event {
        case let .token(content, _, _, _, _, _):
            guard let index = activeAssistantIndex, messages.indices.contains(index) else { return }
            activeToolName = nil
            if messages[index].text.isEmpty {
                messages[index].text = content
            } else {
                messages[index].text += content
            }

        case let .toolUse(name, _, _, _, _, _):
            activeToolName = name

        case let .toolResult(name, summary, _, _, _, _, _):
            activeToolName = nil
            if summary != nil {
                let index = activeAssistantIndex
                if let index, messages.indices.contains(index) {
                    messages[index].text = messages[index].text.isEmpty ? "Tool \(name): \(summary ?? "")" : messages[index].text
                }
            }

        case .done(_, _, _, _, _):
            finalizeStream()

        case let .error(content, _, _, _, _, _):
            finalizeStream(with: content)

        case let .unknown(type, _, _, _, _, _):
            finalizeStream(with: "Stylist sent unknown event: \(type)")

        case let .memoryUpdate(updated, _, _, _, _, _):
            if updated && !messages.contains(where: { $0.text == "Memory updated." }) {
                messages.append(StylistMessageBubble(role: .assistant, text: "Memory updated."))
            }
        }
    }

    private func finalizeStream(with errorTextValue: String? = nil) {
        isSending = false
        activeToolName = nil
        if let index = activeAssistantIndex, messages.indices.contains(index) {
            messages[index].streaming = false
            if let finalMessage = errorTextValue {
                if messages[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    messages[index].text = finalMessage
                } else {
                    messages[index].text += "\n\(finalMessage)"
                }
            }
            if !messages[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                transcript.append(StylistMessage(role: .assistant, content: messages[index].text))
                if transcript.count > 14 {
                    transcript = Array(transcript.suffix(14))
                }
            }
        } else if let finalText = errorTextValue {
            messages.append(StylistMessageBubble(role: .assistant, text: finalText))
            self.errorText = finalText
        }
        activeAssistantIndex = nil
        streamTask = nil
        errorText = errorTextValue
    }
}

private struct StylistMessageBubble: Identifiable {
    let id = UUID()
    let role: StylistMessageRole
    var text: String
    var streaming: Bool = false

    var isPlaceholder: Bool { text.isEmpty && role == .assistant }
}

private struct StylistBubbleRow: View {
    let message: StylistMessageBubble

    var body: some View {
        HStack(alignment: .top, spacing: PluckTheme.Spacing.sm) {
            if message.role == .assistant {
                Circle()
                    .fill(PluckTheme.assistantBubble)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.white)
                    )
                VStack(alignment: .leading, spacing: 6) {
                    bubbleText
                }
                Spacer()
            } else {
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    bubbleText
                }
                Circle()
                    .fill(PluckTheme.userBubble)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.caption2)
                            .foregroundStyle(.white)
                    )
            }
        }
    }

    private var bubbleText: some View {
        Text(message.text)
            .padding(10)
            .font(.caption)
            .foregroundStyle(PluckTheme.primaryText)
            .background(
                RoundedRectangle(cornerRadius: PluckTheme.Radius.medium)
                    .fill(message.role == .user ? PluckTheme.userBubble.opacity(0.75) : PluckTheme.card.opacity(0.85))
            )
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
            .scaleEffect(animate ? 1.2 : 0.7)
            .animation(
                .easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(delay),
                value: animate
            )
            .onAppear {
                animate = true
            }
    }
}

// MARK: - Profile

struct MacProfileView: View {
    @EnvironmentObject private var appServices: AppServices
    @State private var profile: UserProfile?
    @State private var preferences = UserPreferences.default
    @State private var editedPreferences = UserPreferences.default
    @State private var errorText: String?
    @State private var saveMessage: String?
    @State private var loading = false
    @State private var saving = false

    private var isDirty: Bool {
        !prefsEqual(preferences, editedPreferences)
    }

    private let currencies = ["USD", "EUR", "GBP", "INR", "AUD", "CAD", "JPY", "CHF", "CNY", "SEK"]
    private let sizeSystems = ["US", "EU", "UK"]

    private let aesthetics = ["streetwear", "minimalist", "preppy", "smart casual", "athleisure", "bohemian", "classic", "techwear", "y2k", "vintage"]

    var body: some View {
        MacFeatureScreen(title: "Profile", subtitle: "Identity, preferences, and style signals.") {
            ScrollView {
                VStack(spacing: PluckTheme.Spacing.md) {
                    if loading && profile == nil {
                        ProgressView("Loading profile…")
                            .frame(maxWidth: .infinity)
                    } else {
                        if let errorText {
                            Text(errorText)
                                .font(.caption)
                                .foregroundStyle(PluckTheme.danger)
                        }
                        if let saveMessage {
                            Text(saveMessage)
                                .font(.caption)
                                .foregroundStyle(PluckTheme.success)
                        }

                        if let profile {
                            identityCard(for: profile)
                        }

                        preferencesCard
                        measurementsCard
                        styleIdentityCard
                        aiPersonalizationCard

                        HStack {
                            Button("Reset Unsaved") {
                                editedPreferences = preferences
                                saveMessage = nil
                            }
                            .disabled(!isDirty)

                            Spacer()

                            Button("Save Preferences") {
                                Task { await save() }
                            }
                            .disabled(!isDirty || saving)
                            .buttonStyle(.borderedProminent)
                            .tint(PluckTheme.accent)
                        }
                    }
                }
                .padding(PluckTheme.Spacing.sm)
            }
            .task { await load() }
        }
    }

    private func identityCard(for profile: UserProfile) -> some View {
        MacFeatureCard("Active Identity") {
            VStack(alignment: .leading, spacing: PluckTheme.Spacing.sm) {
                Text("Display name: \(fallbackText(profile.displayName))")
                Text("Email: \(fallbackText(profile.email))")
                Text("User ID: \(fallbackText(profile.userId))")

                Divider()

                Button("Sign out", role: .destructive) {
                    appServices.authService.signOut()
                }
            }
            .font(.caption)
        }
    }

    private var preferencesCard: some View {
        MacFeatureCard("Preferences") {
            VStack(spacing: PluckTheme.Spacing.sm) {
                HStack {
                    Text("Currency")
                        .frame(width: 100, alignment: .leading)
                    Picker("Currency", selection: $editedPreferences.currencyCode) {
                        ForEach(currencies, id: \.self) { currency in
                            Text(currency).tag(currency)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)
                }

                HStack {
                    Text("Size system")
                        .frame(width: 100, alignment: .leading)
                    Picker("Size system", selection: $editedPreferences.preferredSizeSystem) {
                        ForEach(sizeSystems, id: \.self) { size in
                            Text(size).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: .infinity)
                }
            }
            .font(.caption)
        }
    }

    private var measurementsCard: some View {
        MacFeatureCard("Body Measurements") {
            VStack(spacing: PluckTheme.Spacing.sm) {
                measurementInput("Height (cm)", binding: $editedPreferences.heightCm)
                measurementInput("Weight (kg)", binding: $editedPreferences.weightKg)
                measurementInput("Chest (cm)", binding: $editedPreferences.chestCm)
                measurementInput("Waist (cm)", binding: $editedPreferences.waistCm)
                measurementInput("Hips (cm)", binding: $editedPreferences.hipsCm)
                measurementInput("Inseam (cm)", binding: $editedPreferences.inseamCm)
            }
            .font(.caption)
        }
    }

    private var styleIdentityCard: some View {
        MacFeatureCard("Style Identity") {
            VStack(alignment: .leading, spacing: PluckTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: PluckTheme.Spacing.sm) {
                    Text("Aesthetics")
                        .font(.caption2)
                        .foregroundStyle(PluckTheme.secondaryText)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: PluckTheme.Spacing.xs)], spacing: PluckTheme.Spacing.xs) {
                        ForEach(aesthetics, id: \.self) { tag in
                            let selected = editedPreferences.stylePreferences.contains(tag)
                            Button(tag) {
                                if selected {
                                    editedPreferences.stylePreferences.removeAll { $0 == tag }
                                } else {
                                    editedPreferences.stylePreferences.append(tag)
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(selected ? PluckTheme.accent : .secondary)
                            .font(.caption2)
                        }
                    }
                }

                inputRow("Favourite brands", placeholder: "e.g. Nike, Zara", binding: Binding(
                    get: { editedPreferences.favoriteBrands.joined(separator: ", ") },
                    set: { editedPreferences.favoriteBrands = splitCSV($0) }
                ))
                inputRow("Preferred colours", placeholder: "e.g. black, navy", binding: Binding(
                    get: { editedPreferences.preferredColours.joined(separator: ", ") },
                    set: { editedPreferences.preferredColours = splitCSV($0) }
                ))
                inputRow("Location city", placeholder: "e.g. London", binding: Binding(
                    get: { editedPreferences.locationCity ?? "" },
                    set: { editedPreferences.locationCity = $0.isEmpty ? nil : $0 }
                ))
            }
            .font(.caption)
        }
    }

    private var aiPersonalizationCard: some View {
        MacFeatureCard("AI Personalisation") {
            Toggle(isOn: Binding(
                get: { editedPreferences.recommendationOptIn ?? false },
                set: { editedPreferences.recommendationOptIn = $0 }
            )) {
                VStack(alignment: .leading) {
                    Text("Enable personalization")
                        .foregroundStyle(PluckTheme.primaryText)
                    Text("Weekly digest and wear-based recommendations")
                        .font(.caption2)
                        .foregroundStyle(PluckTheme.secondaryText)
                }
            }
            .toggleStyle(.switch)
        }
    }

    private func measurementInput(_ title: String, binding: Binding<Double?>) -> some View {
        HStack {
            Text(title)
                .frame(width: 110, alignment: .leading)
            TextField("—", value: binding, format: .number)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .frame(width: 140)
        }
    }

    private func inputRow(_ title: String, placeholder: String, binding: Binding<String>) -> some View {
        HStack(spacing: PluckTheme.Spacing.sm) {
            Text(title)
                .frame(width: 110, alignment: .leading)
            TextField(placeholder, text: binding)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            profile = try await appServices.profileService.fetchProfile()
            preferences = try await appServices.profileService.fetchPreferences()
            editedPreferences = preferences
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func save() async {
        saving = true
        saveMessage = nil
        do {
            try await appServices.profileService.updatePreferences(editedPreferences)
            preferences = editedPreferences
            saveMessage = "Preferences updated."
        } catch {
            errorText = error.localizedDescription
        }
        saving = false
    }

    private func splitCSV(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func prefsEqual(_ lhs: UserPreferences, _ rhs: UserPreferences) -> Bool {
        lhs.currencyCode == rhs.currencyCode &&
        lhs.preferredSizeSystem == rhs.preferredSizeSystem &&
        lhs.heightCm == rhs.heightCm &&
        lhs.weightKg == rhs.weightKg &&
        lhs.chestCm == rhs.chestCm &&
        lhs.waistCm == rhs.waistCm &&
        lhs.hipsCm == rhs.hipsCm &&
        lhs.inseamCm == rhs.inseamCm &&
        lhs.stylePreferences == rhs.stylePreferences &&
        lhs.favoriteBrands == rhs.favoriteBrands &&
        lhs.preferredColours == rhs.preferredColours &&
        lhs.locationCity == rhs.locationCity &&
        lhs.recommendationOptIn == rhs.recommendationOptIn
    }

}

// MARK: - FlowLayout

/// A simple wrapping layout for pills/chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                height += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}


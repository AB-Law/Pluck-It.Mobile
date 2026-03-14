import SwiftUI
import PhotosUI

struct WishlistView: View {
    @EnvironmentObject private var appServices: AppServices

    // Items
    @State private var allItems: [ClothingItem] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var nextToken: String?
    @State private var isLoadingMore = false

    // Upload queue
    @State private var queue: [UploadQueueItem] = []
    @State private var draftItems: [String: ClothingItem] = [:]
    @State private var pollingTask: Task<Void, Never>?
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var presegmentedQueueItemIDs: Set<UUID> = []
    @State private var segmentedWishlistItems: [SegmentedClothingItem] = []
    @State private var isSegmentingWishlist = false

    // Item drawer / draft review
    @State private var selectedItem: ClothingItem?
    @State private var reviewItem: ClothingItem?
    @State private var reviewQueueId: UUID?

    private var wishlistItems: [ClothingItem] { allItems.filter { $0.isWishlisted } }
    private var hasProcessingItems: Bool { queue.contains { $0.state == .processing || $0.state == .uploading } }

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && allItems.isEmpty && queue.isEmpty {
                    ProgressView("Loading wishlist")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .foregroundStyle(PluckTheme.secondaryText)
                        .pluckReveal()
                } else if let loadError, wishlistItems.isEmpty && queue.isEmpty {
                    VStack(spacing: PluckTheme.Spacing.sm) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.largeTitle)
                            .foregroundStyle(PluckTheme.danger)
                        Text(loadError)
                            .font(.caption)
                            .foregroundStyle(PluckTheme.secondaryText)
                        Button("Retry") { Task { await loadItems(refresh: true) } }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .pluckReveal()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: PluckTheme.Spacing.md) {
                            if !queue.isEmpty {
                                draftQueueSection
                                    .pluckReveal()
                            }

                            if wishlistItems.isEmpty && queue.isEmpty {
                                emptyState
                                    .pluckReveal()
                            } else if !wishlistItems.isEmpty {
                                itemsGrid
                                    .pluckReveal()
                            }

                            Spacer(minLength: PluckTheme.Spacing.md)
                        }
                        .padding(.vertical, PluckTheme.Spacing.sm)
                    }
                }
            }
            .navigationTitle("Wishlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    PhotosPicker(selection: $photoPickerItems, maxSelectionCount: 10, matching: .images) {
                        Image(systemName: "plus")
                            .foregroundStyle(PluckTheme.primaryText)
                    }
                    .disabled(isSegmentingWishlist)
                    .onChange(of: photoPickerItems) {
                        guard !photoPickerItems.isEmpty else { return }
                        Task { await enqueuePhotos() }
                    }
                }
            }
            .task {
                await loadItems(refresh: true)
            }
            .refreshable {
                await loadItems(refresh: true)
            }
            .shellToolbar()
            .sheet(item: $selectedItem) { item in
                VaultItemDrawerView(
                    item: item,
                    onUpdated: { updated in
                        syncItem(updated)
                    },
                    onDeleted: { deletedId in
                        allItems.removeAll { $0.id == deletedId }
                        if selectedItem?.id == deletedId {
                            selectedItem = nil
                        }
                    }
                )
                .environmentObject(appServices)
            }
            .sheet(item: $reviewItem) { item in
                WardrobeItemReviewModal(item: item) { updated in
                    Task { await acceptDraft(updated) }
                }
                .environmentObject(appServices)
            }
            .sheet(isPresented: Binding(
                get: { !segmentedWishlistItems.isEmpty },
                set: { if !$0 { segmentedWishlistItems = [] } }
            )) {
                ClothingItemSelectionSheet(
                    items: segmentedWishlistItems,
                    onUpload: { selected in
                        segmentedWishlistItems = []
                        Task { await enqueuePresegmentedWishlistItems(selected) }
                    },
                    onCancel: { segmentedWishlistItems = [] }
                )
            }
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Draft Queue

    private var draftQueueSection: some View {
        VStack(alignment: .leading, spacing: PluckTheme.Spacing.xs) {
            Text("Processing")
                .font(.subheadline)
                .foregroundStyle(PluckTheme.secondaryText)
                .textCase(.uppercase)
                .padding(.horizontal, PluckTheme.Spacing.md)

            ForEach(queue) { queueItem in
                draftRow(for: queueItem)
                    .padding(.horizontal, PluckTheme.Spacing.md)
            }
        }
    }

    @ViewBuilder
    private func draftRow(for queueItem: UploadQueueItem) -> some View {
        HStack(spacing: PluckTheme.Spacing.sm) {
            if let imageUrl = queueItem.draftId.flatMap({ draftItems[$0]?.imageUrl ?? draftItems[$0]?.rawImageBlobUrl }),
               let url = normalizedImageURL(imageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Rectangle().fill(PluckTheme.card)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
            } else {
                RoundedRectangle(cornerRadius: PluckTheme.Radius.small)
                    .fill(PluckTheme.card)
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: "heart").foregroundStyle(PluckTheme.mutedText))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(queueItem.state == .uploading ? "Uploading…" :
                     queueItem.state == .processing ? "Processing…" :
                     queueItem.state == .ready ? "Ready to review" : "Failed")
                    .font(.subheadline)
                    .foregroundStyle(PluckTheme.primaryText)
                if case .failed(let msg) = queueItem.state {
                    Text(msg ?? "Upload failed")
                        .font(.caption2)
                        .foregroundStyle(PluckTheme.danger)
                }
            }

            Spacer()

            switch queueItem.state {
            case .uploading, .processing:
                ProgressView().scaleEffect(0.8)
            case .ready:
                if let draftId = queueItem.draftId, let draft = draftItems[draftId] {
                    Button("Review") {
                        pluckImpactFeedback(.light)
                        reviewQueueId = queueItem.id
                        reviewItem = draft
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PluckTheme.accent)
                    .font(.caption)
                }
            default:
                EmptyView()
            }
        }
        .padding(PluckTheme.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: PluckTheme.Radius.medium).fill(PluckTheme.card))
    }

    // MARK: - Items Grid

    private var itemsGrid: some View {
        VStack(alignment: .leading, spacing: PluckTheme.Spacing.xs) {
            Text("Saved items")
                .font(.subheadline)
                .foregroundStyle(PluckTheme.secondaryText)
                .textCase(.uppercase)
                .padding(.horizontal, PluckTheme.Spacing.md)

            LazyVGrid(columns: columns, spacing: PluckTheme.Spacing.xs) {
                ForEach(Array(wishlistItems.enumerated()), id: \.element.id) { index, item in
                    wishlistCard(for: item)
                        .pluckReveal(delay: min(Double(index) * 0.03, 0.28))
                        .onTapGesture {
                            pluckImpactFeedback(.light)
                            selectedItem = item
                        }
                }
            }
            .padding(.horizontal, PluckTheme.Spacing.sm)

            if nextToken != nil {
                if isLoadingMore {
                    HStack { Spacer(); ProgressView("Loading more").foregroundStyle(PluckTheme.secondaryText); Spacer() }
                        .padding(.vertical, PluckTheme.Spacing.sm)
                } else {
                    Button("Load more") {
                        pluckImpactFeedback(.light)
                        Task { await loadItems(refresh: false) }
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(PluckTheme.info)
                    .padding(.vertical, PluckTheme.Spacing.sm)
                }
            }
        }
    }

    @ViewBuilder
    private func wishlistCard(for item: ClothingItem) -> some View {
        let imageURL = normalizedImageURL(item.imageUrl) ?? normalizedImageURL(item.rawImageBlobUrl)
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    Rectangle().fill(PluckTheme.card)
                        .overlay(Image(systemName: "heart").foregroundStyle(PluckTheme.secondaryText))
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(3/4, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))

            if item.brand != nil || item.category != nil {
                LinearGradient(
                    colors: [.clear, PluckTheme.background.opacity(0.8)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))

                VStack(alignment: .leading, spacing: 2) {
                    if let brand = item.brand {
                        Text(brand)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(PluckTheme.primaryText)
                            .lineLimit(1)
                    }
                    if let category = item.category {
                        Text(category)
                            .font(.caption2)
                            .foregroundStyle(PluckTheme.secondaryText)
                            .lineLimit(1)
                    }
                }
                .padding(6)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: PluckTheme.Spacing.sm) {
            Image(systemName: "heart")
                .font(.largeTitle)
                .foregroundStyle(PluckTheme.mutedText)
            Text("Your wishlist is empty")
                .foregroundStyle(PluckTheme.secondaryText)
            Text("Tap + to add photos of items you want.")
                .font(.caption)
                .foregroundStyle(PluckTheme.mutedText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, PluckTheme.Spacing.lg)
        }
        .padding(.vertical, 64)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Load Items

    private func loadItems(refresh: Bool) async {
        if refresh {
            isLoading = true
            nextToken = nil
            loadError = nil
        } else {
            isLoadingMore = true
        }
        defer {
            isLoading = false
            isLoadingMore = false
        }
        do {
            let response = try await appServices.wardrobeService.fetchItems(
                pageSize: 60,
                continuationToken: refresh ? nil : nextToken,
                includeWishlisted: true
            )
            let wishlisted = response.items.filter { $0.isWishlisted }
            if refresh {
                allItems = wishlisted
            } else {
                allItems.append(contentsOf: wishlisted)
            }
            nextToken = response.nextContinuationToken
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func syncItem(_ updated: ClothingItem) {
        if let idx = allItems.firstIndex(where: { $0.id == updated.id }) {
            allItems[idx] = updated
        }
    }

    // MARK: - Upload

    private func enqueuePhotos() async {
        guard !photoPickerItems.isEmpty else { return }
        isSegmentingWishlist = true
        defer { isSegmentingWishlist = false }

        var segmentedItems: [SegmentedClothingItem] = []
        for pickerItem in photoPickerItems {
            guard let data = try? await pickerItem.loadTransferable(type: Data.self) else { continue }
            segmentedItems.append(contentsOf: await ClothingSegmentationService.segmentIntoItems(imageData: data))
        }
        photoPickerItems = []
        segmentedWishlistItems = segmentedItems
    }

    private func uploadQueueItem(_ queueItem: UploadQueueItem) async {
        updateState(id: queueItem.id, state: .uploading)
        do {
            let draft: ClothingItem
            if presegmentedQueueItemIDs.contains(queueItem.id) {
                draft = try await appServices.wardrobeService.uploadForDraftWishlistedPresegmented(imageData: queueItem.imageData)
            } else {
                draft = try await appServices.wardrobeService.uploadForDraftWishlisted(imageData: queueItem.imageData)
            }
            updateDraftId(id: queueItem.id, draftId: draft.id)
            draftItems[draft.id] = draft
            let status = draft.draftStatus?.lowercased()
            if status == "ready" {
                updateState(id: queueItem.id, state: .ready)
                await loadItems(refresh: true)
            } else if status == "failed" {
                updateState(id: queueItem.id, state: .failed(draft.draftError))
            } else {
                updateState(id: queueItem.id, state: .processing)
                startPollingIfNeeded()
            }
        } catch {
            if let apiError = error as? APIClient.ErrorResponse, apiError.statusCode == 401 {
                updateState(id: queueItem.id, state: .failed("Unauthorized (401). Please sign in again and retry."))
                return
            }
            updateState(id: queueItem.id, state: .failed(error.localizedDescription))
        }
    }

    private func enqueuePresegmentedWishlistItems(_ items: [SegmentedClothingItem]) async {
        var newItems: [UploadQueueItem] = []
        for item in items {
            let queueItem = UploadQueueItem(imageData: item.imageData)
            newItems.append(queueItem)
            presegmentedQueueItemIDs.insert(queueItem.id)
        }
        queue.append(contentsOf: newItems)
        for queueItem in newItems {
            Task { await uploadQueueItem(queueItem) }
        }
    }

    // MARK: - Polling

    private func acceptDraft(_ updated: ClothingItem) async {
        guard let queueId = reviewQueueId,
              let draftId = queue.first(where: { $0.id == queueId })?.draftId else { return }
        reviewItem = nil
        reviewQueueId = nil
        do {
            try await appServices.wardrobeService.acceptDraft(draftId)
            queue.removeAll { $0.id == queueId }
            presegmentedQueueItemIDs.remove(queueId)
            draftItems.removeValue(forKey: draftId)
            await loadItems(refresh: true)
        } catch {
            updateState(id: queueId, state: .failed(error.localizedDescription))
        }
    }

    private func startPollingIfNeeded() {
        guard pollingTask == nil || pollingTask!.isCancelled else { return }
        pollingTask = Task {
            while !Task.isCancelled && hasProcessingItems {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { break }
                await pollDrafts()
            }
            pollingTask = nil
        }
    }

    private func pollDrafts() async {
        guard let drafts = try? await appServices.wardrobeService.fetchDrafts() else { return }
        for draft in drafts {
            guard let item = draft.item, item.isWishlisted else { continue }
            draftItems[draft.id] = item
            guard let idx = queue.firstIndex(where: { $0.draftId == draft.id }) else { continue }
            let status = draft.status.lowercased()
            if status == "ready" {
                queue[idx].state = .ready
                await loadItems(refresh: true)
            } else if status == "failed" {
                queue[idx].state = .failed(item.draftError)
            }
        }
        if !hasProcessingItems { pollingTask?.cancel() }
    }

    // MARK: - Queue helpers

    private func updateState(id: UUID, state: UploadState) {
        guard let idx = queue.firstIndex(where: { $0.id == id }) else { return }
        queue[idx].state = state
    }

    private func updateDraftId(id: UUID, draftId: String) {
        guard let idx = queue.firstIndex(where: { $0.id == id }) else { return }
        queue[idx].draftId = draftId
    }
}

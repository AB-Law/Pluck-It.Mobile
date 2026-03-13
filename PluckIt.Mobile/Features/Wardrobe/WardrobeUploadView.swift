import SwiftUI
import PhotosUI

struct WardrobeUploadView: View {
    @EnvironmentObject private var appServices: AppServices
    @Environment(\.dismiss) private var dismiss

    let onUploaded: () -> Void
    let onPendingCountChanged: ((Int) -> Void)?

    init(onUploaded: @escaping () -> Void, onPendingCountChanged: ((Int) -> Void)? = nil) {
        self.onUploaded = onUploaded
        self.onPendingCountChanged = onPendingCountChanged
    }

    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var queue: [UploadQueueItem] = []
    @State private var draftItems: [String: ClothingItem] = [:]
    @State private var pollingTask: Task<Void, Never>?
    @State private var reviewItem: ClothingItem?
    @State private var reviewQueueId: UUID?
    @State private var isLoadingDrafts = false

    private var hasProcessingItems: Bool {
        queue.contains { $0.isProcessing }
    }

    private var pendingReviewCount: Int {
        queue.filter { $0.isReady }.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PhotosPicker(selection: $photoPickerItems, maxSelectionCount: 10, matching: .images) {
                    Label("Add photos", systemImage: "photo.badge.plus")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(PluckTheme.Spacing.sm)
                        .background(PluckTheme.accent)
                        .foregroundStyle(PluckTheme.background)
                        .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
                }
                .padding(PluckTheme.Spacing.md)
                .onChange(of: photoPickerItems) {
                    Task { await enqueueSelectedPhotos() }
                }

                if isLoadingDrafts {
                    Spacer()
                    ProgressView("Loading pending drafts")
                        .foregroundStyle(PluckTheme.secondaryText)
                    Spacer()
                } else if queue.isEmpty {
                    Spacer()
                    VStack(spacing: PluckTheme.Spacing.sm) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.largeTitle)
                            .foregroundStyle(PluckTheme.mutedText)
                        Text("Select photos to upload")
                            .foregroundStyle(PluckTheme.secondaryText)
                        Text("Items will be processed by AI and ready to review.")
                            .font(.caption)
                            .foregroundStyle(PluckTheme.mutedText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, PluckTheme.Spacing.lg)
                    }
                    Spacer()
                } else {
                    List(queue) { queueItem in
                        uploadRow(for: queueItem)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Upload Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .background(PluckTheme.background)
            .task { await loadExistingDrafts() }
            .onDisappear {
                pollingTask?.cancel()
            }
        }
        .sheet(item: $reviewItem) { item in
            WardrobeItemReviewModal(item: item) { updated in
                Task { await acceptDraft(updated) }
            }
            .environmentObject(appServices)
        }
        .onChange(of: queue) {
            onPendingCountChanged?(queue.filter { $0.isReady }.count)
        }
    }

    @ViewBuilder
    private func uploadRow(for queueItem: UploadQueueItem) -> some View {
        HStack(spacing: PluckTheme.Spacing.sm) {
            Image(uiImage: UIImage(data: queueItem.imageData) ?? UIImage())
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
                .background(PluckTheme.card)

            VStack(alignment: .leading, spacing: 4) {
                if let draftId = queueItem.draftId,
                   let item = draftItems[draftId],
                   let brand = item.brand ?? item.category {
                    Text(brand)
                        .font(.caption)
                        .foregroundStyle(PluckTheme.primaryText)
                }
                stateLabel(for: queueItem.state)
                if case .failed(let msg) = queueItem.state, let msg {
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(PluckTheme.danger)
                        .lineLimit(2)
                }
            }

            Spacer()
            actionButton(for: queueItem)
        }
        .padding(.vertical, PluckTheme.Spacing.xs)
        .listRowBackground(PluckTheme.background)
    }

    @ViewBuilder
    private func stateLabel(for state: UploadState) -> some View {
        switch state {
        case .queued:
            Label("Queued", systemImage: "clock")
                .font(.caption).foregroundStyle(PluckTheme.secondaryText)
        case .uploading:
            Label("Uploading", systemImage: "arrow.up.circle")
                .font(.caption).foregroundStyle(PluckTheme.info)
        case .processing:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.7)
                Text("Processing…").font(.caption).foregroundStyle(PluckTheme.secondaryText)
            }
        case .ready:
            Label("Ready to review", systemImage: "checkmark.circle")
                .font(.caption).foregroundStyle(PluckTheme.success)
        case .failed:
            Label("Failed", systemImage: "exclamationmark.circle")
                .font(.caption).foregroundStyle(PluckTheme.danger)
        }
    }

    @ViewBuilder
    private func actionButton(for queueItem: UploadQueueItem) -> some View {
        switch queueItem.state {
        case .ready:
            if let draftId = queueItem.draftId, let item = draftItems[draftId] {
                Button("Review") {
                    reviewItem = item
                    reviewQueueId = queueItem.id
                }
                .buttonStyle(.borderedProminent)
                .tint(PluckTheme.accent)
                .font(.caption)
            }
        case .failed:
            HStack(spacing: PluckTheme.Spacing.xs) {
                if let draftId = queueItem.draftId {
                    Button("Retry") { Task { await retryQueueItem(queueItem, draftId: draftId) } }
                        .font(.caption).foregroundStyle(PluckTheme.info)
                    Button("Dismiss") { Task { await dismissQueueItem(queueItem, draftId: draftId) } }
                        .font(.caption).foregroundStyle(PluckTheme.danger)
                } else {
                    Button("Re-upload") { Task { await uploadQueueItem(queueItem) } }
                        .font(.caption).foregroundStyle(PluckTheme.info)
                }
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Load existing drafts on open

    private func loadExistingDrafts() async {
        isLoadingDrafts = true
        defer { isLoadingDrafts = false }
        guard let drafts = try? await appServices.wardrobeService.fetchDrafts() else { return }
        for draft in drafts {
            guard let item = draft.item else { continue }
            draftItems[draft.id] = item
            // Only add to queue if not already tracked (avoid duplicates with in-progress uploads)
            guard !queue.contains(where: { $0.draftId == draft.id }) else { continue }
            // Use a 1×1 transparent PNG placeholder — no local image data for server-side drafts
            let placeholder = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==") ?? Data()
            var queueItem = UploadQueueItem(imageData: placeholder)
            queueItem.draftId = draft.id
            let status = draft.status.lowercased()
            if status == "ready" {
                queueItem.state = .ready
            } else if status == "failed" {
                queueItem.state = .failed(item.draftError)
            } else {
                queueItem.state = .processing
            }
            queue.append(queueItem)
        }
        if hasProcessingItems { startPollingIfNeeded() }
    }

    // MARK: - Upload actions

    private func enqueueSelectedPhotos() async {
        var newItems: [UploadQueueItem] = []
        for pickerItem in photoPickerItems {
            guard let data = try? await pickerItem.loadTransferable(type: Data.self) else { continue }
            newItems.append(UploadQueueItem(imageData: data))
        }
        photoPickerItems = []
        queue.append(contentsOf: newItems)
        // Dismiss immediately so upload happens in background; user can re-open to review
        dismiss()
        for item in newItems {
            Task { await uploadQueueItem(item) }
        }
    }

    private func uploadQueueItem(_ queueItem: UploadQueueItem) async {
        updateState(id: queueItem.id, state: .uploading)
        do {
            let draft = try await appServices.wardrobeService.uploadForDraft(imageData: queueItem.imageData)
            updateDraftId(id: queueItem.id, draftId: draft.id)
            draftItems[draft.id] = draft
            let status = draft.draftStatus?.lowercased()
            if status == "ready" {
                updateState(id: queueItem.id, state: .ready)
                onUploaded()
            } else if status == "failed" {
                updateState(id: queueItem.id, state: .failed(draft.draftError))
            } else {
                updateState(id: queueItem.id, state: .processing)
                startPollingIfNeeded()
            }
        } catch {
            updateState(id: queueItem.id, state: .failed(error.localizedDescription))
        }
    }

    private func retryQueueItem(_ queueItem: UploadQueueItem, draftId: String) async {
        updateState(id: queueItem.id, state: .processing)
        do {
            try await appServices.wardrobeService.retryDraft(draftId)
            startPollingIfNeeded()
        } catch {
            updateState(id: queueItem.id, state: .failed(error.localizedDescription))
        }
    }

    private func dismissQueueItem(_ queueItem: UploadQueueItem, draftId: String) async {
        do { try await appServices.wardrobeService.dismissDraft(draftId) } catch {}
        queue.removeAll { $0.id == queueItem.id }
        draftItems.removeValue(forKey: draftId)
    }

    private func acceptDraft(_ updated: ClothingItem) async {
        guard let queueId = reviewQueueId,
              let draftId = queue.first(where: { $0.id == queueId })?.draftId else { return }
        reviewItem = nil
        reviewQueueId = nil
        // WardrobeItemReviewModal already called update() — only need to accept
        do {
            try await appServices.wardrobeService.acceptDraft(draftId)
            queue.removeAll { $0.id == queueId }
            draftItems.removeValue(forKey: draftId)
            onUploaded()
        } catch {
            updateState(id: queueId, state: .failed(error.localizedDescription))
        }
    }

    // MARK: - Polling

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
            guard let item = draft.item else { continue }
            draftItems[draft.id] = item
            let status = draft.status.lowercased()
            if let idx = queue.firstIndex(where: { $0.draftId == draft.id }) {
                if status == "ready" && !queue[idx].isReady {
                    queue[idx].state = .ready
                    onUploaded()
                } else if status == "failed" && !queue[idx].isFailed {
                    queue[idx].state = .failed(item.draftError)
                }
            }
        }
    }

    // MARK: - Helpers

    private func updateState(id: UUID, state: UploadState) {
        if let idx = queue.firstIndex(where: { $0.id == id }) {
            queue[idx].state = state
        }
    }

    private func updateDraftId(id: UUID, draftId: String) {
        if let idx = queue.firstIndex(where: { $0.id == id }) {
            queue[idx].draftId = draftId
        }
    }
}

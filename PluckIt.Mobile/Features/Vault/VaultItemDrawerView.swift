import SwiftUI

struct VaultItemDrawerView: View {
    @EnvironmentObject private var appServices: AppServices
    @Environment(\.dismiss) private var dismiss

    let item: ClothingItem
    let onUpdated: (ClothingItem) -> Void
    let onDeleted: (String) -> Void

    @State private var currentItem: ClothingItem
    @State private var isEditPresented = false
    @State private var isLoggingWear = false
    @State private var isDeleting = false
    @State private var errorText: String?
    @State private var showDeleteConfirmation = false

    init(item: ClothingItem, onUpdated: @escaping (ClothingItem) -> Void, onDeleted: @escaping (String) -> Void) {
        self.item = item
        self.onUpdated = onUpdated
        self.onDeleted = onDeleted
        self._currentItem = State(initialValue: item)
    }

    private var cpw: Double? {
        guard let price = currentItem.price?.amount, price > 0,
              let wears = currentItem.wearCount, wears > 0 else { return nil }
        return price / Double(wears)
    }

    private let careIcons: [String: String] = [
        "dry_clean": "wind",
        "wash": "drop",
        "iron": "thermometer.medium",
        "bleach": "sparkle"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PluckTheme.Spacing.md) {
                    headerSection
                    analyticsSection
                    if let care = currentItem.careInfo, !care.isEmpty {
                        careSection(care)
                    }
                    if let aesthetics = currentItem.aestheticTags, !aesthetics.isEmpty {
                        tagsSection(aesthetics)
                    }
                    if let notes = currentItem.notes, !notes.isEmpty {
                        notesSection(notes)
                    }
                    actionButtons
                    if let err = errorText {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(PluckTheme.danger)
                            .padding(.horizontal, PluckTheme.Spacing.md)
                    }
                    Spacer(minLength: PluckTheme.Spacing.xl)
                }
                .padding(.vertical, PluckTheme.Spacing.sm)
            }
            .background(PluckTheme.background)
            .navigationTitle(currentItem.brand ?? currentItem.category ?? "Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        pluckImpactFeedback(.light)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Edit") {
                        pluckImpactFeedback(.light)
                        isEditPresented = true
                    }
                        .foregroundStyle(PluckTheme.info)
                }
            }
            .sheet(isPresented: $isEditPresented) {
                WardrobeItemReviewModal(item: currentItem) { updated in
                    currentItem = updated
                    onUpdated(updated)
                }
                .environmentObject(appServices)
            }
            .scrollContentBackground(.hidden)
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: PluckTheme.Spacing.md) {
            AsyncImage(url: normalizedImageURL(currentItem.imageUrl)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                default:
                    Rectangle().fill(PluckTheme.card)
                        .overlay(Image(systemName: "tshirt").foregroundStyle(PluckTheme.secondaryText))
                }
            }
            .frame(width: 100, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))

            VStack(alignment: .leading, spacing: PluckTheme.Spacing.xs) {
                if let brand = currentItem.brand {
                    Text(brand)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(PluckTheme.primaryText)
                }
                if let category = currentItem.category {
                    Text(category)
                        .font(.subheadline)
                        .foregroundStyle(PluckTheme.secondaryText)
                }
                if let condition = currentItem.condition, !condition.isEmpty {
                    Text(condition)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(PluckTheme.card)
                        .clipShape(Capsule())
                        .foregroundStyle(PluckTheme.mutedText)
                }
            }
        }
        .padding(.horizontal, PluckTheme.Spacing.md)
    }

    private var analyticsSection: some View {
        HStack(spacing: PluckTheme.Spacing.sm) {
            analyticsCard(
                title: "Wears",
                value: "\(currentItem.wearCount ?? 0)"
            )
            if let price = currentItem.price?.amount, price > 0 {
                analyticsCard(
                    title: "Price",
                    value: formattedCurrency(price)
                )
            }
            if let cpw {
                analyticsCard(
                    title: "CPW",
                    value: formattedCurrency(cpw)
                )
            }
            if let value = currentItem.estimatedMarketValue {
                analyticsCard(
                    title: "Est. Value",
                    value: formattedCurrency(value)
                )
            }
        }
        .padding(.horizontal, PluckTheme.Spacing.md)
    }

    private func analyticsCard(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(PluckTheme.secondaryText)
                .textCase(.uppercase)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PluckTheme.primaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PluckTheme.Spacing.sm)
        .background(PluckTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
    }

    private func careSection(_ care: [String]) -> some View {
        VStack(alignment: .leading, spacing: PluckTheme.Spacing.xs) {
            Text("Care")
                .font(.caption)
                .foregroundStyle(PluckTheme.secondaryText)
                .textCase(.uppercase)
                .padding(.horizontal, PluckTheme.Spacing.md)

            HStack(spacing: PluckTheme.Spacing.sm) {
                ForEach(care, id: \.self) { key in
                    Label(key.replacingOccurrences(of: "_", with: " ").capitalized,
                          systemImage: careIcons[key] ?? "checkmark")
                        .font(.caption2)
                        .foregroundStyle(PluckTheme.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(PluckTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
                }
            }
            .padding(.horizontal, PluckTheme.Spacing.md)
        }
    }

    private func tagsSection(_ tags: [String]) -> some View {
        VStack(alignment: .leading, spacing: PluckTheme.Spacing.xs) {
            Text("Style tags")
                .font(.caption)
                .foregroundStyle(PluckTheme.secondaryText)
                .textCase(.uppercase)
                .padding(.horizontal, PluckTheme.Spacing.md)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PluckTheme.Spacing.xs) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(PluckTheme.card)
                            .clipShape(Capsule())
                            .foregroundStyle(PluckTheme.secondaryText)
                    }
                }
                .padding(.horizontal, PluckTheme.Spacing.md)
            }
        }
    }

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: PluckTheme.Spacing.xs) {
            Text("Notes")
                .font(.caption)
                .foregroundStyle(PluckTheme.secondaryText)
                .textCase(.uppercase)
            Text(notes)
                .font(.subheadline)
                .foregroundStyle(PluckTheme.primaryText)
        }
        .padding(.horizontal, PluckTheme.Spacing.md)
    }

    private var actionButtons: some View {
        VStack(spacing: PluckTheme.Spacing.sm) {
            Button {
                pluckImpactFeedback(.light)
                Task { await logWear() }
            } label: {
                if isLoggingWear {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Log wear", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(PluckTheme.accent)
            .disabled(isLoggingWear)

            Button {
                pluckImpactFeedback(.medium)
                showDeleteConfirmation = true
            } label: {
                if isDeleting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Delete item", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(isDeleting || isLoggingWear)
            .alert("Delete item", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    showDeleteConfirmation = false
                }
                Button("Delete", role: .destructive) {
                    Task { await deleteCurrentItem() }
                }
            } message: {
                Text("This will permanently remove this item from your wardrobe and cannot be undone.")
            }
        }
        .padding(.horizontal, PluckTheme.Spacing.md)
    }

    private func logWear() async {
        guard !isLoggingWear else { return }
        isLoggingWear = true
        errorText = nil
        defer { isLoggingWear = false }
        do {
            try await appServices.wardrobeService.logWear(currentItem.id)
            let newWearCount = (currentItem.wearCount ?? 0) + 1
            currentItem = ClothingItem(
                id: currentItem.id,
                imageUrl: currentItem.imageUrl,
                rawImageBlobUrl: currentItem.rawImageBlobUrl,
                tags: currentItem.tags,
                colours: currentItem.colours,
                brand: currentItem.brand,
                category: currentItem.category,
                price: currentItem.price,
                notes: currentItem.notes,
                dateAdded: currentItem.dateAdded,
                wearCount: newWearCount,
                purchaseDate: currentItem.purchaseDate,
                careInfo: currentItem.careInfo,
                condition: currentItem.condition,
                size: currentItem.size,
                aestheticTags: currentItem.aestheticTags,
                draftStatus: currentItem.draftStatus,
                draftError: currentItem.draftError,
                userId: currentItem.userId,
                estimatedMarketValue: currentItem.estimatedMarketValue,
                lastWornAt: currentItem.lastWornAt,
                wearEvents: currentItem.wearEvents,
                draftCreatedAt: currentItem.draftCreatedAt,
                draftUpdatedAt: currentItem.draftUpdatedAt,
                isWishlisted: currentItem.isWishlisted
            )
            onUpdated(currentItem)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func deleteCurrentItem() async {
        guard !isDeleting else { return }
        isDeleting = true
        errorText = nil
        do {
            try await appServices.wardrobeService.delete(currentItem.id)
            onDeleted(currentItem.id)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
        isDeleting = false
    }

    private func formattedCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "—"
    }
}

import SwiftUI

struct ClothingItemSelectionSheet: View {
    @State private var items: [SegmentedClothingItem]
    let onUpload: ([SegmentedClothingItem]) -> Void
    let onCancel: () -> Void

    init(items: [SegmentedClothingItem], onUpload: @escaping ([SegmentedClothingItem]) -> Void, onCancel: @escaping () -> Void) {
        _items = State(initialValue: items)
        self.onUpload = onUpload
        self.onCancel = onCancel
    }

    private var selectedCount: Int { items.filter(\.isSelected).count }

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: PluckTheme.Spacing.sm) {
                    ForEach(items.indices, id: \.self) { index in
                        itemCard(index: index)
                    }
                }
                .padding(PluckTheme.Spacing.md)
            }
            .navigationTitle("Select Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                uploadButton
            }
            .background(PluckTheme.background)
        }
    }

    @ViewBuilder
    private func itemCard(index: Int) -> some View {
        let item = items[index]
        Button {
            pluckImpactFeedback()
            items[index].isSelected.toggle()
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 8) {
                    if let uiImage = UIImage(data: item.imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
                    }
                    Text(item.label)
                        .font(.caption)
                        .foregroundStyle(item.isSelected ? PluckTheme.primaryText : PluckTheme.mutedText)
                        .lineLimit(1)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: PluckTheme.Radius.medium)
                        .fill(item.isSelected ? PluckTheme.accent.opacity(0.08) : Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PluckTheme.Radius.medium)
                        .stroke(item.isSelected ? PluckTheme.accent : Color.clear, lineWidth: 2)
                )

                // Checkmark badge
                ZStack {
                    Circle()
                        .fill(item.isSelected ? PluckTheme.accent : Color(.tertiarySystemBackground))
                        .frame(width: 24, height: 24)
                    if item.isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(PluckTheme.background)
                    }
                }
                .padding(8)
            }
        }
        .buttonStyle(.plain)
    }

    private var uploadButton: some View {
        Button {
            let selected = items.filter(\.isSelected)
            guard !selected.isEmpty else { return }
            pluckImpactFeedback()
            onUpload(selected)
        } label: {
            Text(selectedCount == 0 ? "Select items to upload" : "Upload \(selectedCount) item\(selectedCount == 1 ? "" : "s")")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(PluckTheme.Spacing.md)
                .background(selectedCount == 0 ? Color.gray.opacity(0.3) : PluckTheme.accent)
                .foregroundStyle(PluckTheme.background)
                .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.medium))
        }
        .disabled(selectedCount == 0)
        .padding(PluckTheme.Spacing.md)
        .background(.ultraThinMaterial)
    }
}

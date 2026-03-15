import SwiftUI

/// Mac-styled item selection panel shown after segmentation.
/// Mirrors the iOS ClothingItemSelectionSheet but uses AppKit images
/// and the terminal aesthetic of the Mac app.
struct MacClothingItemSelectionPanel: View {
    @State private var items: [SegmentedClothingItem]
    let onUpload: ([SegmentedClothingItem]) -> Void
    let onCancel: () -> Void

    init(
        items: [SegmentedClothingItem],
        onUpload: @escaping ([SegmentedClothingItem]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _items = State(initialValue: items)
        self.onUpload = onUpload
        self.onCancel = onCancel
    }

    private var selectedCount: Int { items.filter(\.isSelected).count }

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 0) {
            MacWindowChrome(
                title: "SELECT_ITEMS // \(items.count) detected",
                detail: "\(selectedCount) selected"
            ) {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(PluckTheme.terminalMuter)
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: PluckTheme.Spacing.sm) {
                    ForEach(items.indices, id: \.self) { index in
                        itemCard(index: index)
                    }
                }
                .padding(PluckTheme.Spacing.md)
            }

            Divider()
                .background(PluckTheme.terminalMuter.opacity(0.3))

            HStack(spacing: PluckTheme.Spacing.sm) {
                Text("\(selectedCount) of \(items.count) item\(items.count == 1 ? "" : "s") selected")
                    .font(.caption.monospaced())
                    .foregroundStyle(PluckTheme.secondaryText)

                Spacer()

                Button("Cancel") { onCancel() }
                    .buttonStyle(.bordered)

                Button(
                    selectedCount == 0
                        ? "Select items"
                        : "Upload \(selectedCount) item\(selectedCount == 1 ? "" : "s")"
                ) {
                    let selected = items.filter(\.isSelected)
                    guard !selected.isEmpty else { return }
                    onUpload(selected)
                }
                .buttonStyle(.borderedProminent)
                .tint(PluckTheme.accent)
                .foregroundStyle(.black)
                .disabled(selectedCount == 0)
            }
            .padding(PluckTheme.Spacing.md)
            .background(PluckTheme.terminalPanel)
        }
        .background(PluckTheme.background)
        .frame(width: 540, height: 500)
    }

    @ViewBuilder
    private func itemCard(index: Int) -> some View {
        let item = items[index]
        Button {
            items[index].isSelected.toggle()
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 8) {
                    if let nsImage = NSImage(data: item.imageData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
                    }
                    Text(item.label.uppercased())
                        .font(.caption2.monospaced())
                        .foregroundStyle(item.isSelected ? PluckTheme.primaryText : PluckTheme.secondaryText)
                        .lineLimit(1)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: PluckTheme.Radius.medium)
                        .fill(item.isSelected ? PluckTheme.accent.opacity(0.08) : PluckTheme.terminalPanel)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PluckTheme.Radius.medium)
                        .stroke(item.isSelected ? PluckTheme.accent : Color.clear, lineWidth: 2)
                )

                // Checkmark badge
                ZStack {
                    Circle()
                        .fill(item.isSelected ? PluckTheme.accent : PluckTheme.terminalPanel)
                        .frame(width: 22, height: 22)
                    Circle()
                        .stroke(PluckTheme.terminalMuter.opacity(0.4), lineWidth: 1)
                        .frame(width: 22, height: 22)
                    if item.isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.black)
                    }
                }
                .padding(8)
            }
        }
        .buttonStyle(.plain)
    }
}

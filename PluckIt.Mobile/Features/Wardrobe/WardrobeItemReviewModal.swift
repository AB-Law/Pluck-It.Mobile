import SwiftUI

struct WardrobeItemReviewModal: View {
    @EnvironmentObject private var appServices: AppServices
    let item: ClothingItem
    @Environment(\.dismiss) private var dismiss
    @State private var errorText: String?
    @State private var isLogging = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Metadata") {
                    Text("Brand: \(fallbackText(item.brand))")
                    Text("Category: \(fallbackText(item.category))")
                    Text("Condition: \(fallbackText(item.condition))")
                    if let price = item.price?.amount {
                        Text("Estimated price: \(String(format: "%.2f", price))")
                    }
                    Text("Wears: \(item.wearCount ?? 0)")
                }

                Section("Item") {
                    if let notes = item.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Notes")
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(PluckTheme.secondaryText)
                    }
                    if let size = item.size?.letter, !size.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Size: \(size)")
                    }
                }

                if let tags = item.tags, !tags.isEmpty {
                    Section("Tags") {
                        Text(tags.joined(separator: ", "))
                    }
                }

                Section {
                    if isLogging {
                        ProgressView("Updating wear")
                    } else {
                        Button("Log wear") {
                            Task {
                                await logWear()
                            }
                        }
                        .foregroundStyle(PluckTheme.primaryText)
                    }
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .foregroundStyle(PluckTheme.danger)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(item.brand ?? "Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func logWear() async {
        guard !isLogging else { return }
        isLogging = true
        do {
            try await appServices.wardrobeService.logWear(item.id)
            dismiss()
        } catch {
            errorText = String(describing: error)
        }
        isLogging = false
    }
}

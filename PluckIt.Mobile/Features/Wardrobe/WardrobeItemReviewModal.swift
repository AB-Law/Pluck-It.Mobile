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
                Section("Item") {
                    Text("Brand: \(item.brand ?? "—")")
                    Text("Category: \(item.category ?? "—")")
                    Text("Condition: \(item.condition ?? "—")")
                }
                if let tags = item.tags, !tags.isEmpty {
                    Section("Tags") {
                        Text(tags.joined(separator: ", "))
                    }
                }
                if isLogging {
                    ProgressView("Updating wear")
                } else {
                    Button("Log wear") {
                        Task {
                            await logWear()
                        }
                    }
                }
                if let errorText {
                    Section {
                        Text(errorText)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(item.brand ?? "Item")
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

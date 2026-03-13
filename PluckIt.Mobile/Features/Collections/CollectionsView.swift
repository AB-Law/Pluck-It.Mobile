import SwiftUI

struct CollectionsView: View {
    @EnvironmentObject private var appServices: AppServices
    @State private var collections: [Collection] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var isCreating = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            Group {
                if loading && collections.isEmpty {
                    ProgressView("Loading collections")
                } else if let errorText {
                    VStack(spacing: 12) {
                        Text("Could not read collections")
                            .foregroundStyle(.red)
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(PluckTheme.muted)
                        Button("Retry") {
                            Task { await loadCollections() }
                        }
                    }
                } else {
                    List(collections) { collection in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(collection.name.isEmpty ? "Untitled collection" : collection.name)
                                .font(.headline)
                            Text(collection.description ?? "No description")
                                .font(.caption)
                                .foregroundStyle(PluckTheme.muted)
                            Text("Public: \(collection.isPublic ? "Yes" : "No")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Collections")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isCreating = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task { await loadCollections() }
            .sheet(isPresented: $isCreating) {
                NavigationStack {
                    Form {
                        Section("Create collection") {
                            TextField("Name", text: $newName)
                                .textInputAutocapitalization(.words)
                            Button("Create") {
                                Task {
                                    await createCollection()
                                    isCreating = false
                                }
                            }
                            .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .navigationTitle("New Collection")
                }
            }
        }
    }

    private func loadCollections() async {
        loading = true
        errorText = nil
        do {
            collections = try await appServices.collectionService.fetchCollections()
        } catch {
            errorText = String(describing: error)
        }
        loading = false
    }

    private func createCollection() async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let request = CreateCollectionRequest(name: trimmed, isPublic: true, description: nil)
            _ = try await appServices.collectionService.createCollection(request)
            newName = ""
            await loadCollections()
        } catch {
            errorText = String(describing: error)
        }
    }
}

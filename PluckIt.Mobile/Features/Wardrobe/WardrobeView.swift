import SwiftUI

struct WardrobeView: View {
    @EnvironmentObject private var appServices: AppServices
    @State private var items: [ClothingItem] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var nextToken: String?
    @State private var selectedItem: ClothingItem?
    
    private var isLoadingMore: Bool {
        loading && !items.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading && items.isEmpty {
                    ProgressView("Loading wardrobe")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorText {
                    ScrollView {
                        VStack(spacing: 12) {
                            Text("Wardrobe unavailable")
                                .font(.headline)
                                .foregroundStyle(.red)
                            Text(errorText)
                                .font(.caption)
                                .foregroundStyle(PluckTheme.muted)
                            Button("Retry") {
                                Task { await loadItems(refresh: true) }
                            }
                        }
                        .padding()
                    }
                } else if items.isEmpty {
                    VStack(spacing: 8) {
                        Text("No wardrobe items yet")
                            .font(.headline)
                        Text("Sign in and sync your wardrobe service.")
                            .foregroundStyle(PluckTheme.muted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(items) { item in
                            WardrobeCardView(item: item)
                                .onTapGesture {
                                    selectedItem = item
                                }
                        }
                        if isLoadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else if nextToken != nil {
                            Button("Load more") {
                                Task { await loadItems() }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Wardrobe")
            .background(PluckTheme.background)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                if items.isEmpty {
                    await loadItems(refresh: true)
                }
            }
            .refreshable {
                await refresh()
            }
            .sheet(item: $selectedItem) { item in
                WardrobeItemReviewModal(item: item)
            }
        }
    }

    private func refresh() async {
        await loadItems(refresh: true)
    }

    private func loadItems(refresh: Bool = false) async {
        guard !loading else { return }
        loading = true
        if refresh {
            nextToken = nil
            items = []
        }
        do {
            let response = try await appServices.wardrobeService.fetchItems(
                page: 1,
                pageSize: 30,
                continuationToken: nextToken,
                search: nil
            )
            if refresh {
                items = response.items
            } else {
                items += response.items
            }
            nextToken = response.nextContinuationToken
            errorText = nil
        } catch {
            errorText = "Data could not be read since it isnt correct format: \(error)"
        }
        loading = false
    }
}

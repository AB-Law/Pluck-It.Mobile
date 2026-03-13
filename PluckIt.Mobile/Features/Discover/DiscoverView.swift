import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var appServices: AppServices
    @State private var sourceCount = "Loading..."
    @State private var feedItems: [ScrapedItem] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var request = DiscoverFeedQuery()

    var body: some View {
        NavigationStack {
            Group {
                if loading && feedItems.isEmpty {
                    ProgressView("Loading discover")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorText {
                    VStack(spacing: 12) {
                        Text("Discover request failed")
                            .foregroundStyle(.red)
                        Text(errorText)
                            .foregroundStyle(PluckTheme.muted)
                            .font(.caption)
                        Button("Retry") {
                            Task { await loadFeed() }
                        }
                    }
                    .padding()
                } else if feedItems.isEmpty {
                    VStack {
                        Text("No cards yet")
                            .foregroundStyle(PluckTheme.muted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(feedItems) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.title ?? "Untitled")
                                .font(.headline)
                            Text(item.brand ?? "Unknown brand")
                                .foregroundStyle(PluckTheme.muted)
                                .font(.subheadline)
                            if let urlString = item.imageUrl, let url = URL(string: urlString) {
                                AsyncImage(url: url) { image in
                                    image.resizable().scaledToFit()
                                } placeholder: {
                                    Color.gray.opacity(0.2).frame(height: 160)
                                }
                                .frame(height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            Text(item.displayPriceText ?? item.priceText ?? "")
                                .font(.caption)
                                .foregroundStyle(PluckTheme.accent)
                            Text(item.displaySourceName ?? item.source?.name ?? "Unknown source")
                                .font(.caption2)
                                .foregroundStyle(PluckTheme.muted)
                        }
                        .padding(.vertical, 6)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Discover")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sources: \(sourceCount)") {
                        Task { await loadSources() }
                    }
                    .font(.caption2)
                }
            }
            .task {
                await loadSources()
                await loadFeed()
            }
            .refreshable {
                await loadFeed()
            }
        }
    }

    private func loadSources() async {
        do {
            let sources = try await appServices.discoverService.fetchSources()
            sourceCount = "\(sources.count)"
        } catch {
            sourceCount = "unavailable"
        }
    }

    private func loadFeed() async {
        loading = true
        errorText = nil
        do {
            let response = try await appServices.discoverService.fetchFeed(request)
            feedItems = response.items
            request.continuationToken = response.nextContinuationToken
        } catch {
            errorText = String(describing: error)
        }
        loading = false
    }
}

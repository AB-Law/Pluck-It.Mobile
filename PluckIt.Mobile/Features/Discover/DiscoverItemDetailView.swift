import SwiftUI

struct DiscoverItemDetailView: View {
    @EnvironmentObject private var appServices: AppServices
    @Environment(\.dismiss) private var dismiss

    let item: ScrapedItem
    let sources: [ScraperSource]

    @State private var currentImageIndex = 0
    @State private var votedSignal: String?
    @State private var isCommentsExpanded = false
    @State private var showFeedbackError = false

    private var allImages: [String] {
        var images: [String] = []
        if let gallery = item.galleryImages, !gallery.isEmpty {
            images = gallery
        } else if let url = item.imageUrl {
            images = [url]
        }
        return images
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PluckTheme.Spacing.md) {
                    gallerySection
                        .pluckReveal(delay: 0.02)
                    metaSection
                        .pluckReveal(delay: 0.04)
                    if let links = item.buyLinks, !links.isEmpty {
                        buyLinksSection(links)
                            .pluckReveal(delay: 0.06)
                    }
                    if let comments = item.commentText, !comments.isEmpty {
                        commentsSection(comments)
                            .pluckReveal(delay: 0.08)
                    }
                }
                .padding(.bottom, PluckTheme.Spacing.xl)
            }
            .background(PluckTheme.background)
            .navigationTitle(item.title ?? "Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        pluckImpactFeedback()
                        dismiss()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .alert("Unable to send feedback", isPresented: $showFeedbackError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Could not send feedback right now. Please try again.")
            }
            .background(PluckTheme.background)
        }
    }

    private var gallerySection: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $currentImageIndex) {
                ForEach(Array(allImages.enumerated()), id: \.offset) { index, urlString in
                    AsyncImage(url: URL(string: urlString)) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                        case .empty:
                            Rectangle().fill(PluckTheme.card)
                                .overlay(ProgressView().tint(PluckTheme.primaryText))
                        default:
                            Rectangle().fill(PluckTheme.card)
                                .overlay(Image(systemName: "photo").foregroundStyle(PluckTheme.secondaryText))
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 320)
            .onChange(of: currentImageIndex) {
                votedSignal = nil
            }

            VStack(spacing: 0) {
                HStack {
                    if allImages.count > 1 {
                        Button {
                            withAnimation { currentImageIndex = max(0, currentImageIndex - 1) }
                        } label: {
                            Image(systemName: "chevron.left")
                                .padding(8)
                                .background(.black.opacity(0.5))
                                .clipShape(Circle())
                                .foregroundStyle(.white)
                        }
                        Spacer()
                        Button {
                            withAnimation { currentImageIndex = min(allImages.count - 1, currentImageIndex + 1) }
                        } label: {
                            Image(systemName: "chevron.right")
                                .padding(8)
                                .background(.black.opacity(0.5))
                                .clipShape(Circle())
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.horizontal, PluckTheme.Spacing.md)

                HStack(spacing: PluckTheme.Spacing.sm) {
                    if allImages.count > 1 {
                        HStack(spacing: 4) {
                            ForEach(0..<allImages.count, id: \.self) { idx in
                                Circle()
                                    .fill(idx == currentImageIndex ? Color.white : Color.white.opacity(0.4))
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(.black.opacity(0.4))
                        .clipShape(Capsule())
                    }

                    Spacer()

                    feedbackButtons
                }
                .padding(.horizontal, PluckTheme.Spacing.md)
                .padding(.bottom, PluckTheme.Spacing.sm)
            }
        }
    }

    private var feedbackButtons: some View {
        HStack(spacing: PluckTheme.Spacing.sm) {
            Button {
                pluckImpactFeedback()
                sendFeedback("up")
            } label: {
                Image(systemName: votedSignal == "up" ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .foregroundStyle(votedSignal == "up" ? PluckTheme.success : .white)
                    .padding(8)
                    .background(.black.opacity(0.5))
                    .clipShape(Circle())
            }
            Button {
                pluckImpactFeedback()
                sendFeedback("down")
            } label: {
                Image(systemName: votedSignal == "down" ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .foregroundStyle(votedSignal == "down" ? PluckTheme.danger : .white)
                    .padding(8)
                    .background(.black.opacity(0.5))
                    .clipShape(Circle())
            }
        }
    }

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: PluckTheme.Spacing.sm) {
            if let brand = item.brand, !brand.isEmpty {
                Text(brand)
                    .font(.caption)
                    .foregroundStyle(PluckTheme.mutedText)
            }

            Text(item.title ?? "Untitled")
                .font(.title3.weight(.semibold))
                .foregroundStyle(PluckTheme.primaryText)

            Text(item.resolvedSourceName(from: sources))
                .font(.caption)
                .foregroundStyle(PluckTheme.secondaryText)

            if let price = item.displayPriceText ?? item.priceText {
                Text(price)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PluckTheme.info)
            }

            if let tags = item.tags, !tags.isEmpty {
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
                }
            }

            if let productUrl = item.productUrl ?? item.displayDetailUrl, let url = URL(string: productUrl) {
                Link(destination: url) {
                    Label("View original", systemImage: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(PluckTheme.info)
                }
            }
        }
        .padding(.horizontal, PluckTheme.Spacing.md)
    }

    private func buyLinksSection(_ links: [BuyLink]) -> some View {
        VStack(alignment: .leading, spacing: PluckTheme.Spacing.sm) {
            Text("Buy")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PluckTheme.primaryText)
                .padding(.horizontal, PluckTheme.Spacing.md)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PluckTheme.Spacing.sm) {
                    ForEach(links, id: \.url) { link in
                        if let url = URL(string: link.url) {
                            Link(destination: url) {
                                Text(link.label ?? link.platform ?? "Shop")
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(PluckTheme.accent)
                                    .foregroundStyle(PluckTheme.background)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                .padding(.horizontal, PluckTheme.Spacing.md)
            }
        }
    }

    private func commentsSection(_ comments: String) -> some View {
        VStack(alignment: .leading, spacing: PluckTheme.Spacing.sm) {
            Button {
                pluckImpactFeedback(.light)
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCommentsExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("Top Comments")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PluckTheme.primaryText)
                    Spacer()
                    Image(systemName: isCommentsExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(PluckTheme.secondaryText)
                }
                .padding(.horizontal, PluckTheme.Spacing.md)
            }
            .buttonStyle(.plain)

            if isCommentsExpanded {
                Text(comments)
                    .font(.caption)
                    .foregroundStyle(PluckTheme.secondaryText)
                    .padding(.horizontal, PluckTheme.Spacing.md)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, PluckTheme.Spacing.xs)
        .background(PluckTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
        .padding(.horizontal, PluckTheme.Spacing.md)
    }

    private func sendFeedback(_ signal: String) {
        let previousSignal = votedSignal
        let imageIndex = allImages.count > 1 ? currentImageIndex : nil
        votedSignal = signal
        Task {
            do {
                try await appServices.discoverService.sendFeedback(itemId: item.id, signal: signal, galleryImageIndex: imageIndex)
            } catch {
                await MainActor.run {
                    votedSignal = previousSignal
                    showFeedbackError = true
                }
            }
        }
    }
}

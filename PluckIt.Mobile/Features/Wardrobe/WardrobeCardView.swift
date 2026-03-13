import SwiftUI

struct WardrobeCardView: View {
    let item: ClothingItem

    private var displayTitle: String {
        let trimmed = item.brand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    private var displayCategory: String {
        let trimmed = item.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Uncategorized" : trimmed
    }

    private var wearCountText: String {
        if let count = item.wearCount {
            return "\(count)"
        }
        return "0"
    }

    private var wearCountLabel: String {
        "\(wearCountText) wear" + (item.wearCount == 1 ? "" : "s")
    }

    private var displayImageURL: URL? {
        if let imageUrl = item.imageUrl, let url = normalizedImageURL(imageUrl) {
            return url
        }
        return normalizedImageURL(item.rawImageBlobUrl)
    }

    private var shortTags: String {
        guard let tags = item.tags, !tags.isEmpty else { return "No tags" }
        if tags.count <= 2 {
            return tags.joined(separator: ", ")
        }
        return "\(tags.prefix(2).joined(separator: ", ")) +"
    }

    private var statusLine: String {
        [displayCategory, wearCountLabel]
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: PluckTheme.Spacing.md) {
            AsyncImage(url: displayImageURL) { phase in
                switch phase {
                case .empty:
                    RoundedRectangle(cornerRadius: PluckTheme.Radius.small)
                        .fill(PluckTheme.card)
                        .overlay {
                            ProgressView()
                                .tint(PluckTheme.primaryText)
                        }
                        .frame(width: 92, height: 92)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 92, height: 92)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
                case .failure:
                    RoundedRectangle(cornerRadius: PluckTheme.Radius.small)
                        .fill(PluckTheme.card)
                        .overlay {
                            VStack(spacing: PluckTheme.Spacing.xs) {
                                Image(systemName: "photo")
                                Text("No image")
                            }
                            .foregroundStyle(PluckTheme.secondaryText)
                            .font(.caption2)
                        }
                        .frame(width: 92, height: 92)
                @unknown default:
                    EmptyView()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PluckTheme.title)
                    .lineLimit(1)

                Text(statusLine)
                    .font(.caption2)
                    .foregroundStyle(PluckTheme.secondaryText)
                    .lineLimit(1)

                Text(shortTags)
                    .font(.caption2)
                    .foregroundStyle(item.tags?.isEmpty == false ? PluckTheme.secondaryText : PluckTheme.mutedText)
                    .lineLimit(1)
                if let category = item.category, !category.isEmpty {
                    Text(category.uppercased())
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(PluckTheme.accent)
                        .textCase(.uppercase)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(PluckTheme.card)
                        .clipShape(Capsule())
                }
            }
            .padding(.vertical, PluckTheme.Spacing.xxs)
            Spacer()
        }
        .padding(PluckTheme.Spacing.md)
        .background(PluckTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
        .overlay(
            RoundedRectangle(cornerRadius: PluckTheme.Radius.small)
                .stroke(PluckTheme.border, lineWidth: 1)
        )
    }
}

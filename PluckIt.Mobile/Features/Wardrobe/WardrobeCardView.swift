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

    private var displayImageURL: URL? {
        if let imageUrl = item.imageUrl, let url = normalizedImageURL(imageUrl) {
            return url
        }
        return normalizedImageURL(item.rawImageBlobUrl)
    }

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: displayImageURL) { phase in
                switch phase {
                case .empty:
                    RoundedRectangle(cornerRadius: 12)
                        .fill(PluckTheme.card)
                        .overlay {
                            ProgressView()
                        }
                        .frame(width: 88, height: 88)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 88, height: 88)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                case .failure:
                    RoundedRectangle(cornerRadius: 12)
                        .fill(PluckTheme.card)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 88, height: 88)
                @unknown default:
                    EmptyView()
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(displayTitle)
                    .font(.headline)
                    .foregroundStyle(PluckTheme.title)
                    .lineLimit(1)
                Text(displayCategory)
                    .font(.subheadline)
                    .foregroundStyle(PluckTheme.muted)
                    .lineLimit(1)
                Text("Worn: \(wearCountText)")
                    .font(.caption)
                    .foregroundStyle(PluckTheme.muted)
                if let tags = item.tags, !tags.isEmpty {
                    Text(tags.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

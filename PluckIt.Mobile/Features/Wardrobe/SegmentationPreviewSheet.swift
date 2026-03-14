import SwiftUI

struct SegmentationPreviewSheet: View {
    let originalData: Data
    let segmentedData: Data
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    HStack(spacing: 16) {
                        imageCard(data: originalData, label: "Original")
                        imageCard(data: segmentedData, label: "Segmented")
                    }
                    .padding(.horizontal)

                    if let original = UIImage(data: originalData),
                       let segmented = UIImage(data: segmentedData) {
                        statsView(original: original, segmented: segmented)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Segmentation Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func imageCard(data: Data, label: String) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(3/4, contentMode: .fit)
                    .overlay(Text("No image").foregroundStyle(.secondary))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func statsView(original: UIImage, segmented: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DEBUG INFO")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 4) {
                statRow("Original size", value: sizeString(originalData))
                statRow("Segmented size", value: sizeString(segmentedData))
                statRow("Original px", value: "\(Int(original.size.width))×\(Int(original.size.height))")
                statRow("Segmented px", value: "\(Int(segmented.size.width))×\(Int(segmented.size.height))")
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospaced())
        }
    }

    private func sizeString(_ data: Data) -> String {
        let kb = Double(data.count) / 1024
        return kb < 1024 ? String(format: "%.1f KB", kb) : String(format: "%.1f MB", kb / 1024)
    }
}

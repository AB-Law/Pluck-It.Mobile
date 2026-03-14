import Foundation
import Vision
import UIKit
import CoreImage

enum ClothingSegmentationService {

    /// Segments clothing from an image into individual items for user selection.
    /// - Person detected: SegFormer per-category items (jacket, jeans, shoes…)
    /// - Flat-lay: single item from VNGenerateForegroundInstanceMaskRequest
    /// - Fallback: single item wrapping the original image
    static func segmentIntoItems(imageData: Data) async -> [SegmentedClothingItem] {
        guard let uiImage = UIImage(data: imageData),
              let cgImage = uiImage.cgImage else {
            return fallback(imageData: imageData)
        }

        let orientation = CGImagePropertyOrientation(uiImage.imageOrientation)
        let oriented = orientedCGImage(cgImage, orientation: uiImage.imageOrientation)

        // 1. Fast person detection gate
        if await detectPerson(in: cgImage, orientation: orientation) {
            if let items = try? await HumanParsingSegmenter.segmentIntoItems(cgImage: oriented), !items.isEmpty {
                return items
            }
        }

        // 2. Flat-lay foreground mask
        if #available(iOS 17.0, *),
           let masked = try? foregroundMask(cgImage: cgImage, orientation: orientation),
           let data = masked.pngData() ?? masked.jpegData(compressionQuality: 0.9) {
            return [SegmentedClothingItem(labelID: -1, label: "Clothing", imageData: data)]
        }

        return fallback(imageData: imageData)
    }

    private static func fallback(imageData: Data) -> [SegmentedClothingItem] {
        [SegmentedClothingItem(labelID: -1, label: "Clothing", imageData: imageData)]
    }

    // MARK: - Person detection

    private static func detectPerson(in cgImage: CGImage, orientation: CGImagePropertyOrientation) async -> Bool {
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = false
        guard let _ = try? handler.perform([request]),
              let results = request.results else { return false }
        return results.contains { $0.confidence > 0.25 }
    }

    // MARK: - Flat-lay foreground mask (iOS 17+)

    @available(iOS 17.0, *)
    private static func foregroundMask(cgImage: CGImage, orientation: CGImagePropertyOrientation) throws -> UIImage? {
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])

        guard let observation = request.results?.first else { return nil }

        let pixelBuffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances,
            from: handler,
            croppedToInstancesExtent: false
        )

        let ciMasked = CIImage(cvPixelBuffer: pixelBuffer)
        let ciContext = CIContext()
        guard let maskedCG = ciContext.createCGImage(ciMasked, from: ciMasked.extent) else { return nil }

        let outputSize = CGSize(width: ciMasked.extent.width, height: ciMasked.extent.height)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1

        return UIGraphicsImageRenderer(size: outputSize, format: format).image { ctx in
            ctx.cgContext.translateBy(x: 0, y: outputSize.height)
            ctx.cgContext.scaleBy(x: 1, y: -1)
            ctx.cgContext.draw(maskedCG, in: CGRect(origin: .zero, size: outputSize))
        }
    }

    // MARK: - Orientation helpers

    /// Returns a CGImage with EXIF orientation baked in (so Core ML sees upright pixels).
    private static func orientedCGImage(_ cgImage: CGImage, orientation: UIImage.Orientation) -> CGImage {
        guard orientation != .up else { return cgImage }
        let uiImage = UIImage(cgImage: cgImage, scale: 1, orientation: orientation)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let size = CGSize(width: uiImage.size.width, height: uiImage.size.height)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let redrawn = renderer.image { _ in uiImage.draw(in: CGRect(origin: .zero, size: size)) }
        return redrawn.cgImage ?? cgImage
    }
}

// MARK: - CGImagePropertyOrientation convenience

private extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up:            self = .up
        case .down:          self = .down
        case .left:          self = .left
        case .right:         self = .right
        case .upMirrored:    self = .upMirrored
        case .downMirrored:  self = .downMirrored
        case .leftMirrored:  self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default:    self = .up
        }
    }
}

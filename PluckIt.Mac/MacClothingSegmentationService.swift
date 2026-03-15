import Foundation
import Vision
import AppKit
import CoreImage
import UniformTypeIdentifiers

/// macOS port of ClothingSegmentationService.
///
/// Uses Vision framework foreground masking instead of the SegFormer CoreML model
/// (which lives in the iOS app bundle). Produces one SegmentedClothingItem per
/// detected foreground instance, or falls back to the original image.
enum MacClothingSegmentationService {

    /// Segments clothing from image data into individual items for user selection.
    /// - Foreground mask (macOS 14+): removes background via VNGenerateForegroundInstanceMaskRequest
    /// - Fallback: single item wrapping the original image
    static func segmentIntoItems(imageData: Data) async -> [SegmentedClothingItem] {
        guard let nsImage = NSImage(data: imageData),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return fallback(imageData: imageData)
        }

        if #available(macOS 14.0, *),
           let masked = try? foregroundMask(cgImage: cgImage),
           let data = pngData(from: masked) {
            return [SegmentedClothingItem(labelID: -1, label: "Clothing", imageData: data)]
        }

        return fallback(imageData: imageData)
    }

    // MARK: - Private

    private static func fallback(imageData: Data) -> [SegmentedClothingItem] {
        [SegmentedClothingItem(labelID: -1, label: "Clothing", imageData: imageData)]
    }

    @available(macOS 14.0, *)
    private static func foregroundMask(cgImage: CGImage) throws -> CGImage? {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])

        guard let observation = request.results?.first else { return nil }

        let pixelBuffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances,
            from: handler,
            croppedToInstancesExtent: false
        )

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        return context.createCGImage(ciImage, from: ciImage.extent)
    }

    private static func pngData(from cgImage: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}

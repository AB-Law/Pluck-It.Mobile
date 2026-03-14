import Foundation
import Vision
import UIKit
import CoreImage

enum ClothingSegmentationService {

    /// Segments clothing from an image.
    /// - If a person is detected: uses SegFormer-B2-Clothes (Core ML) to extract only garment pixels.
    /// - If no person (flat-lay): uses VNGenerateForegroundInstanceMaskRequest (iOS 17+).
    /// Falls back to the original image on any failure.
    static func segment(imageData: Data) async throws -> Data {
        guard let uiImage = UIImage(data: imageData),
              let cgImage = uiImage.cgImage else { return imageData }

        let orientation = CGImagePropertyOrientation(uiImage.imageOrientation)

        // 1. Fast person detection gate (~15ms)
        if await detectPerson(in: cgImage, orientation: orientation) {
            // 2a. Human parsing path — clothing-only segmentation
            if let result = try? await HumanParsingSegmenter.segment(cgImage: orientedCGImage(cgImage, orientation: uiImage.imageOrientation)) {
                return result.jpegData(compressionQuality: 0.9) ?? imageData
            }
        }

        // 2b. Flat-lay path — generic foreground mask (iOS 17+)
        if #available(iOS 17.0, *) {
            if let result = try? foregroundMask(cgImage: cgImage, orientation: orientation) {
                return result.jpegData(compressionQuality: 0.9) ?? imageData
            }
        }

        return imageData
    }

    // MARK: - Person detection

    private static func detectPerson(in cgImage: CGImage, orientation: CGImagePropertyOrientation) async -> Bool {
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = false
        guard let _ = try? handler.perform([request]),
              let results = request.results else { return false }
        return results.contains { $0.confidence > 0.5 }
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
        format.opaque = true
        format.scale = 1

        return UIGraphicsImageRenderer(size: outputSize, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: outputSize))
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

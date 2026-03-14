import Foundation
import Vision
import UIKit
import CoreImage

enum ClothingSegmentationService {

    /// Segments the foreground subject(s) from the image and composites them onto a white background.
    /// Requires iOS 17+. Falls back to the original data on older OS or on any failure.
    static func segment(imageData: Data) async throws -> Data {
        guard #available(iOS 17.0, *) else { return imageData }

        guard let uiImage = UIImage(data: imageData),
              let cgImage = uiImage.cgImage else { return imageData }

        // Pass EXIF orientation so Vision operates in the correct coordinate space.
        let orientation = CGImagePropertyOrientation(uiImage.imageOrientation)
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()

        try handler.perform([request])

        guard let observation = request.results?.first else { return imageData }

        let pixelBuffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances,
            from: handler,
            croppedToInstancesExtent: false
        )

        // Render masked image over a white background into an opaque RGB context
        // to avoid carrying an alpha channel into the JPEG output.
        let ciMasked = CIImage(cvPixelBuffer: pixelBuffer)
        let ciContext = CIContext()
        guard let maskedCG = ciContext.createCGImage(ciMasked, from: ciMasked.extent) else {
            return imageData
        }

        let outputSize = CGSize(width: ciMasked.extent.width, height: ciMasked.extent.height)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true   // RGB — no alpha channel
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
        let result = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: outputSize))
            // CIImage origin is bottom-left; flip vertically when drawing into UIKit context
            ctx.cgContext.translateBy(x: 0, y: outputSize.height)
            ctx.cgContext.scaleBy(x: 1, y: -1)
            ctx.cgContext.draw(maskedCG, in: CGRect(origin: .zero, size: outputSize))
        }

        return result.jpegData(compressionQuality: 0.9) ?? imageData
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

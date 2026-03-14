import CoreML
import UIKit

/// Runs SegFormer-B2-Clothes on-device to extract clothing pixels from a person photo.
enum HumanParsingSegmenter {

    private static let clothingLabelIDs: Set<Int> = [4, 5, 6, 7, 8, 9, 10, 16, 17]
    private static let modelInputSize = 512

    private static let mean: [Float] = [0.485, 0.456, 0.406]
    private static let std:  [Float] = [0.229, 0.224, 0.225]

    private static let model: MLModel? = {
        guard let compiledURL = Bundle.main.url(forResource: "SegFormerClothes", withExtension: "mlmodelc") else {
            print("[Segmenter] ❌ SegFormerClothes.mlmodelc not found.")
            return nil
        }
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndGPU
            print("[Segmenter] ✅ Model loaded successfully.")
            return try MLModel(contentsOf: compiledURL, configuration: config)
        } catch {
            print("[Segmenter] ❌ Failed to load model: \(error)")
            return nil
        }
    }()

    static func segment(cgImage: CGImage) async throws -> UIImage {
        print("\n--- [Segmenter] Starting Segmentation ---")
        print("[Segmenter] Original image size: \(cgImage.width)x\(cgImage.height)")
        
        guard let model else { throw SegmentationError.modelNotFound }
        
        let side = modelInputSize

        // 1. Prepare Input
        print("[Segmenter] Preparing input array...")
        let inputArray = try makeInputArray(from: cgImage, targetSize: side)

        // 2. Predict
        print("[Segmenter] Running Core ML prediction...")
        let inputFeatures = try MLDictionaryFeatureProvider(dictionary: ["pixel_values": inputArray])
        let output = try await model.prediction(from: inputFeatures)

        guard let labelArray = output.featureValue(for: "label_map")?.multiArrayValue else {
            print("[Segmenter] ❌ Failed to decode label_map from output.")
            throw SegmentationError.outputDecodeFailed
        }
        print("[Segmenter] Prediction successful. Output shape: \(labelArray.shape)")

        // 3. Build Mask
        print("[Segmenter] Decoding mask from MLMultiArray...")
        let mask512 = buildClothingMask(from: labelArray, size: side)
        
        // --- DEBUG LOGGING: Print the mask to the console ---
        printAsciiMask(mask: mask512, size: side)

        // 4. Scale & Composite
        print("[Segmenter] Scaling mask and compositing final image...")
        let maskFull = scaleMask(mask512, from: side, toWidth: cgImage.width, toHeight: cgImage.height)
        let finalImage = composite(cgImage: cgImage, mask: maskFull, width: cgImage.width, height: cgImage.height)
        
        print("--- [Segmenter] Finished Segmentation ---\n")
        return finalImage
    }

    // MARK: - Private helpers

    private static func makeInputArray(from cgImage: CGImage, targetSize side: Int) throws -> MLMultiArray {
            let array = try MLMultiArray(shape: [1, 3, side as NSNumber, side as NSNumber], dataType: .float32)

            // Step A: STRICTLY FORMAT THE RENDERER
            // Force 1x scale and standard 8-bit color range (no 16-bit wide color)
            let renderSize = CGSize(width: side, height: side)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1.0
            format.opaque = true
            format.preferredRange = .standard
            
            let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)
            let normalizedImage = renderer.image { _ in
                UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: renderSize))
            }
            
            // Step B: Extract raw RGBA/BGRA bytes safely
            guard let normalizedCG = normalizedImage.cgImage,
                  let dataProvider = normalizedCG.dataProvider,
                  let pixelData = dataProvider.data else {
                throw SegmentationError.preprocessFailed
            }
            
            let rawBytes = CFDataGetBytePtr(pixelData)!
            let bytesPerRow = normalizedCG.bytesPerRow
            let bpp = normalizedCG.bitsPerPixel / 8 // Will now correctly be 4 bytes
            let bitmapInfo = normalizedCG.bitmapInfo

            print("[Segmenter] Normalized image created. BytesPerRow: \(bytesPerRow), BitmapInfo: \(bitmapInfo.rawValue)")

            // Handle iOS specific BGRA byte ordering
            let isBGRA = bitmapInfo.contains(.byteOrder32Little)

            let pixelCount = side * side
            let ptr = array.dataPointer.bindMemory(to: Float32.self, capacity: 3 * pixelCount)
            
            for y in 0..<side {
                for x in 0..<side {
                    let offset = y * bytesPerRow + x * bpp
                    
                    // Read colors based on memory layout
                    let rByte = isBGRA ? rawBytes[offset + 2] : rawBytes[offset]
                    let gByte = isBGRA ? rawBytes[offset + 1] : rawBytes[offset + 1]
                    let bByte = isBGRA ? rawBytes[offset]     : rawBytes[offset + 2]
                    
                    let r = Float(rByte) / 255.0
                    let g = Float(gByte) / 255.0
                    let b = Float(bByte) / 255.0
                    
                    let outIndex = y * side + x
                    ptr[0 * pixelCount + outIndex] = (r - mean[0]) / std[0]
                    ptr[1 * pixelCount + outIndex] = (g - mean[1]) / std[1]
                    ptr[2 * pixelCount + outIndex] = (b - mean[2]) / std[2]
                }
            }
            
            return array
        }

    private static func buildClothingMask(from labelArray: MLMultiArray, size: Int) -> [Bool] {
        var mask = [Bool](repeating: false, count: size * size)
        let strides = labelArray.strides
        let yStride = strides[strides.count - 2].intValue
        let xStride = strides[strides.count - 1].intValue
        let rawPtr = labelArray.dataPointer

        for y in 0..<size {
            for x in 0..<size {
                let linearIndex = y * yStride + x * xStride
                let classID: Int
                
                switch labelArray.dataType {
                case .float32: classID = Int(rawPtr.load(fromByteOffset: linearIndex * 4, as: Float32.self))
                case .float16: classID = Int(rawPtr.load(fromByteOffset: linearIndex * 2, as: Float16.self))
                case .int32:   classID = Int(rawPtr.load(fromByteOffset: linearIndex * 4, as: Int32.self))
                default:       return mask
                }

                mask[y * size + x] = clothingLabelIDs.contains(classID)
            }
        }
        return mask
    }
    
    /// Renders a low-res version of the 512x512 mask to the Xcode console
    private static func printAsciiMask(mask: [Bool], size: Int) {
        print("\n--- MASK ASCII PREVIEW (32x32) ---")
        let step = size / 32
        for y in stride(from: 0, to: size, by: step) {
            var rowString = ""
            for x in stride(from: 0, to: size, by: step) {
                // If the pixel is clothing, print a block. Otherwise print a dot.
                rowString += mask[y * size + x] ? "██" : ".."
            }
            print(rowString)
        }
        print("----------------------------------\n")
    }

    private static func scaleMask(_ mask: [Bool], from fromSize: Int, toWidth: Int, toHeight: Int) -> [Bool] {
        var result = [Bool](repeating: false, count: toWidth * toHeight)
        for y in 0..<toHeight {
            let srcY = y * fromSize / toHeight
            for x in 0..<toWidth {
                let srcX = x * fromSize / toWidth
                result[y * toWidth + x] = mask[srcY * fromSize + srcX]
            }
        }
        return result
    }

    private static func composite(cgImage: CGImage, mask: [Bool], width: Int, height: Int) -> UIImage {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            // Draw background
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            // Draw original image exactly as UIKit interprets it
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: size))

            // Punch out non-clothing
            UIColor.white.setFill()
            for y in 0..<height {
                var x = 0
                while x < width {
                    if !mask[y * width + x] {
                        var runEnd = x + 1
                        while runEnd < width && !mask[y * width + runEnd] { runEnd += 1 }
                        ctx.fill(CGRect(x: x, y: y, width: runEnd - x, height: 1))
                        x = runEnd
                    } else {
                        x += 1
                    }
                }
            }
        }
    }

    enum SegmentationError: Error {
        case modelNotFound
        case preprocessFailed
        case outputDecodeFailed
    }
}

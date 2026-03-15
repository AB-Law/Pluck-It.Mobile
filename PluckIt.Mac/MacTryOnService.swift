import Foundation
import AppKit

/// Sends try-on inference requests to the local CatVTON Flask server
/// managed by `MacTryOnSidecar`.
struct MacTryOnService {

    let port: Int

    // MARK: - Try-On

    /// Composites `garmentImageData` onto the person in `personImageData`.
    /// Returns raw PNG data of the result.
    func tryOn(
        personImageData: Data,
        garmentImageData: Data,
        clothType: ClothType = .upper,
        numSteps: Int = 50
    ) async throws -> Data {
        let url = URL(string: "http://127.0.0.1:\(port)/try-on")!
        var request = URLRequest(url: url)
        request.httpMethod      = "POST"
        request.timeoutInterval = 900  // 15 min — chunked attention is slower than native SDPA

        let boundary = "PluckBoundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendFormFile(name: "person_image",  data: personImageData,  filename: "person.png",  mime: "image/png",  boundary: boundary)
        body.appendFormFile(name: "garment_image", data: garmentImageData, filename: "garment.png", mime: "image/png",  boundary: boundary)
        body.appendFormText(name: "cloth_type",    value: clothType.rawValue, boundary: boundary)
        body.appendFormText(name: "num_steps",     value: "\(numSteps)",      boundary: boundary)
        body.append("--\(boundary)--\r\n".utf8Data)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw TryOnError.inferenceFailed(message)
        }

        return data
    }

    // MARK: - Download garment image from ClothingItem URL

    /// Fetches the processed clothing image from the CDN URL on the item.
    func downloadGarmentImage(from item: ClothingItem) async throws -> Data {
        let urlString = item.imageUrl ?? item.rawImageBlobUrl
        guard let urlString, let url = URL(string: urlString) else {
            throw TryOnError.inferenceFailed("Garment has no image URL.")
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }
}

// MARK: - ClothType

enum ClothType: String, CaseIterable, Identifiable {
    case upper   = "upper"
    case lower   = "lower"
    case overall = "overall"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .upper:   return "Upper"
        case .lower:   return "Lower"
        case .overall: return "Full outfit"
        }
    }
}

// MARK: - Multipart helpers

private extension Data {
    mutating func appendFormFile(name: String, data: Data, filename: String, mime: String, boundary: String) {
        append("--\(boundary)\r\n".utf8Data)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8Data)
        append("Content-Type: \(mime)\r\n\r\n".utf8Data)
        append(data)
        append("\r\n".utf8Data)
    }

    mutating func appendFormText(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n".utf8Data)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8Data)
        append(value.utf8Data)
        append("\r\n".utf8Data)
    }
}

private extension String {
    var utf8Data: Data { Data(utf8) }
}

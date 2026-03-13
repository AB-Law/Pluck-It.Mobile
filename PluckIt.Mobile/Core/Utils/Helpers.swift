import Foundation
import SwiftUI

/// Returns a shared fallback title value.
func fallbackText(_ text: String?) -> String {
    let normalized = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return normalized.isEmpty ? "—" : normalized
}

/// Image loading helper to normalize optional and empty image URLs.
func normalizedImageURL(_ value: String?) -> URL? {
    let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return cleaned.isEmpty ? nil : URL(string: cleaned)
}

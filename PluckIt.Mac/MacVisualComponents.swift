import SwiftUI
import AppKit

/// Container primitives used by all terminal-inspired Mac screens.
struct MacGlassPanel<Content: View>: View {
    let title: String?
    let subtitle: String?
    let content: Content

    init(title: String? = nil, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PluckTheme.Spacing.md) {
            if let title {
                HStack(alignment: .firstTextBaseline, spacing: PluckTheme.Spacing.xs) {
                    Text(title.uppercased())
                        .font(PluckTheme.Typography.terminalLabel)
                        .tracking(1.3)
                        .foregroundStyle(PluckTheme.terminalScanline)
                    Spacer()
                }
                if let subtitle {
                    Text(subtitle)
                        .font(PluckTheme.Typography.terminalBody)
                        .foregroundStyle(PluckTheme.secondaryText)
                }
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(PluckTheme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: PluckTheme.Radius.large)
                .fill(PluckTheme.terminalPanel.opacity(0.9))
                .overlay(
                    RoundedRectangle(cornerRadius: PluckTheme.Radius.large)
                        .stroke(PluckTheme.terminalBorder, lineWidth: 1)
                )
        )
    }
}

/// Title bar used in terminal-like sections and shell chrome.
struct MacWindowChrome: View {
    let title: String?
    let detail: String?
    let trailing: AnyView?

    init(title: String? = nil, detail: String? = nil, trailing: AnyView? = nil) {
        self.title = title
        self.detail = detail
        self.trailing = trailing
    }

    init<Trailing: View>(
        title: String? = nil,
        detail: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.detail = detail
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack(spacing: PluckTheme.Spacing.md) {
            HStack(spacing: PluckTheme.Spacing.xs) {
                Circle()
                    .fill(Color(red: 1.0, green: 0.32, blue: 0.26))
                    .frame(width: 10, height: 10)
                Circle()
                    .fill(Color(red: 1.0, green: 0.78, blue: 0.4))
                    .frame(width: 10, height: 10)
                Circle()
                    .fill(Color(red: 0.34, green: 0.78, blue: 0.35))
                    .frame(width: 10, height: 10)
            }

            if let title {
                Text(title)
                    .font(PluckTheme.Typography.terminalLabel)
                    .foregroundStyle(PluckTheme.primaryText)
                    .lineLimit(1)
            }

            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(PluckTheme.terminalMuter)
                    .lineLimit(1)
            }

            Spacer()

            trailing
        }
        .padding(PluckTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 0)
                .fill(PluckTheme.terminalPanel.opacity(0.88))
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(PluckTheme.border),
                    alignment: .bottom
                )
        )
    }
}

/// Generic status chip used for online/offline banners and badges.
struct MacStatusChip: View {
    let label: String
    let tone: ChipTone

    enum ChipTone {
        case success
        case warning
        case muted
        case info

        var color: Color {
            switch self {
            case .success:
                PluckTheme.terminalSuccess
            case .warning:
                PluckTheme.terminalWarning
            case .muted:
                PluckTheme.terminalMuter
            case .info:
                PluckTheme.terminalInfo
            }
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tone.color)
                .frame(width: 7, height: 7)
                .shadow(color: tone.color.opacity(0.8), radius: 6, x: 0, y: 0)
            Text(label)
                .font(.caption2)
                .tracking(1.1)
                .foregroundStyle(tone.color)
                .textCase(.uppercase)
        }
        .padding(.horizontal, PluckTheme.Spacing.sm)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 999)
                .fill(tone.color.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 999)
                .stroke(tone.color.opacity(0.5), lineWidth: 1)
        )
    }
}

/// Terminal-like card container with optional reveal animation.
struct MacStatCard: View {
    let title: String
    let value: String
    let tone: Color
    let delay: Double
    let bodyText: String?

    init(title: String, value: String, tone: Color = PluckTheme.primaryText, delay: Double = 0, bodyText: String? = nil) {
        self.title = title
        self.value = value
        self.tone = tone
        self.delay = delay
        self.bodyText = bodyText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption)
                .foregroundStyle(PluckTheme.terminalMuter)
                .tracking(0.9)

            Text(value)
                .font(PluckTheme.Typography.terminalHeadline)
                .foregroundStyle(tone)
                .lineLimit(2)
                .minimumScaleFactor(0.76)
                .fixedSize(horizontal: false, vertical: true)

            if let bodyText {
                Text(bodyText)
                    .font(.caption2)
                    .foregroundStyle(PluckTheme.secondaryText)
                    .lineLimit(2)
            }
        }
        .padding(PluckTheme.Spacing.md)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: PluckTheme.Radius.medium)
                .fill(PluckTheme.card.opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: PluckTheme.Radius.medium)
                        .stroke(PluckTheme.terminalBorder, lineWidth: 1)
                )
        )
        .pluckReveal(delay: delay, distance: 10, scale: 0.988)
    }
}

/// Repeating matrix scanline overlay for terminal screens.
struct MacScanlineOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            PluckTheme.terminalScanline.opacity(0.1),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: geometry.size.height)
                .mask(
                    VStack(spacing: 5) {
                        ForEach(0..<Int((geometry.size.height / 5).rounded()), id: \.self) { _ in
                            Rectangle()
                                .fill(Color.clear)
                                .frame(height: 1)
                            Rectangle()
                                .fill(Color.white.opacity(0.04))
                                .frame(height: 1)
                        }
                    }
                )
                .allowsHitTesting(false)
        }
    }
}

/// Floating terminal symbol motif for background depth.
struct MacBackgroundGlyph: View {
    let icon: String
    let size: CGFloat

    init(_ icon: String, size: CGFloat = 120) {
        self.icon = icon
        self.size = size
    }

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size))
            .foregroundStyle(PluckTheme.terminalMuter.opacity(0.16))
    }
}

/// Reusable sidebar row for desktop shell navigation.
struct MacShellRow: View {
    let title: String
    let icon: String
    let isSelected: Bool

    var body: some View {
        Label {
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
        }
        .foregroundStyle(isSelected ? PluckTheme.background : PluckTheme.primaryText)
        .padding(.horizontal, PluckTheme.Spacing.sm)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PluckTheme.Radius.medium)
                .fill(isSelected ? PluckTheme.accent.opacity(0.75) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Persistent image cache (memory + disk)

/// Two-level image cache: memory (NSCache) + disk (Caches directory).
///
/// - Uses djb2 hash for stable cache keys. Swift's String.hashValue is
///   randomised per app launch and must NOT be used for disk keys.
/// - Saves raw downloaded bytes — no re-encoding, no quality loss.
/// - Call evict(_:) when the server signals an image is gone (404).
final class ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSString, NSImage>()
    private let diskDir: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("PluckItImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {
        memory.countLimit = 300
        memory.totalCostLimit = 150 * 1024 * 1024
    }

    /// Synchronous memory-only check — safe to call from SwiftUI view init.
    func getMemory(_ url: URL) -> NSImage? {
        memory.object(forKey: stableKey(url) as NSString)
    }

    /// Memory → disk lookup. Promotes disk hit back into memory.
    func get(_ url: URL) -> NSImage? {
        let key = stableKey(url)
        if let img = memory.object(forKey: key as NSString) { return img }
        let file = diskDir.appendingPathComponent(key)
        guard let data = try? Data(contentsOf: file),
              let img = NSImage(data: data) else { return nil }
        memory.setObject(img, forKey: key as NSString)
        return img
    }

    /// Persist raw response bytes + decoded image. Never re-encodes.
    func set(data: Data, image: NSImage, for url: URL) {
        let key = stableKey(url)
        memory.setObject(image, forKey: key as NSString)
        try? data.write(to: diskDir.appendingPathComponent(key), options: .atomic)
    }

    /// Remove entry from both caches (call on 404 or explicit invalidation).
    func evict(_ url: URL) {
        let key = stableKey(url)
        memory.removeObject(forKey: key as NSString)
        try? FileManager.default.removeItem(at: diskDir.appendingPathComponent(key))
    }

    /// djb2 hash — deterministic across app launches, unlike Swift's hashValue.
    private func stableKey(_ url: URL) -> String {
        var h: UInt64 = 5381
        for byte in url.absoluteString.utf8 { h = h &* 31 &+ UInt64(byte) }
        return "\(h)"
    }
}

// MARK: - CachedAsyncImage

/// Drop-in replacement for AsyncImage with persistent memory + disk caching.
/// - First render: seeds phase from memory cache synchronously (no flash on tab switch).
/// - On url change: checks memory → disk → network in that order.
/// - Network hits are saved to disk and survive app restarts.
struct CachedAsyncImage<Content: View>: View {
    private let url: URL?
    private let content: (AsyncImagePhase) -> Content

    init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
    }

    var body: some View {
        if let url {
            CachedAsyncImageBody(url: url, content: content)
        } else {
            content(.empty)
        }
    }
}

private struct CachedAsyncImageBody<Content: View>: View {
    let url: URL
    let content: (AsyncImagePhase) -> Content

    // Seeded from memory cache in init so the very first rendered frame
    // already shows the correct image — zero flash on tab switch.
    @State private var phase: AsyncImagePhase

    init(url: URL, content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.content = content
        if let img = ImageCache.shared.getMemory(url) {
            _phase = State(initialValue: .success(Image(nsImage: img)))
        } else {
            _phase = State(initialValue: .empty)
        }
    }

    var body: some View {
        content(phase)
            .task(id: url) {
                // 1. Memory — instant (already set in init, but re-check for url changes)
                if let img = ImageCache.shared.getMemory(url) {
                    phase = .success(Image(nsImage: img))
                    return
                }
                // 2. Disk — fast, no network call needed
                if let img = ImageCache.shared.get(url) {
                    phase = .success(Image(nsImage: img))
                    return
                }
                // 3. Network — only on first ever load; result is persisted to disk
                phase = .empty
                do {
                    let (data, response) = try await URLSession.shared.data(from: url)
                    guard !Task.isCancelled else { return }
                    if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                        ImageCache.shared.evict(url)
                        phase = .failure(URLError(.fileDoesNotExist))
                        return
                    }
                    if let img = NSImage(data: data) {
                        ImageCache.shared.set(data: data, image: img, for: url)
                        withAnimation(.easeIn(duration: 0.1)) {
                            phase = .success(Image(nsImage: img))
                        }
                    } else {
                        phase = .failure(URLError(.cannotDecodeContentData))
                    }
                } catch {
                    if !Task.isCancelled { phase = .failure(error) }
                }
            }
    }
}

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - MacTryOnView

struct MacTryOnView: View {
    @EnvironmentObject private var appServices: AppServices
    @StateObject private var sidecar = MacTryOnSidecar.shared

    // Person
    @State private var personImageData: Data?

    // Garment picker
    @State private var garments:          [ClothingItem] = []
    @State private var selectedGarment:   ClothingItem?
    @State private var garmentFilter:     GarmentFilter = .all
    @State private var isLoadingGarments  = false
    @State private var loadError: String?

    // Inference
    @State private var clothType:         ClothType = .upper
    @State private var resultImageData:   Data?
    @State private var isRunning          = false
    @State private var runError:          String?

    // Drag state
    @State private var isTargeted         = false

    private var canRun: Bool {
        sidecar.state.isReady && personImageData != nil && selectedGarment != nil && !isRunning
    }

    var body: some View {
        VStack(spacing: 0) {
            MacWindowChrome(title: "TRY_ON_MATRIX", detail: sidecar.state.statusLine) {
                clothTypePicker
            }

            Group {
                if !sidecar.isSetupComplete && sidecar.state == .idle {
                    optInPanel
                } else {
                    HStack(spacing: PluckTheme.Spacing.xs) {
                        personPanel
                        garmentPanel
                        resultPanel
                    }
                    .padding(PluckTheme.Spacing.md)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            statusBar
        }
        .background(PluckTheme.background)
        .task { await sidecar.startIfNeeded() }   // no-op if setup not done
        .task { await loadGarments() }
        .onChange(of: garmentFilter) {
            Task { await loadGarments() }
        }
    }

    // MARK: - Cloth type picker

    private var clothTypePicker: some View {
        Picker("", selection: $clothType) {
            ForEach(ClothType.allCases) { t in
                Text(t.label).tag(t)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 200)
        .padding(.horizontal, PluckTheme.Spacing.sm)
    }

    // MARK: - Person panel

    private var personPanel: some View {
        MacGlassPanel(title: "PERSON", subtitle: "drag & drop or click to choose") {
            Group {
                if let data = personImageData, let img = NSImage(data: data) {
                    personPreview(img)
                } else {
                    personDropZone
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.image, .fileURL], isTargeted: $isTargeted) { providers in
            handlePersonDrop(providers)
        }
        .overlay(
            RoundedRectangle(cornerRadius: PluckTheme.Radius.large)
                .stroke(isTargeted ? PluckTheme.accent : Color.clear, lineWidth: 2)
        )
    }

    private func personPreview(_ image: NSImage) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))

            Button {
                personImageData = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(PluckTheme.primaryText)
                    .background(Circle().fill(PluckTheme.terminalPanel.opacity(0.8)))
            }
            .buttonStyle(.plain)
            .padding(8)
        }
    }

    private var personDropZone: some View {
        VStack(spacing: PluckTheme.Spacing.md) {
            Image(systemName: "person.crop.rectangle.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(PluckTheme.terminalMuter)

            Text("Drop photo here")
                .font(PluckTheme.Typography.terminalBody)
                .foregroundStyle(PluckTheme.secondaryText)

            Button("Choose file…") { pickPersonPhoto() }
                .buttonStyle(.bordered)
                .tint(PluckTheme.accent)
                .foregroundStyle(.black)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Garment panel

    private var garmentPanel: some View {
        MacGlassPanel(title: "GARMENT", subtitle: "pick from wardrobe") {
            VStack(spacing: PluckTheme.Spacing.sm) {
                filterPicker

                if isLoadingGarments {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadError {
                    Text(loadError)
                        .font(PluckTheme.Typography.terminalBody)
                        .foregroundStyle(PluckTheme.danger)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if garments.isEmpty {
                    Text("No items found")
                        .font(PluckTheme.Typography.terminalBody)
                        .foregroundStyle(PluckTheme.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    garmentGrid
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filterPicker: some View {
        Picker("", selection: $garmentFilter) {
            ForEach(GarmentFilter.allCases) { f in
                Text(f.label).tag(f)
            }
        }
        .pickerStyle(.segmented)
    }

    private var garmentGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return ScrollView {
            LazyVGrid(columns: columns, spacing: PluckTheme.Spacing.sm) {
                ForEach(garments) { item in
                    garmentCard(item)
                }
            }
        }
    }

    @ViewBuilder
    private func garmentCard(_ item: ClothingItem) -> some View {
        let isSelected = selectedGarment?.id == item.id
        Button { selectedGarment = item } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 6) {
                    AsyncImage(url: imageURL(for: item)) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable()
                               .scaledToFit()
                               .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
                        default:
                            RoundedRectangle(cornerRadius: PluckTheme.Radius.small)
                                .fill(PluckTheme.terminalPanel)
                                .overlay(Image(systemName: "tshirt").foregroundStyle(PluckTheme.terminalMuter))
                        }
                    }
                    .frame(height: 90)

                    Text((item.brand ?? item.category ?? "Item").uppercased())
                        .font(.caption2.monospaced())
                        .foregroundStyle(isSelected ? PluckTheme.primaryText : PluckTheme.secondaryText)
                        .lineLimit(1)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: PluckTheme.Radius.medium)
                        .fill(isSelected ? PluckTheme.accent.opacity(0.1) : PluckTheme.terminalPanel)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PluckTheme.Radius.medium)
                        .stroke(isSelected ? PluckTheme.accent : Color.clear, lineWidth: 2)
                )

                if item.isWishlisted {
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(PluckTheme.accent)
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Result panel

    private var resultPanel: some View {
        MacGlassPanel(title: "RESULT", subtitle: resultSubtitle) {
            VStack(spacing: PluckTheme.Spacing.md) {
                resultContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                runButton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultSubtitle: String {
        if isRunning { return "running inference…" }
        if let _ = resultImageData { return "done — save or try again" }
        return "awaiting inputs"
    }

    @ViewBuilder
    private var resultContent: some View {
        if case .failed(let msg) = sidecar.state {
            errorPanel(message: msg)
        } else if isRunning {
            VStack(spacing: PluckTheme.Spacing.md) {
                ProgressView()
                    .controlSize(.large)
                Text("DIFFUSING…")
                    .font(PluckTheme.Typography.terminalLabel)
                    .foregroundStyle(PluckTheme.terminalScanline)
                    .tracking(1.5)
                Text("~30–60 seconds on Apple Silicon")
                    .font(.caption.monospaced())
                    .foregroundStyle(PluckTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let data = resultImageData, let img = NSImage(data: data) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))

                Button {
                    saveResult(data: data)
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                        .font(.caption.monospaced())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(PluckTheme.terminalPanel.opacity(0.85))
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(PluckTheme.primaryText)
                .padding(8)
            }
        } else if let err = runError {
            errorPanel(message: err)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: PluckTheme.Spacing.sm) {
                Image(systemName: "sparkles")
                    .font(.system(size: 36))
                    .foregroundStyle(PluckTheme.terminalMuter)
                Text("Select a person photo\nand a garment to begin")
                    .font(PluckTheme.Typography.terminalBody)
                    .foregroundStyle(PluckTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var runButton: some View {
        Button {
            Task { await runInference() }
        } label: {
            HStack(spacing: PluckTheme.Spacing.xs) {
                Image(systemName: "wand.and.stars")
                Text(isRunning ? "Running…" : "Try On")
                    .font(PluckTheme.Typography.terminalLabel)
                    .tracking(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(PluckTheme.accent)
        .foregroundStyle(.black)
        .disabled(!canRun)
        .controlSize(.large)
    }

    // MARK: - Opt-in panel

    private var optInPanel: some View {
        VStack(spacing: PluckTheme.Spacing.lg) {
            Image(systemName: "figure.stand.dress")
                .font(.system(size: 52))
                .foregroundStyle(PluckTheme.terminalMuter)

            VStack(spacing: PluckTheme.Spacing.sm) {
                Text("VIRTUAL TRY-ON")
                    .font(PluckTheme.Typography.terminalHeadline)
                    .foregroundStyle(PluckTheme.primaryText)
                    .tracking(2)

                Text("Runs fully on-device using CatVTON.\nRequires a one-time ~10 GB download.")
                    .font(PluckTheme.Typography.terminalBody)
                    .foregroundStyle(PluckTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: PluckTheme.Spacing.xs) {
                downloadRow(icon: "cpu",              label: "PyTorch + diffusers",                   size: "~2 GB")
                downloadRow(icon: "wand.and.stars",   label: "CatVTON weights",                       size: "~2.5 GB")
                downloadRow(icon: "tshirt",           label: "SD Inpainting base model",              size: "~1.7 GB")
                downloadRow(icon: "scissors",         label: "Cloth segmentation model",              size: "~250 MB")
            }
            .padding(PluckTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: PluckTheme.Radius.medium)
                    .fill(PluckTheme.terminalPanel)
                    .overlay(
                        RoundedRectangle(cornerRadius: PluckTheme.Radius.medium)
                            .stroke(PluckTheme.terminalBorder, lineWidth: 1)
                    )
            )

            Button {
                Task { await sidecar.enableAndStart() }
            } label: {
                HStack(spacing: PluckTheme.Spacing.xs) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Enable Try-On")
                        .tracking(1)
                }
                .font(PluckTheme.Typography.terminalLabel)
                .padding(.horizontal, PluckTheme.Spacing.lg)
                .padding(.vertical, PluckTheme.Spacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .tint(PluckTheme.accent)
            .foregroundStyle(.black)
            .controlSize(.large)

            Text("Downloads on first use only. No internet required after setup.")
                .font(.caption2.monospaced())
                .foregroundStyle(PluckTheme.terminalMuter)
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func downloadRow(icon: String, label: String, size: String) -> some View {
        HStack(spacing: PluckTheme.Spacing.sm) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(PluckTheme.terminalScanline)
            Text(label)
                .font(.caption.monospaced())
                .foregroundStyle(PluckTheme.secondaryText)
            Spacer()
            Text(size)
                .font(.caption.monospaced())
                .foregroundStyle(PluckTheme.terminalMuter)
        }
    }

    // MARK: - Error panel

    @ViewBuilder
    private func errorPanel(message: String) -> some View {
        let logPath = ("~/Library/Application Support/PluckIt/tryon/server.log" as NSString).expandingTildeInPath
        ScrollView {
            VStack(alignment: .leading, spacing: PluckTheme.Spacing.md) {
                HStack(spacing: PluckTheme.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.red.opacity(0.85))
                    Text("ERROR")
                        .font(PluckTheme.Typography.terminalLabel)
                        .foregroundStyle(Color.red.opacity(0.85))
                        .tracking(1.5)
                }

                Text(message)
                    .font(.caption.monospaced())
                    .foregroundStyle(PluckTheme.primaryText)
                    .textSelection(.enabled)
                    .padding(PluckTheme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: PluckTheme.Radius.small)
                            .fill(Color.red.opacity(0.06))
                    )

                Divider().background(PluckTheme.terminalMuter.opacity(0.3))

                Text("Full log:")
                    .font(.caption2.monospaced())
                    .foregroundStyle(PluckTheme.secondaryText)

                Button {
                    NSWorkspace.shared.selectFile(logPath, inFileViewerRootedAtPath: "")
                } label: {
                    Text(logPath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(PluckTheme.accent)
                        .underline()
                        .lineLimit(2)
                }
                .buttonStyle(.plain)

                Button("Retry setup") {
                    Task {
                        let marker = ("~/Library/Application Support/PluckIt/tryon/.setup_complete" as NSString).expandingTildeInPath
                        try? FileManager.default.removeItem(atPath: marker)
                        await sidecar.startIfNeeded()
                    }
                }
                .buttonStyle(.bordered)
                .tint(PluckTheme.accent)
                .foregroundStyle(.black)
            }
            .padding(PluckTheme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: PluckTheme.Spacing.xs) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)

            Text(sidecar.state.statusLine)
                .font(.caption2.monospaced())
                .foregroundStyle(PluckTheme.secondaryText)

            Spacer()

            if sidecar.state.isBusy {
                ProgressView()
                    .controlSize(.mini)
                    .tint(PluckTheme.accent)
            }
        }
        .padding(.horizontal, PluckTheme.Spacing.md)
        .padding(.vertical, PluckTheme.Spacing.sm)
        .background(PluckTheme.terminalPanel)
    }

    private var statusColor: Color {
        switch sidecar.state {
        case .ready:       return .green
        case .failed:      return .red
        case .settingUp,
             .starting:    return .orange
        case .idle:        return PluckTheme.terminalMuter
        }
    }

    // MARK: - Actions

    private func pickPersonPhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        personImageData = try? Data(contentsOf: url)
    }

    private func handlePersonDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        // Prefer loading raw image data (works for drags from Photos, browser, etc.)
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else { return }
                DispatchQueue.main.async { self.personImageData = data }
            }
            return true
        }

        // Fallback: file URL (drag from Finder)
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, let data = try? Data(contentsOf: url) else { return }
                DispatchQueue.main.async { self.personImageData = data }
            }
            return true
        }

        return false
    }

    private func runInference() async {
        guard case .ready(let port) = sidecar.state,
              let personData = personImageData,
              let garment    = selectedGarment
        else { return }

        isRunning = true
        runError  = nil
        resultImageData = nil

        do {
            let service      = MacTryOnService(port: port)
            let garmentData  = try await service.downloadGarmentImage(from: garment)
            let result       = try await service.tryOn(
                personImageData: personData,
                garmentImageData: garmentData,
                clothType: clothType
            )
            resultImageData = result
        } catch {
            runError = error.localizedDescription
        }

        isRunning = false
    }

    private func saveResult(data: Data) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "tryon_result.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
        } catch {
            print("[MacTryOnView] Failed to save try-on result: \(error)")
            let alert = NSAlert()
            alert.messageText = "Failed to Save Image"
            alert.informativeText = "Could not save image to disk.\n\(error.localizedDescription)"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func loadGarments() async {
        isLoadingGarments = true
        loadError = nil
        defer { isLoadingGarments = false }

        let includeWishlisted: Bool? = {
            switch garmentFilter {
            case .all:      return nil
            case .vault:    return false
            case .wishlist: return true
            }
        }()

        do {
            let response = try await appServices.wardrobeService.fetchItems(
                pageSize: 100,
                includeWishlisted: includeWishlisted
            )
            garments = response.items.filter { $0.imageUrl != nil || $0.rawImageBlobUrl != nil }
            loadError = nil
        } catch {
            print("[MacTryOnView] Failed to load garments: \(error)")
            loadError = error.localizedDescription
        }
    }

    private func imageURL(for item: ClothingItem) -> URL? {
        (item.imageUrl ?? item.rawImageBlobUrl).flatMap { URL(string: $0) }
    }
}

// MARK: - Garment filter

private enum GarmentFilter: String, CaseIterable, Identifiable {
    case all      = "all"
    case vault    = "vault"
    case wishlist = "wishlist"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:      return "All"
        case .vault:    return "Vault"
        case .wishlist: return "Wishlist"
        }
    }
}

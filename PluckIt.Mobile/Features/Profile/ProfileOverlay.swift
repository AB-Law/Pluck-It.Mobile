import SwiftUI

struct ProfileOverlay: View {
    @EnvironmentObject private var appServices: AppServices
    @State private var profile: UserProfile?
    @State private var loading = false
    @State private var errorText: String?
    @State private var loadedAt: Date?
    @Environment(\.dismiss) private var dismiss

    private var hasCachedProfile: Bool {
        profile != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: PluckTheme.Spacing.md) {
                    if loading && !hasCachedProfile {
                        stateLoadingView
                    } else if let profile {
                        if let errorText {
                            inlineErrorBanner(errorText)
                        }
                        profileContent(for: profile)
                    } else if let errorText {
                        stateErrorView(message: errorText)
                    } else {
                        stateEmptyView
                    }
                }
                .padding(.horizontal, PluckTheme.Spacing.md)
                .padding(.vertical, PluckTheme.Spacing.sm)
            }
            .background(PluckTheme.background)
            .navigationTitle("Profile & Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await loadProfile(force: true)
                        }
                    } label: {
                        if loading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(PluckTheme.primaryText)
                        }
                    }
                    .disabled(loading)
                }
            }
            .task {
                await loadProfile()
            }
            .refreshable {
                await loadProfile(force: true)
            }
        }
    }

    private var stateLoadingView: some View {
        VStack(spacing: PluckTheme.Spacing.md) {
            ProgressView("Loading profile…")
                .foregroundStyle(PluckTheme.secondaryText)

            VStack(spacing: PluckTheme.Spacing.sm) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: PluckTheme.Radius.small)
                        .fill(PluckTheme.card)
                        .frame(height: 132)
                        .overlay(ProgressView().tint(PluckTheme.primaryText))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var stateEmptyView: some View {
        VStack(spacing: PluckTheme.Spacing.sm) {
            Image(systemName: "person.crop.circle")
                .font(.title2)
                .foregroundStyle(PluckTheme.mutedText)

            Text("No profile loaded")
                .font(.headline)
                .foregroundStyle(PluckTheme.primaryText)

            Text("Pull down to refresh or tap Refresh.")
                .font(.caption)
                .foregroundStyle(PluckTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, PluckTheme.Spacing.xl)
        .frame(maxWidth: .infinity)
    }

    private func stateErrorView(message: String) -> some View {
        VStack(spacing: PluckTheme.Spacing.sm) {
            Text("Could not load profile")
                .font(.headline)
                .foregroundStyle(PluckTheme.danger)

            Text(message)
                .font(.caption)
                .foregroundStyle(PluckTheme.secondaryText)
                .multilineTextAlignment(.center)

            Button("Retry") {
                Task {
                    await loadProfile(force: true)
                }
            }
            .buttonStyle(.bordered)
            .tint(PluckTheme.info)
        }
        .padding(.top, PluckTheme.Spacing.md)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func inlineErrorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: PluckTheme.Spacing.xs) {
            Text("Profile sync failed")
                .font(.caption2)
                .foregroundStyle(PluckTheme.danger)
            Text(message)
                .font(.caption)
                .foregroundStyle(PluckTheme.secondaryText)
                .multilineTextAlignment(.leading)
            Button("Retry") {
                Task {
                    await loadProfile(force: true)
                }
            }
            .buttonStyle(.plain)
            .font(.caption2)
            .foregroundStyle(PluckTheme.info)
        }
        .padding(PluckTheme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PluckTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
    }

    private func profileContent(for profile: UserProfile) -> some View {
        VStack(spacing: PluckTheme.Spacing.md) {
            sectionCard("Active identity") {
                metadataRow("User ID", value: appServices.authService.identity?.userId)
                metadataRow("Email", value: appServices.authService.identity?.email)
                metadataRow(
                    "Auth source",
                    value: appServices.authService.identity?.isLocalMock == true
                        ? "Local mock session"
                        : "Token-backed session"
                )
            }

            sectionCard("Server profile") {
                metadataRow("Display name", value: profile.displayName)
                metadataRow("Email", value: profile.email)
                metadataRow("User ID", value: profile.userId)
                if let loadedAt {
                    metadataRow("Loaded", value: Self.timestampFormatter.string(from: loadedAt))
                }
            }

            metadataSection("Style identity", values: profile.knownCategories, placeholder: "No style categories returned")
            metadataSection("Known brands", values: profile.knownBrands, placeholder: "No brand fingerprints yet")
            metadataSection("Known colours", values: profile.knownColors, placeholder: "No colour preferences yet")
        }
    }

    private func sectionCard<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: PluckTheme.Spacing.sm) {
            Text(title.uppercased())
                .font(PluckTheme.Typography.sectionHeader)
                .foregroundStyle(PluckTheme.secondaryText)

            Divider()
                .background(PluckTheme.border)

            content()
        }
        .padding(PluckTheme.Spacing.md)
        .background(PluckTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
    }

    private func metadataRow(_ label: String, value: String?) -> some View {
        HStack(alignment: .top, spacing: PluckTheme.Spacing.sm) {
            Text(label)
                .font(.caption)
                .foregroundStyle(PluckTheme.secondaryText)
                .frame(width: 108, alignment: .leading)

            Text(value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? value! : "—")
                .font(.caption)
                .foregroundStyle(PluckTheme.primaryText)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metadataSection(_ title: String, values: [String]?, placeholder: String) -> some View {
        sectionCard(title) {
            let normalizedValues = normalizedValues(from: values)
            if normalizedValues.isEmpty {
                Text(placeholder)
                    .font(.caption)
                    .foregroundStyle(PluckTheme.secondaryText)
            } else {
                FlowTileGrid(items: normalizedValues)
            }
        }
    }

    private func normalizedValues(from values: [String]?) -> [String] {
        let normalized = (values ?? [])
            .compactMap { value in
                let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned.isEmpty ? nil : cleaned
            }

        return normalized
    }

    private struct FlowTileGrid: View {
        let items: [String]
        private let columns = [GridItem(.adaptive(minimum: 100), spacing: PluckTheme.Spacing.xs)]

        var body: some View {
            LazyVGrid(columns: columns, alignment: .leading, spacing: PluckTheme.Spacing.sm) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.caption2)
                        .foregroundStyle(PluckTheme.primaryText)
                        .padding(.horizontal, PluckTheme.Spacing.sm)
                        .padding(.vertical, 5)
                        .background(PluckTheme.background)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private func loadProfile(force: Bool = false) async {
        guard !loading else { return }

        let hasExistingProfile = profile != nil
        loading = true
        if !hasExistingProfile || force {
            errorText = nil
        }

        do {
            profile = try await appServices.profileService.fetchProfile()
            loadedAt = Date()
            errorText = nil
        } catch {
            errorText = String(describing: error)
            if !hasExistingProfile {
                profile = nil
            }
        }

        loading = false
    }
}

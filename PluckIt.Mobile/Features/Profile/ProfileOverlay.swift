import SwiftUI

struct ProfileOverlay: View {
    @EnvironmentObject private var appServices: AppServices
    @State private var profile: UserProfile?
    @State private var prefs: UserPreferences = .default
    @State private var editedPrefs: UserPreferences = .default
    @State private var loading = false
    @State private var saving = false
    @State private var errorText: String?
    @State private var saveError: String?
    @State private var loadedAt: Date?
    @Environment(\.dismiss) private var dismiss

    private var isDirty: Bool { !prefsEqual(editedPrefs, prefs) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: PluckTheme.Spacing.md) {
                    if loading && profile == nil {
                        stateLoadingView
                            .pluckReveal()
                    } else {
                        if let errorText {
                            inlineErrorBanner(errorText)
                                .pluckReveal()
                        }
                        if let saveError {
                            inlineErrorBanner(saveError)
                                .pluckReveal()
                        }
                        if let profile {
                            identitySection(for: profile)
                                .pluckReveal()
                        }
                        preferencesSection
                            .pluckReveal()
                        bodyMeasurementsSection
                            .pluckReveal()
                        styleIdentitySection
                            .pluckReveal()
                        aiPersonalisationSection
                            .pluckReveal()
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
                        pluckImpactFeedback(.light)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            pluckImpactFeedback()
                            Task { await savePreferences() }
                        }
                        .fontWeight(.semibold)
                        .disabled(!isDirty)
                        .foregroundStyle(isDirty ? PluckTheme.accent : PluckTheme.mutedText)
                    }
                }
            }
            .task { await loadAll() }
            .refreshable { await loadAll(force: true) }
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Identity (read-only)

    private func identitySection(for profile: UserProfile) -> some View {
        VStack(spacing: PluckTheme.Spacing.md) {
            sectionCard("Active Identity") {
                metadataRow("User ID", value: appServices.authService.identity?.userId)
                metadataRow("Email", value: appServices.authService.identity?.email)
                metadataRow(
                    "Auth source",
                    value: appServices.authService.identity?.isLocalMock == true
                        ? "Local mock session"
                        : "Token-backed session"
                )
                Button("Sign out") {
                    pluckImpactFeedback()
                    appServices.authService.signOut()
                }
                .font(.footnote)
                .foregroundStyle(PluckTheme.danger)
            }

            sectionCard("Server Profile") {
                metadataRow("Display name", value: profile.displayName)
                metadataRow("Email", value: profile.email)
                metadataRow("User ID", value: profile.userId)
                if let loadedAt {
                    metadataRow("Loaded", value: Self.timestampFormatter.string(from: loadedAt))
                }
            }

            metadataChipSection("Style Fingerprint", values: profile.knownCategories, placeholder: "No style categories yet")
            metadataChipSection("Known Brands", values: profile.knownBrands, placeholder: "No brand fingerprints yet")
            metadataChipSection("Known Colours", values: profile.knownColors, placeholder: "No colour preferences yet")
        }
    }

    // MARK: - Editable sections

    private var preferencesSection: some View {
        sectionCard("Preferences") {
            VStack(spacing: PluckTheme.Spacing.sm) {
                HStack {
                    Text("Currency")
                        .font(.caption)
                        .foregroundStyle(PluckTheme.secondaryText)
                        .frame(width: 108, alignment: .leading)
                    Picker("Currency", selection: $editedPrefs.currencyCode) {
                        ForEach(["USD", "EUR", "GBP", "INR", "AUD", "CAD", "JPY", "CHF", "CNY", "SEK"], id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(PluckTheme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    Text("Size system")
                        .font(.caption)
                        .foregroundStyle(PluckTheme.secondaryText)
                        .frame(width: 108, alignment: .leading)
                    Picker("Size system", selection: $editedPrefs.preferredSizeSystem) {
                        ForEach(["US", "EU", "UK"], id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var bodyMeasurementsSection: some View {
        sectionCard("Body Measurements") {
            VStack(spacing: PluckTheme.Spacing.sm) {
                measurementRow("Height (cm)", value: $editedPrefs.heightCm)
                measurementRow("Weight (kg)", value: $editedPrefs.weightKg)
                measurementRow("Chest (cm)", value: $editedPrefs.chestCm)
                measurementRow("Waist (cm)", value: $editedPrefs.waistCm)
                measurementRow("Hips (cm)", value: $editedPrefs.hipsCm)
                measurementRow("Inseam (cm)", value: $editedPrefs.inseamCm)
            }
        }
    }

    private var styleIdentitySection: some View {
        sectionCard("Style Identity") {
            VStack(alignment: .leading, spacing: PluckTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: PluckTheme.Spacing.xs) {
                    Text("Aesthetics")
                        .font(.caption2)
                        .foregroundStyle(PluckTheme.secondaryText)
                    styleChipsGrid
                }

                textInputRow("Favourite brands", placeholder: "e.g. Nike, Zara", binding: Binding(
                    get: { editedPrefs.favoriteBrands.joined(separator: ", ") },
                    set: { editedPrefs.favoriteBrands = splitCSV($0) }
                ))

                textInputRow("Preferred colours", placeholder: "e.g. black, navy", binding: Binding(
                    get: { editedPrefs.preferredColours.joined(separator: ", ") },
                    set: { editedPrefs.preferredColours = splitCSV($0) }
                ))

                textInputRow("Location city", placeholder: "e.g. London", binding: Binding(
                    get: { editedPrefs.locationCity ?? "" },
                    set: { editedPrefs.locationCity = $0.isEmpty ? nil : $0 }
                ))
            }
        }
    }

    private let aesthetics = ["streetwear", "minimalist", "preppy", "smart casual", "athleisure",
                               "bohemian", "classic", "techwear", "y2k", "vintage"]

    private var styleChipsGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 90), spacing: PluckTheme.Spacing.xs)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: PluckTheme.Spacing.xs) {
            ForEach(aesthetics, id: \.self) { tag in
                let selected = editedPrefs.stylePreferences.contains(tag)
                Button {
                    pluckImpactFeedback(.light)
                    if selected {
                        editedPrefs.stylePreferences.removeAll { $0 == tag }
                    } else {
                        editedPrefs.stylePreferences.append(tag)
                    }
                } label: {
                    Text(tag)
                        .font(.caption2)
                        .foregroundStyle(selected ? PluckTheme.background : PluckTheme.primaryText)
                        .padding(.horizontal, PluckTheme.Spacing.sm)
                        .padding(.vertical, 5)
                        .background(selected ? PluckTheme.accent : PluckTheme.background)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var aiPersonalisationSection: some View {
        sectionCard("AI Personalisation") {
            Toggle(isOn: Binding(
                get: { editedPrefs.recommendationOptIn ?? false },
                set: { editedPrefs.recommendationOptIn = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable personalisation")
                        .font(.caption)
                        .foregroundStyle(PluckTheme.primaryText)
                    Text("Weekly digest and wear-based recommendations")
                        .font(.caption2)
                        .foregroundStyle(PluckTheme.secondaryText)
                }
            }
            .tint(PluckTheme.accent)
        }
    }

    // MARK: - Reusable components

    private func sectionCard<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: PluckTheme.Spacing.sm) {
            Text(title.uppercased())
                .font(PluckTheme.Typography.sectionHeader)
                .foregroundStyle(PluckTheme.secondaryText)

            Divider().background(PluckTheme.border)

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

    private func metadataChipSection(_ title: String, values: [String]?, placeholder: String) -> some View {
        sectionCard(title) {
            let normalized = (values ?? []).compactMap { v -> String? in
                let c = v.trimmingCharacters(in: .whitespacesAndNewlines)
                return c.isEmpty ? nil : c
            }
            if normalized.isEmpty {
                Text(placeholder)
                    .font(.caption)
                    .foregroundStyle(PluckTheme.secondaryText)
            } else {
                let columns = [GridItem(.adaptive(minimum: 100), spacing: PluckTheme.Spacing.xs)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: PluckTheme.Spacing.sm) {
                    ForEach(normalized, id: \.self) { item in
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
    }

    private func measurementRow(_ label: String, value: Binding<Double?>) -> some View {
        HStack(spacing: PluckTheme.Spacing.sm) {
            Text(label)
                .font(.caption)
                .foregroundStyle(PluckTheme.secondaryText)
                .frame(width: 108, alignment: .leading)
            TextField("—", value: value, format: .number)
                .font(.caption)
                .foregroundStyle(PluckTheme.primaryText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func textInputRow(_ label: String, placeholder: String, binding: Binding<String>) -> some View {
        HStack(alignment: .top, spacing: PluckTheme.Spacing.sm) {
            Text(label)
                .font(.caption)
                .foregroundStyle(PluckTheme.secondaryText)
                .frame(width: 108, alignment: .leading)
            TextField(placeholder, text: binding)
                .font(.caption)
                .foregroundStyle(PluckTheme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var stateLoadingView: some View {
        VStack(spacing: PluckTheme.Spacing.md) {
            ProgressView("Loading profile…")
                .foregroundStyle(PluckTheme.secondaryText)
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: PluckTheme.Radius.small)
                    .fill(PluckTheme.card)
                    .frame(height: 100)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func inlineErrorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: PluckTheme.Spacing.xs) {
            Text("Error")
                .font(.caption2)
                .foregroundStyle(PluckTheme.danger)
            Text(message)
                .font(.caption)
                .foregroundStyle(PluckTheme.secondaryText)
        }
        .padding(PluckTheme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PluckTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: PluckTheme.Radius.small))
    }

    // MARK: - Helpers

    private func splitCSV(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func prefsEqual(_ a: UserPreferences, _ b: UserPreferences) -> Bool {
        a.currencyCode == b.currencyCode &&
        a.preferredSizeSystem == b.preferredSizeSystem &&
        a.heightCm == b.heightCm && a.weightKg == b.weightKg &&
        a.chestCm == b.chestCm && a.waistCm == b.waistCm &&
        a.hipsCm == b.hipsCm && a.inseamCm == b.inseamCm &&
        a.stylePreferences == b.stylePreferences &&
        a.favoriteBrands == b.favoriteBrands &&
        a.preferredColours == b.preferredColours &&
        a.locationCity == b.locationCity &&
        a.recommendationOptIn == b.recommendationOptIn
    }

    // MARK: - Data

    private func loadAll(force: Bool = false) async {
        guard !loading else { return }
        loading = true
        errorText = nil

        // Identity fetch is best-effort — 404 just hides the identity section
        async let identityFetch: UserProfile? = { try? await appServices.profileService.fetchProfile() }()
        async let prefsFetch: UserPreferences = appServices.profileService.fetchPreferences()

        do {
            let (fetchedProfile, fetchedPrefs) = await (identityFetch, try prefsFetch)
            profile = fetchedProfile
            prefs = fetchedPrefs
            editedPrefs = fetchedPrefs
            loadedAt = Date()
        } catch {
            errorText = String(describing: error)
        }

        loading = false
    }

    private func savePreferences() async {
        guard !saving else { return }
        saving = true
        saveError = nil

        do {
            try await appServices.profileService.updatePreferences(editedPrefs)
            prefs = editedPrefs
        } catch {
            saveError = String(describing: error)
        }

        saving = false
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()
}

import SwiftUI

/// Full edit flow for wardrobe items, aligned to the Angular ReviewItemModal fields:
/// brand, category, price, purchase date, notes, tags, care info, condition, size and wear logging.
struct WardrobeItemReviewModal: View {
    @EnvironmentObject private var appServices: AppServices
    let item: ClothingItem
    let onSaved: (ClothingItem) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var brand = ""
    @State private var category = ""
    @State private var notes = ""
    @State private var purchaseDate = ""
    @State private var priceAmount = ""
    @State private var priceCurrency = "USD"
    @State private var condition = ""
    @State private var tagInput = ""
    @State private var tags: [String] = []
    @State private var careInfo: [String] = []
    @State private var letterSize = ""
    @State private var waistSize = ""
    @State private var inseamSize = ""
    @State private var shoeSize = ""
    @State private var wearCount = 0
    @State private var sizeSystem: String?
    @State private var hasExplicitPriceCurrency = false
    @State private var profileCurrencyLoaded = false

    @State private var errorText: String?
    @State private var isLogging = false
    @State private var isSaving = false

    private enum SizeInputType {
        case none
        case letter
        case bottoms
        case shoe
    }

    private let categories = [
        "Tops",
        "Bottoms",
        "Outerwear",
        "Footwear",
        "Accessories",
        "Knitwear",
        "Dresses",
        "Activewear",
        "Swimwear",
        "Underwear",
    ]

    private let careOptions = [
        ("dry_clean", "Dry clean"),
        ("wash", "Wash"),
        ("iron", "Iron"),
        ("bleach", "Bleach"),
    ]

    private let conditions = ["New", "Excellent", "Good", "Fair"]
    private let letterSizes = ["XS", "S", "M", "L", "XL", "XXL", "XXXL"]
    private let waistSizes = Array(24...48)
    private let inseamSizes = Array(26...36)

    init(item: ClothingItem, onSaved: @escaping (ClothingItem) -> Void = { _ in }) {
        self.item = item
        self.onSaved = onSaved
        _brand = State(initialValue: item.brand ?? "")
        _category = State(initialValue: item.category ?? "")
        _notes = State(initialValue: item.notes ?? "")
        _purchaseDate = State(initialValue: item.purchaseDate ?? "")
        _priceAmount = State(initialValue: Self.formattedPrice(item.price?.amount))
        let itemCurrency = item.price?.originalCurrency?.trimmingCharacters(in: .whitespacesAndNewlines)
        _priceCurrency = State(initialValue: itemCurrency.flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultCurrencyCode)
        _hasExplicitPriceCurrency = State(initialValue: itemCurrency?.isEmpty == false)
        _condition = State(initialValue: item.condition ?? "")
        _tags = State(initialValue: item.tags ?? [])
        _careInfo = State(initialValue: item.careInfo ?? [])
        _wearCount = State(initialValue: item.wearCount ?? 0)
        let knownSize = item.size
        _letterSize = State(initialValue: knownSize?.letter ?? "")
        _waistSize = State(initialValue: Self.formatSizeValue(knownSize?.waist))
        _inseamSize = State(initialValue: Self.formatSizeValue(knownSize?.inseam))
        _shoeSize = State(initialValue: Self.formatSizeValue(knownSize?.shoeSize))
        _sizeSystem = State(initialValue: knownSize?.system)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Metadata") {
                    TextField("Brand", text: $brand)
                    Text("Category: \(category.isEmpty ? "—" : category)")
                    if let selectedCondition = condition.isEmpty ? nil : condition {
                        Text("Condition: \(selectedCondition)")
                    } else {
                        Text("Condition: —")
                    }
                    HStack {
                        Text(priceCurrency)
                            .foregroundStyle(PluckTheme.secondaryText)
                            .padding(.horizontal, PluckTheme.Spacing.sm)
                        TextField("Estimated price", text: $priceAmount)
                            .keyboardType(.decimalPad)
                    }
                    TextField("Purchase date", text: $purchaseDate)
                    Text("Wears: \(wearCount)")
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(4...8)
                        .autocorrectionDisabled()
                }

                Section("Tags") {
                    if tags.isEmpty {
                        Text("No tags")
                            .font(.caption)
                            .foregroundStyle(PluckTheme.secondaryText)
                    } else {
                        ForEach(tags, id: \.self) { tag in
                            HStack {
                                Text(tag)
                                Spacer()
                                Button("Remove") {
                                    removeTag(tag)
                                }
                                .font(.caption)
                                .foregroundStyle(PluckTheme.danger)
                            }
                        }
                    }
                    HStack {
                        TextField("Add tag", text: $tagInput)
                            .autocapitalization(.none)
                        Button("Add") {
                            addTag()
                        }
                    }
                }

                Section("Category") {
                    Picker("Category", selection: $category) {
                        Text("—").tag("")
                        ForEach(categories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: category) {
                        resetSize()
                    }
                }

                if sizeInputType != .none {
                    Section("Size") {
                        sizeSection
                    }
                }

                Section("Care Info") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: PluckTheme.Spacing.sm) {
                        ForEach(careOptions, id: \.0) { option in
                            Button {
                                toggleCare(option.0)
                            } label: {
                                Text(option.1)
                                    .font(.footnote)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(isCareSelected(option.0) ? PluckTheme.info : PluckTheme.secondaryText)
                        }
                    }
                }

                Section("Condition") {
                    Picker("Condition", selection: $condition) {
                        Text("—").tag("")
                        ForEach(conditions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    if isSaving {
                        HStack {
                            Spacer()
                            ProgressView("Saving changes")
                                .foregroundStyle(PluckTheme.secondaryText)
                            Spacer()
                        }
                    } else {
                        Button("Save changes") {
                            Task {
                                await saveChanges()
                            }
                        }
                        .disabled(isLogging)
                        .foregroundStyle(PluckTheme.info)
                    }
                }

                Section {
                    if isLogging {
                        ProgressView("Logging wear")
                            .foregroundStyle(PluckTheme.secondaryText)
                    } else {
                        Button("Log wear") {
                            Task {
                                await logWear()
                            }
                        }
                        .foregroundStyle(PluckTheme.primaryText)
                    }
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .foregroundStyle(PluckTheme.danger)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(brand.isEmpty ? "Item" : brand)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    }
                }
            }
            .task {
                await loadProfileCurrencyIfNeeded()
            }
        }
    }

    private var sizeInputType: SizeInputType {
        if category == "Bottoms" {
            return .bottoms
        }
        if category == "Footwear" {
            return .shoe
        }
        let letterCategories = Set(["Tops", "Knitwear", "Outerwear", "Dresses", "Activewear", "Swimwear", "Underwear"])
        if letterCategories.contains(category) {
            return .letter
        }
        return .none
    }

    private var sizeSection: some View {
        Group {
            switch sizeInputType {
            case .none:
                EmptyView()
            case .letter:
                VStack(alignment: .leading, spacing: PluckTheme.Spacing.sm) {
                    Text("Letter size")
                        .font(.footnote)
                        .foregroundStyle(PluckTheme.secondaryText)
                    Picker("Letter size", selection: $letterSize) {
                        Text("—").tag("")
                        ForEach(letterSizes, id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: letterSize) {
                        if !letterSize.isEmpty {
                            waistSize = ""
                            inseamSize = ""
                            shoeSize = ""
                        }
                    }
                }
            case .bottoms:
                VStack(spacing: PluckTheme.Spacing.sm) {
                    HStack {
                        Picker("Waist", selection: $waistSize) {
                            Text("—").tag("")
                            ForEach(waistSizes, id: \.self) {
                                Text("\($0)").tag("\($0)")
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("Inseam", selection: $inseamSize) {
                            Text("—").tag("")
                            ForEach(inseamSizes, id: \.self) {
                                Text("\($0)").tag("\($0)")
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            case .shoe:
                HStack {
                    Text("Shoe size")
                        .font(.footnote)
                        .foregroundStyle(PluckTheme.secondaryText)
                    TextField("10.5", text: $shoeSize)
                        .keyboardType(.decimalPad)
                }
            }
        }
    }

    private func addTag() {
        let normalizedTag = tagInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedTag.isEmpty else { return }
        guard !tags.contains(normalizedTag) else {
            tagInput = ""
            return
        }
        tags.append(normalizedTag)
        tagInput = ""
    }

    private func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }

    private func resetSize() {
        letterSize = ""
        waistSize = ""
        inseamSize = ""
        shoeSize = ""
    }

    private func isCareSelected(_ key: String) -> Bool {
        careInfo.contains(key)
    }

    private func toggleCare(_ key: String) {
        if careInfo.contains(key) {
            careInfo.removeAll { $0 == key }
        } else {
            careInfo.append(key)
        }
    }

    private func parsedPriceAmount() -> Double? {
        Double(priceAmount.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func buildSizePayload() -> ClothingSize? {
        switch sizeInputType {
        case .none:
            return nil
        case .letter:
            let normalizedLetter = letterSize.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedLetter.isEmpty else { return nil }
            return ClothingSize(
                letter: normalizedLetter,
                waist: nil,
                inseam: nil,
                shoeSize: nil,
                system: sizeSystem
            )
        case .bottoms:
            let waistValue = Double(waistSize.trimmingCharacters(in: .whitespacesAndNewlines))
            let inseamValue = Double(inseamSize.trimmingCharacters(in: .whitespacesAndNewlines))
            guard waistValue != nil || inseamValue != nil else { return nil }
            return ClothingSize(
                letter: nil,
                waist: waistValue,
                inseam: inseamValue,
                shoeSize: nil,
                system: sizeSystem
            )
        case .shoe:
            let size = Double(shoeSize.trimmingCharacters(in: .whitespacesAndNewlines))
            guard let size else { return nil }
            return ClothingSize(
                letter: nil,
                waist: nil,
                inseam: nil,
                shoeSize: size,
                system: sizeSystem
            )
        }
    }

    private func buildUpdatedItem() -> ClothingItem {
        let normalizedBrand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPurchaseDate = purchaseDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCondition = condition.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedConditionValue = normalizedCondition.isEmpty ? nil : normalizedCondition
        let normalizedTags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
        let normalizedCare = Array(Set(careInfo.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))

        let updatedPrice: ClothingPrice?
        if let parsedPrice = parsedPriceAmount() {
            updatedPrice = ClothingPrice(amount: parsedPrice, originalCurrency: priceCurrency)
        } else {
            updatedPrice = nil
        }

        return ClothingItem(
            id: item.id,
            imageUrl: item.imageUrl,
            rawImageBlobUrl: item.rawImageBlobUrl,
            tags: normalizedTags,
            colours: item.colours,
            brand: normalizedBrand.isEmpty ? nil : normalizedBrand,
            category: normalizedCategory.isEmpty ? nil : normalizedCategory,
            price: updatedPrice,
            notes: normalizedNotes.isEmpty ? nil : normalizedNotes,
            dateAdded: item.dateAdded,
            wearCount: wearCount,
            purchaseDate: normalizedPurchaseDate.isEmpty ? nil : normalizedPurchaseDate,
            careInfo: normalizedCare,
            condition: normalizedConditionValue,
            size: buildSizePayload(),
            aestheticTags: item.aestheticTags,
            draftStatus: item.draftStatus,
            draftError: item.draftError,
            userId: item.userId,
            estimatedMarketValue: item.estimatedMarketValue,
            lastWornAt: item.lastWornAt,
            wearEvents: item.wearEvents,
            draftCreatedAt: item.draftCreatedAt,
            draftUpdatedAt: item.draftUpdatedAt
        )
    }

    private func logWear() async {
        guard !isLogging else { return }
        isLogging = true
        errorText = nil
        defer {
            isLogging = false
        }

        do {
            try await appServices.wardrobeService.logWear(item.id)
            wearCount += 1
        } catch {
            errorText = String(describing: error)
        }
    }

    private func saveChanges() async {
        guard !isSaving else { return }
        isSaving = true
        errorText = nil
        defer {
            isSaving = false
        }

        do {
            let updated = buildUpdatedItem()
            try await appServices.wardrobeService.update(updated)
            onSaved(updated)
            dismiss()
        } catch {
            errorText = String(describing: error)
        }
    }

    private func loadProfileCurrencyIfNeeded() async {
        guard !hasExplicitPriceCurrency else { return }
        guard !profileCurrencyLoaded else { return }
        profileCurrencyLoaded = true
        do {
            let profile = try await appServices.profileService.fetchProfile()
            let profileCurrency = profile.currencyCode?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let profileCurrency, !profileCurrency.isEmpty else { return }
            priceCurrency = profileCurrency.uppercased()
        } catch {
            // Keep existing fallback currency when profile fetch is unavailable.
        }
    }

    private static func formattedPrice(_ amount: Double?) -> String {
        guard let amount else { return "" }
        return String(format: "%.2f", amount)
    }

    private static let defaultCurrencyCode = "USD"

    private static func formatSizeValue(_ value: Double?) -> String {
        guard let value else { return "" }
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.0f", value)
    }
}

import SwiftUI

struct VaultFilters: Equatable {
    var group: VaultSmartGroup = .all
    var priceMin: Double = 0
    var priceMax: Double = 5000
    var minWears: Int = 0
    var brand: String = ""
    var condition: String = ""
    var sortField: String = "dateAdded"
    var sortDir: String = "desc"

    var isDefault: Bool {
        self == VaultFilters()
    }
}

enum VaultSmartGroup: String, CaseIterable {
    case all = "All"
    case favorites = "Favorites"
    case recentlyWorn = "Recently Worn"
}

private struct SortOption: Equatable, Hashable {
    let label: String
    let field: String
    let dir: String
}

private let sortOptions: [SortOption] = [
    SortOption(label: "Newest First",       field: "dateAdded",    dir: "desc"),
    SortOption(label: "Oldest First",       field: "dateAdded",    dir: "asc"),
    SortOption(label: "Most Worn",          field: "wearCount",    dir: "desc"),
    SortOption(label: "Least Worn",         field: "wearCount",    dir: "asc"),
    SortOption(label: "Price: High to Low", field: "price.amount", dir: "desc"),
    SortOption(label: "Price: Low to High", field: "price.amount", dir: "asc"),
]

struct VaultFilterSidebarView: View {
    @Binding var filters: VaultFilters
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: VaultFilters

    private let conditions = ["New", "Excellent", "Good", "Fair"]

    init(filters: Binding<VaultFilters>, onApply: @escaping () -> Void) {
        self._filters = filters
        self.onApply = onApply
        self._draft = State(initialValue: filters.wrappedValue)
    }

    private var selectedSortOption: SortOption {
        sortOptions.first { $0.field == draft.sortField && $0.dir == draft.sortDir }
            ?? sortOptions[0]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Smart Group") {
                    Picker("Group", selection: $draft.group) {
                        ForEach(VaultSmartGroup.allCases, id: \.self) { group in
                            Text(group.rawValue).tag(group)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Sort By") {
                    Picker("Sort", selection: Binding(
                        get: { selectedSortOption },
                        set: { opt in
                            draft.sortField = opt.field
                            draft.sortDir = opt.dir
                        }
                    )) {
                        ForEach(sortOptions, id: \.label) { opt in
                            Text(opt.label).tag(opt)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Price Range") {
                    HStack {
                        Text("Min")
                            .font(.caption)
                            .foregroundStyle(PluckTheme.secondaryText)
                            .frame(width: 32, alignment: .leading)
                        Slider(value: $draft.priceMin, in: 0...draft.priceMax, step: 10)
                        Text(formatPrice(draft.priceMin))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(PluckTheme.primaryText)
                            .frame(width: 56, alignment: .trailing)
                    }
                    HStack {
                        Text("Max")
                            .font(.caption)
                            .foregroundStyle(PluckTheme.secondaryText)
                            .frame(width: 32, alignment: .leading)
                        Slider(value: $draft.priceMax, in: draft.priceMin...5000, step: 10)
                        Text(formatPrice(draft.priceMax))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(PluckTheme.primaryText)
                            .frame(width: 56, alignment: .trailing)
                    }
                }

                Section("Minimum Wears") {
                    Stepper("\(draft.minWears) wear\(draft.minWears == 1 ? "" : "s")", value: $draft.minWears, in: 0...200)
                }

                Section("Brand") {
                    TextField("e.g. Nike, Zara", text: $draft.brand)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                }

                Section("Condition") {
                    Picker("Condition", selection: $draft.condition) {
                        Text("Any").tag("")
                        ForEach(conditions, id: \.self) { cond in
                            Text(cond).tag(cond)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    Button("Reset to defaults") {
                        pluckImpactFeedback(.light)
                        draft = VaultFilters()
                    }
                    .foregroundStyle(PluckTheme.danger)
                }
            }
            .navigationTitle("Filter Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        pluckImpactFeedback(.light)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        pluckImpactFeedback()
                        filters = draft
                        onApply()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .scrollContentBackground(.hidden)
            .background(PluckTheme.background)
        }
    }

    private func formatPrice(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }
}

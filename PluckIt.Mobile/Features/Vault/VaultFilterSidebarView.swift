import SwiftUI

struct VaultFilters: Equatable {
    var group: VaultSmartGroup = .all
    var priceMin: Double = 0
    var priceMax: Double = 2000
    var minWears: Int = 0
    var brand: String = ""
    var condition: String = ""

    var isDefault: Bool {
        self == VaultFilters()
    }
}

enum VaultSmartGroup: String, CaseIterable {
    case all = "All"
    case favorites = "Favorites"
    case recentlyWorn = "Recently Worn"
}

struct VaultFilterSidebarView: View {
    @Binding var filters: VaultFilters
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: VaultFilters

    private let conditions = ["", "New", "Excellent", "Good", "Fair", "Poor"]

    init(filters: Binding<VaultFilters>, onApply: @escaping () -> Void) {
        self._filters = filters
        self.onApply = onApply
        self._draft = State(initialValue: filters.wrappedValue)
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
                        ForEach(conditions.dropFirst(), id: \.self) { cond in
                            Text(cond).tag(cond)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    Button("Reset to defaults") {
                        draft = VaultFilters()
                    }
                    .foregroundStyle(PluckTheme.danger)
                }
            }
            .navigationTitle("Filter Vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        filters = draft
                        onApply()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func formatPrice(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }
}

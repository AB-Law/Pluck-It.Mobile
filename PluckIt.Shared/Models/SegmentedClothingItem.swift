import Foundation

struct SegmentedClothingItem: Identifiable {
    let id = UUID()
    let labelID: Int
    let label: String
    let imageData: Data
    var isSelected: Bool = true

    static let labelNames: [Int: String] = [
        4:  "Upper Clothes",
        5:  "Skirt",
        6:  "Pants",
        7:  "Dress",
        8:  "Belt",
        9:  "Left Shoe",
        10: "Right Shoe",
        16: "Bag",
        17: "Scarf",
    ]
}

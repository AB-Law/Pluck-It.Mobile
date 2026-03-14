//
//  Item.swift
//  PluckIt.Mac
//
//  Created by Akshay B on 15/03/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}

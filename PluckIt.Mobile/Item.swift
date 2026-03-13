//
//  Item.swift
//  PluckIt.Mobile
//
//  Created by Akshay B on 13/03/26.
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

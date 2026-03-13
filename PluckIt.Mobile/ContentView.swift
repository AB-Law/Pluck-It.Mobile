//
//  ContentView.swift
//  PluckIt.Mobile
//
//  Created by Akshay B on 13/03/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        AppRootView()
    }
}

#Preview {
    ContentView()
        .environmentObject(AppServices())
        .environmentObject(MobileNavState())
}

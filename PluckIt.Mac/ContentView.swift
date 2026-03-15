//
//  ContentView.swift
//  PluckIt.Mac
//
//  Created by Akshay B on 15/03/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appServices: AppServices

    var body: some View {
        ZStack {
            PluckTheme.background
                .ignoresSafeArea()

            if appServices.authService.isSignedIn {
                MacShellView()
            } else {
                MacLoginView()
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppServices())
}

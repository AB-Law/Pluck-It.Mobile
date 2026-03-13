//
//  ContentView.swift
//  PluckIt.Mobile
//
//  Created by Akshay B on 13/03/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appServices: AppServices

    var body: some View {
        ZStack {
            PluckTheme.background
                .ignoresSafeArea()

            Group {
                if appServices.authService.isSignedIn {
                    AppRootView()
                } else {
                    LoginView()
                }
            }
            .id(appServices.authService.isSignedIn)
            .transition(.opacity)
            .pluckReveal(delay: 0.05)
        }
        .animation(.easeInOut(duration: 0.24), value: appServices.authService.isSignedIn)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppServices())
        .environmentObject(MobileNavState())
}

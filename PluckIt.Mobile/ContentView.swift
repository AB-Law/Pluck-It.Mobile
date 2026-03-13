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
        Group {
            if appServices.authService.isSignedIn {
                AppRootView()
            } else {
                LoginView()
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppServices())
        .environmentObject(MobileNavState())
}

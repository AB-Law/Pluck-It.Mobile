//
//  PluckIt_MobileApp.swift
//  PluckIt.Mobile
//
//  Created by Akshay B on 13/03/26.
//

import SwiftUI
import SwiftData

@main
struct PluckIt_MobileApp: App {
    @StateObject private var appServices = AppServices()
    @StateObject private var navState = MobileNavState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appServices)
                .environmentObject(navState)
                .environmentObject(appServices.authService)
                .environmentObject(appServices.networkMonitor)
        }
    }
}

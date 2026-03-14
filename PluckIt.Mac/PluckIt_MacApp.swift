//
//  PluckIt_MacApp.swift
//  PluckIt.Mac
//
//  Created by Akshay B on 15/03/26.
//

import SwiftUI

@main
struct PluckIt_MacApp: App {
    @StateObject private var appServices = AppServices()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appServices)
                .environmentObject(appServices.authService)
                .environmentObject(appServices.networkMonitor)
        }
        .defaultSize(width: 1440, height: 900)
    }
}

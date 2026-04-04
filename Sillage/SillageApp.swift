//
//  SillageApp.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 19/03/2026.
//

import SwiftUI

@main
struct SillageApp: App {
    @State private var appViewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.marineUIStyle, appViewModel.marineUIStyle)
                .environment(appViewModel)
        }
    }
}

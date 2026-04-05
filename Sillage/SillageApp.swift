//
//  SillageApp.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//
//  Created by Alcyone on 19/03/2026.
//

import SwiftUI

@main
struct SillageApp: App {
  @State private var appViewModel = AppViewModel()
  @StateObject private var mapViewModel = MapViewModel()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(\.marineUIStyle, appViewModel.marineUIStyle)
        .environment(appViewModel)
        .environmentObject(mapViewModel)
    }
  }
}

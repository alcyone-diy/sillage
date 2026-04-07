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
import MapLibre

@main
struct SillageApp: App {
  @State private var appViewModel = AppViewModel()
  @StateObject private var mapViewModel = MapViewModel()
  @AppStorage("hasAcceptedDisclaimer") private var hasAcceptedDisclaimer = false

  init() {
    URLProtocol.registerClass(TileProxyProtocol.self)

    guard let config = MLNNetworkConfiguration.sharedManager.sessionConfiguration else {
        // If maplibre has no configuration, we can't inject. (Extremely rare).
        return
    }

    if let protocolClasses = config.protocolClasses {
        var newProtocolClasses = protocolClasses
        newProtocolClasses.insert(TileProxyProtocol.self, at: 0)
        config.protocolClasses = newProtocolClasses
    } else {
        config.protocolClasses = [TileProxyProtocol.self]
    }
    // Explicitly reassign the configuration object to MapLibre
    MLNNetworkConfiguration.sharedManager.sessionConfiguration = config
  }

  var body: some Scene {
    WindowGroup {
      if hasAcceptedDisclaimer {
        ContentView()
          .environment(\.marineTheme, appViewModel.marineTheme)
          .environment(appViewModel)
          .environmentObject(mapViewModel)
      } else {
        DisclaimerView()
      }
    }
  }
}

//
//  SillageApp.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-03-19.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import MapLibre
import OSLog

@main
struct SillageApp: App {
  @Environment(\.scenePhase) private var scenePhase
  @State private var environment = AppEnvironment()
  
  var body: some Scene {
    WindowGroup {
      Group {
        switch environment.state {
        case .uninitialized, .bootstrapping, .error:
          SplashView(state: environment.state) {
            Task {
              await environment.bootstrap()
            }
          }
        case .ready:
          if let appVM = environment.appViewModel,
             let mapVM = environment.mapViewModel,
             let panelVM = environment.panelManagerViewModel,
             let trackRecService = environment.trackRecordingService,
             let trackService = environment.trackService,
             let preferences = environment.preferencesService {
            MainAppView(
              appViewModel: appVM,
              mapViewModel: mapVM,
              panelManagerViewModel: panelVM,
              trackRecordingService: trackRecService,
              trackService: trackService,
              preferencesService: preferences
            )
          } else {
            // Fallback in case of an unexpected nil after .ready transition
            Text("Critical Error: Missing ViewModels")
              .marineFont(.headline)
              .foregroundColor(.red)
          }
        }
      }
      .task {
        if case .uninitialized = environment.state {
          await environment.bootstrap()
        }
      }
    }
    .onChange(of: scenePhase) { oldPhase, newPhase in
      if newPhase == .background {
        performEmergencySave()
      }
    }
  }
  
  @MainActor
  private func performEmergencySave() {
    guard let trackService = environment.trackRecordingService else { return }
    switch trackService.state {
    case .recording, .paused:
      BackgroundTaskRunner.execute(name: "EmergencyTrackFlush", priority: .high) { [weak trackService] in
        await trackService?.emergencyFlushAsync()
      }
    case .idle, .saving:
      return
    }
  }
}

struct MainAppView: View {
  @Bindable var appViewModel: AppViewModel
  var mapViewModel: MapViewModel
  var panelManagerViewModel: PanelManagerViewModel
  var trackRecordingService: TrackRecordingService
  var trackService: TrackService
  var preferencesService: PreferencesService
  
  @AppStorage("hasAcceptedDisclaimer") private var hasAcceptedDisclaimer = false
  
  var body: some View {
    Group {
      if hasAcceptedDisclaimer {
        ContentView()
          .environment(\.marineTheme, appViewModel.marineTheme)
          .environment(appViewModel)
          .environment(mapViewModel)
          .environment(panelManagerViewModel)
          .environment(trackRecordingService)
          .environment(\.trackService, trackService)
          .onOpenURL { url in
            appViewModel.handleIncomingURL(url)
          }
      } else {
        DisclaimerView()
          .onOpenURL { url in
            appViewModel.handleIncomingURL(url)
          }
      }
    }
    .environment(preferencesService)
  }
}

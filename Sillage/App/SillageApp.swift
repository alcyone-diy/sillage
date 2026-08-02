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
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
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
        case .ready(let container):
          MainAppView()
            .onAppear { appDelegate.appViewModel = container.appViewModel }
            .environment(container.appViewModel)
            .environment(container.chartViewModel)
            .environment(container.panelManagerViewModel)
            .environment(container.activeTrackViewModel)
            .environment(container.barometerViewModel)
            .environment(container.anchorViewModel)
            .environment(container.trackRecordingService)
            .environment(\.trackService, container.trackService)
            .environment(\.waypointService, container.waypointService)
            .environment(container.preferencesService)
            .environment(container.permissionService)
            .environment(container.offlineSelectionViewModel)
            .environment(container.messageService)
            .environment(container.geoGarageAuthService)
        }
      }
      .environment(environment)
      .onAppear {
        UIApplication.shared.isIdleTimerDisabled = true
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
    guard case .ready(let container) = environment.state else { return }
    let trackService = container.trackRecordingService
    switch trackService.state {
    case .recording, .paused, .waitingForFix:
      BackgroundTaskRunner.execute(name: "EmergencyTrackFlush", priority: .high) { [weak trackService] in
        await trackService?.emergencyFlushAsync()
      }
    case .idle, .saving:
      return
    }
  }
}

struct MainAppView: View {
  @Environment(AppViewModel.self) private var appViewModel
  
  @AppStorage("hasAcceptedDisclaimer") private var hasAcceptedDisclaimer = false
  
  var body: some View {
    Group {
      if hasAcceptedDisclaimer {
        ContentView()
          .environment(\.marineTheme, appViewModel.marineTheme)
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
  }
}

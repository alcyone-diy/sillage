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

@main
struct SillageApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      if AppDelegate.isRunningUnitTests {
        // Prevent the host app from booting MapLibre and live services during unit tests
        // so background tile, database, or sensor activity cannot race with isolated tests.
        EmptyView()
      } else {
        appContent
      }
    }
    .onChange(of: scenePhase) { oldPhase, newPhase in
      guard !AppDelegate.isRunningUnitTests else { return }
      if newPhase == .background {
        performEmergencySave()
      }
    }
  }

  private var appContent: some View {
    let environment = appDelegate.environment
    return Group {
      switch environment.state {
      case .uninitialized, .bootstrapping, .error:
        SplashView(state: environment.state) {
          appDelegate.startOrRetryBootstrap()
        }
      case .ready(let container):
        MainAppView()
          .onAppear {
            container.appViewModel.isReady = true
            container.appViewModel.processDeferredIntent()
          }
          .environment(container.appViewModel)
          .environment(container.chartViewModel)
          .environment(container.activeTrackViewModel)
          .environment(container.barometerViewModel)
          .environment(container.anchorViewModel)
          .environment(container.trackRecordingService)
          .environment(container.waypointService)
          .environment(container.checklistService)
          .environment(container.preferencesService)
          .environment(container.permissionService)
          .environment(container.offlineSelectionViewModel)
          .environment(container.messageService)
          .environment(container.geoGarageAuthService)
          .environment(container.secondaryTelemetryViewModel)
          .defaultAppStorage(container.userDefaults)
      }
    }
    .environment(environment)
    .onAppear {
      // CRITICAL MARINE SAFETY: The screen must NEVER automatically go to sleep while Sillage is open.
      // No other service or ViewModel is allowed to reset `isIdleTimerDisabled` to `false`.
      UIApplication.shared.isIdleTimerDisabled = true
    }
  }
  
  @MainActor
  private func performEmergencySave() {
    guard case .ready(let container) = appDelegate.environment.state else { return }
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

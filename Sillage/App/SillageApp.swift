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
import UserNotifications

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
            .onAppear { 
              appDelegate.appViewModel = container.appViewModel
              appDelegate.chartDownloader = container.geoGarageChartDownloader
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
        UIApplication.shared.isIdleTimerDisabled = true
      }
      .task {
        if case .uninitialized = environment.state {
          await environment.bootstrap()
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
        performTerminationWarning()
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
  
  @MainActor
  private func performTerminationWarning() {
    Logger.system.info("performTerminationWarning called.")
    guard case .ready(let container) = environment.state else { return }
    let trackService = container.trackRecordingService
    let isTracking: Bool = {
      switch trackService.state {
      case .recording, .paused, .waitingForFix: return true
      case .idle, .saving: return false
      }
    }()
    
    let isAnchoring = container.anchorViewModel.status != .inactive
    
    if isTracking || isAnchoring {
      let permissionService = container.permissionService
      let isCriticalAuthorized = permissionService.criticalAlertStatus == .enabled
      // Require explicit `.enabled` so `.unknown` during early app termination never sends an unauthorized `.timeSensitive` alert.
      let isTimeSensitiveAuthorized = permissionService.timeSensitiveStatus == .enabled
      let content = LocalNotificationService.makeNotificationContent(
        title: String(localized: "Sillage Terminated"),
        body: String(localized: "The application has been closed by iOS. Active services (like tracking or anchor watch) have been stopped."),
        identifier: NotificationIntent.appTerminated.rawValue,
        isCritical: true,
        isCriticalAuthorized: isCriticalAuthorized,
        isTimeSensitiveAuthorized: isTimeSensitiveAuthorized
      )

      // Note: This XPC call to UNUserNotificationCenter suffers from a race condition
      // during a crash or OOM kill (willTerminate is not even called for OOM).
      // This is a "Best Effort" for explicit user force-quits.
      let request = UNNotificationRequest(identifier: NotificationIntent.appTerminated.rawValue, content: content, trigger: nil)
      UNUserNotificationCenter.current().add(request) { error in
        if let error = error {
          Logger.system.error("Failed to send termination warning: \(error.localizedDescription, privacy: .public)")
        } else {
          Logger.system.info("Termination warning notification sent.")
        }
      }
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

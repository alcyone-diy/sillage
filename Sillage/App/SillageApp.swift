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
  @State private var appViewModel = AppViewModel()
  @State private var mapViewModel = MapViewModel()
  @State private var panelManagerViewModel = PanelManagerViewModel()
  @State private var trackRecordingService = TrackRecordingService()
  
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
    setupFileSystem()
  }
  
  var body: some Scene {
    WindowGroup {
      Group {
        MainAppView(
          appViewModel: appViewModel,
          mapViewModel: mapViewModel,
          panelManagerViewModel: panelManagerViewModel,
          trackRecordingService: trackRecordingService
        )
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
    guard trackRecordingService.isRecording else { return }
    BackgroundTaskRunner.execute(name: "EmergencyTrackFlush", priority: .high) { [weak trackRecordingService] in
      await trackRecordingService?.emergencyFlushAsync()
    }
  }

  private func setupFileSystem() {
    let fm = FileManager.default
    guard let docsURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
    let chartsURL = docsURL.appendingPathComponent("Charts", isDirectory: true)
    do {
      // 1. Create the 'Charts' subdirectory if it doesn't exist
      if !fm.fileExists(atPath: chartsURL.path) {
        try fm.createDirectory(at: chartsURL, withIntermediateDirectories: true)
      }
      // 2. Write a dummy file to force iOS to expose the Sillage folder in the Files app
      let dummyURL = docsURL.appendingPathComponent("Sillage_ReadMe.txt")
      if !fm.fileExists(atPath: dummyURL.path) {
        let text = "Alcyone Sillage - Chart Plotter.\nPlease place your .mbtiles files in the 'Charts' directory."
        try text.write(to: dummyURL, atomically: true, encoding: .utf8)
      }
      Logger.storage.debug("⚓️ FileSystem ready: \(docsURL.path)")
    } catch {
      Logger.storage.error("❌ Critical FileSystem initialization error: \(error.localizedDescription)")
    }
  }
}

struct MainAppView: View {
  @Bindable var appViewModel: AppViewModel
  var mapViewModel: MapViewModel
  var panelManagerViewModel: PanelManagerViewModel
  var trackRecordingService: TrackRecordingService
  
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
          .onOpenURL { url in
            appViewModel.handleIncomingURL(url)
          }
      } else {
        DisclaimerView()
          .onOpenURL { url in
            // Handle URL opening even if disclaimer is not yet accepted
            appViewModel.handleIncomingURL(url)
          }
      }
    }
    .alert("System Failure (Storage)", isPresented: Binding(
      get: { appViewModel.databaseErrorMessage != nil },
      set: { if !$0 { appViewModel.databaseErrorMessage = nil } }
    )) {
      Button("OK", role: .cancel) { }
    } message: {
      if let message = appViewModel.databaseErrorMessage {
        Text(message)
      }
    }
    .task {
      guard case .loading = appViewModel.dbState else { return }
      do {
        let dbManager = try await Task.detached {
          try DatabaseManager()
        }.value
        trackRecordingService.inject(databaseManager: dbManager)
        appViewModel.markDatabaseReady()
      } catch {
        appViewModel.markDatabaseError(error)
      }
    }
  }
}

//
//  AppEnvironment.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-20.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Observation
import OSLog
import MapLibre

@Observable
@MainActor
final class AppEnvironment {
  private(set) var state: AppState = .uninitialized

  // Services
  private(set) var preferencesService: PreferencesService?
  private(set) var locationService: LocationService?
  private(set) var trackRecordingService: TrackRecordingService?
  private(set) var trackService: TrackService?
  private(set) var geoGarageAuthService: GeoGarageAuthService?
  
  // ViewModels
  private(set) var appViewModel: AppViewModel?
  private(set) var mapViewModel: MapViewModel?
  private(set) var panelManagerViewModel: PanelManagerViewModel?
  
  init() {}
  
  func bootstrap() async {
    if case .bootstrapping = state { return }
    if case .ready = state { return }
    state = .bootstrapping
    Logger.system.info("🚀 Starting AppEnvironment bootstrap sequence.")
    
    do {
      // a. File system preparation
      try setupFileSystem()
      setupMapLibreProtocol()
      
      // b. DatabaseManager async initialization
      let databaseManager = try await Task.detached {
        try DatabaseManager()
      }.value
      
      // c. Other Services instantiation (injecting the ready DB)
      let preferencesService = PreferencesService()
      self.preferencesService = preferencesService
      
      let locationService = LocationService()
      self.locationService = locationService
      
      let trackRecordingService = TrackRecordingService(
        locationService: locationService,
        databaseManager: databaseManager
      )
      self.trackRecordingService = trackRecordingService
      
      let trackService = TrackService(databaseManager: databaseManager)
      self.trackService = trackService

      let geoGarageAuthService = GeoGarageAuthService()
      self.geoGarageAuthService = geoGarageAuthService
      
      // d. ViewModels instantiation (injecting the ready Services)
      self.appViewModel = AppViewModel(preferencesService: preferencesService)
      self.mapViewModel = MapViewModel(
        locationService: locationService,
        preferencesService: preferencesService,
        authService: geoGarageAuthService
      )
      self.panelManagerViewModel = PanelManagerViewModel()
      
      Logger.system.info("✅ AppEnvironment bootstrap complete. Transitioning to ready.")
      state = .ready
      
    } catch {
      Logger.system.error("❌ AppEnvironment bootstrap failed: \(error.localizedDescription, privacy: .public)")
      state = .error(error)
    }
  }
  
  private func setupFileSystem() throws {
    let fm = FileManager.default
    guard let docsURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
      throw NSError(domain: "AppEnvironmentError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Document directory not found"])
    }
    let chartsURL = docsURL.appendingPathComponent("Charts", isDirectory: true)
    
    if !fm.fileExists(atPath: chartsURL.path) {
      try fm.createDirectory(at: chartsURL, withIntermediateDirectories: true)
    }
    
    let dummyURL = docsURL.appendingPathComponent("Sillage_ReadMe.txt")
    if !fm.fileExists(atPath: dummyURL.path) {
      let text = "Alcyone Sillage - Chart Plotter.\nPlease place your .mbtiles files in the 'Charts' directory."
      try text.write(to: dummyURL, atomically: true, encoding: .utf8)
    }
    Logger.storage.debug("⚓️ FileSystem ready: \(docsURL.path)")
  }

  private func setupMapLibreProtocol() {
    URLProtocol.registerClass(TileProxyProtocol.self)
    guard let config = MLNNetworkConfiguration.sharedManager.sessionConfiguration else { return }
    
    if let protocolClasses = config.protocolClasses {
      var newProtocolClasses = protocolClasses
      if !newProtocolClasses.contains(where: { $0 == TileProxyProtocol.self }) {
        newProtocolClasses.insert(TileProxyProtocol.self, at: 0)
        config.protocolClasses = newProtocolClasses
      }
    } else {
      config.protocolClasses = [TileProxyProtocol.self]
    }
    MLNNetworkConfiguration.sharedManager.sessionConfiguration = config
  }
}

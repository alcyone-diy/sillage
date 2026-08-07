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

  public let metadata: AppMetadata
  public let bootDate: Date
  public let offlineMapManager: OfflineMapManager
  public let offlineMapDownloadService: OfflineMapDownloadService
  
  struct AppContainer {
    let messageService: MessageService
    let preferencesService: PreferencesService
    let positioningService: CoreLocationPositioningService
    let trackRecordingService: TrackRecordingService
    let trackService: TrackService
    let waypointService: WaypointService
    let geoGarageAuthService: GeoGarageAuthService
    let anchorService: AnchorService
    
    let appViewModel: AppViewModel
    let chartViewModel: ChartViewModel
    let panelManagerViewModel: PanelManagerViewModel
    let activeTrackViewModel: ActiveTrackViewModel
    let barometerViewModel: BarometerViewModel
    let anchorViewModel: AnchorViewModel
    let permissionService: PermissionService
    let offlineSelectionViewModel: OfflineSelectionViewModel
    let networkMonitorService: NetworkMonitorService
    let notificationService: NotificationService
  }
  
  public init(metadata: AppMetadata? = nil) {
    self.metadata = metadata ?? AppMetadataProvider.resolve()
    self.bootDate = Date.now
    Self.setupMapLibreProtocol()
    self.offlineMapManager = OfflineMapManager()
    self.offlineMapDownloadService = OfflineMapDownloadService(offlineMapManager: self.offlineMapManager)
  }
  
  func bootstrap() async {
    if case .bootstrapping = state { return }
    if case .ready = state { return }
    state = .bootstrapping
    Logger.system.info("🚀 Starting AppEnvironment bootstrap sequence. Boot time: \(self.bootDate, privacy: .public)")
    do {
      // a. File system preparation
      try await Task.detached {
        try self.setupFileSystem()
      }.value
      
      // b. DatabaseManager async initialization
      let databaseManager = try await Task.detached {
        try DatabaseManager()
      }.value
      
      // c. Other Services instantiation (injecting the ready DB)
      let messageService = MessageService()
      
      let preferencesService = PreferencesService()
      
      let positioningService = CoreLocationPositioningService()
      
      let instrumentDampingService = InstrumentDampingService(positioningService: positioningService)
      instrumentDampingService.start()
      
      let barometricHistoryStore = BarometricHistoryStore()
      await barometricHistoryStore.load()
      
      let notificationService = LocalNotificationService()
      
      let permissionService = PermissionService(
        positioningService: positioningService,
        notificationService: notificationService
      )
      
      let barometricService = BarometricService(
        historyStore: barometricHistoryStore,
        preferencesService: preferencesService,
        notificationService: notificationService,
        permissionService: permissionService
      )
      if permissionService.motionStatus == .authorized {
          barometricService.startUpdates()
      }
      
      let trackRecordingService = TrackRecordingService(
        positioningService: positioningService,
        databaseManager: databaseManager,
        preferencesService: preferencesService,
        messageService: messageService
      )
      
      let trackService = TrackService(databaseManager: databaseManager)

      let waypointService = WaypointService(
        databaseManager: databaseManager,
        initialGoToWaypointID: preferencesService.goToWaypointID
      )

      func observeWaypointGoTo() {
        withObservationTracking {
          _ = waypointService.goToWaypointID
        } onChange: {
          Task { @MainActor [weak waypointService, weak preferencesService] in
            guard let service = waypointService else { return }
            preferencesService?.goToWaypointID = service.goToWaypointID
            observeWaypointGoTo()
          }
        }
      }
      observeWaypointGoTo()

      let geoGarageAuthService = GeoGarageAuthService(preferencesService: preferencesService)
      await geoGarageAuthService.bootstrap()
      
      let backgroundMonitoringService = DefaultBackgroundMonitoringService(
        positioningService: positioningService,
        notificationService: notificationService
      )
      
      let anchorService = AnchorService(
        positioningService: positioningService,
        preferencesService: preferencesService,
        notificationService: notificationService,
        permissionService: permissionService,
        backgroundMonitoringService: backgroundMonitoringService
      )
      
      let anchorViewModel = AnchorViewModel(anchorService: anchorService)
      
      // d. ViewModels instantiation (injecting the ready Services)
      let panelManagerViewModel = PanelManagerViewModel()
      let appViewModel = AppViewModel(
        preferencesService: preferencesService,
        authService: geoGarageAuthService,
        panelManagerViewModel: panelManagerViewModel,
        anchorService: anchorService
      )

      let chartViewModel = ChartViewModel(
        positioningService: positioningService,
        instrumentDampingService: instrumentDampingService,
        preferencesService: preferencesService,
        authService: geoGarageAuthService,
        anchorService: anchorService,
        anchorViewModel: anchorViewModel,
        waypointService: waypointService,
        messageService: messageService
      )
      let activeTrackViewModel = ActiveTrackViewModel(
        trackRecordingService: trackRecordingService,
        permissionService: permissionService
      )
      let barometerViewModel = BarometerViewModel(
        service: barometricService,
        preferencesService: preferencesService
      )
      
      let offlineSelectionViewModel = OfflineSelectionViewModel(
        offlineMapManager: self.offlineMapManager,
        offlineMapDownloadService: self.offlineMapDownloadService
      )
      let networkMonitorService = NetworkMonitorService()
      await trackRecordingService.attemptRecoveryIfNeeded()
      
      if let displayedTrackID = preferencesService.displayedTrackSessionID {
        Task { @MainActor in
          do {
            try await chartViewModel.loadAndDisplaySavedTrack(sessionID: displayedTrackID, trackService: trackService, edgePadding: 50, centerOnTrack: false)
          } catch {
            Logger.system.error("❌ Failed to reload previous active track: \(error.localizedDescription, privacy: .public)")
          }
        }
      }
      
      let container = AppContainer(
        messageService: messageService,
        preferencesService: preferencesService,
        positioningService: positioningService,
        trackRecordingService: trackRecordingService,
        trackService: trackService,
        waypointService: waypointService,
        geoGarageAuthService: geoGarageAuthService,
        anchorService: anchorService,
        appViewModel: appViewModel,
        chartViewModel: chartViewModel,
        panelManagerViewModel: panelManagerViewModel,
        activeTrackViewModel: activeTrackViewModel,
        barometerViewModel: barometerViewModel,
        anchorViewModel: anchorViewModel,
        permissionService: permissionService,
        offlineSelectionViewModel: offlineSelectionViewModel,
        networkMonitorService: networkMonitorService,
        notificationService: notificationService
      )
      
      Logger.system.info("✅ AppEnvironment bootstrap complete. Transitioning to ready.")
      state = .ready(container)
      
    } catch {
      Logger.system.error("❌ AppEnvironment bootstrap failed: \(error.localizedDescription, privacy: .public)")
      state = .error(error)
    }
  }
  
  nonisolated private func setupFileSystem() throws {
    let fm = FileManager.default
    guard let docsURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
      throw NSError(domain: "AppEnvironmentError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Document directory not found"])
    }
    let chartsURL = docsURL.appendingPathComponent("Charts", isDirectory: true)
    
    if !fm.fileExists(atPath: chartsURL.path) {
      try fm.createDirectory(at: chartsURL, withIntermediateDirectories: true)
    }
    
    let dummyURL = docsURL.appendingPathComponent("\(AppConstants.appName)_ReadMe.txt")
    if !fm.fileExists(atPath: dummyURL.path) {
      Task.detached(priority: .background) {
        let text = "\(AppConstants.appName) - Chart Plotter.\nPlease place your .mbtiles files in the 'Charts' directory."
        do {
          try text.write(to: dummyURL, atomically: true, encoding: .utf8)
        } catch {
          Logger.storage.error("❌ Failed to write ReadMe file: \(error.localizedDescription, privacy: .public)")
        }
      }
    }
    
    // Cleanup GPX temporary directory explicitly in background to avoid blocking bootstrap
    cleanupGPXExports()
    
    Logger.storage.debug("⚓️ FileSystem ready: \(docsURL.path)")
  }
  
  /// Cleans up GPX export temporary files asynchronously.
  nonisolated public func cleanupGPXExports() {
    Task.detached(priority: .background) {
      let fm = FileManager.default
      let gpxTempDir = fm.temporaryDirectory.appendingPathComponent("GPXExports")
      if fm.fileExists(atPath: gpxTempDir.path) {
        do {
          try fm.removeItem(at: gpxTempDir)
          Logger.storage.debug("🧹 GPX temporary folder cleanup successful.")
        } catch {
          Logger.storage.error("❌ Failed to clean GPX temporary folder: \(error.localizedDescription)")
        }
      }
    }
  }

  nonisolated private static func setupMapLibreProtocol() {
    guard let config = MLNNetworkConfiguration.sharedManager.sessionConfiguration else { return }
    
    if let protocolClasses = config.protocolClasses {
      var newProtocolClasses = protocolClasses
      if !newProtocolClasses.contains(where: { $0 == TileProxyProtocol.self }) {
        newProtocolClasses.insert(TileProxyProtocol.self, at: 0)
      }
      config.protocolClasses = newProtocolClasses
    } else {
      config.protocolClasses = [TileProxyProtocol.self]
    }
    MLNNetworkConfiguration.sharedManager.sessionConfiguration = config
  }

}

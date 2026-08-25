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
  
  struct AppContainer {
    let messageService: MessageService
    let preferencesService: PreferencesService
    let positioningService: CoreLocationPositioningService
    let trackRecordingService: TrackRecordingService
    let trackService: TrackService
    let waypointService: WaypointService
    let geoGarageAuthService: GeoGarageAuthService
    let geoGarageDownloadRepository: GeoGarageDownloadRepository
    let geoGaragePackageService: GeoGaragePackageService
    let geoGarageChartDownloader: GeoGarageChartDownloader
    let geoGarageDownloadService: GeoGarageDownloadService
    let geoGarageOfflineTileProvider: GeoGarageOfflineTileProvider
    let anchorService: AnchorService
    
    let appViewModel: AppViewModel
    let chartViewModel: ChartViewModel
    let activeTrackViewModel: ActiveTrackViewModel
    let barometerViewModel: BarometerViewModel
    let anchorViewModel: AnchorViewModel
    let permissionService: PermissionService
    let offlineSelectionViewModel: OfflineSelectionViewModel
    let networkMonitorService: NetworkMonitorService
    let notificationService: NotificationService
    let secondaryTelemetryViewModel: SecondaryTelemetryViewModel
  }
  
  public init(metadata: AppMetadata? = nil) {
    self.metadata = metadata ?? AppMetadataProvider.resolve()
    self.bootDate = Date.now
    Self.setupMapLibreProtocol()
    self.offlineMapManager = OfflineMapManager()
    setupMapLibreProgressObservation()
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
      
      let positioningService = CoreLocationPositioningService(initialAccuracyMode: preferencesService.gpsAccuracyMode)
      
      let instrumentDampingService = InstrumentDampingService(positioningService: positioningService)
      instrumentDampingService.start()
      
      let barometricHistoryStore = BarometricHistoryStore(databaseManager: databaseManager)
      
      // Perform legacy JSON migration asynchronously in background without blocking bootstrap
      Task.detached(priority: .utility) {
        await barometricHistoryStore.migrateLegacyJSONIfNeeded()
      }
      
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

      let geoGaragePersistenceActor = LocalFilePersistenceActor()
      let geoGarageDownloadRepository = GeoGarageDownloadRepository(persistence: geoGaragePersistenceActor)
      await geoGarageDownloadRepository.load()

      let geoGarageOfflineTileProvider = GeoGarageOfflineTileProvider()
      TileProxyProtocol.configure(
        offlineTileProvider: geoGarageOfflineTileProvider,
        tileProxyManager: TileProxyManager.shared
      )

      let sharedSecret = AppConfiguration.shared.geoGarageSharedSecret
      let initialCustomerID = preferencesService.geoGarageCustomerID ?? AppConfiguration.shared.geoGarageClientID
      await geoGarageOfflineTileProvider.reloadDownloads(
        geoGarageDownloadRepository.downloads,
        sharedSecret: sharedSecret,
        customerID: initialCustomerID
      )

      func observeGeoGarageDownloads() {
        withObservationTracking {
          _ = geoGarageDownloadRepository.downloads
          _ = preferencesService.geoGarageCustomerID
        } onChange: {
          Task { @MainActor [weak geoGarageDownloadRepository, weak geoGarageOfflineTileProvider, weak preferencesService] in
            guard let repo = geoGarageDownloadRepository, let provider = geoGarageOfflineTileProvider else { return }
            let secret = AppConfiguration.shared.geoGarageSharedSecret
            let client = preferencesService?.geoGarageCustomerID ?? AppConfiguration.shared.geoGarageClientID
            await provider.reloadDownloads(repo.downloads, sharedSecret: secret, customerID: client)
            observeGeoGarageDownloads()
          }
        }
      }
      observeGeoGarageDownloads()

      let geoGaragePackageService = GeoGaragePackageService()
      let geoGarageChartDownloader = GeoGarageChartDownloader(
        packageService: geoGaragePackageService,
        downloadRepository: geoGarageDownloadRepository
      )
      
      let backgroundMonitoringService = DefaultBackgroundMonitoringService(
        positioningService: positioningService
      )
      
      let alarmAudioService = AlarmAudioService()
      
      let anchorService = AnchorService(
        positioningService: positioningService,
        preferencesService: preferencesService,
        notificationService: notificationService,
        permissionService: permissionService,
        backgroundMonitoringService: backgroundMonitoringService,
        alarmAudioService: alarmAudioService
      )
      
      let anchorViewModel = AnchorViewModel(anchorService: anchorService)
      
      // d. ViewModels instantiation (injecting the ready Services)
      let appViewModel = AppViewModel(
        preferencesService: preferencesService,
        authService: geoGarageAuthService,
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
      
      let networkMonitorService = NetworkMonitorService()
      let geoGarageDownloadService = GeoGarageDownloadService(
        packageService: geoGaragePackageService,
        downloader: geoGarageChartDownloader,
        downloadRepository: geoGarageDownloadRepository,
        preferencesService: preferencesService,
        networkMonitor: networkMonitorService
      )
      
      let offlineSelectionViewModel = OfflineSelectionViewModel(
        downloadService: geoGarageDownloadService,
        downloadRepository: geoGarageDownloadRepository,
        preferencesService: preferencesService,
        chartViewModel: chartViewModel,
        offlineMapManager: self.offlineMapManager,
        downloader: geoGarageChartDownloader
      )
      let secondaryTelemetryViewModel = SecondaryTelemetryViewModel()
      await trackRecordingService.attemptRecoveryIfNeeded()
      await geoGarageDownloadService.resumePendingDownloadIfNeeded()
      
      if let displayedTrackID = preferencesService.displayedTrackSessionID {
        Task { @MainActor in
          do {
            try await chartViewModel.loadAndDisplaySavedTrack(sessionID: displayedTrackID, trackService: trackService, edgePadding: 50, centerOnTrack: false)
          } catch {
            Logger.system.error("❌ Failed to reload previous active track: \(error.localizedDescription, privacy: .public)")
          }
        }
      }
      
      setupGeoGarageProgressObservation(geoGarageDownloadService: geoGarageDownloadService)

      let container = AppContainer(
        messageService: messageService,
        preferencesService: preferencesService,
        positioningService: positioningService,
        trackRecordingService: trackRecordingService,
        trackService: trackService,
        waypointService: waypointService,
        geoGarageAuthService: geoGarageAuthService,
        geoGarageDownloadRepository: geoGarageDownloadRepository,
        geoGaragePackageService: geoGaragePackageService,
        geoGarageChartDownloader: geoGarageChartDownloader,
        geoGarageDownloadService: geoGarageDownloadService,
        geoGarageOfflineTileProvider: geoGarageOfflineTileProvider,
        anchorService: anchorService,
        appViewModel: appViewModel,
        chartViewModel: chartViewModel,
        activeTrackViewModel: activeTrackViewModel,
        barometerViewModel: barometerViewModel,
        anchorViewModel: anchorViewModel,
        permissionService: permissionService,
        offlineSelectionViewModel: offlineSelectionViewModel,
        networkMonitorService: networkMonitorService,
        notificationService: notificationService,
        secondaryTelemetryViewModel: secondaryTelemetryViewModel
      )
      
      Logger.system.info("✅ AppEnvironment bootstrap complete. Transitioning to ready.")
      state = .ready(container)
      
    } catch {
      Logger.system.error("❌ AppEnvironment bootstrap failed: \(error.localizedDescription, privacy: .public)")
      state = .error(error)
    }
  }

  // MARK: - GeoGarage Offline Services

  var geoGarageDownloadService: GeoGarageDownloadService? {
    guard case .ready(let container) = state else { return nil }
    return container.geoGarageDownloadService
  }

  var geoGarageChartDownloader: GeoGarageChartDownloader? {
    guard case .ready(let container) = state else { return nil }
    return container.geoGarageChartDownloader
  }

  var geoGaragePackageService: GeoGaragePackageService? {
    guard case .ready(let container) = state else { return nil }
    return container.geoGaragePackageService
  }

  var geoGarageDownloadRepository: GeoGarageDownloadRepository? {
    guard case .ready(let container) = state else { return nil }
    return container.geoGarageDownloadRepository
  }

  var geoGarageOfflineTileProvider: GeoGarageOfflineTileProvider? {
    guard case .ready(let container) = state else { return nil }
    return container.geoGarageOfflineTileProvider
  }

  var preferencesService: PreferencesService? {
    guard case .ready(let container) = state else { return nil }
    return container.preferencesService
  }

  var offlineSelectionViewModel: OfflineSelectionViewModel? {
    guard case .ready(let container) = state else { return nil }
    return container.offlineSelectionViewModel
  }

  // MARK: - Global Offline Charts Download Status

  @ObservationIgnored
  private var geoGarageObservationTask: Task<Void, Never>?

  @ObservationIgnored
  private var mapLibreObservationTask: Task<Void, Never>?

  @ObservationIgnored
  private var lastGeoGarageProgress: Double?

  @ObservationIgnored
  private var lastMapLibreProgress: Double?

  /// Indicates whether an offline chart download is currently in progress across GeoGarage or MapLibre engines.
  var isDownloadingOfflineCharts: Bool {
    offlineChartsDownloadProgress != nil
  }

  /// Normalized download progress value (0.0 to 1.0) when available, or nil for indeterminate state.
  /// Stored property driven reactively via Swift 6 AsyncStream observation to guarantee SwiftUI updates across protocol boundaries.
  var offlineChartsDownloadProgress: Double? = nil

  @MainActor
  private func setupMapLibreProgressObservation() {
    mapLibreObservationTask?.cancel()
    mapLibreObservationTask = Task { @MainActor [weak self] in
      guard let self = self else { return }
      for await progress in self.offlineMapManager.downloadProgressStream() {
        guard !Task.isCancelled else { break }
        self.lastMapLibreProgress = progress
        self.updateCompositeOfflineChartsProgress()
      }
    }
  }

  @MainActor
  private func setupGeoGarageProgressObservation(geoGarageDownloadService: GeoGarageDownloadServiceProtocol) {
    geoGarageObservationTask?.cancel()
    geoGarageObservationTask = Task { @MainActor [weak self, weak geoGarageDownloadService] in
      guard let service = geoGarageDownloadService else { return }
      for await progress in service.downloadProgressStream() {
        guard !Task.isCancelled else { break }
        guard let self = self else { break }
        self.lastGeoGarageProgress = progress
        self.updateCompositeOfflineChartsProgress()
      }
    }
  }

  @MainActor
  private func updateCompositeOfflineChartsProgress() {
    if let gg = lastGeoGarageProgress, let ml = lastMapLibreProgress {
      self.offlineChartsDownloadProgress = (gg + ml) / 2.0
    } else if let gg = lastGeoGarageProgress {
      self.offlineChartsDownloadProgress = gg
    } else if let ml = lastMapLibreProgress {
      self.offlineChartsDownloadProgress = ml
    } else {
      self.offlineChartsDownloadProgress = nil
    }
  }

  // MARK: - GPS Accuracy

  /// Single entry point for changing GPS accuracy at runtime.
  /// Keeps PreferencesService and CoreLocationPositioningService in sync.
  func updateGPSAccuracy(to mode: GPSAccuracyMode) {
    guard case .ready(let container) = state else { return }
    container.preferencesService.gpsAccuracyMode = mode
    container.positioningService.setDesiredAccuracy(mode)
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

  deinit {
    geoGarageObservationTask?.cancel()
    mapLibreObservationTask?.cancel()
  }

}

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
  /// Fetches the package decryption secret from `/partners/me/` after sign-in, so nothing secret
  /// ships in the binary; the secret lives in the Keychain.
  public let geoGaragePartnerSecretService: any GeoGaragePartnerSecretServiceProtocol
  
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
  
  /// Injectable so unit tests never reach the real GeoGarage portal.
  private let authSession: URLSession

  public init(
    metadata: AppMetadata? = nil,
    partnerSecretService: (any GeoGaragePartnerSecretServiceProtocol)? = nil,
    authSession: URLSession = .shared
  ) {
    self.metadata = metadata ?? AppMetadataProvider.resolve()
    self.bootDate = Date.now
    Self.setupMapLibreProtocol()
    self.offlineMapManager = OfflineMapManager()
    self.geoGaragePartnerSecretService = partnerSecretService ?? GeoGaragePartnerSecretService()
    self.authSession = authSession
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

      let geoGarageAuthService = GeoGarageAuthService(preferencesService: preferencesService, session: authSession)
      await geoGarageAuthService.bootstrap()

      let geoGaragePersistenceActor = LocalFilePersistenceActor()
      let geoGarageDownloadRepository = GeoGarageDownloadRepository(persistence: geoGaragePersistenceActor)
      await geoGarageDownloadRepository.load()

      let geoGarageOfflineTileProvider = GeoGarageOfflineTileProvider()
      TileProxyProtocol.configure(
        offlineTileProvider: geoGarageOfflineTileProvider,
        tileProxyManager: TileProxyManager.shared
      )

      // Empty until the user signs in; `reloadDownloads` then skips it with a warning.
      let sharedSecret = await KeychainManager.shared.retrieveToken(for: GeoGaragePartnerSecretService.keychainAccount) ?? ""
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
            let secret = await KeychainManager.shared.retrieveToken(for: GeoGaragePartnerSecretService.keychainAccount) ?? ""
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

      // The secret catch-up talks to the portal (up to three 15 s calls). Keep it off the launch
      // critical path so a boat connected without WAN never waits on it.
      packageSecretRestoreTask?.cancel()
      packageSecretRestoreTask = Task { @MainActor [weak self] in
        guard let self else { return }
        await self.restorePackageSecretIfMissing(
          authService: geoGarageAuthService,
          messageService: messageService,
          downloadRepository: geoGarageDownloadRepository,
          offlineTileProvider: geoGarageOfflineTileProvider,
          preferencesService: preferencesService
        )
      }

    } catch {
      Logger.system.error("❌ AppEnvironment bootstrap failed: \(error.localizedDescription, privacy: .public)")
      state = .error(error)
    }
  }

  // MARK: - GeoGarage Package Secret Recovery

  /// Secret catch-up started after `state = .ready`; exposed so tests can await it.
  @ObservationIgnored
  private(set) var packageSecretRestoreTask: Task<Void, Never>?

  /// One-shot recovery of a package secret missing from the Keychain at launch. An install signed
  /// in before the secret existed (or whose `/partners/me/` call failed at sign-in) keeps its tokens
  /// but has no secret; without this, `reloadDownloads` silently closed every offline reader.
  private func restorePackageSecretIfMissing(
    authService: GeoGarageAuthService,
    messageService: MessageService,
    downloadRepository: GeoGarageDownloadRepository,
    offlineTileProvider: GeoGarageOfflineTileProvider,
    preferencesService: PreferencesService
  ) async {
    guard authService.isGeoGarageAuthenticated else { return }
    let storedSecret = await KeychainManager.shared.retrieveToken(for: GeoGaragePartnerSecretService.keychainAccount) ?? ""
    guard storedSecret.isEmpty else { return }
    let accessToken = await KeychainManager.shared.retrieveToken(for: "geogarage_access_token") ?? ""
    guard !accessToken.isEmpty else { return }

    do {
      let secrets = try await geoGaragePartnerSecretService.refresh(accessToken: accessToken)
      Logger.network.info("Partner package secret restored at startup.")
      await openOfflineReaders(
        with: secrets.packageSecret,
        messageService: messageService,
        downloadRepository: downloadRepository,
        offlineTileProvider: offlineTileProvider,
        preferencesService: preferencesService
      )
      return
    } catch PartnerSecretError.unauthorized {
      // Access token expired since the last launch: refresh once, then a single retry.
      Logger.network.info("Partner package secret restore rejected the access token, refreshing once.")
    } catch PartnerSecretError.networkError(let description) {
      // Offline at launch: the next launch retries, no need to alarm the user.
      Logger.network.info("Partner package secret restore skipped, network unavailable: \(description, privacy: .public)")
      return
    } catch PartnerSecretError.cancelled {
      Logger.network.info("Partner package secret restore cancelled.")
      return
    } catch {
      Logger.network.error("Partner package secret restore failed: \(String(describing: error), privacy: .public)")
      postPackageSecretWarning(on: messageService)
      return
    }

    do {
      let tokens = try await authService.refreshTokens()
      let secrets = try await geoGaragePartnerSecretService.refresh(accessToken: tokens.access_token)
      Logger.network.info("Partner package secret restored at startup after a token refresh.")
      await openOfflineReaders(
        with: secrets.packageSecret,
        messageService: messageService,
        downloadRepository: downloadRepository,
        offlineTileProvider: offlineTileProvider,
        preferencesService: preferencesService
      )
    } catch AuthError.tokenExpired {
      // Refresh token replaced, revoked or purged: the real cause is "session expired", already
      // published in `authError` and shown by Settings. A second message would mislead the user.
      Logger.network.info("Partner package secret restore stopped, the GeoGarage session has expired.")
    } catch AuthError.networkError(let error) {
      // Offline during the refresh: same policy as `/partners/me/` offline.
      Logger.network.info("Partner package secret restore skipped, token refresh offline: \(error.localizedDescription, privacy: .public)")
    } catch AuthError.cancelled {
      Logger.network.info("Partner package secret restore cancelled during the token refresh.")
    } catch PartnerSecretError.networkError(let description) {
      Logger.network.info("Partner package secret restore skipped after token refresh, network unavailable: \(description, privacy: .public)")
    } catch PartnerSecretError.cancelled {
      Logger.network.info("Partner package secret restore cancelled after token refresh.")
    } catch {
      Logger.network.error("Partner package secret restore failed after token refresh: \(String(describing: error), privacy: .public)")
      postPackageSecretWarning(on: messageService)
    }
  }

  /// Reopens the offline readers with the freshly fetched secret. The launch `reloadDownloads` ran
  /// with an empty Keychain, and neither `downloads` nor `geoGarageCustomerID` changed since, so
  /// observation never fires on its own.
  private func openOfflineReaders(
    with packageSecret: String,
    messageService: MessageService,
    downloadRepository: GeoGarageDownloadRepository,
    offlineTileProvider: GeoGarageOfflineTileProvider,
    preferencesService: PreferencesService
  ) async {
    messageService.clear(category: .offlineCharts)
    let customerID = preferencesService.geoGarageCustomerID ?? AppConfiguration.shared.geoGarageClientID
    await offlineTileProvider.reloadDownloads(
      downloadRepository.downloads,
      sharedSecret: packageSecret,
      customerID: customerID
    )
  }

  private func postPackageSecretWarning(on messageService: MessageService) {
    let appMessage = AppMessage(
      title: LocalizedStringResource("Offline charts unavailable"),
      detail: LocalizedStringResource("GeoGarage did not provide the decryption secret. Online charts work; offline downloads are disabled until the next sign-in."),
      severity: .warning,
      // `.offlineCharts`, not `.geoGarage`: the silent layer fetch purges `.geoGarage` on success
      // and would take this warning with it.
      category: .offlineCharts,
      intent: .openSettings(target: .geoGarage)
    )
    messageService.post(appMessage)
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
    packageSecretRestoreTask?.cancel()
  }

}

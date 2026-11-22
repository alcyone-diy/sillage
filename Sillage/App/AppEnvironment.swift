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
import os
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
  
  @MainActor
  struct AppContainer {
    let userDefaults: UserDefaults
    let messageService: MessageService
    let preferencesService: PreferencesService
    let positioningService: any PositioningService
    let trackRecordingService: TrackRecordingService
    let trackService: TrackService
    let waypointService: WaypointService
    let geoGarageAuthService: GeoGarageAuthService
    let geoGarageLayerRepository: GeoGarageLayerRepository
    let geoGarageDownloadRepository: GeoGarageDownloadRepository
    let geoGaragePackageService: GeoGaragePackageService
    let geoGarageChartDownloader: GeoGarageChartDownloader
    let geoGarageDownloadService: GeoGarageDownloadService
    let geoGarageOfflineTileProvider: GeoGarageOfflineTileProvider
    let anchorService: AnchorService
    let kinematicsService: VesselKinematicsService
    
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
    let checklistService: ChecklistService

    #if DEBUG
    fileprivate(set) var developerSettingsService = DeveloperSettingsService()

    func withDeveloperSettings(_ service: DeveloperSettingsService) -> Self {
      var copy = self
      copy.developerSettingsService = service
      return copy
    }
    #endif
  }
  
  /// Injectable so unit tests never reach the real GeoGarage portal.
  private let authSession: URLSession
  let keychainManager: any KeychainManaging
  private let tileProxyManager: TileProxyManager
  private let preferencesServiceOverride: PreferencesService?
  private let userDefaults: UserDefaults
  private let databaseManagerOverride: DatabaseManager?
  private let anchorStateStoreOverride: (any AnchorStateStoreProtocol)?
  #if DEBUG
  private var screenshotScenarioOverride: ScreenshotScenario?
  #endif

  public init(
    metadata: AppMetadata? = nil,
    partnerSecretService: (any GeoGaragePartnerSecretServiceProtocol)? = nil,
    authSession: URLSession = .shared,
    keychainManager: any KeychainManaging = KeychainManager.shared,
    preferencesService: PreferencesService? = nil,
    userDefaults: UserDefaults = .standard,
    databaseManager: DatabaseManager? = nil,
    anchorStateStore: (any AnchorStateStoreProtocol)? = nil
  ) {
    self.metadata = metadata ?? AppMetadataProvider.resolve()
    self.bootDate = Date.now
    Self.setupMapLibreProtocol()
    self.offlineMapManager = OfflineMapManager()
    self.keychainManager = keychainManager
    self.tileProxyManager = TileProxyManager(keychainManager: keychainManager)
    self.geoGaragePartnerSecretService = partnerSecretService ?? GeoGaragePartnerSecretService(keychainManager: keychainManager)
    self.authSession = authSession
    self.preferencesServiceOverride = preferencesService
    self.userDefaults = userDefaults
    self.databaseManagerOverride = databaseManager
    self.anchorStateStoreOverride = anchorStateStore
    setupMapLibreProgressObservation()
  }

  #if DEBUG
  convenience init(
    screenshotScenario: ScreenshotScenario,
    partnerSecretService: (any GeoGaragePartnerSecretServiceProtocol)? = nil,
    authSession: URLSession = .shared,
    keychainManager: any KeychainManaging = KeychainManager.shared,
    userDefaults: UserDefaults = .standard,
    databaseManager: DatabaseManager? = nil,
    anchorStateStore: (any AnchorStateStoreProtocol)? = nil
  ) {
    self.init(
      partnerSecretService: partnerSecretService,
      authSession: authSession,
      keychainManager: keychainManager,
      userDefaults: userDefaults,
      databaseManager: databaseManager,
      anchorStateStore: anchorStateStore
    )
    self.screenshotScenarioOverride = screenshotScenario
  }
  #endif
  
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
      #if DEBUG
      let activeScreenshotScenario = self.screenshotScenarioOverride ?? ScreenshotScenario.active
      if let scenario = activeScreenshotScenario {
        let gpsLabel = scenario.gpsPreset?.rawValue ?? "off"
        let baroLabel = scenario.baroPreset?.rawValue ?? "off"
        Logger.system.notice("📸 Sensor simulation active (gps=\(gpsLabel, privacy: .public), baro=\(baroLabel, privacy: .public), tracks=\(scenario.simulateTracksAndWaypoints, privacy: .public)). User preferences remain untouched.")
      }
      #endif

      let databaseManager: DatabaseManager
      if let databaseManagerOverride {
        databaseManager = databaseManagerOverride
      } else {
        databaseManager = try await Task.detached {
          try DatabaseManager()
        }.value
      }

      #if DEBUG
      if let scenario = activeScreenshotScenario, scenario.simulateTracksAndWaypoints {
        try await ScreenshotBootstrapper.seedTracksAndWaypoints(scenario, into: databaseManager)
      } else {
        try await ScreenshotBootstrapper.removeSeededTracksAndWaypoints(from: databaseManager)
      }
      #endif
      
      // c. Other Services instantiation (injecting the ready DB)
      let messageService = MessageService()

      let preferencesService = self.preferencesServiceOverride ?? PreferencesService(
        defaults: self.userDefaults,
        keychainManager: self.keychainManager
      )
      #if DEBUG
      let devSettingsDefaults: UserDefaults? = {
        guard activeScreenshotScenario?.gpsPreset != nil else { return nil }
        let suiteName = "com.alcyone.sillage.simulated.devsettings"
        let ephemeralDefaults = UserDefaults(suiteName: suiteName)
        ephemeralDefaults?.removePersistentDomain(forName: suiteName)
        return ephemeralDefaults
      }()
      let developerSettingsService = DeveloperSettingsService(defaults: devSettingsDefaults ?? self.userDefaults)
      if activeScreenshotScenario?.gpsPreset != nil {
        developerSettingsService.cogSogCalculationSource = .iOS
        developerSettingsService.cogDampingDuration = 0.0
      }

      let simulatedPositioning: (any PositioningService)? = if let scenario = activeScreenshotScenario, scenario.gpsPreset != nil {
        SimulatedPositioningService(scenario: scenario)
      } else {
        nil
      }
      let initialPausesAutomatically = developerSettingsService.pausesLocationUpdatesAutomatically
      #else
      let simulatedPositioning: (any PositioningService)? = nil
      let initialPausesAutomatically = false
      #endif
      let positioningService: any PositioningService = simulatedPositioning ?? CoreLocationPositioningService(
        initialAccuracyMode: preferencesService.gpsAccuracyMode,
        initialPausesLocationUpdatesAutomatically: initialPausesAutomatically
      )
      
      let kinematicsService = VesselKinematicsService(
        positioningService: positioningService
      )
      
      let instrumentDampingService = InstrumentDampingService(
        positioningService: kinematicsService
      )

      #if DEBUG
      kinematicsService.calculationSource = developerSettingsService.cogSogCalculationSource
      kinematicsService.noiseMultiplier = developerSettingsService.noiseMultiplier
      kinematicsService.velocityWindowDuration = developerSettingsService.velocityWindowDuration
      instrumentDampingService.cogDampingDuration = developerSettingsService.cogDampingDuration

      observeDeveloperSettings(
        developerSettingsService: developerSettingsService,
        kinematicsService: kinematicsService,
        instrumentDampingService: instrumentDampingService
      )
      #endif
      
      #if DEBUG
      let baroDatabaseManager: DatabaseManager
      if let scenario = activeScreenshotScenario, scenario.baroPreset != nil {
        if let databaseManagerOverride {
          try await ScreenshotBootstrapper.seedBarometricHistory(scenario, into: databaseManagerOverride)
          baroDatabaseManager = databaseManagerOverride
        } else {
          baroDatabaseManager = try await ScreenshotBootstrapper.makeBarometricDatabase(scenario: scenario)
        }
      } else {
        baroDatabaseManager = databaseManager
      }
      #else
      let baroDatabaseManager = databaseManager
      #endif
      let barometricHistoryStore = BarometricHistoryStore(databaseManager: baroDatabaseManager)
      
      let notificationService = LocalNotificationService()
      
      let permissionService = PermissionService(
        positioningService: positioningService,
        notificationService: notificationService
      )
      #if DEBUG
      if let scenario = activeScreenshotScenario {
        permissionService.forceAuthorizedForSimulatedSensors(
          gps: scenario.gpsPreset != nil,
          baro: scenario.baroPreset != nil
        )
      }
      #endif
      
      #if DEBUG
      let simulatedAltimeter: (any AltimeterProvider)? = if let scenario = activeScreenshotScenario, scenario.baroPreset != nil {
        SimulatedAltimeterProvider(scenario: scenario)
      } else {
        nil
      }
      #else
      let simulatedAltimeter: (any AltimeterProvider)? = nil
      #endif
      let altimeterProvider: AltimeterProvider = simulatedAltimeter ?? CMAltimeter()

      let barometricService = BarometricService(
        historyStore: barometricHistoryStore,
        preferencesService: preferencesService,
        notificationService: notificationService,
        permissionService: permissionService,
        altimeter: altimeterProvider
      )
      if permissionService.motionStatus == .authorized {
          barometricService.startUpdates()
      }
      
      let trackRecordingService = TrackRecordingService(
        positioningService: kinematicsService,
        databaseManager: databaseManager,
        preferencesService: preferencesService,
        messageService: messageService
      )
      
      let trackService = TrackService(databaseManager: databaseManager)

      let waypointService = WaypointService(
        databaseManager: databaseManager,
        initialGoToWaypointID: preferencesService.goToWaypointID
      )

      observeWaypointGoTo(waypointService: waypointService, preferencesService: preferencesService)

      let checklistService = ChecklistService(databaseManager: databaseManager)
      try await checklistService.seedDefaultTemplatesIfNeeded()

      let geoGarageLayerRepository = GeoGarageLayerRepository(databaseManager: databaseManager)
      let geoGarageAuthService = GeoGarageAuthService(
        preferencesService: preferencesService,
        layerRepository: geoGarageLayerRepository,
        keychainManager: keychainManager,
        session: authSession
      )
      await geoGarageAuthService.bootstrap()


      let geoGarageDownloadRepository = GeoGarageDownloadRepository(databaseManager: databaseManager)
      await geoGarageDownloadRepository.load()

      let geoGarageOfflineTileProvider = GeoGarageOfflineTileProvider(
        onCompatibilityMismatch: { [weak geoGarageDownloadRepository] downloadID, correctedRequiresV3 in
          guard let repo = geoGarageDownloadRepository else { return }
          guard let download = await MainActor.run(body: {
            repo.downloads.first(where: { $0.id == downloadID })
          }) else { return }
          let updated = download.updatingRequiresV3Compatibility(correctedRequiresV3)
          do {
            try await repo.save(updated)
            Logger.caas.info("Reconciled requiresV3Compatibility=\(correctedRequiresV3, privacy: .public) for package \(downloadID.uuidString, privacy: .public) in database.")
          } catch {
            Logger.caas.error("Failed to reconcile requiresV3Compatibility for package \(downloadID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
          }
        }
      )
      let lastAuthRefreshAttempt = OSAllocatedUnfairLock<ContinuousClock.Instant?>(initialState: nil)
      TileProxyProtocol.configure(
        offlineTileProvider: geoGarageOfflineTileProvider,
        tileProxyManager: tileProxyManager,
        keychainManager: keychainManager,
        onAuthenticationFailure: { [weak geoGarageAuthService] in
          let shouldAttempt = lastAuthRefreshAttempt.withLock { lastAttempt in
            let now = ContinuousClock.now
            if let lastAttempt, now - lastAttempt < .seconds(10) {
              return false
            }
            lastAttempt = now
            return true
          }
          guard shouldAttempt else { return }
          Task { @MainActor in
            guard let authService = geoGarageAuthService else { return }
            do {
              _ = try await authService.refreshTokens()
            } catch {
              Logger.network.warning("GeoGarage token refresh after tile 401/403 failed: \(error.localizedDescription, privacy: .public)")
            }
          }
        }
      )

      // Hydrate GeoGarage customer ID asynchronously from Keychain before checking offline credentials.
      await preferencesService.loadGeoGarageCustomerID()

      // Empty until the user signs in; skip tile loading until valid credentials (secret & customerID) are present.
      if let sharedSecret = try? await keychainManager.retrieveValidToken(for: GeoGaragePartnerSecretService.keychainAccount),
         let initialCustomerID = preferencesService.geoGarageCustomerID, !initialCustomerID.isEmpty {
        await geoGarageOfflineTileProvider.reloadDownloads(
          geoGarageDownloadRepository.downloads,
          sharedSecret: sharedSecret,
          customerID: initialCustomerID
        )
      } else {
        await geoGarageOfflineTileProvider.close()
      }

      observeGeoGarageDownloads(
        downloadRepository: geoGarageDownloadRepository,
        offlineTileProvider: geoGarageOfflineTileProvider,
        preferencesService: preferencesService
      )

      let geoGaragePackageService = GeoGaragePackageService(session: authSession)
      let geoGarageChartDownloader = GeoGarageChartDownloader(
        packageService: geoGaragePackageService,
        downloadRepository: geoGarageDownloadRepository
      )
      (UIApplication.shared.delegate as? AppDelegate)?.chartDownloader = geoGarageChartDownloader
      
      let backgroundMonitoringService = DefaultBackgroundMonitoringService(
        positioningService: positioningService
      )
      
      let alarmAudioService = AlarmAudioService()
      let anchorStateStore: any AnchorStateStoreProtocol
      if let anchorStateStoreOverride {
        anchorStateStore = anchorStateStoreOverride
      } else {
        anchorStateStore = await AnchorStateStore.load()
      }
      
      let anchorService = AnchorService(
        positioningService: positioningService,
        preferencesService: preferencesService,
        notificationService: notificationService,
        permissionService: permissionService,
        backgroundMonitoringService: backgroundMonitoringService,
        alarmAudioService: alarmAudioService,
        stateStore: anchorStateStore
      )
      
      let anchorViewModel = AnchorViewModel(anchorService: anchorService)
      
      // d. ViewModels instantiation (injecting the ready Services)
      let appViewModel = AppViewModel(
        preferencesService: preferencesService,
        anchorService: anchorService
      )

      instrumentDampingService.start()

      let chartViewModel = ChartViewModel(
        positioningService: positioningService,
        instrumentDampingService: instrumentDampingService,
        preferencesService: preferencesService,
        authService: geoGarageAuthService,
        anchorService: anchorService,
        anchorViewModel: anchorViewModel,
        trackService: trackService,
        trackRecordingService: trackRecordingService,
        waypointService: waypointService,
        messageService: messageService,
        keychainManager: keychainManager
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
      let diskSpaceProvider = SystemDiskSpaceProvider()
      let geoGarageDownloadService = GeoGarageDownloadService(
        packageService: geoGaragePackageService,
        downloader: geoGarageChartDownloader,
        downloadRepository: geoGarageDownloadRepository,
        preferencesService: preferencesService,
        networkMonitor: networkMonitorService,
        diskSpaceProvider: diskSpaceProvider,
        messageService: messageService,
        keychainManager: keychainManager
      )
      
      let offlineSelectionViewModel = OfflineSelectionViewModel(
        downloadService: geoGarageDownloadService,
        downloadRepository: geoGarageDownloadRepository,
        preferencesService: preferencesService,
        chartViewModel: chartViewModel,
        offlineMapManager: self.offlineMapManager,
        downloader: geoGarageChartDownloader,
        keychainManager: keychainManager
      )
      #if DEBUG
      let batteryService: (any DeviceBatteryServiceProtocol)? = activeScreenshotScenario.map { SimulatedBatteryService(scenario: $0) }
      if let scenario = activeScreenshotScenario, scenario.baroPreset != nil {
        await barometerViewModel.refreshFullHistory()
      }
      #else
      let batteryService: (any DeviceBatteryServiceProtocol)? = nil
      #endif
      let secondaryTelemetryViewModel = SecondaryTelemetryViewModel(batteryService: batteryService)
      await trackRecordingService.attemptRecoveryIfNeeded()
      await geoGarageDownloadService.resumePendingDownloadIfNeeded()
      
      if let displayedTrackID = preferencesService.displayedTrackSessionID {
        Task { @MainActor in
          do {
            try await chartViewModel.loadAndDisplaySavedTrack(sessionID: displayedTrackID, edgePadding: 50, centerOnTrack: false)
          } catch {
            Logger.system.error("❌ Failed to reload previous active track: \(error.localizedDescription, privacy: .public)")
          }
        }
      }
      
      setupGeoGarageProgressObservation(geoGarageDownloadService: geoGarageDownloadService)

      let container = AppContainer(
        userDefaults: self.userDefaults,
        messageService: messageService,
        preferencesService: preferencesService,
        positioningService: positioningService,
        trackRecordingService: trackRecordingService,
        trackService: trackService,
        waypointService: waypointService,
        geoGarageAuthService: geoGarageAuthService,
        geoGarageLayerRepository: geoGarageLayerRepository,
        geoGarageDownloadRepository: geoGarageDownloadRepository,
        geoGaragePackageService: geoGaragePackageService,
        geoGarageChartDownloader: geoGarageChartDownloader,
        geoGarageDownloadService: geoGarageDownloadService,
        geoGarageOfflineTileProvider: geoGarageOfflineTileProvider,
        anchorService: anchorService,
        kinematicsService: kinematicsService,
        appViewModel: appViewModel,
        chartViewModel: chartViewModel,
        activeTrackViewModel: activeTrackViewModel,
        barometerViewModel: barometerViewModel,
        anchorViewModel: anchorViewModel,
        permissionService: permissionService,
        offlineSelectionViewModel: offlineSelectionViewModel,
        networkMonitorService: networkMonitorService,
        notificationService: notificationService,
        secondaryTelemetryViewModel: secondaryTelemetryViewModel,
        checklistService: checklistService
      )
      #if DEBUG
      .withDeveloperSettings(developerSettingsService)
      #endif
      
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

  #if DEBUG
  private func observeDeveloperSettings<C: Clock & Sendable>(
    developerSettingsService: DeveloperSettingsService,
    kinematicsService: VesselKinematicsService,
    instrumentDampingService: InstrumentDampingService<C>
  ) where C.Duration == Duration {
    withObservationTracking {
      _ = developerSettingsService.cogSogCalculationSource
      _ = developerSettingsService.noiseMultiplier
      _ = developerSettingsService.velocityWindowDuration
      _ = developerSettingsService.cogDampingDuration
    } onChange: { [weak self, weak kinematicsService, weak instrumentDampingService, weak developerSettingsService] in
      Task { @MainActor [weak self, weak kinematicsService, weak instrumentDampingService, weak developerSettingsService] in
        guard let self,
              let settings = developerSettingsService,
              let kinematics = kinematicsService,
              let damping = instrumentDampingService else { return }
        kinematics.calculationSource = settings.cogSogCalculationSource
        kinematics.noiseMultiplier = settings.noiseMultiplier
        kinematics.velocityWindowDuration = settings.velocityWindowDuration
        damping.cogDampingDuration = settings.cogDampingDuration
        self.observeDeveloperSettings(
          developerSettingsService: settings,
          kinematicsService: kinematics,
          instrumentDampingService: damping
        )
      }
    }
  }
  #endif

  private func observeWaypointGoTo(
    waypointService: WaypointService,
    preferencesService: PreferencesService
  ) {
    withObservationTracking {
      _ = waypointService.goToWaypointID
    } onChange: { [weak self, weak waypointService, weak preferencesService] in
      Task { @MainActor [weak self, weak waypointService, weak preferencesService] in
        guard let self, let service = waypointService, let preferences = preferencesService else { return }
        preferences.goToWaypointID = service.goToWaypointID
        self.observeWaypointGoTo(waypointService: service, preferencesService: preferences)
      }
    }
  }

  @ObservationIgnored
  nonisolated(unsafe) private var geoGarageDownloadsObservationTask: Task<Void, Never>?
  @ObservationIgnored
  nonisolated(unsafe) private var geoGarageCustomerIDObservationTask: Task<Void, Never>?
  @ObservationIgnored
  nonisolated(unsafe) private var geoGarageSyncTask: Task<Void, Never>?

  private func observeGeoGarageDownloads(
    downloadRepository: GeoGarageDownloadRepository,
    offlineTileProvider: GeoGarageOfflineTileProvider,
    preferencesService: PreferencesService
  ) {
    geoGarageDownloadsObservationTask?.cancel()
    geoGarageCustomerIDObservationTask?.cancel()
    geoGarageSyncTask?.cancel()
    let downloadsStream = downloadRepository.downloadsDidChangeStream
    let customerIDStream = preferencesService.geoGarageCustomerIDDidChangeStream

    geoGarageDownloadsObservationTask = Task { @MainActor [weak self, weak downloadRepository, weak offlineTileProvider, weak preferencesService] in
      for await _ in downloadsStream {
        guard !Task.isCancelled,
              let self,
              let repo = downloadRepository,
              let provider = offlineTileProvider,
              let preferences = preferencesService else { break }
        self.scheduleGeoGarageSync(
          downloadRepository: repo,
          offlineTileProvider: provider,
          preferencesService: preferences
        )
      }
    }

    geoGarageCustomerIDObservationTask = Task { @MainActor [weak self, weak downloadRepository, weak offlineTileProvider, weak preferencesService] in
      for await _ in customerIDStream {
        guard !Task.isCancelled,
              let self,
              let repo = downloadRepository,
              let provider = offlineTileProvider,
              let preferences = preferencesService else { break }
        self.scheduleGeoGarageSync(
          downloadRepository: repo,
          offlineTileProvider: provider,
          preferencesService: preferences
        )
      }
    }
  }

  private func scheduleGeoGarageSync(
    downloadRepository: GeoGarageDownloadRepository,
    offlineTileProvider: GeoGarageOfflineTileProvider,
    preferencesService: PreferencesService
  ) {
    geoGarageSyncTask?.cancel()
    geoGarageSyncTask = Task { @MainActor [weak self, weak downloadRepository, weak offlineTileProvider, weak preferencesService] in
      guard let self,
            let repo = downloadRepository,
            let provider = offlineTileProvider,
            let preferences = preferencesService else { return }
      await self.syncGeoGarageOfflineTileProvider(
        downloadRepository: repo,
        offlineTileProvider: provider,
        preferencesService: preferences
      )
    }
  }

  private func syncGeoGarageOfflineTileProvider(
    downloadRepository: GeoGarageDownloadRepository,
    offlineTileProvider: GeoGarageOfflineTileProvider,
    preferencesService: PreferencesService
  ) async {
    guard let secret = try? await keychainManager.retrieveValidToken(for: GeoGaragePartnerSecretService.keychainAccount),
          !Task.isCancelled,
          let customerID = preferencesService.geoGarageCustomerID, !customerID.isEmpty else {
      guard !Task.isCancelled else { return }
      await offlineTileProvider.close()
      return
    }
    guard !Task.isCancelled else { return }
    await offlineTileProvider.reloadDownloads(
      downloadRepository.downloads,
      sharedSecret: secret,
      customerID: customerID
    )
  }

  // MARK: - GeoGarage Package Secret Recovery

  /// Secret catch-up started after `state = .ready`; exposed so tests can await it.
  @ObservationIgnored
  private(set) var packageSecretRestoreTask: Task<Void, Never>?

  /// One-shot recovery of package credentials (secret and/or customerID) missing at launch.
  private func restorePackageSecretIfMissing(
    authService: GeoGarageAuthService,
    messageService: MessageService,
    downloadRepository: GeoGarageDownloadRepository,
    offlineTileProvider: GeoGarageOfflineTileProvider,
    preferencesService: PreferencesService
  ) async {
    guard authService.isGeoGarageAuthenticated else { return }
    let currentSecret = try? await keychainManager.retrieveValidToken(for: GeoGaragePartnerSecretService.keychainAccount)
    let currentCustomerID = preferencesService.geoGarageCustomerID
    let isSecretMissing = currentSecret == nil
    let isCustomerMissing = currentCustomerID == nil || currentCustomerID?.isEmpty == true
    guard isSecretMissing || isCustomerMissing else { return }
    guard let accessToken = try? await keychainManager.retrieveValidToken(for: GeoGarageKeychainKeys.accessToken) else { return }

    do {
      let secrets = try await geoGaragePartnerSecretService.refresh(accessToken: accessToken)
      Logger.network.info("Partner package secret restored at startup.")
      if let newCust = secrets.customerID, !newCust.isEmpty {
        preferencesService.geoGarageCustomerID = newCust
      }
      if preferencesService.geoGarageCustomerID == nil {
        _ = try? await authService.fetchAccountSettings(accessToken: accessToken)
      }
      let newSecret = secrets.packageSecret.isEmpty ? nil : secrets.packageSecret
      let resolvedSecret = newSecret ?? currentSecret
      if let resolvedSecret, let resolvedCust = preferencesService.geoGarageCustomerID, !resolvedCust.isEmpty {
        await openOfflineReaders(
          with: resolvedSecret,
          customerID: resolvedCust,
          messageService: messageService,
          downloadRepository: downloadRepository,
          offlineTileProvider: offlineTileProvider
        )
      }
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
      if let newCust = secrets.customerID, !newCust.isEmpty {
        preferencesService.geoGarageCustomerID = newCust
      }
      if preferencesService.geoGarageCustomerID == nil {
        _ = try? await authService.fetchAccountSettings(accessToken: tokens.access_token)
      }
      let newSecret = secrets.packageSecret.isEmpty ? nil : secrets.packageSecret
      let resolvedSecret = newSecret ?? currentSecret
      if let resolvedSecret, let resolvedCust = preferencesService.geoGarageCustomerID, !resolvedCust.isEmpty {
        await openOfflineReaders(
          with: resolvedSecret,
          customerID: resolvedCust,
          messageService: messageService,
          downloadRepository: downloadRepository,
          offlineTileProvider: offlineTileProvider
        )
      }
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

  /// Reopens the offline readers with the freshly fetched credentials.
  private func openOfflineReaders(
    with packageSecret: String,
    customerID: String,
    messageService: MessageService,
    downloadRepository: GeoGarageDownloadRepository,
    offlineTileProvider: GeoGarageOfflineTileProvider
  ) async {
    messageService.clear(category: .offlineCharts)
    guard !customerID.isEmpty else {
      await offlineTileProvider.close()
      return
    }
    await offlineTileProvider.reloadDownloads(
      downloadRepository.downloads,
      sharedSecret: packageSecret,
      customerID: customerID
    )
  }

  private func postPackageSecretWarning(on messageService: MessageService) {
    let appMessage = AppMessage(
      title: LocalizedStringResource("Offline charts unavailable"),
      detail: .localized("GeoGarage did not provide the decryption secret. Online charts work; offline downloads are disabled until the next sign-in."),
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

  var geoGarageLayerRepository: GeoGarageLayerRepository? {
    guard case .ready(let container) = state else { return nil }
    return container.geoGarageLayerRepository
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

  var checklistService: ChecklistService? {
    guard case .ready(let container) = state else { return nil }
    return container.checklistService
  }

  public var trackService: TrackService {
    guard case .ready(let container) = state else {
      fatalError("CRITICAL: TrackService accessed before AppEnvironment is ready.")
    }
    return container.trackService
  }

  var lastKnownLocation: NavigationFix? {
    guard case .ready(let container) = state else { return nil }
    return container.positioningService.lastKnownLocation
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

  // MARK: - Pauses Location Updates Automatically (Debug)

  #if DEBUG
  /// Single entry point for changing pausesLocationUpdatesAutomatically at runtime.
  /// Keeps DeveloperSettingsService and CoreLocationPositioningService in sync.
  func updatePausesLocationUpdatesAutomatically(to pauses: Bool) {
    guard case .ready(let container) = state else { return }
    container.developerSettingsService.pausesLocationUpdatesAutomatically = pauses
    container.positioningService.setPausesLocationUpdatesAutomatically(pauses)
  }
  #endif
  
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
    geoGarageDownloadsObservationTask?.cancel()
    geoGarageCustomerIDObservationTask?.cancel()
    geoGarageSyncTask?.cancel()
    mapLibreObservationTask?.cancel()
    packageSecretRestoreTask?.cancel()
  }

}

#if DEBUG
extension AppEnvironment {
  @MainActor
  static var preview: AppEnvironment {
    let suiteName = "preview.appEnvironment"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removePersistentDomain(forName: suiteName)
    return AppEnvironment(userDefaults: defaults)
  }
}
#endif

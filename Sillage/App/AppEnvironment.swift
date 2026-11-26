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
  static let keychainAccessibilityMigratedDefaultsKey = "keychain_accessibility_migrated_v1"

  private(set) var state: AppState = .uninitialized
  private(set) var needsProtectedDataHydration: Bool = false
  private(set) var didFailWhileProtectedDataUnavailable: Bool = false

  var canAccessProtectedData: Bool {
    isProtectedDataAvailable()
  }

  public private(set) var metadata: AppMetadata?
  public let bootDate: Date
  public let configuration: AppConfiguration
  public let offlineMapManager: OfflineMapManager
  public let offlineChartsProgressMonitor: OfflineChartsProgressMonitor
  /// Fetches the package decryption secret from `/partners/me/` after sign-in, so nothing secret
  /// ships in the binary; the secret lives in the Keychain.
  public let geoGaragePartnerSecretService: any GeoGaragePartnerSecretServiceProtocol

  private let keychainManager: any KeychainManaging
  private let userDefaults: UserDefaults
  private let isProtectedDataAvailable: @MainActor () -> Bool

  /// Holds bootstrap-only overrides until `.ready` is reached; preserved on `.error` so retries keep injected seams.
  @ObservationIgnored
  private var bootstrapOverrides: Overrides?

  @ObservationIgnored
  private var pendingBackgroundSessionCompletion: (@MainActor () -> Void)?
  @ObservationIgnored
  private(set) weak var activeChartDownloader: GeoGarageChartDownloader?
  @ObservationIgnored
  private var isHydratingProtectedData: Bool = false
  @ObservationIgnored
  private var didBecomeProtectedDataAvailableDuringBootstrap: Bool = false
  @ObservationIgnored
  private var geoGarageOfflineCoordinator: GeoGarageOfflineCoordinator?

  init(overrides: Overrides = .init()) {
    let configuration = overrides.configuration ?? .fromBundle()
    let keychainManager = overrides.keychainManager ?? KeychainManager.shared

    self.metadata = overrides.metadata
    self.bootDate = Date.now
    self.configuration = configuration
    self.keychainManager = keychainManager
    self.userDefaults = overrides.userDefaults ?? .standard
    self.isProtectedDataAvailable = overrides.isProtectedDataAvailable ?? {
      UIApplication.shared.isProtectedDataAvailable
    }
    self.offlineMapManager = overrides.offlineMapManager ?? OfflineMapManager()
    self.offlineChartsProgressMonitor = OfflineChartsProgressMonitor()
    self.geoGaragePartnerSecretService = overrides.partnerSecretService
      ?? GeoGaragePartnerSecretService(keychainManager: keychainManager)

    // Strip collaborators already materialized onto `self` so `self` remains the single source of truth.
    var remainingOverrides = overrides
    remainingOverrides.metadata = nil
    remainingOverrides.configuration = nil
    remainingOverrides.keychainManager = nil
    remainingOverrides.userDefaults = nil
    remainingOverrides.isProtectedDataAvailable = nil
    remainingOverrides.offlineMapManager = nil
    remainingOverrides.partnerSecretService = nil
    self.bootstrapOverrides = remainingOverrides

    // Pure synchronous callback wiring (no I/O, no KVO, no unstructured Task in `init`).
    let progressMonitor = self.offlineChartsProgressMonitor
    self.offlineMapManager.onGlobalProgressChanged = { [weak progressMonitor] progress in
      progressMonitor?.updateMapLibreProgress(progress)
    }
  }
  
  /// Routes an iOS background `URLSession` completion handler across all `AppEnvironment` lifecycle windows:
  /// - `.error`: invokes immediately on `@MainActor` so iOS never times out waiting for a failed boot.
  /// - `activeChartDownloader != nil` (late `.bootstrapping` after downloader init, or `.ready`): forwards directly.
  /// - `.uninitialized` / early `.bootstrapping` (before downloader init): buffers for injection into `GeoGarageChartDownloader.init`.
  func registerBackgroundURLSessionCompletionHandler(_ handler: @escaping @MainActor () -> Void) {
    if case .error = state {
      Logger.caas.error("Received background URLSession completion handler while AppEnvironment is in .error state; invoking immediately.")
      handler()
      return
    }
    if let downloader = activeChartDownloader {
      downloader.setBackgroundCompletionHandler(handler)
    } else {
      if let supersededHandler = pendingBackgroundSessionCompletion {
        Logger.caas.warning("Replacing an unconsumed pending background URLSession completion handler; invoking previous handler first.")
        supersededHandler()
      }
      pendingBackgroundSessionCompletion = handler
    }
  }

  func bootstrap() async {
    if case .bootstrapping = state { return }
    if case .ready = state { return }
    state = .bootstrapping
    didFailWhileProtectedDataUnavailable = false
    didBecomeProtectedDataAvailableDuringBootstrap = false
    Logger.system.info("🚀 Starting AppEnvironment bootstrap sequence. Boot time: \(self.bootDate, privacy: .public)")

    let overrides = self.bootstrapOverrides ?? .init()

    // Phase 1: Strictly isolate ALL throwing bootstrap steps (`setupFileSystem`, `DatabaseManager`,
    // debug database seeding, and default checklist seeding). Returning early in `catch` guarantees
    // at compile time that Phase 2 cannot fail and that neither MapLibre nor a background `URLSession`
    // is ever started if Phase 1 fails.
    #if DEBUG
    let activeScreenshotScenario = DebugBootstrapper.resolveScenario(override: overrides.screenshotScenario)
    #endif

    let databaseManager: DatabaseManager
    let baroDatabaseManager: DatabaseManager
    let checklistCatalogService: ChecklistCatalogService
    let databaseFactory = overrides.databaseManagerFactory

    do {
      try await Task.detached {
        try self.setupFileSystem()
      }.value

      if let databaseFactory {
        databaseManager = try await Task.detached {
          try databaseFactory()
        }.value
      } else {
        databaseManager = try await Task.detached {
          try DatabaseManager()
        }.value
      }

      #if DEBUG
      baroDatabaseManager = try await DebugBootstrapper.prepareDatabases(
        scenario: activeScreenshotScenario,
        databaseManager: databaseManager,
        hasCustomDatabaseFactory: databaseFactory != nil
      )
      #else
      baroDatabaseManager = databaseManager
      #endif

      checklistCatalogService = ChecklistCatalogService(databaseManager: databaseManager)
      try await checklistCatalogService.seedDefaultTemplatesIfNeeded()
    } catch {
      Logger.system.error("❌ AppEnvironment bootstrap failed: \(error.localizedDescription, privacy: .public)")
      didFailWhileProtectedDataUnavailable = !self.isProtectedDataAvailable()
      state = .error(error)
      if let pendingHandler = self.pendingBackgroundSessionCompletion {
        self.pendingBackgroundSessionCompletion = nil
        Logger.caas.error("Bootstrap failed with a pending background URLSession completion handler; invoking immediately to prevent OS timeout.")
        pendingHandler()
      }
      return
    }

    // Phase 2: Non-throwing service & ViewModel assembly (compiler-enforced: no `try` outside local closures).
    Self.setupMapLibreProtocol()
    self.offlineMapManager.start()

    async let resolvedMetadata: AppMetadata? = self.metadata == nil
      ? AppMetadataProvider.resolve()
      : nil

    let authSession = overrides.authSession ?? .shared
    let tileProxyManager: any TileProxyManagerProtocol = overrides.tileProxyManager ?? TileProxyManager(
      keychainManager: self.keychainManager,
      configuration: self.configuration
    )

    let messageService = MessageService()

    let preferencesService = overrides.preferencesService ?? PreferencesService(
      defaults: self.userDefaults,
      keychainManager: self.keychainManager
    )
    #if DEBUG
    let developerSettingsService = DebugBootstrapper.makeDeveloperSettingsService(
      scenario: activeScreenshotScenario,
      userDefaults: self.userDefaults
    )
    let simulatedPositioning = DebugBootstrapper.makeSimulatedPositioningService(scenario: activeScreenshotScenario)
    let initialPausesAutomatically = developerSettingsService.pausesLocationUpdatesAutomatically
    #else
    let simulatedPositioning: (any PositioningService)? = nil
    let initialPausesAutomatically = false
    #endif
    let positioningService: any PositioningService = overrides.positioningService ?? simulatedPositioning ?? CoreLocationPositioningService(
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
    DebugBootstrapper.bindDeveloperSettings(
      developerSettingsService,
      to: kinematicsService,
      dampingService: instrumentDampingService
    )
    #endif

    let barometricHistoryStore = BarometricHistoryStore(databaseManager: baroDatabaseManager)

    let notificationService = LocalNotificationService()

    let permissionService = PermissionService(
      positioningService: positioningService,
      notificationService: notificationService
    )
    #if DEBUG
    DebugBootstrapper.applySimulatedPermissions(
      scenario: activeScreenshotScenario,
      to: permissionService
    )
    let simulatedAltimeter = DebugBootstrapper.makeSimulatedAltimeterProvider(scenario: activeScreenshotScenario)
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

    let migrationStatus = await migrateKeychainIfProtectedDataAvailable()

    let geoGarageLayerRepository = GeoGarageLayerRepository(databaseManager: databaseManager)
    let geoGarageAuthService = GeoGarageAuthService(
      preferencesService: preferencesService,
      layerRepository: geoGarageLayerRepository,
      keychainManager: keychainManager,
      session: authSession,
      configuration: configuration
    )
    await geoGarageAuthService.bootstrap()

    let geoGarageDownloadRepository = GeoGarageDownloadRepository(databaseManager: databaseManager)
    await geoGarageDownloadRepository.load()

    let geoGarageOfflineTileProvider = GeoGarageOfflineCoordinator.makeOfflineTileProvider(
      downloadRepository: geoGarageDownloadRepository
    )

    self.geoGarageOfflineCoordinator?.stop()
    let geoGarageOfflineCoordinator = GeoGarageOfflineCoordinator(
      authService: geoGarageAuthService,
      downloadRepository: geoGarageDownloadRepository,
      offlineTileProvider: geoGarageOfflineTileProvider,
      preferencesService: preferencesService,
      partnerSecretService: self.geoGaragePartnerSecretService,
      keychainManager: keychainManager,
      onPackageSecretWarning: { [weak messageService] in
        guard let messageService else { return }
        Self.postPackageSecretWarning(on: messageService)
      },
      onOfflineReadersOpened: { [weak messageService] in
        messageService?.clear(category: .offlineCharts)
      },
      onProtectedDataHydrationRequired: { [weak self] in
        self?.needsProtectedDataHydration = true
      }
    )
    self.geoGarageOfflineCoordinator = geoGarageOfflineCoordinator
    geoGarageOfflineCoordinator.configureTileProxy(tileProxyManager: tileProxyManager)

    // Hydrate GeoGarage customer ID asynchronously from Keychain before checking offline credentials.
    let customerIDStatus = await preferencesService.loadGeoGarageCustomerID()

    // Empty until the user signs in; skip tile loading until valid credentials (secret & customerID) are present.
    // On `errSecInteractionNotAllowed`, preserve open readers and defer hydration until protected data unlocks.
    let secretStatus = await geoGarageOfflineCoordinator.syncOfflineTileProvider(
      customerIDStatus: customerIDStatus
    )
    self.needsProtectedDataHydration = migrationStatus == .deferredForProtectedData
      || geoGarageAuthService.isDeferredForProtectedData
      || customerIDStatus == .deferredForProtectedData
      || secretStatus == .deferredForProtectedData

    geoGarageOfflineCoordinator.start()

    let geoGaragePackageService = GeoGaragePackageService(session: authSession)
    let initialBackgroundCompletion = self.pendingBackgroundSessionCompletion
    self.pendingBackgroundSessionCompletion = nil
    let geoGarageChartDownloader = GeoGarageChartDownloader(
      packageService: geoGaragePackageService,
      downloadRepository: geoGarageDownloadRepository,
      sessionConfiguration: overrides.chartDownloaderSessionConfiguration,
      initialBackgroundCompletionHandler: initialBackgroundCompletion
    )
    self.activeChartDownloader = geoGarageChartDownloader

    let backgroundMonitoringService = DefaultBackgroundMonitoringService(
      positioningService: positioningService
    )

    let alarmAudioService = AlarmAudioService()
    let anchorStateStore: any AnchorStateStoreProtocol
    if let loaderOverride = overrides.anchorStateStoreLoader {
      anchorStateStore = await loaderOverride()
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
      keychainManager: keychainManager,
      configuration: configuration
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
    let batteryService = DebugBootstrapper.makeSimulatedBatteryService(scenario: activeScreenshotScenario)
    await DebugBootstrapper.refreshSimulatedBarometerIfNeeded(
      scenario: activeScreenshotScenario,
      barometerViewModel: barometerViewModel
    )
    #else
    let batteryService: (any DeviceBatteryServiceProtocol)? = nil
    #endif
    let checklistSessionService = ChecklistSessionService(databaseManager: databaseManager)
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

    offlineChartsProgressMonitor.start(
      geoGarageProgressStream: geoGarageDownloadService.downloadProgressStream()
    )

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
      checklistCatalogService: checklistCatalogService,
      checklistSessionService: checklistSessionService
    )
    #if DEBUG
    .withDeveloperSettings(developerSettingsService)
    #endif

    if let resolved = await resolvedMetadata {
      self.metadata = resolved
    }

    Logger.system.info("✅ AppEnvironment bootstrap complete. Transitioning to ready.")
    state = .ready(container)
    self.bootstrapOverrides = nil

    if !self.needsProtectedDataHydration {
      geoGarageOfflineCoordinator.schedulePackageSecretRestore()
    }

    if self.didBecomeProtectedDataAvailableDuringBootstrap {
      self.didBecomeProtectedDataAvailableDuringBootstrap = false
      await self.handleProtectedDataDidBecomeAvailable()
    }
  }

  /// Migrates legacy `WhenUnlocked` Keychain entries to `AfterFirstUnlock` once protected data is unlocked.
  /// Marks `UserDefaults` complete only if every account check/migration succeeds without error.
  @discardableResult
  private func migrateKeychainIfProtectedDataAvailable() async -> KeychainHydrationStatus {
    guard isProtectedDataAvailable() else {
      Logger.system.info("Protected data unavailable; deferring Keychain accessibility migration.")
      return .hydrated
    }
    guard !userDefaults.bool(forKey: Self.keychainAccessibilityMigratedDefaultsKey) else {
      return .hydrated
    }
    do {
      try await keychainManager.migrateAccessibilityIfNeeded(for: GeoGarageKeychainKeys.allAccounts)
      userDefaults.set(true, forKey: Self.keychainAccessibilityMigratedDefaultsKey)
      return .hydrated
    } catch {
      if error.isInteractionNotAllowed {
        Logger.system.warning("Keychain accessibility migration deferred: Keychain interaction not allowed.")
        return .deferredForProtectedData
      }
      Logger.system.error("Keychain accessibility migration failed: \(error.localizedDescription, privacy: .public)")
      return .hydrated
    }
  }

  /// Re-hydrates Keychain-backed GeoGarage credentials after a Before-First-Unlock (BFU) or locked boot.
  /// Triggered both from `AppDelegate.applicationProtectedDataDidBecomeAvailable(_:)` and foreground `scenePhase == .active`.
  func handleProtectedDataDidBecomeAvailable() async {
    guard isProtectedDataAvailable() else { return }

    if case .bootstrapping = state {
      didBecomeProtectedDataAvailableDuringBootstrap = true
      return
    }

    guard case .ready(let container) = state else { return }
    guard !isHydratingProtectedData else { return }

    isHydratingProtectedData = true
    defer { isHydratingProtectedData = false }

    let migrationStatus = await migrateKeychainIfProtectedDataAvailable()

    guard migrationStatus == .deferredForProtectedData
      || needsProtectedDataHydration
      || container.geoGarageAuthService.isDeferredForProtectedData else {
      return
    }

    Logger.system.info("Protected data available; re-hydrating deferred GeoGarage Keychain credentials.")

    let geoGarageStatus = await geoGarageOfflineCoordinator?.rehydrateAfterProtectedDataUnlock() ?? .hydrated

    let stillDeferred = migrationStatus == .deferredForProtectedData
      || geoGarageStatus == .deferredForProtectedData
    self.needsProtectedDataHydration = stillDeferred

    guard !stillDeferred else {
      Logger.system.warning("Protected data re-hydration still blocked by Keychain; keeping needsProtectedDataHydration = true.")
      return
    }

    container.chartViewModel.refreshGeoGarageLayersIfAuthenticated()
    geoGarageOfflineCoordinator?.schedulePackageSecretRestore()
    await container.geoGarageDownloadService.resumePendingDownloadIfNeeded()
  }

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

  /// Secret catch-up started after `state = .ready`; exposed so tests can await it.
  var packageSecretRestoreTask: Task<Void, Never>? {
    geoGarageOfflineCoordinator?.packageSecretRestoreTask
  }

  private static func postPackageSecretWarning(on messageService: MessageService) {
    let appMessage = AppMessage(
      title: LocalizedStringResource("Offline Charts Unavailable"),
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

  public var checklistCatalogService: ChecklistCatalogService {
    guard case .ready(let container) = state else {
      fatalError("CRITICAL: ChecklistCatalogService accessed before AppEnvironment is ready.")
    }
    return container.checklistCatalogService
  }

  public var checklistSessionService: ChecklistSessionService {
    guard case .ready(let container) = state else {
      fatalError("CRITICAL: ChecklistSessionService accessed before AppEnvironment is ready.")
    }
    return container.checklistSessionService
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

  /// Indicates whether an offline chart download is currently in progress across GeoGarage or MapLibre engines.
  var isDownloadingOfflineCharts: Bool {
    offlineChartsProgressMonitor.isDownloading
  }

  /// Normalized download progress value (0.0 to 1.0) when available, or nil when idle.
  var offlineChartsDownloadProgress: Double? {
    offlineChartsProgressMonitor.progress
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

}

#if DEBUG
extension AppEnvironment {
  @MainActor
  static var preview: AppEnvironment {
    let suiteName = "preview.appEnvironment"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removePersistentDomain(forName: suiteName)
    var overrides = Overrides()
    overrides.userDefaults = defaults
    return AppEnvironment(overrides: overrides)
  }
}
#endif

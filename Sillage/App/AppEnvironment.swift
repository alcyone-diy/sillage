//
//  AppEnvironment.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-20.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import CoreMotion
import Foundation
import Observation
import OSLog
import UIKit

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

  // MARK: - Private Bootstrap Assembly Types

  private struct DebugBootstrapContext {
    #if DEBUG
    let scenario: ScreenshotScenario?
    let developerSettingsService: DeveloperSettingsService
    #endif
  }

  private struct NavigationAndSensorServices {
    let positioningService: any PositioningService
    let kinematicsService: VesselKinematicsService
    let instrumentDampingService: InstrumentDampingService<ContinuousClock>
    let notificationService: LocalNotificationService
    let permissionService: PermissionService
    let barometricService: BarometricService
    let trackRecordingService: TrackRecordingService
    let trackService: TrackService
    let waypointService: WaypointService
  }

  private struct GeoGarageServices {
    let layerRepository: GeoGarageLayerRepository
    let authService: GeoGarageAuthService
    let downloadRepository: GeoGarageDownloadRepository
    let offlineTileProvider: GeoGarageOfflineTileProvider
    let coordinator: GeoGarageOfflineCoordinator
    let packageService: GeoGaragePackageService
    let chartDownloader: GeoGarageChartDownloader
    let networkMonitorService: NetworkMonitorService
    let downloadService: GeoGarageDownloadService
    let requiresProtectedDataHydration: Bool
  }

  // MARK: - Initialization

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

  // MARK: - Bootstrap

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
        try AppBootstrapInfrastructure.setupFileSystem()
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
    // Critical order: register `TileProxyProtocol` before starting MapLibre offline storage or map views.
    AppBootstrapInfrastructure.configureMapLibreProtocol()
    self.offlineMapManager.start()

    async let resolvedMetadata: AppMetadata? = self.metadata == nil
      ? AppMetadataProvider.resolve()
      : nil

    let messageService = MessageService()
    let preferencesService = overrides.preferencesService ?? PreferencesService(
      defaults: self.userDefaults,
      keychainManager: self.keychainManager
    )

    #if DEBUG
    let debugContext = DebugBootstrapContext(
      scenario: activeScreenshotScenario,
      developerSettingsService: DebugBootstrapper.makeDeveloperSettingsService(
        scenario: activeScreenshotScenario,
        userDefaults: self.userDefaults
      )
    )
    #else
    let debugContext = DebugBootstrapContext()
    #endif

    let navServices = assembleNavigationAndSensorServices(
      overrides: overrides,
      databaseManager: databaseManager,
      baroDatabaseManager: baroDatabaseManager,
      preferencesService: preferencesService,
      messageService: messageService,
      debugContext: debugContext
    )

    let migrationStatus = await migrateKeychainIfProtectedDataAvailable()
    let geoGarage = await assembleGeoGarageServices(
      overrides: overrides,
      databaseManager: databaseManager,
      preferencesService: preferencesService,
      messageService: messageService
    )
    self.needsProtectedDataHydration = migrationStatus == .deferredForProtectedData
      || geoGarage.requiresProtectedDataHydration

    let anchorService = await makeAnchorService(
      overrides: overrides,
      navServices: navServices,
      preferencesService: preferencesService
    )

    // ViewModels & post-assembly startup
    let anchorViewModel = AnchorViewModel(anchorService: anchorService)
    let appViewModel = AppViewModel(
      preferencesService: preferencesService,
      anchorService: anchorService
    )

    navServices.instrumentDampingService.start()

    let chartViewModel = ChartViewModel(
      positioningService: navServices.positioningService,
      instrumentDampingService: navServices.instrumentDampingService,
      preferencesService: preferencesService,
      authService: geoGarage.authService,
      anchorService: anchorService,
      anchorViewModel: anchorViewModel,
      trackService: navServices.trackService,
      trackRecordingService: navServices.trackRecordingService,
      waypointService: navServices.waypointService,
      messageService: messageService,
      keychainManager: keychainManager,
      configuration: configuration
    )
    let activeTrackViewModel = ActiveTrackViewModel(
      trackRecordingService: navServices.trackRecordingService,
      permissionService: navServices.permissionService
    )
    let barometerViewModel = BarometerViewModel(
      service: navServices.barometricService,
      preferencesService: preferencesService
    )
    let offlineSelectionViewModel = OfflineSelectionViewModel(
      downloadService: geoGarage.downloadService,
      downloadRepository: geoGarage.downloadRepository,
      preferencesService: preferencesService,
      chartViewModel: chartViewModel,
      offlineMapManager: self.offlineMapManager,
      downloader: geoGarage.chartDownloader,
      keychainManager: keychainManager
    )

    #if DEBUG
    let batteryService = DebugBootstrapper.makeSimulatedBatteryService(scenario: debugContext.scenario)
    await DebugBootstrapper.refreshSimulatedBarometerIfNeeded(
      scenario: debugContext.scenario,
      barometerViewModel: barometerViewModel
    )
    #else
    let batteryService: (any DeviceBatteryServiceProtocol)? = nil
    #endif

    let checklistSessionService = ChecklistSessionService(databaseManager: databaseManager)
    let secondaryTelemetryViewModel = SecondaryTelemetryViewModel(batteryService: batteryService)

    await navServices.trackRecordingService.attemptRecoveryIfNeeded()
    await geoGarage.downloadService.resumePendingDownloadIfNeeded()

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
      geoGarageProgressStream: geoGarage.downloadService.downloadProgressStream()
    )

    let container = AppContainer(
      userDefaults: self.userDefaults,
      messageService: messageService,
      preferencesService: preferencesService,
      positioningService: navServices.positioningService,
      trackRecordingService: navServices.trackRecordingService,
      trackService: navServices.trackService,
      waypointService: navServices.waypointService,
      geoGarageAuthService: geoGarage.authService,
      geoGarageLayerRepository: geoGarage.layerRepository,
      geoGarageDownloadRepository: geoGarage.downloadRepository,
      geoGaragePackageService: geoGarage.packageService,
      geoGarageChartDownloader: geoGarage.chartDownloader,
      geoGarageDownloadService: geoGarage.downloadService,
      geoGarageOfflineTileProvider: geoGarage.offlineTileProvider,
      anchorService: anchorService,
      kinematicsService: navServices.kinematicsService,
      appViewModel: appViewModel,
      chartViewModel: chartViewModel,
      activeTrackViewModel: activeTrackViewModel,
      barometerViewModel: barometerViewModel,
      anchorViewModel: anchorViewModel,
      permissionService: navServices.permissionService,
      offlineSelectionViewModel: offlineSelectionViewModel,
      networkMonitorService: geoGarage.networkMonitorService,
      notificationService: navServices.notificationService,
      secondaryTelemetryViewModel: secondaryTelemetryViewModel,
      checklistCatalogService: checklistCatalogService,
      checklistSessionService: checklistSessionService
    )
    #if DEBUG
    .withDeveloperSettings(debugContext.developerSettingsService)
    #endif

    if let resolved = await resolvedMetadata {
      self.metadata = resolved
    }

    Logger.system.info("✅ AppEnvironment bootstrap complete. Transitioning to ready.")
    state = .ready(container)
    self.bootstrapOverrides = nil

    if !self.needsProtectedDataHydration {
      geoGarage.coordinator.schedulePackageSecretRestore()
    }

    if self.didBecomeProtectedDataAvailableDuringBootstrap {
      self.didBecomeProtectedDataAvailableDuringBootstrap = false
      await self.handleProtectedDataDidBecomeAvailable()
    }
  }

  // MARK: - Private Subsystem Assemblers

  private func assembleNavigationAndSensorServices(
    overrides: Overrides,
    databaseManager: DatabaseManager,
    baroDatabaseManager: DatabaseManager,
    preferencesService: PreferencesService,
    messageService: MessageService,
    debugContext: DebugBootstrapContext
  ) -> NavigationAndSensorServices {
    #if DEBUG
    let simulatedPositioning = DebugBootstrapper.makeSimulatedPositioningService(scenario: debugContext.scenario)
    let initialPausesAutomatically = debugContext.developerSettingsService.pausesLocationUpdatesAutomatically
    #else
    let simulatedPositioning: (any PositioningService)? = nil
    let initialPausesAutomatically = false
    #endif

    let positioningService: any PositioningService = overrides.positioningService
      ?? simulatedPositioning
      ?? CoreLocationPositioningService(
        initialAccuracyMode: preferencesService.gpsAccuracyMode,
        initialPausesLocationUpdatesAutomatically: initialPausesAutomatically
      )

    let kinematicsService = VesselKinematicsService(positioningService: positioningService)
    let instrumentDampingService = InstrumentDampingService(positioningService: kinematicsService)

    #if DEBUG
    DebugBootstrapper.bindDeveloperSettings(
      debugContext.developerSettingsService,
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
      scenario: debugContext.scenario,
      to: permissionService
    )
    let simulatedAltimeter = DebugBootstrapper.makeSimulatedAltimeterProvider(scenario: debugContext.scenario)
    #else
    let simulatedAltimeter: (any AltimeterProvider)? = nil
    #endif

    let altimeterProvider: any AltimeterProvider = simulatedAltimeter ?? CMAltimeter()
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

    return NavigationAndSensorServices(
      positioningService: positioningService,
      kinematicsService: kinematicsService,
      instrumentDampingService: instrumentDampingService,
      notificationService: notificationService,
      permissionService: permissionService,
      barometricService: barometricService,
      trackRecordingService: trackRecordingService,
      trackService: trackService,
      waypointService: waypointService
    )
  }

  private func assembleGeoGarageServices(
    overrides: Overrides,
    databaseManager: DatabaseManager,
    preferencesService: PreferencesService,
    messageService: MessageService
  ) async -> GeoGarageServices {
    let authSession = overrides.authSession ?? .shared
    let tileProxyManager: any TileProxyManagerProtocol = overrides.tileProxyManager ?? TileProxyManager(
      keychainManager: self.keychainManager,
      configuration: self.configuration
    )

    let layerRepository = GeoGarageLayerRepository(databaseManager: databaseManager)
    let authService = GeoGarageAuthService(
      preferencesService: preferencesService,
      layerRepository: layerRepository,
      keychainManager: keychainManager,
      session: authSession,
      configuration: configuration
    )
    await authService.bootstrap()

    let downloadRepository = GeoGarageDownloadRepository(databaseManager: databaseManager)
    await downloadRepository.load()

    let offlineTileProvider = GeoGarageOfflineCoordinator.makeOfflineTileProvider(
      downloadRepository: downloadRepository
    )

    self.geoGarageOfflineCoordinator?.stop()
    let coordinator = GeoGarageOfflineCoordinator(
      authService: authService,
      downloadRepository: downloadRepository,
      offlineTileProvider: offlineTileProvider,
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
    self.geoGarageOfflineCoordinator = coordinator
    coordinator.configureTileProxy(tileProxyManager: tileProxyManager)

    // Hydrate GeoGarage customer ID asynchronously from Keychain before checking offline credentials.
    let customerIDStatus = await preferencesService.loadGeoGarageCustomerID()
    let secretStatus = await coordinator.syncOfflineTileProvider(customerIDStatus: customerIDStatus)
    let requiresProtectedDataHydration = authService.isDeferredForProtectedData
      || customerIDStatus == .deferredForProtectedData
      || secretStatus == .deferredForProtectedData

    coordinator.start()

    let packageService = GeoGaragePackageService(session: authSession)
    let initialBackgroundCompletion = self.pendingBackgroundSessionCompletion
    self.pendingBackgroundSessionCompletion = nil
    let chartDownloader = GeoGarageChartDownloader(
      packageService: packageService,
      downloadRepository: downloadRepository,
      sessionConfiguration: overrides.chartDownloaderSessionConfiguration,
      initialBackgroundCompletionHandler: initialBackgroundCompletion
    )
    self.activeChartDownloader = chartDownloader

    let networkMonitorService = NetworkMonitorService()
    let diskSpaceProvider = SystemDiskSpaceProvider()
    let downloadService = GeoGarageDownloadService(
      packageService: packageService,
      downloader: chartDownloader,
      downloadRepository: downloadRepository,
      preferencesService: preferencesService,
      networkMonitor: networkMonitorService,
      diskSpaceProvider: diskSpaceProvider,
      messageService: messageService,
      keychainManager: keychainManager
    )

    return GeoGarageServices(
      layerRepository: layerRepository,
      authService: authService,
      downloadRepository: downloadRepository,
      offlineTileProvider: offlineTileProvider,
      coordinator: coordinator,
      packageService: packageService,
      chartDownloader: chartDownloader,
      networkMonitorService: networkMonitorService,
      downloadService: downloadService,
      requiresProtectedDataHydration: requiresProtectedDataHydration
    )
  }

  private func makeAnchorService(
    overrides: Overrides,
    navServices: NavigationAndSensorServices,
    preferencesService: PreferencesService
  ) async -> AnchorService {
    let backgroundMonitoringService = DefaultBackgroundMonitoringService(
      positioningService: navServices.positioningService
    )
    let alarmAudioService = AlarmAudioService()
    let anchorStateStore: any AnchorStateStoreProtocol
    if let loaderOverride = overrides.anchorStateStoreLoader {
      anchorStateStore = await loaderOverride()
    } else {
      anchorStateStore = await AnchorStateStore.load()
    }

    return AnchorService(
      positioningService: navServices.positioningService,
      preferencesService: preferencesService,
      notificationService: navServices.notificationService,
      permissionService: navServices.permissionService,
      backgroundMonitoringService: backgroundMonitoringService,
      alarmAudioService: alarmAudioService,
      stateStore: anchorStateStore
    )
  }

  // MARK: - Protected Data (BFU) & Keychain Migration

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

  // MARK: - Runtime Coordination Helpers

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

  // MARK: - Exposed Container & Stateless Services

  var geoGarageDownloadRepository: GeoGarageDownloadRepository? {
    guard case .ready(let container) = state else { return nil }
    return container.geoGarageDownloadRepository
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

  // MARK: - Runtime Sensor Settings

  /// Single entry point for changing GPS accuracy at runtime.
  /// Keeps PreferencesService and CoreLocationPositioningService in sync.
  func updateGPSAccuracy(to mode: GPSAccuracyMode) {
    guard case .ready(let container) = state else { return }
    container.preferencesService.gpsAccuracyMode = mode
    container.positioningService.setDesiredAccuracy(mode)
  }

  #if DEBUG
  /// Single entry point for changing pausesLocationUpdatesAutomatically at runtime.
  /// Keeps DeveloperSettingsService and CoreLocationPositioningService in sync.
  func updatePausesLocationUpdatesAutomatically(to pauses: Bool) {
    guard case .ready(let container) = state else { return }
    container.developerSettingsService.pausesLocationUpdatesAutomatically = pauses
    container.positioningService.setPausesLocationUpdatesAutomatically(pauses)
  }
  #endif
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

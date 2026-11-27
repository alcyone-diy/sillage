//
//  GeoGarageOfflineCoordinator.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-26.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import os
import OSLog

/// Coordinates GeoGarage offline chart credentials, reactive tile-reader synchronization,
/// `TileProxyURLProtocol` configuration, and startup package-secret recovery.
///
/// Lifecycle is explicit via `start()` / `stop()` with `[weak self]` captures so no
/// `nonisolated(unsafe)` task properties or `deinit` task cancellations are required.
@MainActor
final class GeoGarageOfflineCoordinator {

  private let authService: GeoGarageAuthService
  private let downloadRepository: GeoGarageDownloadRepository
  private let offlineTileProvider: any GeoGarageOfflineTileProviderProtocol
  private let preferencesService: PreferencesService
  private let partnerSecretService: any GeoGaragePartnerSecretServiceProtocol
  private let keychainManager: any KeychainManaging
  private let onPackageSecretWarning: @MainActor () -> Void
  private let onOfflineReadersOpened: @MainActor () -> Void
  private let onProtectedDataHydrationRequired: @MainActor () -> Void

  private var isStarted: Bool = false
  private var isRehydrating: Bool = false
  private var didConfigureTileProxy: Bool = false
  private var downloadsObservationTask: Task<Void, Never>?
  private var customerIDObservationTask: Task<Void, Never>?
  private var syncTask: Task<Void, Never>?

  /// Secret catch-up task started after boot or protected-data unlock; exposed so tests can await it.
  private(set) var packageSecretRestoreTask: Task<Void, Never>?

  init(
    authService: GeoGarageAuthService,
    downloadRepository: GeoGarageDownloadRepository,
    offlineTileProvider: any GeoGarageOfflineTileProviderProtocol,
    preferencesService: PreferencesService,
    partnerSecretService: any GeoGaragePartnerSecretServiceProtocol,
    keychainManager: any KeychainManaging,
    onPackageSecretWarning: @escaping @MainActor () -> Void,
    onOfflineReadersOpened: @escaping @MainActor () -> Void,
    onProtectedDataHydrationRequired: @escaping @MainActor () -> Void = {}
  ) {
    self.authService = authService
    self.downloadRepository = downloadRepository
    self.offlineTileProvider = offlineTileProvider
    self.preferencesService = preferencesService
    self.partnerSecretService = partnerSecretService
    self.keychainManager = keychainManager
    self.onPackageSecretWarning = onPackageSecretWarning
    self.onOfflineReadersOpened = onOfflineReadersOpened
    self.onProtectedDataHydrationRequired = onProtectedDataHydrationRequired
  }

  // MARK: - Factory & TileProxy Configuration

  /// Creates the `GeoGarageOfflineTileProvider` with V3 compatibility reconciliation
  /// wired back into `downloadRepository`.
  static func makeOfflineTileProvider(
    downloadRepository: GeoGarageDownloadRepository
  ) -> GeoGarageOfflineTileProvider {
    GeoGarageOfflineTileProvider(
      onCompatibilityMismatch: { [weak downloadRepository] downloadID, correctedRequiresV3 in
        guard let repo = downloadRepository else { return }
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
  }

  /// Configures `TileProxyURLProtocol` with the offline tile provider and a rate-limited
  /// `nonisolated` 401/403 authentication failure callback.
  func configureTileProxy(tileProxyManager: any TileProxyManagerProtocol) {
    let lastAuthRefreshAttempt = OSAllocatedUnfairLock<ContinuousClock.Instant?>(initialState: nil)
    let authFailureHandler = Self.makeRateLimitedAuthFailureHandler(
      authService: authService,
      lastAuthRefreshAttempt: lastAuthRefreshAttempt
    )
    TileProxyURLProtocol.configure(
      offlineTileProvider: offlineTileProvider,
      tileProxyManager: tileProxyManager,
      keychainManager: keychainManager,
      onAuthenticationFailure: authFailureHandler
    )
    didConfigureTileProxy = true
  }

  /// Built in a `nonisolated` context so the `@Sendable` callback invoked on arbitrary
  /// `URLProtocol` network threads never inherits `@MainActor` isolation before the lock check.
  private nonisolated static func makeRateLimitedAuthFailureHandler(
    authService: GeoGarageAuthService,
    lastAuthRefreshAttempt: OSAllocatedUnfairLock<ContinuousClock.Instant?>
  ) -> @Sendable () -> Void {
    { [weak authService] in
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
        guard let authService else { return }
        do {
          _ = try await authService.refreshTokens()
        } catch {
          Logger.network.warning("GeoGarage token refresh after tile 401/403 failed: \(error.localizedDescription, privacy: .public)")
        }
      }
    }
  }

  // MARK: - Lifecycle

  /// Idempotently starts observing download registry and customer ID changes.
  func start() {
    guard !isStarted else { return }
    isStarted = true

    let downloadsStream = downloadRepository.downloadsDidChangeStream
    let customerIDStream = preferencesService.geoGarageCustomerIDDidChangeStream

    downloadsObservationTask = Task { @MainActor [weak self] in
      for await _ in downloadsStream {
        guard !Task.isCancelled, let self else { break }
        self.scheduleSync()
      }
    }

    customerIDObservationTask = Task { @MainActor [weak self] in
      for await _ in customerIDStream {
        guard !Task.isCancelled, let self else { break }
        self.scheduleSync()
      }
    }
  }

  /// Cancels and clears all observation, synchronization, and secret-recovery tasks,
  /// and resets static `TileProxyURLProtocol` dependencies if configured by this coordinator.
  func stop() {
    isStarted = false
    downloadsObservationTask?.cancel()
    downloadsObservationTask = nil
    customerIDObservationTask?.cancel()
    customerIDObservationTask = nil
    syncTask?.cancel()
    syncTask = nil
    packageSecretRestoreTask?.cancel()
    packageSecretRestoreTask = nil
    if didConfigureTileProxy {
      TileProxyURLProtocol.reset()
      didConfigureTileProxy = false
    }
  }

  // MARK: - Synchronization & Protected Data Re-Hydration

  /// Re-hydrates Keychain-backed GeoGarage auth state, customer ID, and offline tile readers
  /// once protected data becomes available after a BFU or locked boot.
  @discardableResult
  func rehydrateAfterProtectedDataUnlock() async -> KeychainHydrationStatus {
    syncTask?.cancel()
    syncTask = nil
    packageSecretRestoreTask?.cancel()
    packageSecretRestoreTask = nil

    isRehydrating = true
    defer { isRehydrating = false }

    await authService.bootstrap()
    let customerIDStatus = await preferencesService.loadGeoGarageCustomerID()
    // Drain any buffered `geoGarageCustomerIDDidChangeStream` wakeup while `isRehydrating`
    // suppresses `scheduleSync()`, and ensure no concurrent `syncTask` remains before syncing.
    await Task.yield()
    syncTask?.cancel()
    syncTask = nil

    let secretStatus = await syncOfflineTileProvider(customerIDStatus: customerIDStatus)

    let stillDeferred = authService.isDeferredForProtectedData
      || customerIDStatus == .deferredForProtectedData
      || secretStatus == .deferredForProtectedData
    return stillDeferred ? .deferredForProtectedData : .hydrated
  }

  private func scheduleSync() {
    guard !isRehydrating else { return }
    syncTask?.cancel()
    syncTask = Task { @MainActor [weak self] in
      guard let self else { return }
      let status = await self.syncOfflineTileProvider()
      guard !Task.isCancelled else { return }
      if status == .deferredForProtectedData {
        self.onProtectedDataHydrationRequired()
      }
    }
  }

  /// Synchronizes `offlineTileProvider` with the current download registry and Keychain credentials.
  /// On `errSecInteractionNotAllowed`, preserves open readers and returns `.deferredForProtectedData`.
  @discardableResult
  func syncOfflineTileProvider(
    customerIDStatus: KeychainHydrationStatus = .hydrated
  ) async -> KeychainHydrationStatus {
    let secret: String?
    do {
      secret = try await keychainManager.retrieveValidToken(for: GeoGaragePartnerSecretService.keychainAccount)
    } catch {
      if error.isInteractionNotAllowed {
        Logger.caas.warning("Deferred loading GeoGarage package secret: Keychain locked while protected data is unavailable.")
        return .deferredForProtectedData
      }
      Logger.caas.error("Failed to read GeoGarage package secret from Keychain: \(error.localizedDescription, privacy: .public)")
      guard !Task.isCancelled else { return .hydrated }
      await offlineTileProvider.close()
      return .hydrated
    }

    guard !Task.isCancelled else { return .hydrated }

    if customerIDStatus == .deferredForProtectedData {
      return .deferredForProtectedData
    }

    guard let secret,
          let customerID = preferencesService.geoGarageCustomerID,
          !customerID.isEmpty else {
      await offlineTileProvider.close()
      return .hydrated
    }

    await offlineTileProvider.reloadDownloads(
      downloadRepository.downloads,
      sharedSecret: secret,
      customerID: customerID
    )
    return .hydrated
  }

  // MARK: - Package Secret Recovery

  /// Schedules one-shot recovery off the launch critical path so a boat without WAN never blocks on it.
  func schedulePackageSecretRestore() {
    packageSecretRestoreTask?.cancel()
    packageSecretRestoreTask = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.restorePackageSecretIfMissing()
    }
  }

  /// One-shot recovery of package credentials (secret and/or customerID) missing at launch.
  func restorePackageSecretIfMissing() async {
    guard authService.isGeoGarageAuthenticated else { return }
    let currentSecret = try? await keychainManager.retrieveValidToken(for: GeoGaragePartnerSecretService.keychainAccount)
    let currentCustomerID = preferencesService.geoGarageCustomerID
    let isSecretMissing = currentSecret == nil
    let isCustomerMissing = currentCustomerID == nil || currentCustomerID?.isEmpty == true
    guard isSecretMissing || isCustomerMissing else { return }
    guard let accessToken = try? await keychainManager.retrieveValidToken(for: GeoGarageKeychainKeys.accessToken) else { return }

    do {
      let secrets = try await partnerSecretService.refresh(accessToken: accessToken)
      Logger.network.info("Partner package secret restored at startup.")
      await applyRestoredSecrets(secrets, accessToken: accessToken, fallbackSecret: currentSecret)
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
      onPackageSecretWarning()
      return
    }

    do {
      let tokens = try await authService.refreshTokens()
      let secrets = try await partnerSecretService.refresh(accessToken: tokens.access_token)
      Logger.network.info("Partner package secret restored at startup after a token refresh.")
      await applyRestoredSecrets(secrets, accessToken: tokens.access_token, fallbackSecret: currentSecret)
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
      onPackageSecretWarning()
    }
  }

  private func applyRestoredSecrets(
    _ secrets: GeoGaragePartnerSecrets,
    accessToken: String,
    fallbackSecret: String?
  ) async {
    if let newCust = secrets.customerID, !newCust.isEmpty {
      preferencesService.geoGarageCustomerID = newCust
    }
    if preferencesService.geoGarageCustomerID == nil {
      _ = try? await authService.fetchAccountSettings(accessToken: accessToken)
    }
    let newSecret = secrets.packageSecret.isEmpty ? nil : secrets.packageSecret
    let resolvedSecret = newSecret ?? fallbackSecret
    if let resolvedSecret, let resolvedCust = preferencesService.geoGarageCustomerID, !resolvedCust.isEmpty {
      await openOfflineReaders(with: resolvedSecret, customerID: resolvedCust)
    }
  }

  /// Reopens the offline readers with freshly fetched credentials.
  private func openOfflineReaders(with packageSecret: String, customerID: String) async {
    onOfflineReadersOpened()
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
}

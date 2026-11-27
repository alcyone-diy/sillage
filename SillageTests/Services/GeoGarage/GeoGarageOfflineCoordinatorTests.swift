//
//  GeoGarageOfflineCoordinatorTests.swift
//  SillageTests
//
//  Created by Alcyone on 2026-11-26.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import os
import Security
import Testing
@testable import Sillage

@Suite("GeoGarageOfflineCoordinator", .serialized)
@MainActor
struct GeoGarageOfflineCoordinatorTests {

  private final class SpyOfflineTileProvider: GeoGarageOfflineTileProviderProtocol, @unchecked Sendable {
    struct ReloadCall: Sendable, Equatable {
      let downloadIDs: [UUID]
      let sharedSecret: String
      let customerID: String
    }

    private let state = OSAllocatedUnfairLock<(reloads: [ReloadCall], closeCount: Int)>(
      initialState: (reloads: [], closeCount: 0)
    )

    var reloads: [ReloadCall] {
      state.withLock { $0.reloads }
    }

    var closeCount: Int {
      state.withLock { $0.closeCount }
    }

    func tile(layerID: String, z: Int, x: Int, y: Int) async -> Data? {
      nil
    }

    func reloadDownloads(
      _ downloads: [OfflineChartDownload],
      sharedSecret: String,
      customerID: String
    ) async {
      let call = ReloadCall(
        downloadIDs: downloads.map(\.id),
        sharedSecret: sharedSecret,
        customerID: customerID
      )
      state.withLock { $0.reloads.append(call) }
    }

    func close() async {
      state.withLock { $0.closeCount += 1 }
    }
  }

  private struct Fixture {
    let coordinator: GeoGarageOfflineCoordinator
    let authService: GeoGarageAuthService
    let downloadRepository: GeoGarageDownloadRepository
    let tileProvider: SpyOfflineTileProvider
    let preferencesService: PreferencesService
    let partnerSecretService: MockGeoGaragePartnerSecretService
    let keychainManager: MockKeychainManager
    let isolatedDefaults: IsolatedUserDefaults
    let warningCount: OSAllocatedUnfairLock<Int>
    let readersOpenedCount: OSAllocatedUnfairLock<Int>
    let hydrationRequiredCount: OSAllocatedUnfairLock<Int>
  }

  private func makeFixture() throws -> Fixture {
    MockURLProtocol.reset()
    installPortalHandler()

    let databaseManager = try DatabaseManager.inMemory()
    let keychain = MockKeychainManager()
    let isolatedDefaults = IsolatedUserDefaults(prefix: "GeoGarageOfflineCoordinatorTests")
    let preferences = PreferencesService(defaults: isolatedDefaults.defaults, keychainManager: keychain)
    preferences.clearAll()

    let layerRepository = GeoGarageLayerRepository(databaseManager: databaseManager)
    let downloadRepository = GeoGarageDownloadRepository(databaseManager: databaseManager)
    let authSession = MockURLProtocol.makeMockSession()
    let authService = GeoGarageAuthService(
      preferencesService: preferences,
      layerRepository: layerRepository,
      keychainManager: keychain,
      session: authSession,
      configuration: .fromBundle()
    )
    let tileProvider = SpyOfflineTileProvider()
    let partnerSecretService = MockGeoGaragePartnerSecretService()

    let warningCount = OSAllocatedUnfairLock<Int>(initialState: 0)
    let readersOpenedCount = OSAllocatedUnfairLock<Int>(initialState: 0)
    let hydrationRequiredCount = OSAllocatedUnfairLock<Int>(initialState: 0)

    let coordinator = GeoGarageOfflineCoordinator(
      authService: authService,
      downloadRepository: downloadRepository,
      offlineTileProvider: tileProvider,
      preferencesService: preferences,
      partnerSecretService: partnerSecretService,
      keychainManager: keychain,
      onPackageSecretWarning: {
        warningCount.withLock { $0 += 1 }
      },
      onOfflineReadersOpened: {
        readersOpenedCount.withLock { $0 += 1 }
      },
      onProtectedDataHydrationRequired: {
        hydrationRequiredCount.withLock { $0 += 1 }
      }
    )

    return Fixture(
      coordinator: coordinator,
      authService: authService,
      downloadRepository: downloadRepository,
      tileProvider: tileProvider,
      preferencesService: preferences,
      partnerSecretService: partnerSecretService,
      keychainManager: keychain,
      isolatedDefaults: isolatedDefaults,
      warningCount: warningCount,
      readersOpenedCount: readersOpenedCount,
      hydrationRequiredCount: hydrationRequiredCount
    )
  }

  private func installPortalHandler(tokenStatus: Int = 403, tokenBody: String = "") {
    MockURLProtocol.setHandler { request in
      let url = request.url ?? URL(fileURLWithPath: "/")
      let isTokenEndpoint = request.url?.path == "/o/token"
      let status = isTokenEndpoint ? tokenStatus : 403
      let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) ?? HTTPURLResponse()
      return (response, isTokenEndpoint ? Data(tokenBody.utf8) : Data())
    }
  }

  private func makeSampleDownload(id: UUID = UUID()) -> OfflineChartDownload {
    OfflineChartDownload(
      id: id,
      layerID: "shom",
      layerName: "SHOM",
      downloadDate: Date(),
      relativePath: "Charts/test_\(id.uuidString).mbtiles",
      md5: "abc123",
      zoomMax: 12,
      boundsWKT: "POLYGON((0 0, 0 1, 1 1, 1 0, 0 0))"
    )
  }

  private func waitUntil(
    timeout: Duration = .seconds(1),
    condition: @MainActor () -> Bool
  ) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
      if ContinuousClock.now >= deadline {
        return false
      }
      await Task.yield()
      try? await Task.sleep(for: .milliseconds(5))
    }
    return true
  }

  @Test("Reactive sync reloads offline tile provider on downloads and customerID changes")
  func reactiveSyncOnDownloadsAndCustomerIDChanges() async throws {
    let fixture = try makeFixture()
    defer {
      fixture.coordinator.stop()
      fixture.isolatedDefaults.tearDown()
      MockURLProtocol.reset()
    }

    try await fixture.keychainManager.save(token: "shared-secret", for: GeoGaragePartnerSecretService.keychainAccount)
    fixture.preferencesService.geoGarageCustomerID = "cus_initial"

    fixture.coordinator.start()
    // Calling start() a second time must remain idempotent.
    fixture.coordinator.start()

    let download = makeSampleDownload()
    try await fixture.downloadRepository.save(download)

    let reloadedAfterDownload = await waitUntil {
      fixture.tileProvider.reloads.last == .init(
        downloadIDs: [download.id],
        sharedSecret: "shared-secret",
        customerID: "cus_initial"
      )
    }
    #expect(reloadedAfterDownload)

    fixture.preferencesService.geoGarageCustomerID = "cus_updated"
    let reloadedAfterCustomerID = await waitUntil {
      fixture.tileProvider.reloads.last == .init(
        downloadIDs: [download.id],
        sharedSecret: "shared-secret",
        customerID: "cus_updated"
      )
    }
    #expect(reloadedAfterCustomerID)

    fixture.preferencesService.geoGarageCustomerID = nil
    let closedAfterClear = await waitUntil {
      fixture.tileProvider.closeCount >= 1
    }
    #expect(closedAfterClear)
  }

  @Test("restorePackageSecretIfMissing succeeds directly and opens offline readers")
  func restorePackageSecretDirectSuccess() async throws {
    let fixture = try makeFixture()
    defer {
      fixture.coordinator.stop()
      fixture.isolatedDefaults.tearDown()
      MockURLProtocol.reset()
    }

    try await fixture.keychainManager.save(token: "valid-access-token", for: GeoGarageKeychainKeys.accessToken)
    await fixture.authService.bootstrap()
    #expect(fixture.authService.isGeoGarageAuthenticated == true)

    fixture.partnerSecretService.secrets = GeoGaragePartnerSecrets(
      clientID: "client-1",
      customerID: "cus_restored",
      packageSecret: "restored-secret",
      teaSecret: ""
    )

    await fixture.coordinator.restorePackageSecretIfMissing()

    #expect(fixture.partnerSecretService.receivedAccessTokens == ["valid-access-token"])
    #expect(fixture.preferencesService.geoGarageCustomerID == "cus_restored")
    #expect(fixture.readersOpenedCount.withLock { $0 } == 1)
    #expect(fixture.warningCount.withLock { $0 } == 0)
    #expect(fixture.tileProvider.reloads.last == .init(
      downloadIDs: [],
      sharedSecret: "restored-secret",
      customerID: "cus_restored"
    ))
  }

  @Test("restorePackageSecretIfMissing refreshes token on 401 and retries successfully")
  func restorePackageSecretRefreshesOn401ThenRetries() async throws {
    let fixture = try makeFixture()
    defer {
      fixture.coordinator.stop()
      fixture.isolatedDefaults.tearDown()
      MockURLProtocol.reset()
    }

    try await fixture.keychainManager.save(token: "expired-access-token", for: GeoGarageKeychainKeys.accessToken)
    try await fixture.keychainManager.save(token: "valid-refresh-token", for: GeoGarageKeychainKeys.refreshToken)
    await fixture.authService.bootstrap()

    installPortalHandler(
      tokenStatus: 200,
      tokenBody: #"{"access_token":"fresh-access-token","token_type":"Bearer","expires_in":3600,"refresh_token":"fresh-refresh-token","scope":"read"}"#
    )
    fixture.partnerSecretService.results = [
      .failure(.unauthorized),
      .success(GeoGaragePartnerSecrets(
        clientID: "client-1",
        customerID: "cus_after_refresh",
        packageSecret: "secret-after-refresh",
        teaSecret: ""
      ))
    ]

    await fixture.coordinator.restorePackageSecretIfMissing()

    #expect(fixture.partnerSecretService.receivedAccessTokens == ["expired-access-token", "fresh-access-token"])
    #expect(fixture.preferencesService.geoGarageCustomerID == "cus_after_refresh")
    #expect(fixture.readersOpenedCount.withLock { $0 } == 1)
    #expect(fixture.warningCount.withLock { $0 } == 0)
    #expect(fixture.tileProvider.reloads.last == .init(
      downloadIDs: [],
      sharedSecret: "secret-after-refresh",
      customerID: "cus_after_refresh"
    ))
  }

  @Test("restorePackageSecretIfMissing triggers onPackageSecretWarning on non-network failure")
  func restorePackageSecretFailureTriggersWarning() async throws {
    let fixture = try makeFixture()
    defer {
      fixture.coordinator.stop()
      fixture.isolatedDefaults.tearDown()
      MockURLProtocol.reset()
    }

    try await fixture.keychainManager.save(token: "valid-access-token", for: GeoGarageKeychainKeys.accessToken)
    await fixture.authService.bootstrap()
    fixture.partnerSecretService.errorToThrow = .noProfile

    await fixture.coordinator.restorePackageSecretIfMissing()

    #expect(fixture.warningCount.withLock { $0 } == 1)
    #expect(fixture.readersOpenedCount.withLock { $0 } == 0)
    #expect(fixture.tileProvider.reloads.isEmpty)
  }

  @Test("rehydrateAfterProtectedDataUnlock defers while Keychain is locked and hydrates once unlocked")
  func rehydrateAfterProtectedDataUnlockBFUFlow() async throws {
    let fixture = try makeFixture()
    defer {
      fixture.coordinator.stop()
      fixture.isolatedDefaults.tearDown()
      MockURLProtocol.reset()
    }

    try await fixture.keychainManager.save(token: "bfu-access-token", for: GeoGarageKeychainKeys.accessToken)
    try await fixture.keychainManager.save(token: "bfu-secret", for: GeoGaragePartnerSecretService.keychainAccount)
    try await fixture.keychainManager.save(token: "cus_bfu", for: GeoGarageKeychainKeys.customerID)

    // Simulate Before-First-Unlock Keychain lock.
    fixture.keychainManager.setStubbedError(.unexpectedStatus(errSecInteractionNotAllowed))

    let lockedStatus = await fixture.coordinator.rehydrateAfterProtectedDataUnlock()
    #expect(lockedStatus == .deferredForProtectedData)
    #expect(fixture.tileProvider.closeCount == 0)
    #expect(fixture.tileProvider.reloads.isEmpty)

    // Unlock protected data and re-hydrate.
    fixture.keychainManager.setStubbedError(nil)

    let unlockedStatus = await fixture.coordinator.rehydrateAfterProtectedDataUnlock()
    #expect(unlockedStatus == .hydrated)
    #expect(fixture.authService.isGeoGarageAuthenticated == true)
    #expect(fixture.preferencesService.geoGarageCustomerID == "cus_bfu")
    #expect(fixture.tileProvider.reloads.last == .init(
      downloadIDs: [],
      sharedSecret: "bfu-secret",
      customerID: "cus_bfu"
    ))
  }

  private final class SuspendingPartnerSecretService: GeoGaragePartnerSecretServiceProtocol, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock<(started: Bool, continuation: CheckedContinuation<Void, Never>?)>(
      initialState: (started: false, continuation: nil)
    )

    var hasStartedRefresh: Bool {
      state.withLock { $0.started }
    }

    func resumeRefresh() {
      let continuation = state.withLock { state -> CheckedContinuation<Void, Never>? in
        let cont = state.continuation
        state.continuation = nil
        return cont
      }
      continuation?.resume()
    }

    func refresh(accessToken: String) async throws -> GeoGaragePartnerSecrets {
      await withCheckedContinuation { continuation in
        state.withLock {
          $0.started = true
          $0.continuation = continuation
        }
      }
      if Task.isCancelled {
        throw PartnerSecretError.cancelled
      }
      return GeoGaragePartnerSecrets(
        clientID: "client-1",
        customerID: "cus_from_suspended_restore",
        packageSecret: "secret_from_suspended_restore",
        teaSecret: ""
      )
    }
  }

  @Test("rehydrateAfterProtectedDataUnlock cancels in-flight restore task and avoids duplicate reload")
  func rehydrateCancelsInFlightRestoreAndAvoidsDuplicateReload() async throws {
    MockURLProtocol.reset()
    installPortalHandler()

    let databaseManager = try DatabaseManager.inMemory()
    let keychain = MockKeychainManager()
    let isolatedDefaults = IsolatedUserDefaults(prefix: "GeoGarageOfflineCoordinatorRehydrateRace")
    let preferences = PreferencesService(defaults: isolatedDefaults.defaults, keychainManager: keychain)
    preferences.clearAll()

    let layerRepository = GeoGarageLayerRepository(databaseManager: databaseManager)
    let downloadRepository = GeoGarageDownloadRepository(databaseManager: databaseManager)
    let authService = GeoGarageAuthService(
      preferencesService: preferences,
      layerRepository: layerRepository,
      keychainManager: keychain,
      session: MockURLProtocol.makeMockSession(),
      configuration: .fromBundle()
    )
    let tileProvider = SpyOfflineTileProvider()
    let suspendingSecretService = SuspendingPartnerSecretService()

    let coordinator = GeoGarageOfflineCoordinator(
      authService: authService,
      downloadRepository: downloadRepository,
      offlineTileProvider: tileProvider,
      preferencesService: preferences,
      partnerSecretService: suspendingSecretService,
      keychainManager: keychain,
      onPackageSecretWarning: {},
      onOfflineReadersOpened: {}
    )
    defer {
      suspendingSecretService.resumeRefresh()
      coordinator.stop()
      isolatedDefaults.tearDown()
      MockURLProtocol.reset()
    }

    // Start active stream observations so `loadGeoGarageCustomerID()` emits onto an active listener.
    coordinator.start()

    // Seed access token with missing secret/customerID so `schedulePackageSecretRestore()` enters `refresh`.
    try await keychain.save(token: "valid-access-token", for: GeoGarageKeychainKeys.accessToken)
    await authService.bootstrap()

    coordinator.schedulePackageSecretRestore()
    let inFlightRestoreTask = try #require(coordinator.packageSecretRestoreTask)
    let enteredRefresh = await waitUntil { suspendingSecretService.hasStartedRefresh }
    #expect(enteredRefresh)

    // Populate Keychain credentials before protected-data rehydration runs.
    try await keychain.save(token: "rehydrated-secret", for: GeoGaragePartnerSecretService.keychainAccount)
    try await keychain.save(token: "cus_rehydrated", for: GeoGarageKeychainKeys.customerID)

    let status = await coordinator.rehydrateAfterProtectedDataUnlock()
    #expect(status == .hydrated)
    #expect(inFlightRestoreTask.isCancelled == true)
    #expect(coordinator.packageSecretRestoreTask == nil)

    // Unblock the cancelled refresh and allow any stray tasks to drain.
    suspendingSecretService.resumeRefresh()
    await inFlightRestoreTask.value
    try? await Task.sleep(for: .milliseconds(50))

    // Exactly one reload must have occurred (no concurrent duplicate from `geoGarageCustomerIDDidChangeStream`
    // and no late reload from the cancelled restore task).
    #expect(tileProvider.reloads == [
      .init(downloadIDs: [], sharedSecret: "rehydrated-secret", customerID: "cus_rehydrated")
    ])
  }

  @Test("stop() cancels observation streams and resets TileProxyURLProtocol when configured")
  func stopCancelsObservation() async throws {
    let fixture = try makeFixture()
    defer {
      TileProxyURLProtocol.resetForTesting()
      fixture.isolatedDefaults.tearDown()
      MockURLProtocol.reset()
    }

    try await fixture.keychainManager.save(token: "shared-secret", for: GeoGaragePartnerSecretService.keychainAccount)
    fixture.preferencesService.geoGarageCustomerID = "cus_active"

    let proxyManager = TileProxyManager(
      keychainManager: fixture.keychainManager,
      configuration: .fromBundle()
    )
    fixture.coordinator.configureTileProxy(tileProxyManager: proxyManager)
    #expect(TileProxyURLProtocol.offlineTileProvider != nil)
    #expect(TileProxyURLProtocol.onAuthenticationFailure != nil)

    fixture.coordinator.start()
    fixture.coordinator.stop()

    #expect(TileProxyURLProtocol.offlineTileProvider == nil)
    #expect(TileProxyURLProtocol.tileProxyManager == nil)
    #expect(TileProxyURLProtocol.keychainManager == nil)
    #expect(TileProxyURLProtocol.onAuthenticationFailure == nil)

    let download = makeSampleDownload()
    try await fixture.downloadRepository.save(download)
    fixture.preferencesService.geoGarageCustomerID = "cus_after_stop"

    try? await Task.sleep(for: .milliseconds(50))
    #expect(fixture.tileProvider.reloads.isEmpty)
    #expect(fixture.tileProvider.closeCount == 0)
  }
}

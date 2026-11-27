//
//  ActiveNavigationServiceTests.swift
//  Alcyone SillageTests
//
//  Created by Alcyone on 2026-11-27.
//  Copyright © 2026 Alcyone.
//  See LICENSE file in the project root for full license information.
//

import Testing
import Foundation
import CoreLocation
import GRDB
@testable import Sillage

@Suite("Active Navigation Evaluator & Service Tests")
struct ActiveNavigationServiceTests {

  // MARK: - Helpers

  private static func makeState(
    coordinate: CLLocationCoordinate2D?,
    gpsState: GPSState,
    timestamp: Date = Date(timeIntervalSince1970: 1_700_000_000)
  ) -> InstrumentState {
    InstrumentState(
      coordinate: coordinate,
      horizontalAccuracy: Measurement(value: 5.0, unit: .meters),
      smoothedSOG: Measurement(value: 5.0, unit: .knots),
      smoothedCOG: Measurement(value: 90.0, unit: .degrees),
      courseState: .active,
      gpsState: gpsState,
      sensorTimestamp: timestamp,
      systemDate: timestamp
    )
  }

  private static func makeWaypoint(
    id: String = "wpt-dest",
    name: String = "Phare de Chauveau",
    coordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 46.0, longitude: -1.0)
  ) -> Waypoint {
    Waypoint(
      id: id,
      name: name,
      colorHex: "#FF9500",
      coordinate: coordinate,
      timestamp: Date(timeIntervalSince1970: 1_700_000_000)
    )
  }

  // MARK: - Pure Evaluator Truth Table Tests

  @Test("Evaluator truth table across .active, .degraded, .stale, .lost, and nil states")
  func testEvaluatorTruthTable() throws {
    let origin = CLLocationCoordinate2D(latitude: 46.0, longitude: -1.20)
    let destination = CLLocationCoordinate2D(latitude: 46.0, longitude: -1.00)
    // Displaced north of the E-W leg -> starboard/port non-zero XTE
    let current = CLLocationCoordinate2D(latitude: 46.02, longitude: -1.10)
    let waypoint = Self.makeWaypoint(coordinate: destination)

    let lockedLeg = ActiveNavigationLeg(
      waypoint: waypoint,
      originCoordinate: origin,
      activatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let unlockedLeg = ActiveNavigationLeg(
      waypoint: waypoint,
      originCoordinate: nil,
      activatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    // 1. .active with locked origin -> BTW, RNG, and XTE all non-nil
    let activeState = Self.makeState(coordinate: current, gpsState: .active)
    #expect(ActiveNavigationEvaluator.eligibleOriginCoordinate(from: activeState) == current)
    let activeMetrics = ActiveNavigationEvaluator.evaluate(leg: lockedLeg, state: activeState)
    #expect(activeMetrics.bearingToWaypoint != nil)
    #expect(activeMetrics.rangeToWaypoint != nil)
    let xteMeters = try #require(activeMetrics.crossTrackError?.converted(to: .meters).value)
    #expect(abs(xteMeters) > 1000.0)

    // 2. .active without locked origin -> BTW and RNG computed, XTE strictly nil (never dummy 0)
    let unlockedActiveMetrics = ActiveNavigationEvaluator.evaluate(leg: unlockedLeg, state: activeState)
    #expect(unlockedActiveMetrics.bearingToWaypoint != nil)
    #expect(unlockedActiveMetrics.rangeToWaypoint != nil)
    #expect(unlockedActiveMetrics.crossTrackError == nil)

    // 3. .degraded -> NOT eligible to lock origin, but computes BTW, RNG, and XTE (if origin already locked)
    let degradedState = Self.makeState(coordinate: current, gpsState: .degraded)
    #expect(ActiveNavigationEvaluator.eligibleOriginCoordinate(from: degradedState) == nil)
    let degradedLockedMetrics = ActiveNavigationEvaluator.evaluate(leg: lockedLeg, state: degradedState)
    #expect(degradedLockedMetrics.bearingToWaypoint == activeMetrics.bearingToWaypoint)
    #expect(degradedLockedMetrics.rangeToWaypoint == activeMetrics.rangeToWaypoint)
    #expect(degradedLockedMetrics.crossTrackError == activeMetrics.crossTrackError)

    let degradedUnlockedMetrics = ActiveNavigationEvaluator.evaluate(leg: unlockedLeg, state: degradedState)
    #expect(degradedUnlockedMetrics.bearingToWaypoint != nil)
    #expect(degradedUnlockedMetrics.rangeToWaypoint != nil)
    #expect(degradedUnlockedMetrics.crossTrackError == nil)

    // 4. .stale -> NOT eligible to lock origin, all metrics strictly nil
    let staleState = Self.makeState(coordinate: current, gpsState: .stale)
    #expect(ActiveNavigationEvaluator.eligibleOriginCoordinate(from: staleState) == nil)
    #expect(ActiveNavigationEvaluator.evaluate(leg: lockedLeg, state: staleState) == .empty)

    // 5. .lost -> NOT eligible to lock origin, all metrics strictly nil even if cached coordinate is retained
    let lostState = Self.makeState(coordinate: current, gpsState: .lost)
    #expect(ActiveNavigationEvaluator.eligibleOriginCoordinate(from: lostState) == nil)
    #expect(ActiveNavigationEvaluator.evaluate(leg: lockedLeg, state: lostState) == .empty)

    // 6. nil state or nil leg -> strictly empty
    #expect(ActiveNavigationEvaluator.evaluate(leg: lockedLeg, state: nil) == .empty)
    #expect(ActiveNavigationEvaluator.evaluate(leg: nil, state: activeState) == .empty)
  }

  @Test("Exact geodesic BTW, RNG, and port vs starboard XTE sign inversion")
  func testEvaluatorExactGeodesicValuesAndPortStarboardSignInversion() throws {
    // 1° Eastbound leg along the equator: (0°N, 0°E) -> (0°N, 1°E)
    let origin = CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)
    let destination = CLLocationCoordinate2D(latitude: 0.0, longitude: 1.0)
    let waypoint = Self.makeWaypoint(coordinate: destination)
    let leg = ActiveNavigationLeg(
      waypoint: waypoint,
      originCoordinate: origin,
      activatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    // A. On-track at origin: BTW == 90.0°, RNG ≈ 60.11 NM (111,319.5 m), XTE == 0.0 m
    let atOriginMetrics = ActiveNavigationEvaluator.evaluate(
      leg: leg,
      state: Self.makeState(coordinate: origin, gpsState: .active)
    )
    let btwDeg = try #require(atOriginMetrics.bearingToWaypoint?.converted(to: .degrees).value)
    let rngNM = try #require(atOriginMetrics.rangeToWaypoint?.converted(to: .marineNauticalMiles).value)
    let rngMeters = try #require(atOriginMetrics.rangeToWaypoint?.converted(to: .meters).value)
    let onTrackXTE = try #require(atOriginMetrics.crossTrackError?.converted(to: .meters).value)

    #expect(abs(btwDeg - 90.0) < 0.05)
    #expect(abs(rngNM - 60.107) < 0.1)
    #expect(abs(rngMeters - 111_319.5) < 150.0)
    #expect(abs(onTrackXTE) < 0.01)

    // B. Displaced 0.01° North (Port side of an 090° Eastbound leg) at midpoint (0.01°N, 0.5°E)
    let portPosition = CLLocationCoordinate2D(latitude: 0.01, longitude: 0.5)
    let portMetrics = ActiveNavigationEvaluator.evaluate(
      leg: leg,
      state: Self.makeState(coordinate: portPosition, gpsState: .active)
    )
    let portXTEMeters = try #require(portMetrics.crossTrackError?.converted(to: .meters).value)

    // C. Symmetrically displaced 0.01° South (Starboard side of an 090° Eastbound leg) at (-0.01°S, 0.5°E)
    let starboardPosition = CLLocationCoordinate2D(latitude: -0.01, longitude: 0.5)
    let starboardMetrics = ActiveNavigationEvaluator.evaluate(
      leg: leg,
      state: Self.makeState(coordinate: starboardPosition, gpsState: .active)
    )
    let starboardXTEMeters = try #require(starboardMetrics.crossTrackError?.converted(to: .meters).value)

    // 0.01° of latitude ≈ 1,105.7 m — verify magnitude, symmetry, and strict opposite signs
    #expect(abs(abs(portXTEMeters) - 1_111.9) < 15.0)
    #expect(abs(abs(starboardXTEMeters) - 1_111.9) < 15.0)
    #expect(portXTEMeters * starboardXTEMeters < 0.0, "Port and starboard XTE must have opposite signs")
    #expect(portXTEMeters < 0.0, "Port of course is negative XTE")
    #expect(starboardXTEMeters > 0.0, "Starboard of course is positive XTE")
    #expect(abs(portXTEMeters + starboardXTEMeters) < 0.1)
  }

  // MARK: - Service Lifecycle, Origin Locking & Persistence Tests

  @Test("Stationary boat at pontoon with .active GPS locks origin immediately without waiting for new fix")
  @MainActor
  func testStationaryPontoonImmediateOriginLock() async throws {
    let db = try DatabaseManager.inMemory()
    let waypointService = WaypointService(databaseManager: db)
    let target = Self.makeWaypoint()
    try await waypointService.saveWaypoint(target)

    let pontoonCoord = CLLocationCoordinate2D(latitude: 46.1591, longitude: -1.1522)
    // Sensor timestamp is 60s BEFORE GoTo activation (stationary within distanceFilter)
    let stationaryFix = Self.makeState(
      coordinate: pontoonCoord,
      gpsState: .active,
      timestamp: Date(timeIntervalSince1970: 1_700_000_000)
    )

    let (stream, _) = AsyncStream<InstrumentState>.makeStream()
    let service = ActiveNavigationService(
      databaseManager: db,
      currentInstrumentState: { stationaryFix },
      observeInstrumentState: { stream },
      dateProvider: { Date(timeIntervalSince1970: 1_700_000_060) }
    )
    await service.start()
    defer { service.stop() }

    try await service.setDestination(waypointID: target.id)

    let leg = try #require(service.activeLeg)
    #expect(leg.originCoordinate == pontoonCoord)
    #expect(service.bearingToWaypoint != nil)
    #expect(service.rangeToWaypoint != nil)
    let initialXTE = try #require(service.crossTrackError?.converted(to: .meters).value)
    #expect(abs(initialXTE) < 0.01)

    // Verify atomic persistence in SQLite
    let record = try await db.reader.read { dbConn in
      try ActiveNavigationRecord.fetchOne(dbConn, key: ActiveNavigationRecord.singletonID)
    }
    #expect(record?.originCoordinate == pontoonCoord)
  }

  @Test("Deferred origin lock ignores .lost/.degraded/.stale and locks on first .active fix, surviving app restart")
  @MainActor
  func testDeferredOriginLockAndAppRestartStatePreservation() async throws {
    let db = try DatabaseManager.inMemory()
    let waypointService = WaypointService(databaseManager: db)
    let target = Self.makeWaypoint(
      id: "wpt-offshore",
      coordinate: CLLocationCoordinate2D(latitude: 46.00, longitude: -1.00)
    )
    try await waypointService.saveWaypoint(target)

    var currentState: InstrumentState? = Self.makeState(
      coordinate: CLLocationCoordinate2D(latitude: 48.85, longitude: 2.35), // Cached old coordinate while GPS is .lost!
      gpsState: .lost
    )
    let (stream, continuation) = AsyncStream<InstrumentState>.makeStream()

    let service = ActiveNavigationService(
      databaseManager: db,
      currentInstrumentState: { currentState },
      observeInstrumentState: { stream }
    )
    await service.start()

    // 1. Activate indoors while GPS is .lost -> must NOT lock onto cached Paris coordinate
    try await service.setDestination(waypointID: target.id)
    #expect(service.activeLeg?.waypoint.id == target.id)
    #expect(service.activeLeg?.originCoordinate == nil)
    #expect(service.bearingToWaypoint == nil)
    #expect(service.rangeToWaypoint == nil)
    #expect(service.crossTrackError == nil)

    // 2. Receive a .degraded fix -> computes BTW & RNG, but still refuses to lock origin (XTE == nil)
    let degradedCoord = CLLocationCoordinate2D(latitude: 46.00, longitude: -1.25)
    let degradedState = Self.makeState(coordinate: degradedCoord, gpsState: .degraded)
    currentState = degradedState
    continuation.yield(degradedState)
    try await waitUntil { service.bearingToWaypoint != nil }
    #expect(service.activeLeg?.originCoordinate == nil)
    #expect(service.crossTrackError == nil)

    // 3. Receive first .active fix at leg origin -> locks origin immediately and persists to SQLite
    let trueOrigin = CLLocationCoordinate2D(latitude: 46.00, longitude: -1.20)
    let firstActiveState = Self.makeState(coordinate: trueOrigin, gpsState: .active)
    currentState = firstActiveState
    continuation.yield(firstActiveState)
    try await waitUntil { service.activeLeg?.originCoordinate == trueOrigin }

    // Wait for background SQLite origin persistence to flush
    var persistedOrigin: CLLocationCoordinate2D?
    for _ in 0..<50 {
      let persisted = try await db.reader.read { dbConn in
        try ActiveNavigationRecord.fetchOne(dbConn, key: ActiveNavigationRecord.singletonID)
      }
      if let coord = persisted?.originCoordinate {
        persistedOrigin = coord
        break
      }
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect(persistedOrigin == trueOrigin)

    // 4. Vessel drifts 0.03° (~3.3 km) north of the leg
    let driftedCoord = CLLocationCoordinate2D(latitude: 46.03, longitude: -1.10)
    let driftedState = Self.makeState(coordinate: driftedCoord, gpsState: .active)
    currentState = driftedState
    continuation.yield(driftedState)
    try await waitUntil {
      guard let xte = service.crossTrackError?.converted(to: .meters).value else { return false }
      return abs(xte) > 2500.0
    }
    let preKillXTE = try #require(service.crossTrackError)
    #expect(service.activeLeg?.originCoordinate == trueOrigin)

    // 5. GPS temporarily drops to .lost mid-passage -> metrics return nil, origin stays locked in DB
    let midPassageLost = Self.makeState(coordinate: driftedCoord, gpsState: .lost)
    currentState = midPassageLost
    continuation.yield(midPassageLost)
    try await waitUntil { service.crossTrackError == nil }
    #expect(service.bearingToWaypoint == nil)
    #expect(service.rangeToWaypoint == nil)
    #expect(service.activeLeg?.originCoordinate == trueOrigin)

    service.stop()

    // 6. Simulate iOS killing and relaunching Sillage at `driftedCoord` -> XTE must NOT reset to 0!
    let (restartedStream, _) = AsyncStream<InstrumentState>.makeStream()
    let restartedService = ActiveNavigationService(
      databaseManager: db,
      currentInstrumentState: { driftedState },
      observeInstrumentState: { restartedStream }
    )

    var emittedOnColdStart = false
    let activationCheckTask = Task { @MainActor in
      for await _ in restartedService.navigationActivationStream {
        emittedOnColdStart = true
      }
    }

    await restartedService.start()
    defer {
      activationCheckTask.cancel()
      restartedService.stop()
    }

    #expect(restartedService.activeLeg?.originCoordinate == trueOrigin)
    #expect(restartedService.crossTrackError == preKillXTE)
    #expect(emittedOnColdStart == false)
  }

  @Test("Deleting target waypoint in WaypointService cascade-clears ActiveNavigationService automatically")
  @MainActor
  func testWaypointDeletionCascadesAndClearsActiveNavigation() async throws {
    let db = try DatabaseManager.inMemory()
    let waypointService = WaypointService(databaseManager: db)
    let target = Self.makeWaypoint(id: "wpt-to-delete")
    try await waypointService.saveWaypoint(target)

    let activeState = Self.makeState(
      coordinate: CLLocationCoordinate2D(latitude: 46.05, longitude: -1.15),
      gpsState: .active
    )
    let (stream, _) = AsyncStream<InstrumentState>.makeStream()
    let navService = ActiveNavigationService(
      databaseManager: db,
      currentInstrumentState: { activeState },
      observeInstrumentState: { stream }
    )
    await navService.start()
    defer { navService.stop() }

    try await navService.setDestination(waypointID: target.id)
    #expect(navService.goToWaypointID == target.id)
    #expect(navService.bearingToWaypoint != nil)

    // Delete waypoint strictly through WaypointService (zero direct call to ActiveNavigationService)
    try await waypointService.deleteWaypoint(id: target.id)

    try await waitUntil { navService.activeLeg == nil }
    #expect(navService.goToWaypointID == nil)
    #expect(navService.bearingToWaypoint == nil)
    #expect(navService.rangeToWaypoint == nil)
    #expect(navService.crossTrackError == nil)
  }

  @Test("ChartViewModel frames camera on explicit GoTo activation but preserves saved camera on cold-start restoration")
  @MainActor
  func testChartViewModelColdStartVsExplicitActivationCameraFraming() async throws {
    let db = try DatabaseManager.inMemory()
    let waypointService = WaypointService(databaseManager: db)
    let target = Self.makeWaypoint(id: "wpt-camera")
    try await waypointService.saveWaypoint(target)

    let positioningService = MockPositioningService()
    let instrumentDampingService = InstrumentDampingService(positioningService: positioningService)
    let activeNavigationService = ActiveNavigationService(
      databaseManager: db,
      instrumentDampingService: instrumentDampingService
    )
    // Pre-persist an active leg BEFORE ChartViewModel is constructed (simulating cold start)
    try await activeNavigationService.setDestination(waypointID: target.id)

    let preferencesService = MockPreferencesService()
    preferencesService.lastMapTrackingMode = .courseUp
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let anchorService = AnchorService(
      positioningService: positioningService,
      preferencesService: preferencesService,
      notificationService: LocalNotificationService(),
      permissionService: permissionService,
      backgroundMonitoringService: DefaultBackgroundMonitoringService(positioningService: positioningService),
      stateStore: MockAnchorStateStore()
    )

    let chartVM = ChartViewModel(
      positioningService: positioningService,
      instrumentDampingService: instrumentDampingService,
      preferencesService: preferencesService,
      authService: MockGeoGarageAuthService(),
      anchorService: anchorService,
      anchorViewModel: AnchorViewModel(anchorService: anchorService),
      waypointService: waypointService,
      activeNavigationService: activeNavigationService
    )

    // 1. Cold start: visual state is hydrated, but trackingMode (.courseUp) is preserved!
    #expect(chartVM.goToWaypointVisualState?.id == target.id)
    #expect(chartVM.trackingMode == .courseUp)

    // 2. Explicit user GoTo activation at runtime: switches trackingMode to .free and emits camera move event
    final class EventBox {
      var events: [CameraMoveEvent] = []
    }
    let box = EventBox()
    let cameraStream = chartVM.cameraMoveStream
    let collector = Task { @MainActor in
      for await event in cameraStream {
        box.events.append(event)
      }
    }
    defer { collector.cancel() }

    try await activeNavigationService.setDestination(waypointID: target.id)
    try await waitUntil { !box.events.isEmpty }

    #expect(chartVM.trackingMode == .free)
    #expect(preferencesService.lastMapTrackingMode == .free)
  }

  @Test("ChartViewModel ignores cached coordinate when GPS is .lost during GoTo activation and hides bearing line")
  @MainActor
  func testChartViewModelIgnoresDeadGPSCoordinateOnActivationAndBearingLine() async throws {
    let db = try DatabaseManager.inMemory()
    let waypointService = WaypointService(databaseManager: db)
    let target = Self.makeWaypoint(
      id: "wpt-dead-gps",
      coordinate: CLLocationCoordinate2D(latitude: 46.15, longitude: -1.16)
    )
    try await waypointService.saveWaypoint(target)

    let positioningService = MockPositioningService()
    let instrumentDampingService = InstrumentDampingService(positioningService: positioningService)
    instrumentDampingService.start()
    defer { instrumentDampingService.stop() }

    // 1. Emit an active fix in Paris, then immediately transition to .lost so damping retains a dead cached coordinate
    let staleParisFix = NavigationFix(
      coordinate: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522),
      horizontalAccuracy: Measurement(value: 10.0, unit: .meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: nil,
      speedOverGroundAccuracy: nil,
      timestamp: Date(timeIntervalSince1970: 1_700_000_000)
    )
    positioningService.yieldLocation(.active(staleParisFix))
    try await waitUntil { instrumentDampingService.state?.gpsState == .active }

    enum SimulatedGPSError: Error { case signalLost }
    positioningService.yieldLocation(.lost(SimulatedGPSError.signalLost))
    try await waitUntil { instrumentDampingService.state?.gpsState == .lost }
    // Precondition: InstrumentDampingService still holds the cached Paris coordinate while gpsState == .lost
    #expect(instrumentDampingService.state?.coordinate != nil)

    let activeNavigationService = ActiveNavigationService(
      databaseManager: db,
      instrumentDampingService: instrumentDampingService
    )
    await activeNavigationService.start()
    defer { activeNavigationService.stop() }

    let preferencesService = MockPreferencesService()
    let permissionService = PermissionService(positioningService: positioningService, notificationService: LocalNotificationService())
    let anchorService = AnchorService(
      positioningService: positioningService,
      preferencesService: preferencesService,
      notificationService: LocalNotificationService(),
      permissionService: permissionService,
      backgroundMonitoringService: DefaultBackgroundMonitoringService(positioningService: positioningService),
      stateStore: MockAnchorStateStore()
    )

    let chartVM = ChartViewModel(
      positioningService: positioningService,
      instrumentDampingService: instrumentDampingService,
      preferencesService: preferencesService,
      authService: MockGeoGarageAuthService(),
      anchorService: anchorService,
      anchorViewModel: AnchorViewModel(anchorService: anchorService),
      databaseManager: db,
      waypointService: waypointService,
      activeNavigationService: activeNavigationService
    )

    final class EventBox {
      var lastEvent: CameraMoveEvent?
    }
    let box = EventBox()
    let cameraStream = chartVM.cameraMoveStream
    let collector = Task { @MainActor in
      for await event in cameraStream {
        box.lastEvent = event
      }
    }
    defer { collector.cancel() }

    // 2. Activate GoTo while GPS is .lost: must emit `.center` on waypoint (NOT `.fitBounds` to dead Paris coord)
    //    and bearingLineVisualState must stay nil!
    try await activeNavigationService.setDestination(waypointID: target.id)
    try await waitUntil { box.lastEvent != nil }

    if case .center(let centeredCoord, let zoom, let heading) = box.lastEvent {
      #expect(centeredCoord == target.coordinate)
      #expect(zoom == nil)
      #expect(heading == nil)
    } else {
      Issue.record("Expected CameraMoveEvent.center on target waypoint when GPS is .lost, got fitBounds/other")
    }
    #expect(chartVM.bearingLineVisualState == nil)
  }
}

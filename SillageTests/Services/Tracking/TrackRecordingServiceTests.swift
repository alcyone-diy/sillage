//
//  TrackRecordingServiceTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-24.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Testing
import CoreLocation
import Foundation
@testable import Sillage

@MainActor
@Suite("Track Recording Service Tests")
struct TrackRecordingServiceTests {
  
  // MARK: - Mocks
  
  class MockBackgroundLocationToken: BackgroundLocationToken {
    let onInvalidate: (() -> Void)?
    init(onInvalidate: (() -> Void)? = nil) {
      self.onInvalidate = onInvalidate
    }
    func invalidate() {
      onInvalidate?()
    }
  }

  @MainActor
  class MockPositioningService: PositioningService, Sendable {
    let (locationUpdates, locationContinuation) = AsyncStream.makeStream(of: PositioningState.self)
    var currentDistanceFilter: Measurement<UnitLength> = Measurement(value: 5, unit: .meters)
    let (authorizationStatusStream, authContinuation) = AsyncStream.makeStream(of: CLAuthorizationStatus.self)
    
    var currentAuthorizationStatus: CLAuthorizationStatus = .notDetermined
    
    var lastKnownLocation: NavigationFix?

    var requestAuthorizationCallCount = 0
    func requestAuthorization() {
      requestAuthorizationCallCount += 1
    }

    private final class MockLocationUpdateToken: LocationUpdateToken {
      let onInvalidate: () -> Void
      init(onInvalidate: @escaping () -> Void) {
        self.onInvalidate = onInvalidate
      }
      func invalidate() {
        onInvalidate()
      }
    }
    
    var requestLocationUpdatesCallCount = 0
    var locationUpdateTokenInvalidatedCount = 0
    func requestLocationUpdates() -> any LocationUpdateToken {
      requestLocationUpdatesCallCount += 1
      return MockLocationUpdateToken { [weak self] in
        self?.locationUpdateTokenInvalidatedCount += 1
      }
    }
    
    var requestedDistanceFilters: [String: Double] = [:]
    func requestDistanceFilter(_ distance: Measurement<UnitLength>, for identifier: String) {
      requestedDistanceFilters[identifier] = distance.converted(to: .meters).value
    }
    func removeDistanceFilter(for identifier: String) {
      requestedDistanceFilters.removeValue(forKey: identifier)
    }
    
    var requestBackgroundLocationCallCount = 0
    var backgroundLocationTokenInvalidatedCount = 0
    var lastToken: MockBackgroundLocationToken?
    func requestBackgroundLocation() -> any BackgroundLocationToken {
      requestBackgroundLocationCallCount += 1
      let token = MockBackgroundLocationToken { [weak self] in
        self?.backgroundLocationTokenInvalidatedCount += 1
      }
      lastToken = token
      return token
    }
    
    func emit(fix: NavigationFix) {
      locationContinuation.yield(.active(fix))
    }
    
    func emitDegraded(fix: NavigationFix) {
      locationContinuation.yield(.degraded(fix))
    }
    
    func emitLost(error: Error) {
      locationContinuation.yield(.lost(error))
    }
  }

  @Observable
  class MockPreferencesService: PreferencesServiceProtocol {
    var savedChartSource: String?
    var savedGeoGarageLayerID: String?
    var geoGarageUsername: String?
    var savedLatitude: Double?
    var savedLongitude: Double?
    var savedZoom: Double?
    var savedDirection: Double?
    var savedTrackingMode: ChartTrackingMode = .northUp
    var gloveModeEnabled: Bool = false
    var hasAcceptedDisclaimer: Bool = false
    var isOpenSeaMapOverlayEnabled: Bool = false
    var isCOGVectorEnabled: Bool = false
    var cogVectorTimeHorizon: Measurement<UnitDuration> = Measurement(value: 3600, unit: .seconds)
    var isCOGVectorTicksEnabled: Bool = false
    
    func saveCameraState(coordinate: CLLocationCoordinate2D, zoom: Double, direction: Double) {}
    func loadCameraState() -> (coordinate: CLLocationCoordinate2D, zoom: Double, direction: Double)? { return nil }
    
    var activeTrackSessionID: String?
    func saveActiveTrackSessionID(_ id: String) {
      activeTrackSessionID = id
    }
    func clearActiveTrackSessionID() {
      activeTrackSessionID = nil
    }
    
    var goToWaypointID: String?
    var displayedTrackSessionID: String?
    
    var isBaroAlarmEnabled: Bool = false
    var baroAlarmSensitivity: BaroAlarmSensitivity = .medium
    var barometerOffset: Measurement<UnitPressure> = Measurement(value: 0, unit: .hectopascals)
    
    var savedAnchorRadius: Measurement<UnitLength> = Measurement(value: 25.0, unit: .meters)
  }

  // MARK: - Helpers
  
  func makeDatabaseManager() throws -> DatabaseManager {
    return try DatabaseManager.inMemory()
  }
  
  func createNavigationFix(
    latitude: CLLocationDegrees,
    longitude: CLLocationDegrees,
    speed: Double = 5,
    accuracy: Double = 5,
    timestamp: Date = Date()
  ) -> NavigationFix {
    return NavigationFix(
      coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
      horizontalAccuracy: Measurement(value: accuracy, unit: .meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: Measurement(value: speed, unit: .metersPerSecond),
      speedOverGroundAccuracy: nil,
      timestamp: timestamp
    )
  }

  func waitUntil(
    _ condition: @escaping @MainActor () -> Bool,
    timeout: Duration = .seconds(2)
  ) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await Task.sleep(for: timeout)
        throw CancellationError()
      }
      group.addTask { @MainActor in
        while !condition() {
          await withCheckedContinuation { continuation in
            withObservationTracking {
              _ = condition()
            } onChange: {
              Task { @MainActor in
                continuation.resume()
              }
            }
          }
        }
      }
      try await group.next()
      group.cancelAll()
    }
  }

  // MARK: - Tests


  @Test("Initial state is idle")
  @MainActor
  func testInitialState() async throws {
    let dbManager = try makeDatabaseManager()
    let mockPositioning = MockPositioningService()
    let mockPreferences = MockPreferencesService()
    
    let service = TrackRecordingService(
      positioningService: mockPositioning,
      databaseManager: dbManager,
      preferencesService: mockPreferences,
      messageService: MessageService()
    )
    
    #expect(service.state == .idle)
    #expect(service.trackPoints.isEmpty)
    #expect(service.telemetry.startTime == nil)
  }
  
  @Test("Start recording changes state to waitingForFix and requests background token")
  @MainActor
  func testStartRecording() async throws {
    let dbManager = try makeDatabaseManager()
    let mockPositioning = MockPositioningService()
    let mockPreferences = MockPreferencesService()
    
    let service = TrackRecordingService(
      positioningService: mockPositioning,
      databaseManager: dbManager,
      preferencesService: mockPreferences,
      messageService: MessageService()
    )
    
    service.startRecording()
    
    #expect(service.state == .waitingForFix)
    #expect(mockPositioning.requestBackgroundLocationCallCount == 1)
    #expect(mockPreferences.activeTrackSessionID == nil) // No fix yet, so no ID saved
  }
  
  @Test("Receiving good fix transitions to recording state")
  @MainActor
  func testTransitionToRecordingOnFix() async throws {
    let dbManager = try makeDatabaseManager()
    let mockPositioning = MockPositioningService()
    let mockPreferences = MockPreferencesService()
    
    let service = TrackRecordingService(
      positioningService: mockPositioning,
      databaseManager: dbManager,
      preferencesService: mockPreferences,
      messageService: MessageService()
    )
    
    service.startRecording()
    #expect(service.state == .waitingForFix)
    
    // Emit an active fix
    let activeFix = createNavigationFix(latitude: 45.0, longitude: -1.0)
    mockPositioning.emit(fix: activeFix)
    
    try await waitUntil { service.state == .recording && service.trackPoints.count == 1 }
    
    #expect(service.state == .recording)
    #expect(service.trackPoints.count == 1)
    #expect(mockPreferences.activeTrackSessionID != nil)
    #expect(service.telemetry.startTime == activeFix.timestamp)
    
    // Emit a degraded fix
    let degradedFix = createNavigationFix(latitude: 45.1, longitude: -1.1, accuracy: 50)
    mockPositioning.emitDegraded(fix: degradedFix)
    
    try await waitUntil { service.trackPoints.count == 2 }
    
    #expect(service.trackPoints.count == 2)
    let lastPoint = try #require(service.trackPoints.last)
    #expect(lastPoint.coordinate.latitude == 45.1)
    #expect(lastPoint.horizontalAccuracy.value == 50)
  }
  
  @Test("Poor accuracy fix is ignored")
  @MainActor
  func testPoorAccuracyFixIgnored() async throws {
    let dbManager = try makeDatabaseManager()
    let mockPositioning = MockPositioningService()
    let mockPreferences = MockPreferencesService()
    
    let service = TrackRecordingService(
      positioningService: mockPositioning,
      databaseManager: dbManager,
      preferencesService: mockPreferences,
      messageService: MessageService()
    )
    
    service.startRecording()
    
    // Emit a poor fix
    let poorFix = createNavigationFix(latitude: 45.0, longitude: -1.0, accuracy: 100) // Assuming max horizontal accuracy < 100
    mockPositioning.emit(fix: poorFix)
    
    try await Task.sleep(for: .milliseconds(200))
    
    #expect(service.state == .waitingForFix)
    #expect(service.trackPoints.isEmpty)
  }
  
  @Test("Pause recording")
  @MainActor
  func testPauseRecording() async throws {
    let dbManager = try makeDatabaseManager()
    let mockPositioning = MockPositioningService()
    let mockPreferences = MockPreferencesService()
    
    let service = TrackRecordingService(
      positioningService: mockPositioning,
      databaseManager: dbManager,
      preferencesService: mockPreferences,
      messageService: MessageService()
    )
    
    service.startRecording()
    mockPositioning.emit(fix: createNavigationFix(latitude: 45.0, longitude: -1.0))
    try await waitUntil { service.state == .recording }
    
    #expect(service.state == .recording)
    
    service.pauseRecording()
    #expect(service.state == .paused)
  }
  
  @Test("Resume recording")
  @MainActor
  func testResumeRecording() async throws {
    let dbManager = try makeDatabaseManager()
    let mockPositioning = MockPositioningService()
    let mockPreferences = MockPreferencesService()
    
    let service = TrackRecordingService(
      positioningService: mockPositioning,
      databaseManager: dbManager,
      preferencesService: mockPreferences,
      messageService: MessageService()
    )
    
    service.startRecording()
    mockPositioning.emit(fix: createNavigationFix(latitude: 45.0, longitude: -1.0))
    try await waitUntil { service.state == .recording }
    
    service.pauseRecording()
    #expect(service.state == .paused)
    
    let initialTokenCount = mockPositioning.requestBackgroundLocationCallCount
    
    service.resumeRecording()
    #expect(service.state == .waitingForFix)
    #expect(mockPositioning.requestBackgroundLocationCallCount == initialTokenCount + 1)
  }
  
  @Test("Stop recording without fix")
  @MainActor
  func testStopRecordingWithoutFix() async throws {
    let dbManager = try makeDatabaseManager()
    let mockPositioning = MockPositioningService()
    let mockPreferences = MockPreferencesService()
    
    let service = TrackRecordingService(
      positioningService: mockPositioning,
      databaseManager: dbManager,
      preferencesService: mockPreferences,
      messageService: MessageService()
    )
    
    service.startRecording()
    #expect(service.state == .waitingForFix)
    
    do {
      _ = try await service.stopRecording()
      Issue.record("Expected abortedNoFix error to be thrown")
    } catch TrackRecordingService.TrackRecordingError.abortedNoFix {
      // Expected behavior
    } catch {
      Issue.record("Unexpected error thrown: \(error)")
    }
    #expect(service.state == .idle)
  }
  
  @Test("Stop recording with fix")
  @MainActor
  func testStopRecordingWithFix() async throws {
    let dbManager = try makeDatabaseManager()
    let mockPositioning = MockPositioningService()
    let mockPreferences = MockPreferencesService()
    
    let service = TrackRecordingService(
      positioningService: mockPositioning,
      databaseManager: dbManager,
      preferencesService: mockPreferences,
      messageService: MessageService()
    )
    
    service.startRecording()
    mockPositioning.emit(fix: createNavigationFix(latitude: 45.0, longitude: -1.0))
    try await waitUntil { service.state == .recording }
    
    #expect(service.state == .recording)
    
    do {
      let sessionID = try await service.stopRecording()
      #expect(!sessionID.isEmpty)
    } catch {
      Issue.record("Expected successful stop but got error: \(error)")
    }
    
    #expect(service.state == .idle)
    #expect(mockPreferences.activeTrackSessionID == nil)
  }
  @Test("Coordinate precision is maintained as Double")
  @MainActor
  func testCoordinatePrecision() async throws {
    let dbManager = try makeDatabaseManager()
    let mockPositioning = MockPositioningService()
    let mockPreferences = MockPreferencesService()
    
    let service = TrackRecordingService(
      positioningService: mockPositioning,
      databaseManager: dbManager,
      preferencesService: mockPreferences,
      messageService: MessageService()
    )
    
    service.startRecording()
    
    // A coordinate that would lose precision if cast to Float
    let highPrecisionLat: CLLocationDegrees = 45.12345678912345
    let highPrecisionLon: CLLocationDegrees = -1.98765432198765
    
    let fix = createNavigationFix(latitude: highPrecisionLat, longitude: highPrecisionLon)
    mockPositioning.emit(fix: fix)
    
    try await waitUntil { service.state == .recording && !service.trackPoints.isEmpty }
    
    let trackPoint = try #require(service.trackPoints.first)
    
    // Validate that the underlying Measurement value matches exactly the Double precision
    #expect(trackPoint.coordinate.latitude == highPrecisionLat)
    #expect(trackPoint.coordinate.longitude == highPrecisionLon)
  }
  
  @Test("Signal lost creates a new segment")
  @MainActor
  func testSignalLostCreatesNewSegment() async throws {
    let dbManager = try makeDatabaseManager()
    let mockPositioning = MockPositioningService()
    let mockPreferences = MockPreferencesService()
    
    let service = TrackRecordingService(
      positioningService: mockPositioning,
      databaseManager: dbManager,
      preferencesService: mockPreferences,
      messageService: MessageService()
    )
    
    service.startRecording()
    
    // Emit an active fix (segment 0)
    let fix1 = createNavigationFix(latitude: 45.0, longitude: -1.0)
    mockPositioning.emit(fix: fix1)
    
    try await waitUntil { service.state == .recording && service.trackPoints.count == 1 }
    
    // Verify first segment is 0
    #expect(service.trackPoints.last?.segmentIndex == 0)
    
    // Emit lost state
    struct DummyError: Error {}
    mockPositioning.emitLost(error: DummyError())
    
    try await waitUntil { service.state == .waitingForFix }
    
    // Emit another active fix
    let fix2 = createNavigationFix(latitude: 45.1, longitude: -1.1)
    mockPositioning.emit(fix: fix2)
    
    try await waitUntil { service.state == .recording && service.trackPoints.count == 2 }
    
    // Verify second segment is 1 (incremented)
    let lastPoint2 = try #require(service.trackPoints.last)
    #expect(lastPoint2.segmentIndex == 1)
    
    // The total distance should NOT include the artificial straight line between fix1 and fix2.
    // Because the segment was broken, distance should be 0.
    #expect(service.telemetry.totalDistanceOverGround?.value == 0)
  }

  // MARK: - Token and Filter Tests
  
  @Test("TrackRecording acquires UpdateToken and forces 0m distance filter")
  func testTrackRecording_AcquiresUpdateToken_And_ForcesZeroFilter() async throws {
    let mockPositioning = MockPositioningService()
    let databaseManager = try makeDatabaseManager()
    let mockPreferences = MockPreferencesService()
    let mockMessages = MessageService()
    
    let service = TrackRecordingService(
      positioningService: mockPositioning,
      databaseManager: databaseManager,
      preferencesService: mockPreferences,
      messageService: mockMessages
    )
    
    // Action
    service.startRecording()
    
    // Assertions
    #expect(mockPositioning.requestLocationUpdatesCallCount == 1)
    #expect(mockPositioning.requestedDistanceFilters["TrackRecording"] == 0.0)
  }
  
  @Test("TrackRecording restores distance filter to 5m on first valid fix")
  func testTrackRecording_RestoresDistanceFilter_OnFirstFix() async throws {
    let mockPositioning = MockPositioningService()
    let databaseManager = try makeDatabaseManager()
    let mockPreferences = MockPreferencesService()
    let mockMessages = MessageService()
    
    let service = TrackRecordingService(
      positioningService: mockPositioning,
      databaseManager: databaseManager,
      preferencesService: mockPreferences,
      messageService: mockMessages
    )
    
    service.startRecording()
    #expect(service.state == .waitingForFix)
    #expect(mockPositioning.requestedDistanceFilters["TrackRecording"] == 0.0)
    
    // Action: Inject a valid fix
    let validFix = createNavigationFix(latitude: 45.0, longitude: -1.0)
    mockPositioning.emit(fix: validFix)
    
    // Wait for the async task to process the fix
    try await waitUntil { service.state == .recording }
    
    // Assertions
    #expect(service.state == .recording)
    #expect(mockPositioning.requestedDistanceFilters["TrackRecording"] == 5.0)
  }
  
  @Test("TrackRecording releases tokens on stop")
  func testTrackRecording_ReleasesTokens_OnStop() async throws {
    let mockPositioning = MockPositioningService()
    let databaseManager = try makeDatabaseManager()
    let mockPreferences = MockPreferencesService()
    let mockMessages = MessageService()
    
    let service = TrackRecordingService(
      positioningService: mockPositioning,
      databaseManager: databaseManager,
      preferencesService: mockPreferences,
      messageService: mockMessages
    )
    
    service.startRecording()
    
    // Get into recording state
    let validFix = createNavigationFix(latitude: 45.0, longitude: -1.0)
    mockPositioning.emit(fix: validFix)
    try await waitUntil { service.state == .recording }
    
    // Action
    _ = try await service.stopRecording()
    
    // Assertions
    #expect(mockPositioning.locationUpdateTokenInvalidatedCount == 1)
    #expect(mockPositioning.backgroundLocationTokenInvalidatedCount == 1)
    #expect(mockPositioning.requestedDistanceFilters["TrackRecording"] == nil)
  }
}

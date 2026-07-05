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
    var invalidateCallCount = 0
    func invalidate() {
      invalidateCallCount += 1
    }
  }

  @MainActor
  class MockPositioningService: PositioningService, Sendable {
    let (locationUpdates, locationContinuation) = AsyncStream.makeStream(of: NavigationFix.self)
    let (authorizationStatusStream, authContinuation) = AsyncStream.makeStream(of: CLAuthorizationStatus.self)

    var requestAuthorizationCallCount = 0
    func requestAuthorization() {
      requestAuthorizationCallCount += 1
    }

    var startUpdatingLocationCallCount = 0
    func startUpdatingLocation() {
      startUpdatingLocationCallCount += 1
    }

    var stopUpdatingLocationCallCount = 0
    func stopUpdatingLocation() {
      stopUpdatingLocationCallCount += 1
    }
    
    var requestBackgroundLocationCallCount = 0
    var lastToken: MockBackgroundLocationToken?
    func requestBackgroundLocation() -> any BackgroundLocationToken {
      requestBackgroundLocationCallCount += 1
      let token = MockBackgroundLocationToken()
      lastToken = token
      return token
    }
    
    func emit(fix: NavigationFix) {
      locationContinuation.yield(fix)
    }
  }

  @Observable
  class MockPreferencesService: PreferencesServiceProtocol {
    var savedChartSource: String?
    var savedGeoGarageLayerID: String?
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
    
    var savedAnchorWatch: AnchorWatch?
    var savedAnchorStatus: AnchorStatus = .inactive
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
      courseState: .invalid,
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
  func testInitialState() async throws {
    let dbManager = try makeDatabaseManager()
    let mockPositioning = MockPositioningService()
    let mockPreferences = MockPreferencesService()
    
    let service = TrackRecordingService(
      positioningService: mockPositioning,
      databaseManager: dbManager,
      preferencesService: mockPreferences
    )
    
    #expect(service.state == .idle)
    #expect(service.trackPoints.isEmpty)
    #expect(service.telemetry.startTime == nil)
  }
  
  @Test("Start recording changes state to waitingForFix and requests background token")
  func testStartRecording() async throws {
    let dbManager = try makeDatabaseManager()
    let mockPositioning = MockPositioningService()
    let mockPreferences = MockPreferencesService()
    
    let service = TrackRecordingService(
      positioningService: mockPositioning,
      databaseManager: dbManager,
      preferencesService: mockPreferences
    )
    
    service.startRecording()
    
    #expect(service.state == .waitingForFix)
    #expect(mockPositioning.requestBackgroundLocationCallCount == 1)
    #expect(mockPreferences.activeTrackSessionID == nil) // No fix yet, so no ID saved
  }
  
  @Test("Receiving good fix transitions to recording state")
  func testTransitionToRecordingOnFix() async throws {
    let dbManager = try makeDatabaseManager()
    let mockPositioning = MockPositioningService()
    let mockPreferences = MockPreferencesService()
    
    let service = TrackRecordingService(
      positioningService: mockPositioning,
      databaseManager: dbManager,
      preferencesService: mockPreferences
    )
    
    service.startRecording()
    #expect(service.state == .waitingForFix)
    
    // Emit a fix
    let fix = createNavigationFix(latitude: 45.0, longitude: -1.0)
    mockPositioning.emit(fix: fix)
    
    try await waitUntil { service.state == .recording }
    
    #expect(service.state == .recording)
    #expect(service.trackPoints.count == 1)
    #expect(mockPreferences.activeTrackSessionID != nil)
    #expect(service.telemetry.startTime == fix.timestamp)
  }
  
  @Test("Poor accuracy fix is ignored")
  func testPoorAccuracyFixIgnored() async throws {
    let dbManager = try makeDatabaseManager()
    let mockPositioning = MockPositioningService()
    let mockPreferences = MockPreferencesService()
    
    let service = TrackRecordingService(
      positioningService: mockPositioning,
      databaseManager: dbManager,
      preferencesService: mockPreferences
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
  func testPauseRecording() async throws {
    let dbManager = try makeDatabaseManager()
    let mockPositioning = MockPositioningService()
    let mockPreferences = MockPreferencesService()
    
    let service = TrackRecordingService(
      positioningService: mockPositioning,
      databaseManager: dbManager,
      preferencesService: mockPreferences
    )
    
    service.startRecording()
    mockPositioning.emit(fix: createNavigationFix(latitude: 45.0, longitude: -1.0))
    try await waitUntil { service.state == .recording }
    
    #expect(service.state == .recording)
    
    service.pauseRecording()
    #expect(service.state == .paused)
  }
  
  @Test("Resume recording")
  func testResumeRecording() async throws {
    let dbManager = try makeDatabaseManager()
    let mockPositioning = MockPositioningService()
    let mockPreferences = MockPreferencesService()
    
    let service = TrackRecordingService(
      positioningService: mockPositioning,
      databaseManager: dbManager,
      preferencesService: mockPreferences
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
  func testStopRecordingWithoutFix() async throws {
    let dbManager = try makeDatabaseManager()
    let mockPositioning = MockPositioningService()
    let mockPreferences = MockPreferencesService()
    
    let service = TrackRecordingService(
      positioningService: mockPositioning,
      databaseManager: dbManager,
      preferencesService: mockPreferences
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
  func testStopRecordingWithFix() async throws {
    let dbManager = try makeDatabaseManager()
    let mockPositioning = MockPositioningService()
    let mockPreferences = MockPreferencesService()
    
    let service = TrackRecordingService(
      positioningService: mockPositioning,
      databaseManager: dbManager,
      preferencesService: mockPreferences
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
  func testCoordinatePrecision() async throws {
    let dbManager = try makeDatabaseManager()
    let mockPositioning = MockPositioningService()
    let mockPreferences = MockPreferencesService()
    
    let service = TrackRecordingService(
      positioningService: mockPositioning,
      databaseManager: dbManager,
      preferencesService: mockPreferences
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
}

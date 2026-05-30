//
//  TrackServiceTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-26.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Testing
import CoreLocation
import Foundation
import GRDB
@testable import Sillage

@MainActor
@Suite("Track Service and ViewModel Deletion Tests")
struct TrackServiceTests {
  
  // MARK: - Mocks
  
  class MockBackgroundLocationToken: BackgroundLocationToken {
    func invalidate() {}
  }
  
  @MainActor
  class MockPositioningService: PositioningService, Sendable {
    let (locationUpdates, locationContinuation) = AsyncStream.makeStream(of: NavigationFix.self)
    let (authorizationStatusStream, authContinuation) = AsyncStream.makeStream(of: CLAuthorizationStatus.self)
    
    func requestAuthorization() {}
    func startUpdatingLocation() {}
    func stopUpdatingLocation() {}
    func requestBackgroundLocation() -> any BackgroundLocationToken {
      return MockBackgroundLocationToken()
    }
    
    func emit(fix: NavigationFix) {
      locationContinuation.yield(fix)
    }
  }
  
  @Observable
  class MockPreferencesService: PreferencesServiceProtocol {
    var savedMapSource: String?
    var savedGeoGarageLayerID: String?
    var savedLatitude: Double?
    var savedLongitude: Double?
    var savedZoom: Double?
    var savedDirection: Double?
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
  }
  
  // MARK: - Helpers
  
  func makeDatabaseManager() throws -> DatabaseManager {
    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    let uniqueDBURL = tempDir.appendingPathComponent("test_db_\(UUID().uuidString).sqlite")
    return try DatabaseManager(url: uniqueDBURL)
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
  
  @Test("Delete session deletes session and cascadingly deletes its points")
  func testDeleteSessionCascades() async throws {
    let dbManager = try makeDatabaseManager()
    let trackService = TrackService(databaseManager: dbManager)
    
    let sessionId = "session-to-delete"
    let session = TrackSessionRecord(id: sessionId, startTime: Date())
    
    let point = TrackPointRecord(
      id: nil,
      sessionId: sessionId,
      timestamp: Date(),
      segmentIndex: 0,
      latitude: Measurement(value: 45.0, unit: .degrees),
      longitude: Measurement(value: -1.0, unit: .degrees),
      horizontalAccuracy: Measurement(value: 5.0, unit: .meters)
    )
    
    try await dbManager.write { db in
      try session.insert(db)
      try point.insert(db)
    }
    
    // Verify they exist
    let sessionExistsBefore = try await dbManager.reader.read { db in
      try TrackSessionRecord.exists(db, key: sessionId)
    }
    let pointsCountBefore = try await dbManager.reader.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM track_point WHERE sessionId = ?", arguments: [sessionId]) ?? 0
    }
    #expect(sessionExistsBefore)
    #expect(pointsCountBefore == 1)
    
    // Perform deletion
    try await trackService.deleteSession(id: sessionId)
    
    // Verify they are deleted
    let sessionExistsAfter = try await dbManager.reader.read { db in
      try TrackSessionRecord.exists(db, key: sessionId)
    }
    let pointsCountAfter = try await dbManager.reader.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM track_point WHERE sessionId = ?", arguments: [sessionId]) ?? 0
    }
    #expect(!sessionExistsAfter)
    #expect(pointsCountAfter == 0)
  }
  
  @Test("Delete non-existent session does not throw")
  func testDeleteNonExistentSession() async throws {
    let dbManager = try makeDatabaseManager()
    let trackService = TrackService(databaseManager: dbManager)
    
    // Should not throw
    try await trackService.deleteSession(id: "non-existent-id")
  }
  
  @Test("ViewModel delete session succeeds when session is not active")
  func testViewModelDeleteSessionSucceeds() async throws {
    let dbManager = try makeDatabaseManager()
    let trackService = TrackService(databaseManager: dbManager)
    let mockPositioning = MockPositioningService()
    let mockPreferences = MockPreferencesService()
    let recordingService = TrackRecordingService(
      positioningService: mockPositioning,
      databaseManager: dbManager,
      preferencesService: mockPreferences
    )
    
    let sessionId = "session-to-delete-vm"
    let session = TrackSessionRecord(id: sessionId, startTime: Date())
    try await dbManager.write { db in
      try session.insert(db)
    }
    
    let viewModel = TrackDetailViewModel(
      sessionId: sessionId,
      trackService: trackService,
      trackRecordingService: recordingService
    )
    
    // Deletion should succeed because recordingService is idle (no active recording)
    do {
      try await viewModel.deleteSession()
    } catch {
      Issue.record("Expected deleteSession to succeed, but threw error: \(error)")
    }
    
    // Verify it is gone
    let sessionExists = try await dbManager.reader.read { db in
      try TrackSessionRecord.exists(db, key: sessionId)
    }
    #expect(!sessionExists)
  }
  
  @Test("ViewModel delete session throws error when session is active")
  func testViewModelDeleteSessionFailsForActive() async throws {
    let dbManager = try makeDatabaseManager()
    let trackService = TrackService(databaseManager: dbManager)
    let mockPositioning = MockPositioningService()
    let mockPreferences = MockPreferencesService()
    let recordingService = TrackRecordingService(
      positioningService: mockPositioning,
      databaseManager: dbManager,
      preferencesService: mockPreferences
    )
    
    // Start recording so we have an active session
    recordingService.startRecording()
    // Emit a fix to transition state to .recording and generate sessionId
    let fix = NavigationFix(
      coordinate: CLLocationCoordinate2D(latitude: 45.0, longitude: -1.0),
      horizontalAccuracy: Measurement(value: 5.0, unit: .meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: Measurement(value: 5.0, unit: .metersPerSecond),
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )
    mockPositioning.emit(fix: fix)
    
    // Wait for the state to update to recording
    try await waitUntil { recordingService.state == .recording }
    
    #expect(recordingService.state == .recording)
    guard let activeSessionId = mockPreferences.activeTrackSessionID else {
      Issue.record("Active session ID was not generated")
      return
    }
    
    // Flush recording state to database so it exists before the VM deletes it
    await recordingService.emergencyFlushAsync()
    
    let viewModel = TrackDetailViewModel(
      sessionId: activeSessionId,
      trackService: trackService,
      trackRecordingService: recordingService
    )
    
    // Try to delete the active session
    do {
      try await viewModel.deleteSession()
      Issue.record("Expected deleteSession to throw an error for active session")
    } catch let error as TrackDeletionError {
      #expect(error == .activeSession)
    } catch {
      Issue.record("Expected TrackDeletionError.activeSession, but got \(error)")
    }
    
    // Verify it is NOT deleted from DB (should still exist)
    let sessionExists = try await dbManager.reader.read { db in
      try TrackSessionRecord.exists(db, key: activeSessionId)
    }
    #expect(sessionExists)
  }
  
  @Test("updateSession modifies metadata without overwriting background telemetry updates (Partial Update)")
  func testUpdateSessionPreventsLostUpdate() async throws {
    let dbManager = try makeDatabaseManager()
    let trackService = TrackService(databaseManager: dbManager)
    
    let sessionId = "session-lost-update-test"
    
    // 1. Initial session creation (e.g., at the start of the track)
    let session = TrackSessionRecord(
      id: sessionId,
      startTime: Date()
    )
    
    try await dbManager.write { db in
      try session.insert(db)
      // Simulating a starting value for distance (e.g., 10 nautical miles)
      // Using a raw query to simulate the initial state on the SQLite side.
      try db.execute(sql: "UPDATE track_session SET totalDistance_m = 18520 WHERE id = ?", arguments: [sessionId])
    }
    
    // 2. BACKGROUND GPS SIMULATION:
    // TrackRecordingService updates the distance in the database (e.g., changes to 15 nautical miles)
    try await dbManager.write { db in
      try db.execute(sql: "UPDATE track_session SET totalDistance_m = 27780 WHERE id = ?", arguments: [sessionId])
    }
    
    // 3. UI ACTION:
    // The user renames the track while the boat is sailing.
    try await trackService.updateSession(id: sessionId, name: "Crossing to Re", description: "Good weather")
    
    // 4. VERIFICATION: The source of truth audit
    let updatedSession = try await dbManager.reader.read { db in
      try TrackSessionRecord.fetchOne(db, key: sessionId)
    }
    
    // Ensure metadata has been successfully updated
    #expect(updatedSession?.name == "Crossing to Re")
    #expect(updatedSession?.description == "Good weather")
    
    // CRITICAL: Ensure the GPS telemetry from step 2 was NOT overwritten
    // by the UI action in step 3. The distance must be 27780, not 18520.
    // (Adjust the distance verification according to your TrackSessionRecord implementation)
    let currentDistance = try #require(updatedSession).totalDistance_m // Example property name
    #expect(currentDistance == 27780.0)
  }
}

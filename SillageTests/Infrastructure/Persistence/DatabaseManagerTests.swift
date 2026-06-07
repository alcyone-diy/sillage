//
//  DatabaseManagerTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-26.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Testing
import Foundation
import GRDB
import CoreLocation
@testable import Sillage

@Suite("Database Manager Tests")
final class DatabaseManagerTests {
  let dbManager: DatabaseManager
  
  init() throws {
    dbManager = try DatabaseManager.inMemory()
  }
  
  // MARK: - Tests
  
  @Test("sanitizeUnfinishedSessions updates end time and deletes empty sessions")
  func testSanitizeUnfinishedSessions() async throws {
    let now = Date(timeIntervalSince1970: 0)
    
    // 1. Session with points but no endTimestamp (should be updated)
    let session1Id = "session-1"
    let session1 = TrackSessionRecord(id: session1Id, startTime: now.addingTimeInterval(-1000))
    let point1 = makeTrackPoint(
      sessionID: session1Id,
      timestamp: now.addingTimeInterval(-500)
    )
    
    // 2. Session without points (should be deleted)
    let session2Id = "session-2"
    let session2 = TrackSessionRecord(id: session2Id, startTime: now.addingTimeInterval(-2000))
    
    // 3. Active session without points (should NOT be deleted because it is excluded)
    let session3Id = "session-3-active"
    let session3 = TrackSessionRecord(id: session3Id, startTime: now.addingTimeInterval(-3000))
    
    try await dbManager.write { db in
      try session1.insert(db)
      try point1.insert(db)
      try session2.insert(db)
      try session3.insert(db)
    }
    
    // Perform sanitization, excluding session3
    try await dbManager.sanitizeUnfinishedSessions(excluding: session3Id)
    
    // Verify session1 has updated endTimestamp
    let updatedSession1 = try await dbManager.reader.read { db in
      try TrackSessionRecord.fetchOne(db, key: session1Id)
    }
    #expect(updatedSession1 != nil)
    #expect(updatedSession1?.endTimestamp_unix != nil)
    #expect(updatedSession1?.endTimestamp_unix == point1.timestamp_unix)
    
    // Verify session2 was deleted
    let session2Exists = try await dbManager.reader.read { db in
      try TrackSessionRecord.exists(db, key: session2Id)
    }
    #expect(!session2Exists)
    
    // Verify session3 was kept (excluded)
    let session3Exists = try await dbManager.reader.read { db in
      try TrackSessionRecord.exists(db, key: session3Id)
    }
    #expect(session3Exists)
  }
  
  @Test("fetchMaxSegmentIndex returns correct max index")
  func testFetchMaxSegmentIndex() async throws {
    let sessionID = "session-1"
    let session = TrackSessionRecord(id: sessionID, startTime: Date(timeIntervalSince1970: 0))
    
    try await dbManager.write { db in
      try session.insert(db)
    }
    
    // Empty session should return nil
    let emptyIndex = try await dbManager.fetchMaxSegmentIndex(for: sessionID)
    #expect(emptyIndex == nil)
    
    // Add points with different segment indices
    let point0 = makeTrackPoint(
      sessionID: sessionID,
      timestamp: Date(timeIntervalSince1970: 0),
      segmentIndex: 0
    )
    let point2 = makeTrackPoint(
      sessionID: sessionID,
      timestamp: Date(timeIntervalSince1970: 10),
      segmentIndex: 2
    )
    try await dbManager.write { db in
      try point0.insert(db)
      try point2.insert(db)
    }
    
    let maxIndex = try await dbManager.fetchMaxSegmentIndex(for: sessionID)
    #expect(maxIndex == 2)
  }
  
  @Test("fetchLastPointTime returns precise Date of the last point")
  func testFetchLastPointTime() async throws {
    let sessionID = "session-1"
    let session = TrackSessionRecord(id: sessionID, startTime: Date(timeIntervalSince1970: 0))
    
    try await dbManager.write { db in
      try session.insert(db)
    }
    
    // Empty session should return nil
    let emptyTime = try await dbManager.fetchLastPointTime(for: sessionID)
    #expect(emptyTime == nil)
    
    let time1 = Date(timeIntervalSince1970: 10)
    let time2 = Date(timeIntervalSince1970: 10.001)
    
    let point1 = makeTrackPoint(
      sessionID: sessionID,
      timestamp: time1
    )
    let point2 = makeTrackPoint(
      sessionID: sessionID,
      timestamp: time2
    )
    
    try await dbManager.write { db in
      try point1.insert(db)
      try point2.insert(db)
    }
    
    let lastTime = try await dbManager.fetchLastPointTime(for: sessionID)
    if let lastTime = lastTime {
      #expect(abs(lastTime.timeIntervalSince(time2)) < 0.0001)
    } else {
      Issue.record("lastTime should not be nil")
    }
  }
  
  @Test("fetchRecentPoints returns most recent points within limit")
  func testFetchRecentPoints() async throws {
    let sessionID = "session-1"
    let session = TrackSessionRecord(id: sessionID, startTime: Date(timeIntervalSince1970: 0))
    
    try await dbManager.write { db in
      try session.insert(db)
    }
    
    // Insert 5 points sequentially
    try await dbManager.write { db in
      for i in 0..<5 {
        let point = self.makeTrackPoint(
          sessionID: sessionID,
          timestamp: Date(timeIntervalSince1970: TimeInterval(1000 + i * 10))
        )
        try point.insert(db)
      }
    }
    
    // Fetch with limit 3
    let recentPoints = try await dbManager.fetchRecentPoints(for: sessionID, limit: 3)
    
    #expect(recentPoints.count == 3)
    // Should be oldest of the recent ones first (chronological order)
    let timestamp0 = await recentPoints[0].timestamp
    let timestamp1 = await recentPoints[1].timestamp
    let timestamp2 = await recentPoints[2].timestamp
    #expect(timestamp0.timeIntervalSince1970 == 1020)
    #expect(timestamp1.timeIntervalSince1970 == 1030)
    #expect(timestamp2.timeIntervalSince1970 == 1040)
  }
  
  @Test("Cascade deletion removes all associated points")
  func testCascadeDeletionRemovesAllAssociatedPoints() async throws {
    let sessionID = "session-cascade"
    let session = TrackSessionRecord(id: sessionID, startTime: Date(timeIntervalSince1970: 0))
    
    try await dbManager.write { db in
      try session.insert(db)
    }
    
    // Insert 5 points sequentially
    try await dbManager.write { db in
      for i in 0..<5 {
        let point = self.makeTrackPoint(
          sessionID: sessionID,
          timestamp: Date(timeIntervalSince1970: TimeInterval(1000 + i * 10))
        )
        try point.insert(db)
      }
    }
    
    // Verify 5 points exist
    let pointCountBefore = try await dbManager.reader.read { db in
      try TrackPointRecord.fetchCount(db)
    }
    #expect(pointCountBefore == 5)
    
    // Delete the session
    try await dbManager.write { db in
      _ = try session.delete(db)
    }
    
    // Check that the points table is empty
    let pointCountAfter = try await dbManager.reader.read { db in
      try TrackPointRecord.fetchCount(db)
    }
    #expect(pointCountAfter == 0)
  }
  
  @Test("Concurrent track point insertions")
  func testConcurrentTrackPointInsertions() async throws {
    let sessionID = "session-concurrent"
    let session = TrackSessionRecord(id: sessionID, startTime: Date(timeIntervalSince1970: 0))
    
    try await dbManager.write { db in
      try session.insert(db)
    }
    
    let manager = self.dbManager
    
    // Insert 100 points concurrently
    try await withThrowingTaskGroup(of: Void.self) { group in
      for i in 0..<100 {
        let point = self.makeTrackPoint(
          sessionID: sessionID,
          timestamp: Date(timeIntervalSince1970: TimeInterval(1000 + i))
        )
        
        group.addTask {
          try await manager.write { db in
            try point.insert(db)
          }
        }
      }
      
      // Wait for all tasks to finish to propagate any potential errors
      for try await _ in group {}
    }
    
    // Verify that totalPointCount is exactly 100 at the end
    let totalPointCount = try await manager.reader.read { db in
      try TrackPointRecord.fetchCount(db)
    }
    #expect(totalPointCount == 100)
  }
  
  @Test("Database constraints reject invalid coordinates")
  func testDatabaseConstraintsRejectInvalidCoordinates() async throws {
    let sessionID = "session-invalid-coord"
    let session = TrackSessionRecord(id: sessionID, startTime: Date(timeIntervalSince1970: 0))
    
    try await dbManager.write { db in
      try session.insert(db)
    }
    
    let invalidPoint = TrackPointRecord(
      id: nil,
      sessionID: sessionID,
      timestamp: Date(),
      segmentIndex: 0,
      coordinate: CLLocationCoordinate2D(latitude: 91.0, longitude: 0.0),
      horizontalAccuracy: Measurement(value: 5.0, unit: .meters)
    )
    
    await #expect(throws: GRDB.DatabaseError.self) {
      try await dbManager.write { db in
        try invalidPoint.insert(db)
      }
    }
  }
  
  // MARK: - Helpers
  
  private func makeTrackPoint(sessionID: String, timestamp: Date, segmentIndex: Int = 0) -> TrackPointRecord {
    return TrackPointRecord(
      id: nil,
      sessionID: sessionID,
      timestamp: timestamp,
      segmentIndex: segmentIndex,
      coordinate: CLLocationCoordinate2D(latitude: 45.0, longitude: -1.0),
      horizontalAccuracy: Measurement(value: 5.0, unit: .meters)
    )
  }
}

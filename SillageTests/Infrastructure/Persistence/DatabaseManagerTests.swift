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
      sessionId: session1Id,
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
    let sessionId = "session-1"
    let session = TrackSessionRecord(id: sessionId, startTime: Date(timeIntervalSince1970: 0))
    
    try await dbManager.write { db in
      try session.insert(db)
    }
    
    // Empty session should return nil
    let emptyIndex = try await dbManager.fetchMaxSegmentIndex(for: sessionId)
    #expect(emptyIndex == nil)
    
    // Add points with different segment indices
    let point0 = makeTrackPoint(
      sessionId: sessionId,
      timestamp: Date(timeIntervalSince1970: 0),
      segmentIndex: 0
    )
    let point2 = makeTrackPoint(
      sessionId: sessionId,
      timestamp: Date(timeIntervalSince1970: 10),
      segmentIndex: 2
    )
    try await dbManager.write { db in
      try point0.insert(db)
      try point2.insert(db)
    }
    
    let maxIndex = try await dbManager.fetchMaxSegmentIndex(for: sessionId)
    #expect(maxIndex == 2)
  }
  
  @Test("fetchLastPointTime returns precise Date of the last point")
  func testFetchLastPointTime() async throws {
    let sessionId = "session-1"
    let session = TrackSessionRecord(id: sessionId, startTime: Date(timeIntervalSince1970: 0))
    
    try await dbManager.write { db in
      try session.insert(db)
    }
    
    // Empty session should return nil
    let emptyTime = try await dbManager.fetchLastPointTime(for: sessionId)
    #expect(emptyTime == nil)
    
    let time1 = Date(timeIntervalSince1970: 10)
    let time2 = Date(timeIntervalSince1970: 10.001)
    
    let point1 = makeTrackPoint(
      sessionId: sessionId,
      timestamp: time1
    )
    let point2 = makeTrackPoint(
      sessionId: sessionId,
      timestamp: time2
    )
    
    try await dbManager.write { db in
      try point1.insert(db)
      try point2.insert(db)
    }
    
    let lastTime = try await dbManager.fetchLastPointTime(for: sessionId)
    if let lastTime = lastTime {
      #expect(abs(lastTime.timeIntervalSince(time2)) < 0.0001)
    } else {
      Issue.record("lastTime should not be nil")
    }
  }
  
  @Test("fetchRecentPoints returns most recent points within limit")
  func testFetchRecentPoints() async throws {
    let sessionId = "session-1"
    let session = TrackSessionRecord(id: sessionId, startTime: Date(timeIntervalSince1970: 0))
    
    try await dbManager.write { db in
      try session.insert(db)
    }
    
    // Insert 5 points sequentially
    try await dbManager.write { db in
      for i in 0..<5 {
        let point = self.makeTrackPoint(
          sessionId: sessionId,
          timestamp: Date(timeIntervalSince1970: TimeInterval(1000 + i * 10))
        )
        try point.insert(db)
      }
    }
    
    // Fetch with limit 3
    let recentPoints = try await dbManager.fetchRecentPoints(for: sessionId, limit: 3)
    
    #expect(recentPoints.count == 3)
    // Should be oldest of the recent ones first (chronological order)
    let timestamp0 = recentPoints[0].timestamp.timeIntervalSince1970
    let timestamp1 = recentPoints[1].timestamp.timeIntervalSince1970
    let timestamp2 = recentPoints[2].timestamp.timeIntervalSince1970

    #expect(timestamp0 == 1020)
    #expect(timestamp1 == 1030)
    #expect(timestamp2 == 1040)
  }
  
  // MARK: - Helpers
  
  private func makeTrackPoint(sessionId: String, timestamp: Date, segmentIndex: Int = 0) -> TrackPointRecord {
    return TrackPointRecord(
      id: nil,
      sessionId: sessionId,
      timestamp: timestamp,
      segmentIndex: segmentIndex,
      latitude: Measurement(value: 45.0, unit: .degrees),
      longitude: Measurement(value: -1.0, unit: .degrees),
      horizontalAccuracy: Measurement(value: 5.0, unit: .meters)
    )
  }
}

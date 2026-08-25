//
//  BarometricHistoryStoreTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-25.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Testing
import Foundation
import GRDB
@testable import Sillage

@Suite("Barometric History Store Tests")
final class BarometricHistoryStoreTests {
  let dbManager: DatabaseManager
  let store: BarometricHistoryStore
  
  init() throws {
    dbManager = try DatabaseManager.inMemory()
    store = BarometricHistoryStore(databaseManager: dbManager)
  }
  
  @Test("Add and retrieve readings over 7 days")
  func testAddAndRetrieveReadingsAcross7Days() async throws {
    let now = Date.now
    
    let reading1h = BarometricReading(
      timestamp: now.addingTimeInterval(-3600),
      pressure: Measurement(value: 1013.25, unit: .hectopascals)
    )
    let reading12h = BarometricReading(
      timestamp: now.addingTimeInterval(-12 * 3600),
      pressure: Measurement(value: 1015.0, unit: .hectopascals)
    )
    let reading6Days = BarometricReading(
      timestamp: now.addingTimeInterval(-6 * 24 * 3600),
      pressure: Measurement(value: 1008.5, unit: .hectopascals)
    )
    
    await store.add(reading: reading6Days)
    await store.add(reading: reading12h)
    await store.add(reading: reading1h)
    
    let all7Days = await store.getReadings(for: 7 * 24)
    #expect(all7Days.count == 3)
    #expect(all7Days[0].pressure.value == 1008.5)
    #expect(all7Days[1].pressure.value == 1015.0)
    #expect(all7Days[2].pressure.value == 1013.25)
    
    let last24h = await store.getReadings(for: 24)
    #expect(last24h.count == 2)
  }
  
  @Test("Automatic pruning retains 7 days and deletes older points")
  func testAutomaticPruningRetains7DaysAndRemovesOlder() async throws {
    let now = Date.now
    
    let reading8DaysAgo = BarometricReading(
      timestamp: now.addingTimeInterval(-8 * 24 * 3600),
      pressure: Measurement(value: 1020.0, unit: .hectopascals)
    )
    let reading6DaysAgo = BarometricReading(
      timestamp: now.addingTimeInterval(-6 * 24 * 3600),
      pressure: Measurement(value: 1012.0, unit: .hectopascals)
    )
    let readingRecent = BarometricReading(
      timestamp: now.addingTimeInterval(-60),
      pressure: Measurement(value: 1014.0, unit: .hectopascals)
    )
    
    // Insert older point directly into SQLite to simulate existing pre-cutoff record
    try await dbManager.write { db in
      var oldRecord = BarometricReadingRecord(domainModel: reading8DaysAgo)
      try oldRecord.insert(db)
    }
    
    // Adding new points triggers automatic pruning of anything older than 7 days
    await store.add(reading: reading6DaysAgo)
    await store.add(reading: readingRecent)
    
    let storedReadings = await store.getReadings(for: 10 * 24)
    #expect(storedReadings.count == 2)
    #expect(!storedReadings.contains(where: { $0.pressure.value == 1020.0 }))
    #expect(storedReadings.contains(where: { $0.pressure.value == 1012.0 }))
    #expect(storedReadings.contains(where: { $0.pressure.value == 1014.0 }))
  }
  
  @Test("Query custom DateInterval")
  func testQueryCustomDateInterval() async throws {
    let now = Date.now
    let t1 = now.addingTimeInterval(-5 * 3600)
    let t2 = now.addingTimeInterval(-3 * 3600)
    let t3 = now.addingTimeInterval(-1 * 3600)
    
    await store.add(reading: BarometricReading(timestamp: t1, pressure: Measurement(value: 1000.0, unit: .hectopascals)))
    await store.add(reading: BarometricReading(timestamp: t2, pressure: Measurement(value: 1005.0, unit: .hectopascals)))
    await store.add(reading: BarometricReading(timestamp: t3, pressure: Measurement(value: 1010.0, unit: .hectopascals)))
    
    let interval = DateInterval(start: now.addingTimeInterval(-4 * 3600), end: now.addingTimeInterval(-2 * 3600))
    let results = try await store.getReadings(in: interval)
    
    #expect(results.count == 1)
    #expect(results.first?.pressure.value == 1005.0)
  }
  
  @Test("One-shot batch migration from legacy JSON file")
  func testBatchLegacyJSONMigration() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let jsonURL = tempDir.appendingPathComponent("test_legacy_baro_\(UUID().uuidString).json")
    
    let now = Date.now
    let legacyReadings = [
      BarometricReading(timestamp: now.addingTimeInterval(-3600), pressure: Measurement(value: 1012.0, unit: .hectopascals)),
      BarometricReading(timestamp: now.addingTimeInterval(-7200), pressure: Measurement(value: 1011.5, unit: .hectopascals)),
      BarometricReading(timestamp: now.addingTimeInterval(-10 * 24 * 3600), pressure: Measurement(value: 1025.0, unit: .hectopascals))
    ]
    
    let data = try JSONEncoder().encode(legacyReadings)
    try data.write(to: jsonURL)
    #expect(FileManager.default.fileExists(atPath: jsonURL.path))
    
    await store.migrateLegacyJSONIfNeeded(fileURL: jsonURL)
    
    // File must be deleted after successful batch insertion
    #expect(!FileManager.default.fileExists(atPath: jsonURL.path))
    
    // Check SQLite contents
    let migratedReadings = await store.getReadings(for: 7 * 24)
    #expect(migratedReadings.count == 2)
    #expect(migratedReadings.contains(where: { $0.pressure.value == 1012.0 }))
    #expect(migratedReadings.contains(where: { $0.pressure.value == 1011.5 }))
    #expect(!migratedReadings.contains(where: { $0.pressure.value == 1025.0 }))
  }
  
  @Test("Empty legacy JSON file is deleted")
  func testEmptyLegacyJSONFileRemoved() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let jsonURL = tempDir.appendingPathComponent("test_empty_baro_\(UUID().uuidString).json")
    
    let data = try JSONEncoder().encode([BarometricReading]())
    try data.write(to: jsonURL)
    #expect(FileManager.default.fileExists(atPath: jsonURL.path))
    
    await store.migrateLegacyJSONIfNeeded(fileURL: jsonURL)
    
    #expect(!FileManager.default.fileExists(atPath: jsonURL.path))
  }
}

//
//  BarometricHistoryStore.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import GRDB
import OSLog

/// Actor responsible for thread-safe storage and persistence of barometric history in SQLite using GRDB.
/// It acts as a circular database store, automatically pruning readings older than the maximum history duration.
public actor BarometricHistoryStore {
  
  private let databaseManager: DatabaseManager
  private let maxHistoryDuration: TimeInterval
  
  /// Initializes the store with a GRDB `DatabaseManager` instance.
  /// - Parameters:
  ///   - databaseManager: The database manager coordinating SQLite transactions.
  ///   - maxHistoryDuration: The maximum duration of data to retain (defaults to 7 days / 168 hours).
  public init(
    databaseManager: DatabaseManager,
    maxHistoryDuration: TimeInterval = 7 * 24 * 3600
  ) {
    self.databaseManager = databaseManager
    self.maxHistoryDuration = maxHistoryDuration
  }
  
  /// Adds a new reading to the database and prunes readings older than `maxHistoryDuration` in an asynchronous transaction.
  /// - Parameter reading: The new `BarometricReading` to persist.
  public func add(reading: BarometricReading) async {
    let maxDuration = maxHistoryDuration
    let cutoffUnix = Date.now.addingTimeInterval(-maxDuration).timeIntervalSince1970
    let record = BarometricReadingRecord(domainModel: reading)
    
    do {
      try await databaseManager.write { db in
        try record.insert(db)
        // Prune older points to maintain the 7-day circular rolling window
        try BarometricReadingRecord
          .filter(BarometricReadingRecord.Columns.timestampUnix < cutoffUnix)
          .deleteAll(db)
      }
    } catch {
      Logger.barometer.error("Failed to persist barometric reading to database: \(error.localizedDescription, privacy: .public)")
    }
  }
  
  /// Retrieves all readings recorded within the specified arbitrary `DateInterval`.
  /// Enables seamless querying for custom intervals (e.g. historical scrolling).
  /// - Parameter interval: The date interval to fetch readings for.
  /// - Returns: An array of `BarometricReading` ordered chronologically.
  public func getReadings(in interval: DateInterval) async throws -> [BarometricReading] {
    let startUnix = interval.start.timeIntervalSince1970
    let endUnix = interval.end.timeIntervalSince1970
    
    return try await databaseManager.reader.read { db in
      let records = try BarometricReadingRecord
        .filter(BarometricReadingRecord.Columns.timestampUnix >= startUnix && BarometricReadingRecord.Columns.timestampUnix <= endUnix)
        .order(BarometricReadingRecord.Columns.timestampUnix.asc)
        .fetchAll(db)
      return records.map { $0.domainModel }
    }
  }
  
  /// Retrieves all readings recorded within the specified number of past hours.
  /// Convenience helper maintaining backward compatibility for fixed lookback windows (e.g. 1h, 3h, 24h).
  /// - Parameter lastHours: The number of hours to look back.
  /// - Returns: An array of `BarometricReading` matching the timeframe.
  public func getReadings(for lastHours: Int) async -> [BarometricReading] {
    let now = Date.now
    let cutoff = now.addingTimeInterval(-Double(lastHours) * 3600)
    let interval = DateInterval(start: cutoff, end: now)
    
    do {
      return try await getReadings(in: interval)
    } catch {
      Logger.barometer.error("Failed to fetch barometric history for last \(lastHours)h: \(error.localizedDescription, privacy: .public)")
      return []
    }
  }
}

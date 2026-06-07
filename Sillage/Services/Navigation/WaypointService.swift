//
//  WaypointService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-06-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import GRDB
import OSLog
import Observation

public enum WaypointError: LocalizedError {
  case notFound
  case serviceUnavailable

  public var errorDescription: String? {
    switch self {
    case .notFound: return String(localized: "Waypoint not found in the database.")
    case .serviceUnavailable: return String(localized: "Waypoint service is unavailable.")
    }
  }
}

@MainActor
@Observable
public final class WaypointService {
  public private(set) var currentWaypoints: [Waypoint] = []
  public private(set) var goToWaypointID: String?
  
  private let databaseManager: DatabaseManager
  private var observationTask: TaskCancellable?

  public init(databaseManager: DatabaseManager, initialGoToWaypointID: String? = nil) {
    self.databaseManager = databaseManager
    self.goToWaypointID = initialGoToWaypointID
    startObservation()
  }

  private func startObservation() {
    let observation = ValueObservation.tracking { db in
      try WaypointRecord
        .order(WaypointRecord.Columns.timestamp_unix.desc)
        .fetchAll(db)
        .map { $0.toDomain() }
    }

    observationTask = TaskCancellable(Task { [weak self] in
      do {
        guard let dbReader = self?.databaseManager.reader else { return }
        for try await waypoints in observation.values(in: dbReader) {
          guard !Task.isCancelled else { break }
          self?.currentWaypoints = waypoints
        }
      } catch {
        Logger.database.error("Waypoint observation failed: \(error, privacy: .public)")
      }
    })
  }

  public func fetchWaypoints() async throws -> [Waypoint] {
    try await databaseManager.reader.read { db in
      let records = try WaypointRecord
        .order(WaypointRecord.Columns.timestamp_unix.desc)
        .fetchAll(db)
      return records.map { $0.toDomain() }
    }
  }

  public func fetchWaypoint(id: String) async throws -> Waypoint? {
    try await databaseManager.reader.read { db in
      let record = try WaypointRecord.fetchOne(db, key: id)
      return record?.toDomain()
    }
  }

  public func saveWaypoint(_ waypoint: Waypoint) async throws {
    _ = try await databaseManager.write { db in
      let record = WaypointRecord(domainModel: waypoint)
      try record.save(db)
      Logger.database.info("Successfully saved waypoint: \(waypoint.id, privacy: .public)")
    }
  }

  public func fetchNextDefaultName() async throws -> String {
    let baseName = String(localized: "Waypoint")
    return try await databaseManager.reader.read { db in
      let count = try WaypointRecord.fetchCount(db)
      let records = try WaypointRecord.fetchAll(db, sql: "SELECT * FROM waypoint WHERE name LIKE ?", arguments: ["\(baseName) %"])
      
      var maxNum = 0
      for record in records {
        let remainder = record.name.dropFirst(baseName.count + 1)
        if let num = Int(String(remainder)) {
          maxNum = max(maxNum, num)
        }
      }
      
      let nextNum = max(count + 1, maxNum + 1)
      return "\(baseName) \(nextNum)"
    }
  }

  public func deleteWaypoint(id: String) async throws {
    _ = try await databaseManager.write { db in
      let deleted = try WaypointRecord.deleteOne(db, key: id)
      if deleted {
        Logger.database.info("Successfully deleted waypoint: \(id, privacy: .public)")
      } else {
        Logger.database.warning("Waypoint not found for deletion: \(id, privacy: .public)")
      }
    }
    
    if goToWaypointID == id {
      setGoToWaypoint(id: nil)
    }
  }

  public func setGoToWaypoint(id: String?) {
    goToWaypointID = id
  }
}

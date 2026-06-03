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

/// A thread-safe service providing read and write operations for waypoints in the database.
public struct WaypointService: Sendable {
  private let databaseManager: DatabaseManager
  private let selectionStore: WaypointSelectionStore
  
  public init(databaseManager: DatabaseManager, initialSelection: String? = nil) {
    self.databaseManager = databaseManager
    self.selectionStore = WaypointSelectionStore(initialSelection: initialSelection)
  }
  
  /// Observes saved waypoints, ordered by timestamp descending, in real-time.
  /// - Returns: An AsyncSequence emitting arrays of `Waypoint` whenever the database updates.
  public func observeWaypoints() -> some AsyncSequence<[Waypoint], Error> {
    let observation = ValueObservation.tracking { db in
      let records = try WaypointRecord
        .order(WaypointRecord.Columns.timestamp_unix.desc)
        .fetchAll(db)
      
      return records.map { $0.toDomain() }
    }
    
    return observation.values(in: databaseManager.reader)
  }
  
  /// Fetches all waypoints in the database.
  /// - Returns: An array of `Waypoint`.
  public func fetchWaypoints() async throws -> [Waypoint] {
    try await databaseManager.reader.read { db in
      let records = try WaypointRecord
        .order(WaypointRecord.Columns.timestamp_unix.desc)
        .fetchAll(db)
      return records.map { $0.toDomain() }
    }
  }
  
  /// Fetches a specific waypoint from the database by its ID.
  /// - Returns: The `Waypoint` if found, nil otherwise.
  public func fetchWaypoint(id: String) async throws -> Waypoint? {
    try await databaseManager.reader.read { db in
      let record = try WaypointRecord.fetchOne(db, key: id)
      return record?.toDomain()
    }
  }
  
  /// Saves a waypoint to the database. Inserts or updates existing.
  public func saveWaypoint(_ waypoint: Waypoint) async throws {
    _ = try await databaseManager.write { db in
      let record = WaypointRecord(domainModel: waypoint)
      try record.save(db)
      Logger.database.info("Successfully saved waypoint: \(waypoint.id, privacy: .public)")
    }
  }
  
  /// Deletes a waypoint from the database by its ID.
  public func deleteWaypoint(id: String) async throws {
    _ = try await databaseManager.write { db in
      let deleted = try WaypointRecord.deleteOne(db, key: id)
      if deleted {
        Logger.database.info("Successfully deleted waypoint: \(id, privacy: .public)")
      } else {
        Logger.database.warning("Waypoint not found for deletion: \(id, privacy: .public)")
      }
    }
  }
  
  /// Selects a waypoint by its ID.
  public func selectWaypoint(id: String?) async {
    await selectionStore.select(id)
  }
  
  /// Observes the currently selected waypoint ID.
  public func observeSelectedWaypoint() async -> AsyncStream<String?> {
    await selectionStore.observe()
  }
}

/// An actor responsible for managing the isolated in-memory selection state of a waypoint.
actor WaypointSelectionStore {
  private var selectedId: String?
  private var continuations: [UUID: AsyncStream<String?>.Continuation] = [:]
  
  init(initialSelection: String?) {
    self.selectedId = initialSelection
  }
  
  func select(_ id: String?) {
    selectedId = id
    for continuation in continuations.values {
      continuation.yield(id)
    }
  }
  
  func observe() -> AsyncStream<String?> {
    AsyncStream { continuation in
      let id = UUID()
      Task { [weak self] in
        await self?.addContinuation(id: id, continuation: continuation)
      }
      continuation.onTermination = { _ in
        Task { [weak self] in
          await self?.removeContinuation(id: id)
        }
      }
    }
  }
  
  private func addContinuation(id: UUID, continuation: AsyncStream<String?>.Continuation) {
    continuations[id] = continuation
    continuation.yield(selectedId)
  }
  
  private func removeContinuation(id: UUID) {
    continuations.removeValue(forKey: id)
  }
}

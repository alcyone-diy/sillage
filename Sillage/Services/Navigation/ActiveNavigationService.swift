//
//  ActiveNavigationService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-27.
//  Copyright © 2026 Alcyone.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation
import GRDB
import Observation
import OSLog

/// Domain orchestrator owning the active point-to-point navigation leg ("Go To") and its real-time
/// geodesic telemetry (`BTW`, `RNG`, `XTE`).
///
/// Persists both `waypoint_id` and `originCoordinate` atomically in SQLite (`active_navigation`
/// with `ON DELETE CASCADE` on `waypoint`) so app restarts at sea never reset Cross-Track Error to zero.
@MainActor
@Observable
public final class ActiveNavigationService {

  /// Legacy `UserDefaults` key migrated one-shot into SQLite `active_navigation` during bootstrap.
  public static let legacyGoToWaypointDefaultsKey = "goToWaypointID"

  // MARK: - Observable Domain State

  public private(set) var activeLeg: ActiveNavigationLeg?

  public var goToWaypointID: String? {
    activeLeg?.waypoint.id
  }

  public private(set) var bearingToWaypoint: Measurement<UnitAngle>?
  public private(set) var rangeToWaypoint: Measurement<UnitLength>?
  public private(set) var crossTrackError: Measurement<UnitLength>?

  // MARK: - Activation Multicast Stream

  /// Emits the destination `Waypoint` strictly when an explicit user action starts a new GoTo leg.
  /// Never fires on cold-start restoration or passive waypoint edits, preserving saved camera state on launch.
  public var navigationActivationStream: AsyncStream<Waypoint> {
    let (stream, continuation) = AsyncStream.makeStream(of: Waypoint.self)
    let id = UUID()
    activationContinuations[id] = continuation

    continuation.onTermination = { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.activationContinuations.removeValue(forKey: id)
      }
    }
    return stream
  }

  // MARK: - Private Dependencies & Tasks

  private let databaseManager: DatabaseManager
  @ObservationIgnored private let currentInstrumentStateProvider: @MainActor () -> InstrumentState?
  @ObservationIgnored private let observeInstrumentStateProvider: @MainActor () -> AsyncStream<InstrumentState>
  @ObservationIgnored private let dateProvider: @Sendable () -> Date

  @ObservationIgnored private var activationContinuations: [UUID: AsyncStream<Waypoint>.Continuation] = [:]
  @ObservationIgnored private var databaseObservationTask: TaskCancellable?
  @ObservationIgnored private var instrumentObservationTask: TaskCancellable?
  @ObservationIgnored private var originPersistenceTask: TaskCancellable?
  @ObservationIgnored private var latestObservedInstrumentState: InstrumentState?
  @ObservationIgnored private var isStarted: Bool = false

  // MARK: - Pure Initializers

  /// Designated pure initializer (zero I/O, zero database queries, zero asynchronous tasks).
  /// Call `start(legacyDefaults:)` during `AppEnvironment.bootstrap()` to hydrate state and start streams.
  public init(
    databaseManager: DatabaseManager,
    currentInstrumentState: @escaping @MainActor () -> InstrumentState?,
    observeInstrumentState: @escaping @MainActor () -> AsyncStream<InstrumentState>,
    dateProvider: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.databaseManager = databaseManager
    self.currentInstrumentStateProvider = currentInstrumentState
    self.observeInstrumentStateProvider = observeInstrumentState
    self.dateProvider = dateProvider
  }

  /// Convenience pure initializer binding directly to `InstrumentDampingService`.
  convenience init<C: Clock & Sendable>(
    databaseManager: DatabaseManager,
    instrumentDampingService: InstrumentDampingService<C>,
    dateProvider: @escaping @Sendable () -> Date = { Date() }
  ) where C.Duration == Duration {
    self.init(
      databaseManager: databaseManager,
      currentInstrumentState: { [weak instrumentDampingService] in
        instrumentDampingService?.state
      },
      observeInstrumentState: { [weak instrumentDampingService] in
        guard let instrumentDampingService else {
          return AsyncStream { $0.finish() }
        }
        return instrumentDampingService.observeState()
      },
      dateProvider: dateProvider
    )
  }

  // MARK: - Lifecycle

  /// Hydrates any persisted active navigation leg from SQLite (including one-shot migration from legacy
  /// `UserDefaults` if present) and starts observing both GRDB waypoint/leg changes and `InstrumentState`.
  public func start(legacyDefaults: UserDefaults? = nil) async {
    guard !isStarted else { return }
    isStarted = true

    if let legacyDefaults {
      await migrateLegacyUserDefaultsIfNeeded(defaults: legacyDefaults)
    }

    do {
      var hydratedLeg = try await fetchPersistedLeg()
      let initialState = resolveCurrentInstrumentState()

      if let leg = hydratedLeg,
         leg.originCoordinate == nil,
         let validOrigin = ActiveNavigationEvaluator.eligibleOriginCoordinate(from: initialState) {
        try await persistLockedOrigin(validOrigin, forWaypointID: leg.waypoint.id)
        hydratedLeg = leg.withOrigin(validOrigin)
      }

      self.activeLeg = hydratedLeg
      applyMetrics(for: hydratedLeg, state: initialState)
    } catch {
      Logger.navigation.error("Failed to hydrate active navigation leg during startup: \(error.localizedDescription, privacy: .public)")
    }

    startDatabaseObservation()
    startInstrumentObservation()
  }

  public func stop() {
    databaseObservationTask?.cancel()
    databaseObservationTask = nil
    instrumentObservationTask?.cancel()
    instrumentObservationTask = nil
    originPersistenceTask?.cancel()
    originPersistenceTask = nil

    for continuation in activationContinuations.values {
      continuation.finish()
    }
    activationContinuations.removeAll()
    isStarted = false
  }

  // MARK: - Commands

  /// Activates point-to-point navigation toward `waypointID`, or cancels active navigation when `nil`.
  ///
  /// - Throws: `WaypointError.notFound` if `waypointID` does not exist in SQLite, or a `GRDB.DatabaseError` on I/O failure.
  public func setDestination(waypointID: String?) async throws {
    originPersistenceTask?.cancel()
    originPersistenceTask = nil

    guard let waypointID else {
      try await databaseManager.write { db in
        _ = try ActiveNavigationRecord.deleteOne(db, key: ActiveNavigationRecord.singletonID)
      }
      self.activeLeg = nil
      applyMetrics(for: nil, state: nil)
      Logger.navigation.info("Active GoTo navigation cancelled.")
      return
    }

    let snapshotState = resolveCurrentInstrumentState()
    let initialOrigin = ActiveNavigationEvaluator.eligibleOriginCoordinate(from: snapshotState)
    let activatedAt = dateProvider()

    let persistedLeg = try await databaseManager.write { db -> ActiveNavigationLeg in
      guard let waypointRecord = try WaypointRecord.fetchOne(db, key: waypointID) else {
        throw WaypointError.notFound
      }
      let navRecord = ActiveNavigationRecord(
        waypoint_id: waypointID,
        originCoordinate: initialOrigin,
        activatedAt: activatedAt
      )
      try navRecord.save(db)
      return navRecord.toDomain(waypoint: waypointRecord.toDomain())
    }

    var resolvedLeg = persistedLeg
    let postWriteState = resolveCurrentInstrumentState()
    if resolvedLeg.originCoordinate == nil,
       let lateOrigin = ActiveNavigationEvaluator.eligibleOriginCoordinate(from: postWriteState) {
      resolvedLeg = resolvedLeg.withOrigin(lateOrigin)
      scheduleOriginPersistence(lateOrigin, forWaypointID: waypointID)
    }

    self.activeLeg = resolvedLeg
    applyMetrics(for: resolvedLeg, state: postWriteState)

    Logger.navigation.info("Started GoTo navigation toward waypoint \(waypointID, privacy: .public) (originLocked=\(resolvedLeg.originCoordinate != nil, privacy: .public)).")

    for continuation in activationContinuations.values {
      continuation.yield(resolvedLeg.waypoint)
    }
  }

  // MARK: - Private Observation & Persistence

  private func resolveCurrentInstrumentState() -> InstrumentState? {
    currentInstrumentStateProvider() ?? latestObservedInstrumentState
  }

  private func fetchPersistedLeg() async throws -> ActiveNavigationLeg? {
    try await databaseManager.reader.read { db in
      try Self.readActiveLeg(in: db)
    }
  }

  nonisolated private static func readActiveLeg(in db: Database) throws -> ActiveNavigationLeg? {
    guard let navRecord = try ActiveNavigationRecord.fetchOne(db, key: ActiveNavigationRecord.singletonID),
          let waypointRecord = try WaypointRecord.fetchOne(db, key: navRecord.waypoint_id) else {
      return nil
    }
    return navRecord.toDomain(waypoint: waypointRecord.toDomain())
  }

  private func startDatabaseObservation() {
    let observation = ValueObservation.tracking { db in
      try Self.readActiveLeg(in: db)
    }

    databaseObservationTask = TaskCancellable(Task { [weak self] in
      guard let dbReader = self?.databaseManager.reader else { return }
      do {
        for try await observedLeg in observation.values(in: dbReader) {
          guard !Task.isCancelled, let self else { break }
          self.handleObservedLegChange(observedLeg)
        }
      } catch is CancellationError {
        return
      } catch {
        Logger.database.error("Active navigation observation failed: \(error.localizedDescription, privacy: .public)")
      }
    })
  }

  private func handleObservedLegChange(_ observedLeg: ActiveNavigationLeg?) {
    let state = resolveCurrentInstrumentState()

    guard var leg = observedLeg else {
      originPersistenceTask?.cancel()
      originPersistenceTask = nil
      self.activeLeg = nil
      applyMetrics(for: nil, state: state)
      return
    }

    // Preserve an already-locked in-memory origin if the DB snapshot raced just ahead of `originPersistenceTask`,
    // or lock immediately if `state` is currently `.active`.
    if leg.originCoordinate == nil {
      if let inMemoryLeg = self.activeLeg,
         inMemoryLeg.waypoint.id == leg.waypoint.id,
         let inMemoryOrigin = inMemoryLeg.originCoordinate {
        leg = leg.withOrigin(inMemoryOrigin)
      } else if let validOrigin = ActiveNavigationEvaluator.eligibleOriginCoordinate(from: state) {
        leg = leg.withOrigin(validOrigin)
        scheduleOriginPersistence(validOrigin, forWaypointID: leg.waypoint.id)
      }
    }

    self.activeLeg = leg
    applyMetrics(for: leg, state: state)
  }

  private func startInstrumentObservation() {
    let stream = observeInstrumentStateProvider()
    instrumentObservationTask = TaskCancellable(Task { @MainActor [weak self] in
      for await state in stream {
        guard !Task.isCancelled, let self else { break }
        self.latestObservedInstrumentState = state
        self.handleInstrumentState(state)
      }
    })
  }

  private func handleInstrumentState(_ state: InstrumentState) {
    if let leg = activeLeg,
       leg.originCoordinate == nil,
       let validOrigin = ActiveNavigationEvaluator.eligibleOriginCoordinate(from: state) {
      let lockedLeg = leg.withOrigin(validOrigin)
      self.activeLeg = lockedLeg
      scheduleOriginPersistence(validOrigin, forWaypointID: leg.waypoint.id)
      Logger.navigation.info("Locked deferred GoTo origin coordinate on first active GPS fix for waypoint \(leg.waypoint.id, privacy: .public).")
    }

    applyMetrics(for: activeLeg, state: state)
  }

  private func scheduleOriginPersistence(_ origin: CLLocationCoordinate2D, forWaypointID waypointID: String) {
    originPersistenceTask?.cancel()
    originPersistenceTask = TaskCancellable(Task { [weak self] in
      guard let self else { return }
      do {
        try await self.persistLockedOrigin(origin, forWaypointID: waypointID)
      } catch is CancellationError {
        return
      } catch {
        Logger.database.error("Failed to persist locked GoTo origin coordinate for waypoint \(waypointID, privacy: .public): \(error.localizedDescription, privacy: .public)")
      }
    })
  }

  private func persistLockedOrigin(_ origin: CLLocationCoordinate2D, forWaypointID waypointID: String) async throws {
    try await databaseManager.write { db in
      try db.execute(
        sql: """
          UPDATE active_navigation
          SET origin_latitude_deg = ?, origin_longitude_deg = ?
          WHERE id = ? AND waypoint_id = ? AND origin_latitude_deg IS NULL
          """,
        arguments: [
          origin.latitude,
          origin.longitude,
          ActiveNavigationRecord.singletonID,
          waypointID
        ]
      )
    }
  }

  private func applyMetrics(for leg: ActiveNavigationLeg?, state: InstrumentState?) {
    let metrics = ActiveNavigationEvaluator.evaluate(leg: leg, state: state)
    if self.bearingToWaypoint != metrics.bearingToWaypoint {
      self.bearingToWaypoint = metrics.bearingToWaypoint
    }
    if self.rangeToWaypoint != metrics.rangeToWaypoint {
      self.rangeToWaypoint = metrics.rangeToWaypoint
    }
    if self.crossTrackError != metrics.crossTrackError {
      self.crossTrackError = metrics.crossTrackError
    }
  }

  private func migrateLegacyUserDefaultsIfNeeded(defaults: UserDefaults) async {
    guard let legacyID = defaults.string(forKey: Self.legacyGoToWaypointDefaultsKey),
          !legacyID.isEmpty else {
      return
    }

    let initialOrigin = ActiveNavigationEvaluator.eligibleOriginCoordinate(from: resolveCurrentInstrumentState())
    let now = dateProvider()

    do {
      try await databaseManager.write { db in
        let hasExistingRow = try ActiveNavigationRecord.exists(db, key: ActiveNavigationRecord.singletonID)
        guard !hasExistingRow, try WaypointRecord.exists(db, key: legacyID) else {
          return
        }
        let migratedRecord = ActiveNavigationRecord(
          waypoint_id: legacyID,
          originCoordinate: initialOrigin,
          activatedAt: now
        )
        try migratedRecord.insert(db)
      }
      defaults.removeObject(forKey: Self.legacyGoToWaypointDefaultsKey)
      Logger.navigation.info("Migrated legacy UserDefaults goToWaypointID (\(legacyID, privacy: .public)) into SQLite active_navigation.")
    } catch {
      Logger.database.error("Failed to migrate legacy goToWaypointID to SQLite: \(error.localizedDescription, privacy: .public)")
    }
  }
}

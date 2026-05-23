//
//  TrackRecordingService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation
import Observation
import OSLog
import GRDB

@MainActor
@Observable
public final class TrackRecordingService {
  public private(set) var trackPoints: [TrackPoint] = []
  
  public enum RecordingState: Equatable, Sendable {
    case idle
    case waitingForFix
    case recording
    case paused
    case saving
  }
  
  public private(set) var state: RecordingState = .idle
  
  public var recordingError: TrackRecordingError?
  
  // MARK: - Telemetry State
  public private(set) var sessionStartTime: Date?
  public private(set) var lastSessionDurationUpdateMonotonicTime: ContinuousClock.Instant?
  public private(set) var sessionDistance: Measurement<UnitLength>?
  public private(set) var sessionDuration: Duration?
  
  public private(set) var minLatitude: Measurement<UnitAngle>?
  public private(set) var maxLatitude: Measurement<UnitAngle>?
  public private(set) var minLongitude: Measurement<UnitAngle>?
  public private(set) var maxLongitude: Measurement<UnitAngle>?
  public private(set) var maxSpeedOverGround: Measurement<UnitSpeed>?
  public private(set) var pointsCount: Int?
  
  /// Centralized configuration for the track recording service logic.
  internal struct Configuration {
    /// The number of points buffered in memory before a batch commit to the database.
    nonisolated static let flushThreshold = 150
    /// The maximum number of points held in memory for real-time map rendering.
    nonisolated static let maxTrackPoints = 2000
    /// The maximum time delay before flushing buffered points to the database.
    nonisolated static let maxFlushInterval: Duration = .seconds(600) // 10mn.
  }
  
  private var currentSessionId: String?
  private var segmentIndex: Int = 0
  private var writeBuffer: [TrackPointRecord] = []
  private var lastRecordedNavigationFix: NavigationFix?
  private var filters: TrackFilters
  
  public enum TrackRecordingError: LocalizedError {
    case databaseUnavailable
    
    public var errorDescription: String? {
      switch self {
      case .databaseUnavailable:
        return "Database is unavailable. Recording cannot start."
      }
    }
  }
  
  private let locationService: LocationServiceProtocol
  private let databaseManager: DatabaseManager
  private var locationUpdatesTask: TaskCancellable?
  private var backgroundLocationToken: (any BackgroundLocationToken)?
  private var flushTask: TaskCancellable?
  
  private enum TrackDatabaseAction: Sendable {
    case insertSession(TrackSessionRecord)
    case flushBatch(points: [TrackPointRecord], sessionUpdate: TrackSessionRecord)
  }
  private var dbActionContinuation: AsyncStream<TrackDatabaseAction>.Continuation?
  private var persistenceTask: Task<Void, Never>?
  
  init(
    filters: TrackFilters = .default,
    locationService: LocationServiceProtocol,
    databaseManager: DatabaseManager
  ) {
    self.filters = filters
    self.locationService = locationService
    self.databaseManager = databaseManager
  }
  
  public func updateFilters(_ newFilters: TrackFilters) {
    self.filters = newFilters
    Logger.telemetry.info("Track filters updated: \(newFilters.minDistanceMeters)m, \(newFilters.minTimeIntervalSeconds)s, \(newFilters.maxHorizontalAccuracy) accuracy")
  }
  
  public func startRecording() {
    switch state {
    case .idle:
      break
    case .waitingForFix, .recording, .paused, .saving:
      return
    }
    
    currentSessionId = nil
    segmentIndex = 0
    sessionStartTime = nil
    lastSessionDurationUpdateMonotonicTime = nil
    sessionDuration = nil
    sessionDistance = Measurement(value: 0, unit: UnitLength.meters)
    lastRecordedNavigationFix = nil
    writeBuffer.removeAll()
    trackPoints.removeAll()
    minLatitude = nil
    maxLatitude = nil
    minLongitude = nil
    maxLongitude = nil
    maxSpeedOverGround = nil
    pointsCount = nil
    
    let service = self.locationService
    self.backgroundLocationToken = service.requestBackgroundLocation()
    
    startFlushTimer()
    
    locationUpdatesTask = TaskCancellable(Task { [weak self] in
      for await navigationFix in service.locationUpdates {
        guard !Task.isCancelled else { break }
        self?.processLocationUpdate(navigationFix)
      }
    })
    
    let (stream, continuation) = AsyncStream.makeStream(of: TrackDatabaseAction.self)
    self.dbActionContinuation = continuation
    self.persistenceTask = Task.detached(priority: .utility) { [databaseManager] in
      for await action in stream {
        do {
          try await databaseManager.dbPool.write { db in
            switch action {
            case .insertSession(let session):
              try session.insert(db)
            case .flushBatch(let points, let sessionUpdate):
              try points.forEach { try $0.insert(db) }
              try sessionUpdate.update(db)
            }
          }
        } catch {
          Logger.database.error("Failed to execute database action: \(error.localizedDescription, privacy: .public)")
        }
      }
    }
    
    state = .waitingForFix
  }
  
  public enum StopRecordingResult: Equatable, Sendable {
    case savedAsync(sessionId: String)
    case abortedNoFix
    case noActiveRecording
  }
  
  @discardableResult
  public func stopRecording() -> StopRecordingResult {
    switch state {
    case .recording, .paused, .waitingForFix:
      break
    case .idle, .saving:
      return .noActiveRecording
    }
    locationUpdatesTask?.cancel()
    locationUpdatesTask = nil
    backgroundLocationToken = nil
    flushTask?.cancel()
    flushTask = nil
    
    guard let sessionId = currentSessionId,
          let endTime = lastRecordedNavigationFix?.timestamp else {
      state = .idle
      return .abortedNoFix
    }
    
    // Removed manual segment duration addition since it's now updated continuously in processLocationUpdate
    
    state = .saving
    
    let finalDurationSeconds = sessionDuration
    let finalDistanceMeters = sessionDistance
    let sessionUpdate = buildCurrentSessionRecord()
    
    flushBuffer()
    dbActionContinuation?.finish()
    let localPersistenceTask = persistenceTask
    BackgroundTaskRunner.execute(name: "FinalizeTrack_\(sessionId)") { [weak self, databaseManager, localPersistenceTask] in
      _ = await localPersistenceTask?.value
      do {
        try await databaseManager.dbPool.write { db in
          if var session = sessionUpdate {
            session.endTimestamp_unix = endTime.timeIntervalSince1970
            try session.update(db)
          }
        }
        Logger.database.info("Track session \(sessionId, privacy: .public) finalized successfully with \(finalDurationSeconds?.components.seconds ?? 0, privacy: .public)s and \(finalDistanceMeters?.converted(to: .meters).value ?? 0, privacy: .public)m.")
      } catch {
        Logger.database.error("Finalization failed: \(error.localizedDescription, privacy: .public)")
      }
      await self?.stopSavingState()
    }
    
    currentSessionId = nil
    lastRecordedNavigationFix = nil
    
    return .savedAsync(sessionId: sessionId)
  }
  
  public func pauseRecording() {
    switch state {
    case .recording, .waitingForFix:
      break
    case .idle, .paused, .saving:
      return
    }
    
    locationUpdatesTask?.cancel()
    locationUpdatesTask = nil
    backgroundLocationToken = nil
    flushTask?.cancel()
    flushTask = nil
    
    lastSessionDurationUpdateMonotonicTime = nil
    lastRecordedNavigationFix = nil
    
    flushBuffer()
    
    state = .paused
    Logger.telemetry.info("Track recording paused.")
  }
  
  public func resumeRecording() {
    switch state {
    case .paused:
      break
    case .idle, .recording, .waitingForFix, .saving:
      return
    }
    
    segmentIndex += 1
    lastSessionDurationUpdateMonotonicTime = nil
    
    let service = self.locationService
    self.backgroundLocationToken = service.requestBackgroundLocation()
    
    startFlushTimer()
    
    locationUpdatesTask = TaskCancellable(Task { [weak self] in
      for await navigationFix in service.locationUpdates {
        guard !Task.isCancelled else { break }
        self?.processLocationUpdate(navigationFix)
      }
    })
    
    state = .waitingForFix
    Logger.telemetry.info("Track recording resumed (segment \(self.segmentIndex, privacy: .public)).")
  }
  
  public func activeSessionDuration() -> Duration? {
    guard let lastReceiveTime = lastSessionDurationUpdateMonotonicTime else {
      return sessionDuration
    }
    
    switch state {
    case .recording:
      let clock = ContinuousClock()
      let timeSinceLastLocation = clock.now - lastReceiveTime
      let currentSessionDuration = sessionDuration ?? .seconds(0)
      return currentSessionDuration + timeSinceLastLocation
    case .idle, .paused, .saving, .waitingForFix:
      return sessionDuration
    }
  }
  
  private func flushBuffer() {
    guard !writeBuffer.isEmpty else { return }
    let batch = writeBuffer
    writeBuffer.removeAll()
    if let sessionUpdate = buildCurrentSessionRecord() {
      dbActionContinuation?.yield(.flushBatch(points: batch, sessionUpdate: sessionUpdate))
    }
    switch state {
    case .recording, .waitingForFix:
      startFlushTimer()
    case .paused, .idle, .saving:
      break
    }
  }
  
  public func emergencyFlushAsync() async {
    guard !writeBuffer.isEmpty else { return }
    let pointsToInsert = writeBuffer
    writeBuffer.removeAll()
    let sessionUpdate = buildCurrentSessionRecord()

    do {
      try await databaseManager.dbPool.write { db in
        try pointsToInsert.forEach { try $0.insert(db) }
        try sessionUpdate?.update(db)
      }
      Logger.database.info("Emergency flush successful: \(pointsToInsert.count) points saved.")
    } catch {
      Logger.database.error("Emergency flush failed: \(error.localizedDescription, privacy: .public)")
    }
  }
  
  public enum ToggleRecordingResult: Sendable {
    case started
    case stopped(StopRecordingResult)
  }
  
  @discardableResult
  public func toggleRecording() -> ToggleRecordingResult {
    switch state {
    case .recording, .paused, .waitingForFix:
      return .stopped(stopRecording())
    case .idle, .saving:
      startRecording()
      return .started
    }
  }
  
  private func processLocationUpdate(_ navigationFix: NavigationFix) {
    guard navigationFix.horizontalAccuracy <= filters.maxHorizontalAccuracy else { return }
    
    switch state {
    case .waitingForFix:
      state = .recording
      
      if currentSessionId == nil {
        let sessionId = UUID().uuidString
        let startTime = navigationFix.timestamp
        
        currentSessionId = sessionId
        sessionStartTime = startTime
        
        let sessionRecord = TrackSessionRecord(id: sessionId, startTime: startTime)
        dbActionContinuation?.yield(.insertSession(sessionRecord))
      }
      
    case .idle, .recording, .paused, .saving:
      break
    }
    
    // Filtering Logic (Anti-Jitter)
    if let lastLoc = lastRecordedNavigationFix {
      let distanceSinceLast = navigationFix.distance(from: lastLoc)
      let timeSinceLast = navigationFix.timestamp.timeIntervalSince(lastLoc.timestamp)
      
      let hasMovedSignificantly = distanceSinceLast > filters.minDistanceMeters
      let hasSufficientTimePassed = timeSinceLast > filters.minTimeIntervalSeconds
      
      guard hasMovedSignificantly || hasSufficientTimePassed else { return }
      
      // Update cumulative distance only with validated points to prevent GPS noise inflation
      if let currentDistance = sessionDistance {
        let distanceIncrement = Measurement(value: distanceSinceLast, unit: UnitLength.meters)
        sessionDistance = currentDistance + distanceIncrement
      }
    }
    
    if let lastLoc = lastRecordedNavigationFix {
      let timeSinceLast = max(0, navigationFix.timestamp.timeIntervalSince(lastLoc.timestamp))
      let currentDuration = sessionDuration ?? .seconds(0)
      sessionDuration = currentDuration + .seconds(timeSinceLast)
    }
    lastSessionDurationUpdateMonotonicTime = .now
    lastRecordedNavigationFix = navigationFix
    
    var cog: Measurement<UnitAngle>? = nil
    if navigationFix.course >= 0 {
      cog = Measurement(value: navigationFix.course, unit: UnitAngle.degrees)
    }
    
    let latitude = Measurement(value: navigationFix.coordinate.latitude, unit: UnitAngle.degrees)
    let longitude = Measurement(value: navigationFix.coordinate.longitude, unit: UnitAngle.degrees)
    
    minLatitude = min(minLatitude ?? latitude, latitude)
    maxLatitude = max(maxLatitude ?? latitude, latitude)
    minLongitude = min(minLongitude ?? longitude, longitude)
    maxLongitude = max(maxLongitude ?? longitude, longitude)
    
    if let speedOverGround = navigationFix.speedOverGround {
      maxSpeedOverGround = max(maxSpeedOverGround ?? speedOverGround, speedOverGround)
    }
    
    pointsCount = (pointsCount ?? 0) + 1
    
    let trackPoint = TrackPoint(
      timestamp: navigationFix.timestamp,
      segmentIndex: segmentIndex,
      latitude: Measurement(value: navigationFix.coordinate.latitude, unit: .degrees),
      longitude: Measurement(value: navigationFix.coordinate.longitude, unit: .degrees),
      horizontalAccuracy: navigationFix.horizontalAccuracy,
      sog: navigationFix.speedOverGround,
      cog: cog,
    )
    
    trackPoints.append(trackPoint)
    if trackPoints.count > Configuration.maxTrackPoints {
      trackPoints.removeFirst()
    }
    
    if let sessionId = currentSessionId {
      let record = TrackPointRecord(domainModel: trackPoint, sessionId: sessionId)
      writeBuffer.append(record)
      
      if writeBuffer.count >= Configuration.flushThreshold {
        flushBuffer()
      }
    }
  }
  
  private func stopSavingState() {
    state = .idle
  }
  
  private func startFlushTimer() {
    flushTask?.cancel()
    let task = Task { [weak self] in
      // No need for @MainActor since TrackRecordingService is @MainActor.
      try? await Task.sleep(for: Configuration.maxFlushInterval)
      guard !Task.isCancelled, let self else { return }
      self.flushBuffer()
    }
    flushTask = TaskCancellable(task)
  }
  
  private func buildCurrentSessionRecord() -> TrackSessionRecord? {
    guard let sessionId = currentSessionId, let startTime = sessionStartTime else { return nil }
    
    var record = TrackSessionRecord(id: sessionId, startTime: startTime)
    
    if let duration = activeSessionDuration() {
      let totalSeconds = Double(duration.components.seconds) + (Double(duration.components.attoseconds) / 1e18)
      record.duration_s = totalSeconds
    }
    
    if let distance = sessionDistance {
      record.totalDistance_m = distance.converted(to: .meters).value
    }
    
    record.minLatitude_deg = minLatitude?.converted(to: .degrees).value
    record.maxLatitude_deg = maxLatitude?.converted(to: .degrees).value
    record.minLongitude_deg = minLongitude?.converted(to: .degrees).value
    record.maxLongitude_deg = maxLongitude?.converted(to: .degrees).value
    record.maxSpeed_mps = maxSpeedOverGround?.converted(to: .metersPerSecond).value
    record.pointsCount = pointsCount
    record.segmentCount = segmentIndex + 1
    
    return record
  }
}

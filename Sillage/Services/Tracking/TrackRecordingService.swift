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
  public private(set) var currentSegmentStartTime: Date?
  public private(set) var currentSegmentMonotonicStartTime: ContinuousClock.Instant?
  public private(set) var sessionDistance: Measurement<UnitLength>?
  public private(set) var sessionDuration: Duration?
  
  public private(set) var minLatitude: Measurement<UnitAngle>?
  public private(set) var maxLatitude: Measurement<UnitAngle>?
  public private(set) var minLongitude: Measurement<UnitAngle>?
  public private(set) var maxLongitude: Measurement<UnitAngle>?
  public private(set) var maxSpeed: Measurement<UnitSpeed>?
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
  private var lastRecordedLocation: CLLocation?
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
    case insertPoints([TrackPointRecord])
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
    Logger.telemetry.info("Track filters updated: \(newFilters.minDistanceMeters)m, \(newFilters.minTimeIntervalSeconds)s, \(newFilters.maxHorizontalAccuracyMeters)m accuracy")
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
    currentSegmentStartTime = nil
    currentSegmentMonotonicStartTime = nil
    sessionDuration = .seconds(0)
    sessionDistance = Measurement(value: 0, unit: UnitLength.meters)
    lastRecordedLocation = nil
    writeBuffer.removeAll()
    trackPoints.removeAll()
    minLatitude = nil
    maxLatitude = nil
    minLongitude = nil
    maxLongitude = nil
    maxSpeed = nil
    pointsCount = nil
    
    let service = self.locationService
    self.backgroundLocationToken = service.requestBackgroundLocation()
    
    startFlushTimer()
    
    locationUpdatesTask = TaskCancellable(Task { [weak self] in
      for await location in service.locationUpdates {
        guard !Task.isCancelled else { break }
        self?.processLocationUpdate(location)
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
            case .insertPoints(let points):
              try points.forEach { try $0.insert(db) }
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
          let endTime = lastRecordedLocation?.timestamp else {
      state = .idle
      return .abortedNoFix
    }
    
    switch state {
    case .recording, .waitingForFix:
      if let startTime = currentSegmentStartTime {
        let finalSegmentSeconds = endTime.timeIntervalSince(startTime)
        let previousDuration = sessionDuration ?? .seconds(0)
        sessionDuration = previousDuration + .seconds(finalSegmentSeconds)
      }
    case .paused, .idle, .saving:
      break
    }
    
    state = .saving
    
    let finalDurationSeconds = sessionDuration
    let finalDistanceMeters = sessionDistance
    let localMinLat = minLatitude
    let localMaxLat = maxLatitude
    let localMinLon = minLongitude
    let localMaxLon = maxLongitude
    let localMaxSpeed = maxSpeed
    let localPointsCount = pointsCount
    let localSegmentCount = segmentIndex + 1
    
    flushBuffer()
    dbActionContinuation?.finish()
    let localPersistenceTask = persistenceTask
    BackgroundTaskRunner.execute(name: "FinalizeTrack_\(sessionId)") { [weak self, databaseManager, localPersistenceTask] in
      _ = await localPersistenceTask?.value
      do {
        try await databaseManager.dbPool.write { db in
          if var session = try TrackSessionRecord.fetchOne(db, key: sessionId) {
            if let duration = finalDurationSeconds {
              let totalSeconds = Double(duration.components.seconds) + (Double(duration.components.attoseconds) / 1e18)
              session.duration_s = totalSeconds
            }
            if let distance = finalDistanceMeters {
              session.totalDistance_m = distance.converted(to: .meters).value
            }
            session.endTimestamp_unix = endTime.timeIntervalSince1970
            session.minLatitude_deg = localMinLat?.converted(to: .degrees).value
            session.maxLatitude_deg = localMaxLat?.converted(to: .degrees).value
            session.minLongitude_deg = localMinLon?.converted(to: .degrees).value
            session.maxLongitude_deg = localMaxLon?.converted(to: .degrees).value
            session.maxSpeed_mps = localMaxSpeed?.converted(to: .metersPerSecond).value
            session.pointsCount = localPointsCount
            session.segmentCount = localSegmentCount
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
    lastRecordedLocation = nil
    
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
    
    if let pauseTime = lastRecordedLocation?.timestamp,
       let startTime = currentSegmentStartTime {
      let segmentSeconds = pauseTime.timeIntervalSince(startTime)
      let previousDuration = sessionDuration ?? .seconds(0)
      sessionDuration = previousDuration + .seconds(segmentSeconds)
    }
    currentSegmentStartTime = nil
    currentSegmentMonotonicStartTime = nil
    
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
    currentSegmentStartTime = nil
    currentSegmentMonotonicStartTime = nil
    
    let service = self.locationService
    self.backgroundLocationToken = service.requestBackgroundLocation()
    
    startFlushTimer()
    
    locationUpdatesTask = TaskCancellable(Task { [weak self] in
      for await location in service.locationUpdates {
        guard !Task.isCancelled else { break }
        self?.processLocationUpdate(location)
      }
    })
    
    state = .waitingForFix
    Logger.telemetry.info("Track recording resumed (segment \(self.segmentIndex, privacy: .public)).")
  }
  
  public func activeSessionDuration() -> Duration? {
    guard let startInstant = currentSegmentMonotonicStartTime else {
      return sessionDuration
    }
    
    switch state {
    case .recording:
      let clock = ContinuousClock()
      let currentSegmentDuration = clock.now - startInstant
      let currentSessionDuration = sessionDuration ?? .seconds(0)
      return currentSessionDuration + currentSegmentDuration
    case .idle, .paused, .saving, .waitingForFix:
      return sessionDuration
    }
  }
  
  private func flushBuffer() {
    guard !writeBuffer.isEmpty else { return }
    let batch = writeBuffer
    writeBuffer.removeAll()
    dbActionContinuation?.yield(.insertPoints(batch))
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
    
    do {
      try await databaseManager.dbPool.write { db in
        try pointsToInsert.forEach { try $0.insert(db) }
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
  
  private func processLocationUpdate(_ location: CLLocation) {
    guard location.horizontalAccuracy >= 0 else { return }
    guard location.horizontalAccuracy <= filters.maxHorizontalAccuracyMeters else { return }
    
    switch state {
    case .waitingForFix:
      state = .recording
      
      if currentSessionId == nil {
        let sessionId = UUID().uuidString
        let startTime = location.timestamp
        
        currentSessionId = sessionId
        sessionStartTime = startTime
        currentSegmentStartTime = startTime
        
        let sessionRecord = TrackSessionRecord(id: sessionId, startTime: startTime)
        dbActionContinuation?.yield(.insertSession(sessionRecord))
      } else {
        currentSegmentStartTime = location.timestamp
      }
      currentSegmentMonotonicStartTime = .now

    case .idle, .recording, .paused, .saving:
      break
    }
    
    // Filtering Logic (Anti-Jitter)
    if let lastLoc = lastRecordedLocation {
      let distanceSinceLast = location.distance(from: lastLoc)
      let timeSinceLast = location.timestamp.timeIntervalSince(lastLoc.timestamp)
      
      let hasMovedSignificantly = distanceSinceLast > filters.minDistanceMeters
      let hasSufficientTimePassed = timeSinceLast > filters.minTimeIntervalSeconds
      
      guard hasMovedSignificantly || hasSufficientTimePassed else { return }
      
      // Update cumulative distance only with validated points to prevent GPS noise inflation
      if let currentDistance = sessionDistance {
        let distanceIncrement = Measurement(value: distanceSinceLast, unit: UnitLength.meters)
        sessionDistance = currentDistance + distanceIncrement
      }
    }
    
    lastRecordedLocation = location
    
    var sog: Measurement<UnitSpeed>? = nil
    if location.speed >= 0 {
      sog = Measurement(value: location.speed, unit: UnitSpeed.metersPerSecond)
    }
    
    var cog: Measurement<UnitAngle>? = nil
    if location.course >= 0 {
      cog = Measurement(value: location.course, unit: UnitAngle.degrees)
    }
    
    let horizontalAccuracy = Measurement(value: location.horizontalAccuracy, unit: UnitLength.meters)
    
    let lat = Measurement(value: location.coordinate.latitude, unit: UnitAngle.degrees)
    let lon = Measurement(value: location.coordinate.longitude, unit: UnitAngle.degrees)
    
    minLatitude = min(minLatitude ?? lat, lat)
    maxLatitude = max(maxLatitude ?? lat, lat)
    minLongitude = min(minLongitude ?? lon, lon)
    maxLongitude = max(maxLongitude ?? lon, lon)
    
    if location.speed >= 0 {
      let currentSpeed = Measurement(value: location.speed, unit: UnitSpeed.metersPerSecond)
      maxSpeed = max(maxSpeed ?? currentSpeed, currentSpeed)
    }
    
    pointsCount = (pointsCount ?? 0) + 1
    
    let trackPoint = TrackPoint(
      timestamp: location.timestamp,
      segmentIndex: segmentIndex,
      latitude: Measurement(value: location.coordinate.latitude, unit: .degrees),
      longitude: Measurement(value: location.coordinate.longitude, unit: .degrees),
      horizontalAccuracy: horizontalAccuracy,
      sog: sog,
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
}

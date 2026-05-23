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
  public private(set) var trackPoints: ArraySlice<TrackPoint> = []
  
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
  public private(set) var telemetry = TrackSessionTelemetry()
  
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
  private var unflushedPointCount: Int = 0
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
  
  private let positioningService: PositioningService
  private let databaseManager: DatabaseManager
  private var locationUpdatesTask: TaskCancellable?
  private var backgroundLocationToken: (any BackgroundLocationToken)?
  private var flushTask: TaskCancellable?
  
  private var persistenceWriter: TrackPersistenceWriter?
  
  init(
    filters: TrackFilters = .default,
    positioningService: PositioningService,
    databaseManager: DatabaseManager
  ) {
    self.filters = filters
    self.positioningService = positioningService
    self.databaseManager = databaseManager
  }
  
  public func updateFilters(_ newFilters: TrackFilters) {
    self.filters = newFilters
    Logger.telemetry.info("Track filters updated: \(newFilters.minDistance), \(newFilters.minTimeIntervalSeconds)s, \(newFilters.maxHorizontalAccuracy) accuracy")
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
    unflushedPointCount = 0
    telemetry.clear()
    trackPoints.removeAll()
    
    let service = self.positioningService
    self.backgroundLocationToken = service.requestBackgroundLocation()
    
    startFlushTimer()
    
    locationUpdatesTask = TaskCancellable(Task { [weak self] in
      for await navigationFix in service.locationUpdates {
        guard !Task.isCancelled, let self = self else { break }
        self.processLocationUpdate(navigationFix)
      }
    })
    
    persistenceWriter = TrackPersistenceWriter(databaseManager: databaseManager)
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
          let endTime = telemetry.lastRecordedNavigationFix?.timestamp else {
      state = .idle
      return .abortedNoFix
    }
    
    // Removed manual segment duration addition since it's now updated continuously in processLocationUpdate
    
    state = .saving
    
    let finalDurationSeconds = telemetry.sessionDuration
    let finalDistanceMeters = telemetry.sessionDistance
    let sessionUpdate = buildCurrentSessionRecord()
    
    let writerToFinish = persistenceWriter
    persistenceWriter = nil
    
    BackgroundTaskRunner.execute(name: "FinalizeTrack_\(sessionId)") { [weak self, writerToFinish] in
      if var session = sessionUpdate {
        session.endTimestamp_unix = endTime.timeIntervalSince1970
        await writerToFinish?.flush(sessionUpdate: session)
      }
      await writerToFinish?.finish()
      
      let durationStr = finalDurationSeconds.map { String(describing: $0) } ?? "nil"
      let distanceStr = finalDistanceMeters.map { String(describing:$0) } ?? "nil"
      Logger.database.info("Track session \(sessionId, privacy: .public) finalized successfully with \(durationStr, privacy: .public)s and \(distanceStr, privacy: .public)m.")
      await self?.stopSavingState()
    }
    
    currentSessionId = nil
    telemetry.clear()
    
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
    
    persistenceWriter?.flushAsync(sessionUpdate: buildCurrentSessionRecord())
    unflushedPointCount = 0
    
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
    telemetry.startNewSegment()
    
    let service = self.positioningService
    self.backgroundLocationToken = service.requestBackgroundLocation()
    
    startFlushTimer()
    
    locationUpdatesTask = TaskCancellable(Task { [weak self] in
      for await navigationFix in service.locationUpdates {
        guard !Task.isCancelled, let self = self else { break }
        self.processLocationUpdate(navigationFix)
      }
    })
    
    state = .waitingForFix
    Logger.telemetry.info("Track recording resumed (segment \(self.segmentIndex, privacy: .public)).")
  }
  
  public func activeSessionDuration() -> Duration? {
    return telemetry.activeDuration(isRecording: state == .recording)
  }
  
  public func emergencyFlushAsync() async {
    await persistenceWriter?.flush(sessionUpdate: buildCurrentSessionRecord())
    unflushedPointCount = 0
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
        telemetry.start(at: navigationFix)
        
        let sessionRecord = TrackSessionRecord(id: sessionId, startTime: startTime)
        persistenceWriter?.insertSession(sessionRecord)
      }
      
    case .idle, .recording, .paused, .saving:
      break
    }
    
    // Always update session time to reflect real-world progression regardless of movement
    telemetry.updateTime(with: navigationFix)
    
    // Filtering Logic (Anti-Jitter)
    guard telemetry.append(fix: navigationFix, filters: filters) else {
      return
    }
    
    let trackPoint = TrackPoint(
      timestamp: navigationFix.timestamp,
      segmentIndex: segmentIndex,
      latitude: Measurement(value: navigationFix.coordinate.latitude, unit: .degrees),
      longitude: Measurement(value: navigationFix.coordinate.longitude, unit: .degrees),
      horizontalAccuracy: navigationFix.horizontalAccuracy,
      speedOverGround: navigationFix.speedOverGround,
      courseOverGround: navigationFix.courseOverGround
    )
    
    trackPoints.append(trackPoint)
    if trackPoints.count > Configuration.maxTrackPoints {
      trackPoints.removeFirst()
    }
    
    if let sessionId = currentSessionId {
      let record = TrackPointRecord(domainModel: trackPoint, sessionId: sessionId)
      persistenceWriter?.appendPoint(record)
      
      unflushedPointCount += 1
      if unflushedPointCount >= Configuration.flushThreshold {
        persistenceWriter?.flushAsync(sessionUpdate: buildCurrentSessionRecord())
        unflushedPointCount = 0
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
      while !Task.isCancelled {
        try? await Task.sleep(for: Configuration.maxFlushInterval)
        guard !Task.isCancelled, let self = self else { break }
        
        self.persistenceWriter?.flushAsync(sessionUpdate: self.buildCurrentSessionRecord())
        self.unflushedPointCount = 0
      }
    }
    flushTask = TaskCancellable(task)
  }
  
  private func buildCurrentSessionRecord() -> TrackSessionRecord? {
    guard let sessionId = currentSessionId, let startTime = telemetry.sessionStartTime else { return nil }
    
    var record = TrackSessionRecord(id: sessionId, startTime: startTime)
    
    if let duration = activeSessionDuration() {
      let totalSeconds = Double(duration.components.seconds) + (Double(duration.components.attoseconds) / 1e18)
      record.duration_s = totalSeconds
    }
    
    if let distance = telemetry.sessionDistance {
      record.totalDistance_m = distance.converted(to: .meters).value
    }
    
    record.minLatitude_deg = telemetry.minLatitude?.converted(to: .degrees).value
    record.maxLatitude_deg = telemetry.maxLatitude?.converted(to: .degrees).value
    record.minLongitude_deg = telemetry.minLongitude?.converted(to: .degrees).value
    record.maxLongitude_deg = telemetry.maxLongitude?.converted(to: .degrees).value
    record.maxSpeed_mps = telemetry.maxSpeedOverGround?.converted(to: .metersPerSecond).value
    record.pointsCount = telemetry.pointsCount
    record.segmentCount = segmentIndex + 1
    
    return record
  }
}

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
    nonisolated static let maxRecoveryAge: TimeInterval = 12 * 3600
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
  private let preferencesService: PreferencesServiceProtocol
  
  init(
    filters: TrackFilters = .default,
    positioningService: PositioningService,
    databaseManager: DatabaseManager,
    preferencesService: PreferencesServiceProtocol
  ) {
    self.filters = filters
    self.positioningService = positioningService
    self.databaseManager = databaseManager
    self.preferencesService = preferencesService
  }
  
  public func updateFilters(_ newFilters: TrackFilters) {
    self.filters = newFilters
    Logger.database.info("Track filters updated: \(newFilters.minDistance), \(newFilters.minTimeIntervalSeconds)s, \(newFilters.maxHorizontalAccuracy) accuracy")
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
    telemetry.start()
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
    
    if let lastNavigationFix = telemetry.stop() {
      self.saveNavigationFix(lastNavigationFix)
    }
    
    guard let sessionId = currentSessionId,
          let endTime = telemetry.lastRecordedNavigationFix?.timestamp else {
      state = .idle
      return .abortedNoFix
    }
    
    // Removed manual segment duration addition since it's now updated continuously in processLocationUpdate
    
    state = .saving
    
    let finalDurationSeconds = telemetry.duration
    let finalDistanceMeters = telemetry.distance
    let telemetryUpdate = buildTelemetryUpdate(endTime: endTime)
    
    let writerToFinish = persistenceWriter
    persistenceWriter = nil
    
    BackgroundTaskRunner.execute(name: "FinalizeTrack_\(sessionId)") { [weak self, writerToFinish] in
      if let update = telemetryUpdate {
        await writerToFinish?.flush(telemetryUpdate: update)
      }
      await writerToFinish?.finish()
      
      let durationStr = finalDurationSeconds.map { String(describing: $0) } ?? "nil"
      let distanceStr = finalDistanceMeters.map { String(describing:$0) } ?? "nil"
      Logger.database.info("Track session \(sessionId, privacy: .public) finalized successfully with \(durationStr, privacy: .public)s and \(distanceStr, privacy: .public)m.")
      await self?.stopSavingState()
    }
    
    currentSessionId = nil
    preferencesService.clearActiveTrackSessionID()
    
    return .savedAsync(sessionId: sessionId)
  }
  
  public func pauseRecording() {
    switch state {
    case .recording, .waitingForFix:
      break
    case .idle, .paused, .saving:
      return
    }
    
    telemetry.pause()
    locationUpdatesTask?.cancel()
    locationUpdatesTask = nil
    backgroundLocationToken = nil
    flushTask?.cancel()
    flushTask = nil
    
    persistenceWriter?.flushAsync(telemetryUpdate: buildTelemetryUpdate())
    unflushedPointCount = 0
    
    state = .paused
    Logger.database.info("Track recording paused.")
  }
  
  public func resumeRecording() {
    switch state {
    case .paused:
      break
    case .idle, .recording, .waitingForFix, .saving:
      return
    }
    
    segmentIndex += 1
    
    telemetry.resume()
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
    Logger.database.info("Track recording resumed (segment \(self.segmentIndex, privacy: .public)).")
  }
  
  public func activeSessionDuration() -> Duration? {
    return telemetry.activeDuration()
  }

  /// Checks if a session is currently actively recording or paused.
  /// - Parameter sessionId: The ID of the session to check.
  /// - Returns: True if the session is currently active.
  public func isSessionActive(_ sessionId: String) -> Bool {
    return (state != .idle && state != .saving) && currentSessionId == sessionId
  }
  
  public func emergencyFlushAsync() async {
    await persistenceWriter?.flush(telemetryUpdate: buildTelemetryUpdate())
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
  
  public func attemptRecoveryIfNeeded() async {
    let activeId = preferencesService.activeTrackSessionID
    
    // 1. Sanitize ONLY what is NOT the active session
    do {
      try await databaseManager.sanitizeUnfinishedSessions(excluding: activeId)
      Logger.database.info("Sanitized ghost tracks successfully.")
    } catch {
      Logger.database.error("Failed to sanitize ghost tracks: \(error.localizedDescription)")
    }
    
    // 2. Resume activef session
    await resumeTrackIfPossible(sessionId: activeId)
  }
  
  // MARK: - Private
  
  private func resumeTrackIfPossible(sessionId: String?) async {
    guard let sessionId = sessionId else { return }
    do {
      let trackSession = try await databaseManager.reader.read { db in
        try TrackSessionRecord.fetchOne(db, key: sessionId)?.toDomain()
      }
      
      guard let validTrackSession = trackSession else {
        preferencesService.clearActiveTrackSessionID()
        return
      }
      
      // 1. Find the true last update time (last point recorded in DB)
      let lastPointDate = try await databaseManager.fetchLastPointTime(for: sessionId)
      let lastUpdate = lastPointDate ?? validTrackSession.startTime
      // 2. Evaluate age
      let age = abs(Date().timeIntervalSince(lastUpdate))
      if age > Configuration.maxRecoveryAge {
        Logger.database.warning("Track \(sessionId, privacy: .public) is too old (\(age)s). Forcing closure.")
        // 3. Critial: Close it in DB immediately by running a sanitize with NO exclusion
        try await databaseManager.sanitizeUnfinishedSessions(excluding: nil)
        preferencesService.clearActiveTrackSessionID()
        return
      }
      
      // 4. Recover the session
      try await self.recoverRecording(trackSession: validTrackSession)
      
    } catch {
      Logger.database.error("Failed to read db for restore: \(error.localizedDescription)")
      preferencesService.clearActiveTrackSessionID()
    }
  }
  
  private func recoverRecording(trackSession: TrackSession) async throws {
    guard state == .idle else { return }
    currentSessionId = trackSession.id
    
    // 1. Fetch all async data BEFORE starting the engine
    let lastSegmentIndex = try await databaseManager.fetchMaxSegmentIndex(for: trackSession.id)
    let previousPoints = try await databaseManager.fetchRecentPoints(for: trackSession.id, limit: Configuration.maxTrackPoints)
    
    // 2. Setup internal state
    // Start a new segment.
    segmentIndex = (lastSegmentIndex ?? 0) + 1
    telemetry.restore(from: trackSession)
    trackPoints = ArraySlice(previousPoints)
    
    // 3. Setup dependencies
    persistenceWriter = TrackPersistenceWriter(databaseManager: databaseManager)
    
    // 4. Start the engine (No 'await' beyond this point to avoid race conditions)
    let service = positioningService
    backgroundLocationToken = service.requestBackgroundLocation()
    startFlushTimer()
    locationUpdatesTask = TaskCancellable(Task { [weak self] in
      for await navigationFix in service.locationUpdates {
        guard !Task.isCancelled, let self = self else { break }
        self.processLocationUpdate(navigationFix)
      }
    })
    
    state = .waitingForFix
    Logger.database.info("Restored session \(trackSession.id, privacy: .public) at segment \(self.segmentIndex).")
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
        preferencesService.saveActiveTrackSessionID(sessionId)
        
        let sessionRecord = TrackSessionRecord(id: sessionId, startTime: startTime)
        persistenceWriter?.insertSession(sessionRecord)
      }
      
    case .idle, .recording, .paused, .saving:
      break
    }
    
    // Update session with filtering Logic (Anti-Jitter)
    guard telemetry.process(fix: navigationFix, filters: filters) else {
      return
    }
    saveNavigationFix(navigationFix)
  }
  
  private func saveNavigationFix(_ navigationFix: NavigationFix) {
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
        persistenceWriter?.flushAsync(telemetryUpdate: buildTelemetryUpdate())
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
        
        self.persistenceWriter?.flushAsync(telemetryUpdate: self.buildTelemetryUpdate())
        self.unflushedPointCount = 0
      }
    }
    flushTask = TaskCancellable(task)
  }
  
  private func buildTelemetryUpdate(endTime: Date? = nil) -> TrackTelemetryUpdate? {
    guard let sessionId = currentSessionId else { return nil }
    
    let finalEndTime = endTime ?? telemetry.lastRecordedNavigationFix?.timestamp
    
    return TrackTelemetryUpdate(
      id: sessionId,
      endTimestamp_unix: finalEndTime?.timeIntervalSince1970,
      duration_s: activeSessionDuration()?.timeInterval,
      totalDistance_m: telemetry.distance?.converted(to: .meters).value,
      southLatitude_deg: telemetry.geographicBoundingBox?.southLatitude.converted(to: .degrees).value,
      northLatitude_deg: telemetry.geographicBoundingBox?.northLatitude.converted(to: .degrees).value,
      westLongitude_deg: telemetry.geographicBoundingBox?.westLongitude.converted(to: .degrees).value,
      eastLongitude_deg: telemetry.geographicBoundingBox?.eastLongitude.converted(to: .degrees).value,
      maxSpeed_mps: telemetry.maxSpeedOverGround?.converted(to: .metersPerSecond).value,
      pointsCount: telemetry.pointsCount,
      segmentCount: segmentIndex + 1
    )
  }
}

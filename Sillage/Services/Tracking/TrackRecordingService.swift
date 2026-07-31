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
  
  private var currentSessionID: String?
  private var unflushedPointCount: Int = 0
  private var filters: TrackFilters
  
  public enum TrackRecordingError: LocalizedError {
    case databaseUnavailable
    case abortedNoFix
    case noActiveRecording
    case operationInProgress
    
    public var errorDescription: String? {
      switch self {
      case .databaseUnavailable:
        return "Database is unavailable. Recording cannot start."
      case .abortedNoFix:
        return String(localized: "Recording aborted. No GPS fix was obtained.")
      case .noActiveRecording:
        return String(localized: "No active recording to stop.")
      case .operationInProgress:
        return String(localized: "Operation in progress. Please wait.")
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
  private let messageService: MessageService
  
  init(
    filters: TrackFilters = .default,
    positioningService: PositioningService,
    databaseManager: DatabaseManager,
    preferencesService: PreferencesServiceProtocol,
    messageService: MessageService
  ) {
    self.filters = filters
    self.positioningService = positioningService
    self.databaseManager = databaseManager
    self.preferencesService = preferencesService
    self.messageService = messageService
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
    
    currentSessionID = nil
    unflushedPointCount = 0
    telemetry.start()
    trackPoints.removeAll()
    
    let service = self.positioningService
    self.backgroundLocationToken = service.requestBackgroundLocation()
    service.requestDistanceFilter(Measurement(value: 5, unit: .meters), for: "TrackRecording")
    
    startFlushTimer()
    
    subscribeToLocationUpdates()
    
    persistenceWriter = TrackPersistenceWriter(databaseManager: databaseManager)
    state = .waitingForFix
  }
  
  @discardableResult
  public func stopRecording() async throws -> String {
    switch state {
    case .recording, .paused, .waitingForFix:
      break
    case .idle, .saving:
      throw TrackRecordingError.noActiveRecording
    }
    locationUpdatesTask?.cancel()
    locationUpdatesTask = nil
    backgroundLocationToken?.invalidate()
    backgroundLocationToken = nil
    flushTask?.cancel()
    flushTask = nil
    
    positioningService.removeDistanceFilter(for: "TrackRecording")
    
    if let lastNavigationFix = telemetry.stop() {
      self.saveNavigationFix(lastNavigationFix)
    }
    
    guard let sessionID = currentSessionID,
          let endTime = telemetry.lastRecordedNavigationFix?.timestamp else {
      state = .idle
      throw TrackRecordingError.abortedNoFix
    }
    
    // Removed manual segment duration addition since it's now updated continuously in processLocationUpdate
    
    state = .saving
    
    let finalDurationSeconds = telemetry.totalDuration
    let finalDistanceMeters = telemetry.totalDistanceOverGround
    let telemetryUpdate = buildTelemetryUpdate(endTime: endTime)
    
    let writerToFinish = persistenceWriter
    persistenceWriter = nil
    
    await BackgroundTaskRunner.executeAndWait(name: "FinalizeTrack_\(sessionID)") { [weak self, writerToFinish] in
      if let update = telemetryUpdate {
        await writerToFinish?.flush(telemetryUpdate: update)
      }
      await writerToFinish?.finish()
      
      let durationStr = finalDurationSeconds.map { String(describing: $0) } ?? "nil"
      let distanceStr = finalDistanceMeters.map { String(describing:$0) } ?? "nil"
      Logger.database.info("Track session \(sessionID, privacy: .public) finalized successfully with \(durationStr, privacy: .public)s and \(distanceStr, privacy: .public)m.")
      await self?.stopSavingState()
    }
    
    currentSessionID = nil
    preferencesService.clearActiveTrackSessionID()
    
    return sessionID
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
    backgroundLocationToken?.invalidate()
    backgroundLocationToken = nil
    flushTask?.cancel()
    flushTask = nil
    
    positioningService.removeDistanceFilter(for: "TrackRecording")
    
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
    
    telemetry.resume()
    let service = self.positioningService
    self.backgroundLocationToken = service.requestBackgroundLocation()
    service.requestDistanceFilter(Measurement(value: 5, unit: .meters), for: "TrackRecording")
    
    startFlushTimer()
    
    subscribeToLocationUpdates()
    
    state = .waitingForFix
    Logger.database.info("Track recording resumed (segment \(self.telemetry.segmentIndex ?? 0, privacy: .public)).")
  }
  
  public func activeSessionDuration() -> Duration? {
    return telemetry.activeTotalDuration()
  }
  
  /// Checks if a session is currently actively recording or paused.
  /// - Parameter sessionID: The ID of the session to check.
  /// - Returns: True if the session is currently active.
  public func isSessionActive(_ sessionID: String) -> Bool {
    return (state != .idle && state != .saving) && currentSessionID == sessionID
  }
  
  public func emergencyFlushAsync() async {
    await persistenceWriter?.flush(telemetryUpdate: buildTelemetryUpdate())
    unflushedPointCount = 0
  }
  
  @discardableResult
  public func toggleRecording() async throws -> String? {
    switch state {
    case .recording, .paused, .waitingForFix:
      return try await stopRecording()
    case .idle:
      startRecording()
      return nil
    case .saving:
      throw TrackRecordingError.operationInProgress
    }
  }
  
  public func attemptRecoveryIfNeeded() async {
    let activeID = preferencesService.activeTrackSessionID
    
    // 1. Sanitize ONLY what is NOT the active session
    do {
      try await databaseManager.sanitizeUnfinishedSessions(excluding: activeID)
      Logger.database.info("Sanitized ghost tracks successfully.")
    } catch {
      Logger.database.error("Failed to sanitize ghost tracks: \(error.localizedDescription)")
    }
    
    // 2. Resume activef session
    await resumeTrackIfPossible(sessionID: activeID)
  }
  
  // MARK: - Private
  
  private func resumeTrackIfPossible(sessionID: String?) async {
    guard let sessionID = sessionID else { return }
    do {
      let trackSession = try await databaseManager.reader.read { db in
        try TrackSessionRecord.fetchOne(db, key: sessionID)?.toDomain()
      }
      
      guard let validTrackSession = trackSession else {
        preferencesService.clearActiveTrackSessionID()
        return
      }
      
      // 1. Find the true last update time (last point recorded in DB)
      let lastPointDate = try await databaseManager.fetchLastPointTime(for: sessionID)
      let lastUpdate = lastPointDate ?? validTrackSession.startTime
      // 2. Evaluate age
      let age = abs(Date().timeIntervalSince(lastUpdate))
      if age > Configuration.maxRecoveryAge {
        Logger.database.warning("Track \(sessionID, privacy: .public) is too old (\(age)s). Forcing closure.")
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
    currentSessionID = trackSession.id
    
    // 1. Fetch all async data BEFORE starting the engine
    let lastSegmentIndex = try await databaseManager.fetchMaxSegmentIndex(for: trackSession.id)
    let previousPoints = try await databaseManager.fetchRecentPoints(for: trackSession.id, limit: Configuration.maxTrackPoints)
    
    // 2. Setup internal state
    telemetry.restore(from: trackSession, lastSegmentIndex: lastSegmentIndex)
    trackPoints = ArraySlice(previousPoints)
    
    // 3. Setup dependencies
    persistenceWriter = TrackPersistenceWriter(databaseManager: databaseManager)
    
    // 4. Start the engine (No 'await' beyond this point to avoid race conditions)
    let service = positioningService
    backgroundLocationToken = service.requestBackgroundLocation()
    service.requestDistanceFilter(Measurement(value: 5, unit: .meters), for: "TrackRecording")
    startFlushTimer()
    subscribeToLocationUpdates()
    
    state = .waitingForFix
    Logger.database.info("Restored session \(trackSession.id, privacy: .public) at segment \(self.telemetry.segmentIndex ?? 0).")
  }
  
  private func subscribeToLocationUpdates() {
    locationUpdatesTask?.cancel()
    let service = positioningService
    locationUpdatesTask = TaskCancellable(Task { @MainActor [weak self] in
      for await state in service.locationUpdates {
        guard !Task.isCancelled, let self = self else { break }
        switch state {
        case .active(let fix), .degraded(let fix):
          self.processLocationUpdate(fix)
        case .lost:
          break
        }
      }
    })
  }
  
  private func processLocationUpdate(_ navigationFix: NavigationFix) {
    guard navigationFix.horizontalAccuracy <= filters.maxHorizontalAccuracy else {
      if let accuracy = navigationFix.horizontalAccuracy {
        Logger.database.debug("GPS point ignored: insufficient accuracy (\(accuracy.converted(to: .meters).value, format: .fixed(precision: 1))m)")
      }
      return
    }
    
    switch state {
    case .waitingForFix:
      state = .recording
      
      if currentSessionID == nil {
        let sessionID = UUID().uuidString
        let startTime = navigationFix.timestamp
        
        currentSessionID = sessionID
        preferencesService.saveActiveTrackSessionID(sessionID)
        
        let sessionRecord = TrackSessionRecord(id: sessionID, startTime: startTime)
        persistenceWriter?.insertSession(sessionRecord)
      }
      
    case .idle, .recording, .paused, .saving:
      break
    }
    
    // Update session with filtering Logic (Anti-Jitter)
    do {
      try telemetry.process(fix: navigationFix, filters: filters)
      saveNavigationFix(navigationFix)
    } catch TrackSessionTelemetry.ProcessError.filteredOut {
      return
    } catch {
      Logger.database.error("Failed to process navigation fix: \(String(describing: error), privacy: .public)")
      return
    }
  }
  
  private func saveNavigationFix(_ navigationFix: NavigationFix) {
    let trackPoint = TrackPoint(
      timestamp: navigationFix.timestamp,
      segmentIndex: telemetry.segmentIndex ?? 0,
      coordinate: navigationFix.coordinate,
      horizontalAccuracy: navigationFix.horizontalAccuracy,
      speedOverGround: navigationFix.speedOverGround,
      courseOverGround: navigationFix.courseOverGround
    )
    
    trackPoints.append(trackPoint)
    if trackPoints.count > Configuration.maxTrackPoints {
      trackPoints.removeFirst()
    }
    
    if let sessionID = currentSessionID {
      let record = TrackPointRecord(domainModel: trackPoint, sessionID: sessionID)
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
    guard let sessionID = currentSessionID else { return nil }
    
    let finalEndTime = endTime ?? telemetry.lastRecordedNavigationFix?.timestamp
    
    return TrackTelemetryUpdate(
      id: sessionID,
      endTimestamp_unix: finalEndTime?.timeIntervalSince1970,
      totalDuration_s: activeSessionDuration()?.timeInterval,
      totalDistanceOverGround_m: telemetry.totalDistanceOverGround?.converted(to: .meters).value,
      southLatitude_deg: telemetry.geographicBoundingBox?.southWest.latitude,
      northLatitude_deg: telemetry.geographicBoundingBox?.northEast.latitude,
      westLongitude_deg: telemetry.geographicBoundingBox?.southWest.longitude,
      eastLongitude_deg: telemetry.geographicBoundingBox?.northEast.longitude,
      maxSpeedOverGround_mps: telemetry.maxSpeedOverGround?.converted(to: .metersPerSecond).value,
      segmentCount: telemetry.segmentIndex.map { $0 + 1 } ?? 0,
      totalPointCount: telemetry.totalPointCount
    )
  }
}

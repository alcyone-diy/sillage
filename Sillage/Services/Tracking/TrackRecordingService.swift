//
//  TrackRecordingService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-03.
//  Copyright © 2026 Alcyone. All rights reserved.
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

  public private(set) var isRecording: Bool = false
  public private(set) var isSaving: Bool = false
  public var recordingError: TrackRecordingError?

  /// Centralized configuration for the track recording service logic.
  internal struct Configuration {
    /// Thresholds for memory management and database persistence.
    internal struct RAMManagement {
      /// The number of points buffered in memory before a batch commit to the database.
      nonisolated static let flushThreshold = 20
      /// The maximum number of points held in memory for real-time map rendering.
      nonisolated static let maxTrackPoints = 2000
    }
    
    /// Constants for file system operations and GPX serialization.
    internal struct Export {
      /// The sub-directory name within the Documents folder dedicated to track storage.
      nonisolated static let directoryName = "Tracks"
      /// The date format used for generating timestamped, unique file names.
      nonisolated static let dateFormat = "yyyyMMdd_HHmm"
      /// The branding suffix appended to every exported GPX file name.
      nonisolated static let filenameSuffix = "_Sillage"
    }
  }

  private var currentSessionId: String?
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
  private var databaseManager: DatabaseManager?
  private var locationUpdatesTask: TaskCancellable?
  private var backgroundLocationToken: (any BackgroundLocationToken)?
  private var flushContinuation: AsyncStream<[TrackPointRecord]>.Continuation?
  private var persistenceTask: Task<Void, Never>?

  init(filters: TrackFilters = .default, locationService: LocationServiceProtocol? = nil, databaseManager: DatabaseManager? = nil) {
    self.filters = filters
    self.locationService = locationService ?? LocationService.shared
    self.databaseManager = databaseManager
  }

  public func updateFilters(_ newFilters: TrackFilters) {
    self.filters = newFilters
    Logger.telemetry.info("Track filters updated: \(newFilters.minDistanceMeters)m, \(newFilters.minTimeIntervalSeconds)s, \(newFilters.maxHorizontalAccuracyMeters)m accuracy")
  }

  public func inject(databaseManager: DatabaseManager) {
    self.databaseManager = databaseManager
  }

  public func startRecording() throws {
    guard !isRecording && !isSaving else { return }
    guard let dbManager = databaseManager else {
      throw TrackRecordingError.databaseUnavailable
    }
    
    let sessionId = UUID().uuidString
    currentSessionId = sessionId
    lastRecordedLocation = nil
    writeBuffer.removeAll()
    trackPoints.removeAll()
    
    let sessionRecord = TrackSessionRecord(id: sessionId, startTime: Date())
    Task.detached(priority: .utility) { [dbManager] in
      do {
        try await dbManager.dbPool.write { db in
          try sessionRecord.insert(db)
        }
      } catch {
        Logger.database.error("Failed to insert session: \(error)")
      }
    }
    
    let service = self.locationService
    self.backgroundLocationToken = service.requestBackgroundLocation()
    
    locationUpdatesTask = TaskCancellable(Task { [weak self] in
      for await location in service.locationUpdates {
        guard !Task.isCancelled else { break }
        self?.append(location: location)
      }
    })

    let (stream, continuation) = AsyncStream.makeStream(of: [TrackPointRecord].self)
    self.flushContinuation = continuation
    self.persistenceTask = Task.detached(priority: .utility) { [dbManager] in
      for await batch in stream {
        do {
          try await dbManager.dbPool.write { db in
            try batch.forEach { try $0.insert(db) }
          }
        } catch {
          Logger.database.error("Failed to insert batch: \(error.localizedDescription, privacy: .public)")
        }
      }
    }
    
    self.isRecording = true
  }

  public func stopRecording() {
    locationUpdatesTask?.cancel()
    locationUpdatesTask = nil
    backgroundLocationToken = nil
    isRecording = false
    isSaving = true

    if let sessionId = currentSessionId, let dbManager = databaseManager {
      let endTime = Date()
      flushBuffer()
      flushContinuation?.finish()
      Task.detached(priority: .utility) { [weak self, dbManager] in
        await self?.persistenceTask?.value
        do {
          try await dbManager.dbPool.write { db in
            if var session = try TrackSessionRecord.fetchOne(db, key: sessionId) {
              session.endTime = endTime
              try session.update(db)
            }
          }
          try await Self.runExport(sessionId: sessionId, dbManager: dbManager)
        } catch {
          Logger.database.error("Finalization failed: \(error.localizedDescription, privacy: .public)")
        }
        await self?.stopSavingState()
      }
    }

    currentSessionId = nil
    lastRecordedLocation = nil
  }

  private func flushBuffer() {
    guard !writeBuffer.isEmpty else { return }
    let batch = writeBuffer
    writeBuffer.removeAll()
    flushContinuation?.yield(batch)
  }
  
  public func emergencyFlushAsync() async {
    guard !writeBuffer.isEmpty, let dbManager = databaseManager else { return }
    let pointsToInsert = writeBuffer
    writeBuffer.removeAll()

    do {
      try await dbManager.dbPool.write { db in
        try pointsToInsert.forEach { try $0.insert(db) }
      }
      Logger.database.info("Emergency flush successful: \(pointsToInsert.count) points saved.")
    } catch {
      Logger.database.error("Emergency flush failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  public func toggleRecording() {
    if isRecording {
      stopRecording()
    } else {
      do {
        try startRecording()
      } catch let error as TrackRecordingError {
        self.recordingError = error
        Logger.telemetry.error("Track recording error: \(error.localizedDescription, privacy: .public)")
      } catch {
        Logger.telemetry.error("Unhandled track recording error: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  private nonisolated static func runExport(sessionId: String, dbManager: DatabaseManager) async throws {
    do {
      let startedAt: Date = try await dbManager.dbPool.read { db in
        if let session = try TrackSessionRecord.fetchOne(db, key: sessionId) {
          return session.startTime
        }
        return Date()
      }
      
      guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
      
      let tracksDirectory = documentsDirectory.appendingPathComponent(Configuration.Export.directoryName, isDirectory: true)
      if !FileManager.default.fileExists(atPath: tracksDirectory.path) {
        try FileManager.default.createDirectory(at: tracksDirectory, withIntermediateDirectories: true, attributes: nil)
      }
      
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.dateFormat = Configuration.Export.dateFormat
      let dateString = formatter.string(from: startedAt)
      let baseFilename = "\(dateString)\(Configuration.Export.filenameSuffix)"
      
      var fileURL = tracksDirectory.appendingPathComponent("\(baseFilename).gpx")
      var counter = 1
      while FileManager.default.fileExists(atPath: fileURL.path) {
        fileURL = tracksDirectory.appendingPathComponent("\(baseFilename)_\(counter).gpx")
        counter += 1
      }
      let finalFileURL = fileURL
      
      Logger.storage.info("Starting GPX export for session \(sessionId, privacy: .public)")
      
      let count = try await dbManager.dbPool.read { db in
        let cursor = try TrackPointRecord.filter(Column("sessionId") == sessionId).order(Column("timestamp")).fetchCursor(db)
        return try GPXExportService.export(cursor: cursor, to: finalFileURL)
      }
      
      Logger.storage.info("Successfully exported \(count) points to \(finalFileURL.path, privacy: .public)")
    } catch {
      Logger.database.fault("GPX export failed: \(error.localizedDescription, privacy: .public)")
      throw error
    }
  }

  private func append(location: CLLocation) {
    guard location.horizontalAccuracy >= 0 else { return }
    guard location.horizontalAccuracy <= filters.maxHorizontalAccuracyMeters else { return }

    // Filtering Logic (Anti-Jitter)
    if let lastLoc = lastRecordedLocation {
      let hasMovedSignificantly = location.distance(from: lastLoc) > filters.minDistanceMeters
      let hasSufficientTimePassed = location.timestamp.timeIntervalSince(lastLoc.timestamp) > filters.minTimeIntervalSeconds
      
      guard hasMovedSignificantly || hasSufficientTimePassed else { return }
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

    var accuracy: Measurement<UnitLength>? = nil
    if location.horizontalAccuracy >= 0 {
      accuracy = Measurement(value: location.horizontalAccuracy, unit: UnitLength.meters)
    }

    let trackPoint = TrackPoint(
      latitude: location.coordinate.latitude,
      longitude: location.coordinate.longitude,
      timestamp: location.timestamp,
      sog: sog,
      cog: cog,
      accuracy: accuracy
    )

    trackPoints.append(trackPoint)
    if trackPoints.count > Configuration.RAMManagement.maxTrackPoints {
      trackPoints.removeFirst()
    }
    
    if let sessionId = currentSessionId {
      let record = TrackPointRecord(domainModel: trackPoint, sessionId: sessionId)
      writeBuffer.append(record)
      
      if writeBuffer.count >= Configuration.RAMManagement.flushThreshold {
        flushBuffer()
      }
    }
  }

  @MainActor
  private func stopSavingState() {
    self.isSaving = false
  }
}

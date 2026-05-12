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

  private var currentSessionId: String?
  private var writeBuffer: [TrackPointRecord] = []
  private let flushThreshold = 20
  private var lastRecordedLocation: CLLocation?

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

  init(locationService: LocationServiceProtocol? = nil, databaseManager: DatabaseManager? = nil) {
    self.locationService = locationService ?? LocationService.shared
    self.databaseManager = databaseManager
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
    
    self.isRecording = true
  }

  public func stopRecording() {
    locationUpdatesTask?.cancel()
    locationUpdatesTask = nil
    self.backgroundLocationToken = nil
    self.isRecording = false
    isSaving = true

    if !writeBuffer.isEmpty {
      Logger.database.info("Performing final buffer flush on stop")
      flushBuffer()
    }

    if let sessionId = currentSessionId, let dbManager = databaseManager {
      let endTime = Date()
      let pointsToFlush = writeBuffer
      writeBuffer.removeAll()
      Task.detached(priority: .utility) {
        do {
          try await dbManager.dbPool.write { db in
            for record in pointsToFlush { try record.insert(db) }
            if var session = try TrackSessionRecord.fetchOne(db, key: sessionId) {
              session.endTime = endTime
              try session.update(db)
            }
          }
          try await Self.runExport(sessionId: sessionId, dbManager: dbManager)
        } catch {
          Logger.database.error("Failed to finalize session record or export: \(error.localizedDescription, privacy: .public)")
        }
        await self.stopSavingState()
      }
    }

    currentSessionId = nil
    lastRecordedLocation = nil
  }

  public func clearActiveTrack() {
    trackPoints.removeAll()
  }

  private func flushBuffer() {
    guard !writeBuffer.isEmpty else { return }
    guard let dbManager = databaseManager else {
      Logger.database.fault("DatabaseManager is nil during flushBuffer")
      return
    }
    
    let pointsToInsert = writeBuffer
    writeBuffer.removeAll()
    
    Task.detached(priority: .utility) {
      do {
        try await dbManager.dbPool.write { db in
          try pointsToInsert.forEach { try $0.insert(db) }
        }
        Logger.database.info("Successfully flushed \(pointsToInsert.count) points to disk.")
      } catch {
        Logger.database.error("Failed to flush points: \(error)")
      }
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
      
      let tracksDirectory = documentsDirectory.appendingPathComponent("Tracks", isDirectory: true)
      if !FileManager.default.fileExists(atPath: tracksDirectory.path) {
        try FileManager.default.createDirectory(at: tracksDirectory, withIntermediateDirectories: true, attributes: nil)
      }
      
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.dateFormat = "yyyyMMdd_HHmm"
      let dateString = formatter.string(from: startedAt)
      let baseFilename = "\(dateString)_Sillage"
      
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
    let accuracy = Measurement(value: location.horizontalAccuracy, unit: UnitLength.meters)
    guard accuracy.value >= 0, accuracy.value <= 50 else { return }

    // Filtering Logic (Anti-Jitter)
    if let lastLoc = lastRecordedLocation {
      let distance = Measurement(value: location.distance(from: lastLoc), unit: UnitLength.meters)
      let timePassed = location.timestamp.timeIntervalSince(lastLoc.timestamp)
      
      let hasMovedSignificantly = distance.value > 3.0
      let hasSufficientTimePassed = timePassed > 30.0
      
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

    let trackPoint = TrackPoint(
      latitude: location.coordinate.latitude,
      longitude: location.coordinate.longitude,
      timestamp: location.timestamp,
      sog: sog,
      cog: cog
    )

    trackPoints.append(trackPoint)
    if trackPoints.count > 2000 {
      trackPoints.removeFirst()
    }
    
    if let sessionId = currentSessionId {
      let record = TrackPointRecord(domainModel: trackPoint, sessionId: sessionId)
      writeBuffer.append(record)
      
      if writeBuffer.count >= flushThreshold {
        flushBuffer()
      }
    }
  }

  @MainActor
  private func stopSavingState() {
    self.isSaving = false
  }
}

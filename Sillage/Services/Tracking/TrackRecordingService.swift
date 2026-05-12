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

@MainActor
@Observable
public final class TrackRecordingService {
  public private(set) var trackPoints: [TrackPoint] = []

  public private(set) var isRecording: Bool = false
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
    guard databaseManager != nil else {
      throw TrackRecordingError.databaseUnavailable
    }
    
    currentSessionId = UUID().uuidString
    lastRecordedLocation = nil
    writeBuffer.removeAll()
    
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
    // Pseudo-flush before stopping
    if !writeBuffer.isEmpty {
      Logger.database.info("Buffer pseudo-flush on stop")
      writeBuffer.removeAll()
    }
    currentSessionId = nil
    lastRecordedLocation = nil
    
    locationUpdatesTask?.cancel()
    locationUpdatesTask = nil
    self.backgroundLocationToken = nil
    self.isRecording = false

    let pointsToSave = trackPoints
    if !pointsToSave.isEmpty {
      let startedAt = pointsToSave.first?.timestamp ?? Date()
      Task.detached(priority: .utility) { [pointsToSave] in
        await Self.saveTrack(points: pointsToSave, startedAt: startedAt)
      }
    }
    trackPoints.removeAll()
  }

  private func checkBuffer() {
    if writeBuffer.count >= flushThreshold {
      Logger.database.info("Buffer reached threshold, ready for flush")
      writeBuffer.removeAll()
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

  // `nonisolated static` guarantees pure execution off the MainActor
  private nonisolated static func saveTrack(points: [TrackPoint], startedAt: Date) async {
    let exporter = GPXExportService()
    do {
      let gpxString = try await exporter.export(track: points)
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
      
      try gpxString.write(to: fileURL, atomically: true, encoding: .utf8)
      Logger.storage.info("Successfully saved track to \(fileURL.path, privacy: .public)")
    } catch {
      Logger.storage.error("Failed to save track: \(error.localizedDescription, privacy: .public)")
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
    
    if let sessionId = currentSessionId {
      let record = TrackPointRecord(domainModel: trackPoint, sessionId: sessionId)
      writeBuffer.append(record)
      checkBuffer()
    }
  }
}

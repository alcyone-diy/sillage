//
//  ScreenshotBootstrapper.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-14.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

#if DEBUG
import Foundation
import CoreLocation
import GRDB
import OSLog

/// Prepares an isolated SQLite database for synthetic 7-day barometric pressure history (`--simulate-baro`)
/// and optionally seeds demo tracks and waypoints (`--simulate-tracks`), without modifying `UserDefaults`.
@MainActor
enum ScreenshotBootstrapper {

  /// Creates an isolated SQLite `DatabaseManager` in the temporary directory
  /// pre-seeded with the 7-day barometric pressure curve for `scenario`.
  static func makeBarometricDatabase(
    scenario: ScreenshotScenario
  ) async throws -> DatabaseManager {
    let fm = FileManager.default
    let screenshotDir = fm.temporaryDirectory.appendingPathComponent("ScreenshotDatabase", isDirectory: true)
    if fm.fileExists(atPath: screenshotDir.path) {
      try? fm.removeItem(at: screenshotDir)
    }
    try fm.createDirectory(at: screenshotDir, withIntermediateDirectories: true)

    let dbURL = screenshotDir.appendingPathComponent("sillage_simulated_baro.sqlite")
    let dbManager = try await Task.detached {
      try DatabaseManager(url: dbURL)
    }.value

    try await seedBarometricHistory(scenario, into: dbManager)

    Logger.system.info("📸 Simulated barometric database ready at \(dbURL.path, privacy: .public)")
    return dbManager
  }

  /// Seeds 7 days of synthetic barometric pressure history into an existing `DatabaseManager`.
  static func seedBarometricHistory(
    _ scenario: ScreenshotScenario,
    into dbManager: DatabaseManager,
    referenceDate: Date = Date.now
  ) async throws {
    let barometricRecords = scenario
      .makeBarometricHistory(referenceDate: referenceDate)
      .map { BarometricReadingRecord(domainModel: $0) }

    try await dbManager.write { db in
      for record in barometricRecords {
        try record.insert(db)
      }
    }
  }

  /// Idempotently seeds the demo navigation waypoints and completed track sessions into `dbManager`
  /// when `--simulate-tracks` is enabled, without deleting any user-created waypoints or tracks
  /// and without modifying `UserDefaults` selections.
  static func seedTracksAndWaypoints(
    _ scenario: ScreenshotScenario,
    into dbManager: DatabaseManager,
    referenceDate: Date = Date.now
  ) async throws {
    let waypointRecords = scenario.waypoints.map { WaypointRecord(domainModel: $0) }

    let activeTrack = makeActiveWakeTrack(scenario: scenario, referenceDate: referenceDate)
    let activeSessionRecord = TrackSessionRecord(domainModel: activeTrack.session)
    let activePointRecords = activeTrack.points.map {
      TrackPointRecord(domainModel: $0, sessionID: activeTrack.session.id)
    }

    let secondaryTrack = makeHistoricalIslandTrack(referenceDate: referenceDate)
    let secondarySessionRecord = TrackSessionRecord(domainModel: secondaryTrack.session)
    let secondaryPointRecords = secondaryTrack.points.map {
      TrackPointRecord(domainModel: $0, sessionID: secondaryTrack.session.id)
    }

    try await dbManager.write { db in
      for record in waypointRecords {
        try record.save(db)
      }

      _ = try TrackSessionRecord.deleteOne(db, key: activeTrack.session.id)
      _ = try TrackSessionRecord.deleteOne(db, key: secondaryTrack.session.id)

      try activeSessionRecord.save(db)
      for pointRecord in activePointRecords {
        try pointRecord.insert(db)
      }

      try secondarySessionRecord.save(db)
      for pointRecord in secondaryPointRecords {
        try pointRecord.insert(db)
      }
    }
  }

  /// Removes only the demo waypoints (`screenshot-wpt-*`) and demo tracks (`screenshot-track-*`)
  /// when the app is launched without `--simulate-tracks`, keeping all user-created data intact.
  static func removeSeededTracksAndWaypoints(
    from dbManager: DatabaseManager
  ) async throws {
    let demoWaypointIDs = [
      "screenshot-wpt-chauveau",
      "screenshot-wpt-lavardin",
      "screenshot-wpt-sablanceaux",
      "screenshot-wpt-boyardville"
    ]
    let demoTrackIDs = [
      "screenshot-track-pertuis",
      "screenshot-track-ile-de-re"
    ]

    try await dbManager.write { db in
      for id in demoWaypointIDs {
        _ = try WaypointRecord.deleteOne(db, key: id)
      }
      for id in demoTrackIDs {
        _ = try TrackSessionRecord.deleteOne(db, key: id)
      }
    }
  }

  // MARK: - Private Helpers

  /// Builds a smooth, realistic 35-point wake track starting from La Rochelle channel
  /// and ending at the Antioche Strait sailing position.
  private static func makeActiveWakeTrack(
    scenario: ScreenshotScenario,
    referenceDate: Date
  ) -> (session: TrackSession, points: [TrackPoint]) {
    let pointCount = 35
    let durationSeconds: TimeInterval = 42 * 60 // 42 minutes
    let startTime = referenceDate.addingTimeInterval(-durationSeconds)

    let startLat = 46.1475
    let startLon = -1.1685
    let endLat = 46.1365
    let endLon = -1.2150

    var points: [TrackPoint] = []
    points.reserveCapacity(pointCount)

    var minLat = 90.0, maxLat = -90.0
    var minLon = 180.0, maxLon = -180.0
    var totalDistanceMeters = 0.0
    var previousLocation: CLLocation?

    for index in 0..<pointCount {
      let t = Double(index) / Double(pointCount - 1)
      let timestamp = startTime.addingTimeInterval(t * durationSeconds)

      // Smooth S-curve out of the La Rochelle channel into Pertuis d'Antioche
      let curveAngle = Measurement(value: t * 180.0, unit: UnitAngle.degrees).converted(to: .radians).value
      let latOffset = 0.0022 * sin(curveAngle)
      let lat = startLat + (endLat - startLat) * t + latOffset
      let lon = startLon + (endLon - startLon) * t

      minLat = min(minLat, lat)
      maxLat = max(maxLat, lat)
      minLon = min(minLon, lon)
      maxLon = max(maxLon, lon)

      let currentLocation = CLLocation(latitude: lat, longitude: lon)
      if let prev = previousLocation {
        totalDistanceMeters += currentLocation.distance(from: prev)
      }
      previousLocation = currentLocation

      let sogKnots = 5.8 + 0.8 * sin(curveAngle)
      let cogDeg = 252.0 + 6.0 * cos(curveAngle)

      points.append(
        TrackPoint(
          timestamp: timestamp,
          segmentIndex: 0,
          coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
          horizontalAccuracy: Measurement(value: 3.5, unit: .meters),
          speedOverGround: Measurement(value: sogKnots, unit: .knots),
          courseOverGround: Measurement(value: cogDeg, unit: .degrees)
        )
      )
    }

    let bounds = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
      northEast: CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon)
    )

    let session = TrackSession(
      id: "screenshot-track-pertuis",
      startTime: startTime,
      endTime: referenceDate,
      name: "La Rochelle → Antioche Strait",
      description: "Departure from Les Minimes channel in a fresh westerly breeze, close-hauled toward Chauveau.",
      startLocation: "La Rochelle (Les Minimes)",
      endLocation: "Antioche Strait",
      totalDuration: .seconds(durationSeconds),
      totalDistanceOverGround: Measurement(value: totalDistanceMeters, unit: .meters),
      boundingBox: bounds,
      maxSpeedOverGround: Measurement(value: 7.2, unit: .knots),
      segmentCount: 1,
      totalPointCount: points.count,
      colorHex: "#00E5FF"
    )

    return (session, points)
  }

  /// Builds a secondary historical track session so the Tracks Manager screen shows multiple rich entries.
  private static func makeHistoricalIslandTrack(
    referenceDate: Date
  ) -> (session: TrackSession, points: [TrackPoint]) {
    let sessionID = "screenshot-track-ile-de-re"
    let endTime = referenceDate.addingTimeInterval(-26 * 3600)
    let durationSeconds: TimeInterval = 3 * 3600 + 18 * 60 // 3h 18m
    let startTime = endTime.addingTimeInterval(-durationSeconds)

    let coords: [(Double, Double)] = [
      (46.2065, -1.3660),
      (46.2150, -1.3300),
      (46.1980, -1.2850),
      (46.1680, -1.2520),
      (46.1480, -1.2100),
      (46.1450, -1.1700)
    ]

    var points: [TrackPoint] = []
    for (idx, pair) in coords.enumerated() {
      let fraction = Double(idx) / Double(coords.count - 1)
      points.append(
        TrackPoint(
          timestamp: startTime.addingTimeInterval(fraction * durationSeconds),
          segmentIndex: 0,
          coordinate: CLLocationCoordinate2D(latitude: pair.0, longitude: pair.1),
          horizontalAccuracy: Measurement(value: 4.0, unit: .meters),
          speedOverGround: Measurement(value: 6.8, unit: .knots),
          courseOverGround: Measurement(value: 132.0, unit: .degrees)
        )
      )
    }

    let bounds = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 46.1450, longitude: -1.3660),
      northEast: CLLocationCoordinate2D(latitude: 46.2150, longitude: -1.1700)
    )

    let session = TrackSession(
      id: sessionID,
      startTime: startTime,
      endTime: endTime,
      name: "Saint-Martin-de-Ré → La Rochelle",
      description: "Downwind return with poled-out genoa, slight sea.",
      startLocation: "Saint-Martin-de-Ré",
      endLocation: "La Rochelle",
      totalDuration: .seconds(durationSeconds),
      totalDistanceOverGround: Measurement(value: 14.8, unit: .marineNauticalMiles).converted(to: .meters),
      boundingBox: bounds,
      maxSpeedOverGround: Measurement(value: 8.4, unit: .knots),
      segmentCount: 1,
      totalPointCount: points.count,
      colorHex: "#FF9500"
    )

    return (session, points)
  }
}
#endif

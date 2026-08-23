//
//  GPXExportService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import GRDB
import CoreLocation

public enum GPXExportError: Error {
  case emptyTrack
  case fileCreationFailure
}

public struct GPXExportService: Sendable {
  // Added sessionID and sessionName to uniquely identify and properly name the trace in the GPX file.
  /// Exports track points from a database cursor into a GPX file.
  /// - Parameters:
  ///   - sessionID: The unique identifier of the track session.
  ///   - sessionName: The optional user-defined name of the track session.
  ///   - cursor: The GRDB record cursor providing `TrackPointRecord` entries.
  ///   - totalCount: Optional total count of track points for calculating normalized progress.
  ///   - fileURL: Destination URL on disk.
  ///   - onProgress: Optional closure emitting normalized progress (0.0 to 1.0), throttled to at least 1% increments.
  /// - Throws: `GPXExportError`, `CancellationError`, or file system/database errors.
  /// - Returns: The number of track points exported.
  public nonisolated static func export(
    sessionID: String,
    sessionName: String? = nil,
    cursor: RecordCursor<TrackPointRecord>,
    totalCount: Int? = nil,
    to fileURL: URL,
    onProgress: (@Sendable (Double) -> Void)? = nil
  ) throws -> Int {
    if !FileManager.default.fileExists(atPath: fileURL.path) {
      guard FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil) else {
        throw GPXExportError.fileCreationFailure
      }
    }

    let fileHandle = try FileHandle(forWritingTo: fileURL)
    defer { try? fileHandle.close() }

    do {
      // Escaping XML special characters to prevent broken GPX files if the user inputs special characters in the session name.
      let safeName = (sessionName ?? sessionID).xmlEscaped
      let header = """
      <?xml version="1.0" encoding="UTF-8"?>
      <gpx version="1.1" creator="\(AppConstants.appName)" xmlns="http://www.topografix.com/GPX/1/1" xmlns:sillage="\(AppConstants.appURL.absoluteString)/gpx">
        <trk>
          <name>\(safeName)</name>
          <desc>Session ID: \(sessionID)</desc>
          <trkseg>
      """
      if let headerData = header.data(using: .utf8) {
        try fileHandle.write(contentsOf: headerData)
      }

      let enUSLocale = Locale(identifier: "en_US")
      let isoFormatter = ISO8601DateFormatter()

      var pointBuffer = ""
      var count = 0
      let total = totalCount ?? 0
      var lastEmittedProgress: Double = 0.0

      while let record = try cursor.next() {
        // Strict cooperative cancellation check to immediately abort on user cancel
        try Task.checkCancellation()

        let point = record.domainModel
        let latString = String(format: "%.6f", locale: enUSLocale, point.coordinate.latitude)
        let lonString = String(format: "%.6f", locale: enUSLocale, point.coordinate.longitude)
        let timeString = isoFormatter.string(from: point.timestamp)

        pointBuffer += "\n      <trkpt lat=\"\(latString)\" lon=\"\(lonString)\">"
        pointBuffer += "\n        <time>\(timeString)</time>"
        pointBuffer += "\n        <extensions>"

        let horizontalAccuracyString = String(format: "%.1f", locale: enUSLocale, point.horizontalAccuracy.converted(to: .meters).value)
        pointBuffer += "\n          <sillage:accuracy unit=\"meter\">\(horizontalAccuracyString)</sillage:accuracy>"

        if point.speedOverGround != nil || point.courseOverGround != nil {
          if let speedOverGround = point.speedOverGround {
            let sogString = String(format: "%.2f", locale: enUSLocale, speedOverGround.converted(to: .knots).value)
            pointBuffer += "\n          <sillage:sog unit=\"knot\">\(sogString)</sillage:sog>"
          }

          if let courseOverGround = point.courseOverGround {
            let cogString = String(format: "%.1f", locale: enUSLocale, courseOverGround.converted(to: .degrees).value)
            pointBuffer += "\n          <sillage:cog unit=\"degree\">\(cogString)</sillage:cog>"
          }
        }

        pointBuffer += "\n        </extensions>"
        pointBuffer += "\n      </trkpt>"

        count += 1

        if count % 500 == 0 {
          if let bufferData = pointBuffer.data(using: .utf8) {
            try fileHandle.write(contentsOf: bufferData)
          }
          pointBuffer = ""

          // Throttling: Emit progress only if it advanced by >= 1% to save CPU & battery
          if total > 0 {
            let currentProgress = min(1.0, Double(count) / Double(total))
            if (currentProgress - lastEmittedProgress) >= 0.01 {
              lastEmittedProgress = currentProgress
              onProgress?(currentProgress)
            }
          }
        }
      }

      if !pointBuffer.isEmpty {
        if let bufferData = pointBuffer.data(using: .utf8) {
          try fileHandle.write(contentsOf: bufferData)
        }
      }

      if count == 0 {
        throw GPXExportError.emptyTrack
      }

      let footer = """

          </trkseg>
        </trk>
      </gpx>
      """
      if let footerData = footer.data(using: .utf8) {
        try fileHandle.write(contentsOf: footerData)
      }

      // Emit 100% completion progress
      if total > 0 {
        onProgress?(1.0)
      }

      return count
    } catch {
      // Prevent leaving truncated/corrupt files on the user's storage in case of writing failure or cancellation.
      try? FileManager.default.removeItem(at: fileURL)
      throw error
    }
  }
}

// MARK: - String XML Escaping

extension String {
  /// Escapes special characters for safe XML inclusion.
  nonisolated var xmlEscaped: String {
    var result = ""
    for character in self {
      switch character {
      case "&": result.append("&amp;")
      case "<": result.append("&lt;")
      case ">": result.append("&gt;")
      case "\"": result.append("&quot;")
      case "'": result.append("&apos;")
      default: result.append(character)
      }
    }
    return result
  }
}

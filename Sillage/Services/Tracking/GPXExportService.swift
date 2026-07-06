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
  public nonisolated static func export(cursor: RecordCursor<TrackPointRecord>, to fileURL: URL) throws -> Int {
    if !FileManager.default.fileExists(atPath: fileURL.path) {
      guard FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil) else {
        throw GPXExportError.fileCreationFailure
      }
    }

    let fileHandle = try FileHandle(forWritingTo: fileURL)
    defer { try? fileHandle.close() }

    let header = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="\(AppConstants.appName)" xmlns="http://www.topografix.com/GPX/1/1" xmlns:sillage="http://alcyone.com/sillage/gpx">
      <trk>
        <trkseg>
    """
    if let headerData = header.data(using: .utf8) {
      try fileHandle.write(contentsOf: headerData)
    }

    var count = 0
    while let record = try cursor.next() {
      let point = record.domainModel
      let latString = String(format: "%.6f", locale: Locale(identifier: "en_US"), point.coordinate.latitude)
      let lonString = String(format: "%.6f", locale: Locale(identifier: "en_US"), point.coordinate.longitude)
      let timeString = point.timestamp.ISO8601Format()

      var pointXml = "\n      <trkpt lat=\"\(latString)\" lon=\"\(lonString)\">"
      pointXml += "\n        <time>\(timeString)</time>"

      pointXml += "\n        <extensions>"
      let horizontalAccuracyString = String(format: "%.1f", locale: Locale(identifier: "en_US"), point.horizontalAccuracy.converted(to: .meters).value)
      pointXml += "\n          <sillage:accuracy unit=\"meter\">\(horizontalAccuracyString)</sillage:accuracy>"

      if point.speedOverGround != nil || point.courseOverGround != nil {
        if let speedOverGround = point.speedOverGround {
          let sogString = String(format: "%.2f", locale: Locale(identifier: "en_US"), speedOverGround.converted(to: .knots).value)
          pointXml += "\n          <sillage:sog unit=\"knot\">\(sogString)</sillage:sog>"
        }

        if let courseOverGround = point.courseOverGround {
          let cogString = String(format: "%.1f", locale: Locale(identifier: "en_US"), courseOverGround.converted(to: .degrees).value)
          pointXml += "\n          <sillage:cog unit=\"degree\">\(cogString)</sillage:cog>"
        }
      }
      pointXml += "\n        </extensions>"
      pointXml += "\n      </trkpt>"

      if let pointData = pointXml.data(using: .utf8) {
        try fileHandle.write(contentsOf: pointData)
      }
      count += 1
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

    return count
  }
}

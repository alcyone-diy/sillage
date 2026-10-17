//
//  OfflinePackageSizeEstimator.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-17.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

/// Pure domain helper to calculate estimated download archive sizes and storage safety policies.
nonisolated public enum OfflinePackageSizeEstimator {

  /// Average compressed raster tile size (approx. 40 KB per tile).
  private static let averageTileSizeBytes: Double = 40_960.0

  /// Fixed SQLite / MBTiles database overhead (metadata, indexes, headers: ~2 MB).
  private static let mbtilesOverheadBytes: Double = 2_097_152.0

  /// Minimum zoom level included in GeoGarage standard offline packages.
  private static let minZoomLevel: Int = 8

  /// Estimates the uncompressed/compressed MBTiles archive package size for a bounding box up to `zoomMax`.
  public static func estimatePackageSize(
    bounds: GeographicBoundingBox,
    zoomMax: Int
  ) -> Measurement<UnitInformationStorage> {
    let startZoom = max(minZoomLevel, min(zoomMax, 10))
    var totalTiles: Int = 0

    let sw = bounds.southWest
    let ne = bounds.northEast

    let minLon = min(sw.longitude, ne.longitude)
    let maxLon = max(sw.longitude, ne.longitude)
    let minLat = max(-85.05112878, min(sw.latitude, ne.latitude))
    let maxLat = min(85.05112878, max(sw.latitude, ne.latitude))

    for z in startZoom...zoomMax {
      let n = pow(2.0, Double(z))

      let minX = max(0, min(Int(n) - 1, Int(floor((minLon + 180.0) / 360.0 * n))))
      let maxX = max(0, min(Int(n) - 1, Int(floor((maxLon + 180.0) / 360.0 * n))))

      let minLatRad = Measurement(value: minLat, unit: UnitAngle.degrees).converted(to: .radians).value
      let maxLatRad = Measurement(value: maxLat, unit: UnitAngle.degrees).converted(to: .radians).value

      let yAtMaxLat = (1.0 - (log(tan(.pi / 4.0 + maxLatRad / 2.0)) / .pi)) / 2.0 * n
      let yAtMinLat = (1.0 - (log(tan(.pi / 4.0 + minLatRad / 2.0)) / .pi)) / 2.0 * n

      let minY = max(0, min(Int(n) - 1, Int(floor(yAtMaxLat))))
      let maxY = max(0, min(Int(n) - 1, Int(floor(yAtMinLat))))

      let tilesX = max(1, maxX - minX + 1)
      let tilesY = max(1, maxY - minY + 1)

      totalTiles += (tilesX * tilesY)
    }

    let estimatedBytes = (Double(totalTiles) * averageTileSizeBytes) + mbtilesOverheadBytes
    return Measurement(value: estimatedBytes, unit: .bytes)
  }

  /// Convenience estimator from WKT POLYGON string.
  public static func estimatePackageSize(
    wkt: String,
    zoomMax: Int
  ) -> Measurement<UnitInformationStorage> {
    guard let box = GeographicBoundingBox(wkt: wkt) else {
      // Fallback baseline package size: 50 MB
      return Measurement(value: 50, unit: .megabytes)
    }
    return estimatePackageSize(bounds: box, zoomMax: zoomMax)
  }
}

/// Evaluates storage safety margins when downloading or replacing offline charts.
nonisolated public enum OfflineStoragePolicy {

  /// Minimum disk space buffer that must remain free on the device after completing the download.
  public static let minimumDeviceFreeBuffer = Measurement(value: 300, unit: UnitInformationStorage.megabytes)

  /// Headroom factor applied to estimated download size (1.5x = 50% safety margin).
  public static let safetyHeadroomMultiplier: Double = 1.5

  /// Evaluates whether the device has enough space (with margin) to retain the previous chart during download.
  public static func hasSufficientSpace(
    availableSpace: Measurement<UnitInformationStorage>,
    estimatedDownloadSize: Measurement<UnitInformationStorage>
  ) -> Bool {
    let scaledBytes = estimatedDownloadSize.converted(to: .bytes).value * safetyHeadroomMultiplier
    let requiredBytes = scaledBytes + minimumDeviceFreeBuffer.converted(to: .bytes).value
    let requiredSpace = Measurement(value: requiredBytes, unit: UnitInformationStorage.bytes)

    return availableSpace >= requiredSpace
  }
}

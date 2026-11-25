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
  /// Returns `nil` if `zoomMax` is outside valid GeoGarage offline bounds (`minZoomLevel...30`).
  public static func estimatePackageSize(
    bounds: GeographicBoundingBox,
    zoomMax: Int
  ) -> Measurement<UnitInformationStorage>? {
    guard zoomMax >= minZoomLevel, zoomMax <= 30 else {
      return nil
    }
    let startZoom = max(minZoomLevel, min(zoomMax, 10))
    guard startZoom <= zoomMax else {
      return nil
    }

    var totalTiles = 0
    for z in startZoom...zoomMax {
      totalTiles += MBTilesCoordinateMath.tileCount(for: bounds, zoom: z, clampLatitude: true)
    }

    let estimatedBytes = (Double(totalTiles) * averageTileSizeBytes) + mbtilesOverheadBytes
    return Measurement(value: estimatedBytes, unit: .bytes)
  }

  /// Convenience estimator from WKT POLYGON string.
  /// Returns `nil` if `wkt` cannot be parsed or `zoomMax` is outside valid GeoGarage offline bounds (`minZoomLevel...30`).
  public static func estimatePackageSize(
    wkt: String,
    zoomMax: Int
  ) -> Measurement<UnitInformationStorage>? {
    guard let box = GeographicBoundingBox(wkt: wkt) else {
      return nil
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

  /// Computes the minimum available device storage required to safely download a package of the given size,
  /// including the safety headroom multiplier and minimum free buffer.
  public static func requiredSpace(
    forDownloadSize estimatedDownloadSize: Measurement<UnitInformationStorage>
  ) -> Measurement<UnitInformationStorage> {
    let scaledBytes = estimatedDownloadSize.converted(to: .bytes).value * safetyHeadroomMultiplier
    let requiredBytes = scaledBytes + minimumDeviceFreeBuffer.converted(to: .bytes).value
    return Measurement(value: requiredBytes, unit: UnitInformationStorage.bytes)
  }

  /// Evaluates whether the device has enough space (with safety margin) to download a package
  /// without touching existing local charts.
  public static func hasSufficientSpace(
    availableSpace: Measurement<UnitInformationStorage>,
    estimatedDownloadSize: Measurement<UnitInformationStorage>
  ) -> Bool {
    return availableSpace >= requiredSpace(forDownloadSize: estimatedDownloadSize)
  }
}

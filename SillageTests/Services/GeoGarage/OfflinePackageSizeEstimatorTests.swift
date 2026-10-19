//
//  OfflinePackageSizeEstimatorTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-17.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CoreLocation
@testable import Sillage

final class OfflinePackageSizeEstimatorTests: XCTestCase {

  func testEstimatePackageSize_returnsPositiveStorageMeasurement() {
    let bounds = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 47.0, longitude: -3.5),
      northEast: CLLocationCoordinate2D(latitude: 48.0, longitude: -2.5)
    )

    let estimated = OfflinePackageSizeEstimator.estimatePackageSize(bounds: bounds, zoomMax: 14)

    XCTAssertGreaterThan(estimated.converted(to: .megabytes).value, 5.0, "Estimated size for a ~60nm zone at zoom 14 should exceed baseline overhead")
    XCTAssertLessThan(estimated.converted(to: .gigabytes).value, 2.0, "Estimated size should be realistic and bounded")
  }

  func testEstimatePackageSize_higherZoomLevelIncreasesEstimatedSize() {
    let bounds = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0),
      northEast: CLLocationCoordinate2D(latitude: 47.5, longitude: -2.5)
    )

    let sizeAt12 = OfflinePackageSizeEstimator.estimatePackageSize(bounds: bounds, zoomMax: 12)
    let sizeAt14 = OfflinePackageSizeEstimator.estimatePackageSize(bounds: bounds, zoomMax: 14)
    let sizeAt16 = OfflinePackageSizeEstimator.estimatePackageSize(bounds: bounds, zoomMax: AppConstants.Cartography.Zoom.defaultOfflineZoomMax)

    XCTAssertGreaterThan(sizeAt14.value, sizeAt12.value, "Higher zoom level must yield a larger estimated size")
    XCTAssertGreaterThan(sizeAt16.value, sizeAt14.value, "Zoom 16 must yield a larger estimated size than zoom 14")
  }

  func testEstimatePackageSize_largerBoundingBoxIncreasesEstimatedSize() {
    let smallBounds = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 47.0, longitude: -3.0),
      northEast: CLLocationCoordinate2D(latitude: 47.1, longitude: -2.9)
    )
    let largeBounds = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 47.0, longitude: -4.0),
      northEast: CLLocationCoordinate2D(latitude: 48.0, longitude: -2.0)
    )

    let smallSize = OfflinePackageSizeEstimator.estimatePackageSize(bounds: smallBounds, zoomMax: 14)
    let largeSize = OfflinePackageSizeEstimator.estimatePackageSize(bounds: largeBounds, zoomMax: 14)

    XCTAssertGreaterThan(largeSize.value, smallSize.value, "Larger bounding box must yield a larger estimated size")
  }

  func testOfflineStoragePolicy_withSufficientSpace_returnsTrue() {
    let estimated = Measurement(value: 50, unit: UnitInformationStorage.megabytes)
    // Required: (50 * 1.5) + 300 = 375 MB. Available: 1000 MB.
    let available = Measurement(value: 1000, unit: UnitInformationStorage.megabytes)

    let result = OfflineStoragePolicy.hasSufficientSpace(
      availableSpace: available,
      estimatedDownloadSize: estimated
    )

    XCTAssertTrue(result)
  }

  func testOfflineStoragePolicy_withConstrainedSpace_returnsFalse() {
    let estimated = Measurement(value: 100, unit: UnitInformationStorage.megabytes)
    // Required: (100 * 1.5) + 300 = 450 MB. Available: 350 MB.
    let available = Measurement(value: 350, unit: UnitInformationStorage.megabytes)

    let result = OfflineStoragePolicy.hasSufficientSpace(
      availableSpace: available,
      estimatedDownloadSize: estimated
    )

    XCTAssertFalse(result)
  }
}

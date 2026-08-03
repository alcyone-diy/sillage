//
//  OfflineSelectionViewModelTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-01.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CoreLocation
@testable import Sillage

@MainActor
final class OfflineSelectionViewModelTests: XCTestCase {
  var viewModel: OfflineSelectionViewModel!
  var offlineMapManager: MockOfflineMapManager!
  var offlineMapDownloadService: OfflineMapDownloadService!

  override func setUp() async throws {
    offlineMapManager = MockOfflineMapManager()
    offlineMapDownloadService = OfflineMapDownloadService(offlineMapManager: offlineMapManager)
    viewModel = OfflineSelectionViewModel(
      offlineMapManager: offlineMapManager,
      offlineMapDownloadService: offlineMapDownloadService
    )
  }

  override func tearDown() async throws {
    viewModel = nil
    offlineMapDownloadService = nil
    offlineMapManager = nil
  }

  func testStartDownloadResetsSelectionStateSynchronously() {
    // Given
    viewModel.isSelectionModeActive = true
    let bounds = GeographicBoundingBox(southWest: .init(latitude: 44, longitude: 0), northEast: .init(latitude: 45, longitude: 1))
    viewModel.updateBoundingBox(bounds)
    viewModel.updateCropRect(CGRect(x: 0, y: 0, width: 100, height: 100))
    
    // When
    viewModel.startDownload(chartSource: nil)

    // Then
    XCTAssertFalse(viewModel.isSelectionModeActive, "isSelectionModeActive should be false immediately after startDownload")
    XCTAssertNil(viewModel.selectedBounds, "selectedBounds should be reset")
    XCTAssertNil(viewModel.cropRect, "cropRect should be reset")
  }
}

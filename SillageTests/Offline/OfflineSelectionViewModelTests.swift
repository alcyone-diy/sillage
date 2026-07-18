//
//  OfflineSelectionViewModelTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-18.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

//
//  OfflineSelectionViewModelTests.swift
//  SillageTests
//
//  Created by Alcyone on 2026-07-18.
//

import XCTest
import CoreLocation
@testable import Sillage

@MainActor
final class OfflineSelectionViewModelTests: XCTestCase {

    var viewModel: OfflineSelectionViewModel!
    var offlineMapManager: OfflineMapManager!

    override func setUp() async throws {
        offlineMapManager = OfflineMapManager()
        viewModel = OfflineSelectionViewModel(offlineMapManager: offlineMapManager)
    }

    override func tearDown() async throws {
        viewModel = nil
        offlineMapManager = nil
    }

    func testDynamicStyleGenerationForRemoteSource() async throws {
        // Given
        let layerID = "test_layer_123"
        let chartSource = ChartSource.remoteGeoGarage(clientID: "test_client", layerID: layerID)
        viewModel.isSelectionModeActive = true
        let bounds = GeographicBoundingBox(southWest: .init(latitude: 44, longitude: 0), northEast: .init(latitude: 45, longitude: 1))
        viewModel.updateBoundingBox(bounds)
        
        // Wait for area calculation to finish
        try await Task.sleep(nanoseconds: 500_000_000)

        // When
        viewModel.startDownload(chartSource: chartSource)

        // Then
        // The dynamic style should be generated in the Caches directory
        let fm = FileManager.default
        let cachesDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let styleURL = cachesDir.appendingPathComponent("DynamicStyles").appendingPathComponent("geogarage-\(layerID).json")

        XCTAssertTrue(fm.fileExists(atPath: styleURL.path), "Dynamic style JSON file should be created.")

        let data = try Data(contentsOf: styleURL)
        let jsonString = String(data: data, encoding: .utf8)

        XCTAssertNotNil(jsonString)
        XCTAssertTrue(jsonString!.contains("https://tiles.geogarage.com/test_client/\(layerID)/{z}/{x}/{y}.png"), "The dynamic style JSON should contain the correct HTTPS URL for the layer.")
        XCTAssertTrue(jsonString!.contains("GeoGarage Raster - \(layerID)"))
    }
}

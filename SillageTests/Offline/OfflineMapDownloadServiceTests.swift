//
//  OfflineMapDownloadServiceTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
@testable import Sillage

@MainActor
final class OfflineMapDownloadServiceTests: XCTestCase {
  var offlineMapManager: MockOfflineMapManager!
  var offlineMapDownloadService: OfflineMapDownloadService!

  override func setUp() async throws {
    offlineMapManager = MockOfflineMapManager()
    offlineMapDownloadService = OfflineMapDownloadService(offlineMapManager: offlineMapManager)
  }

  override func tearDown() async throws {
    offlineMapDownloadService = nil
    offlineMapManager = nil
  }

  func testGenerateDynamicStyleJSON() async throws {
    // Given
    let layerID = "test_layer_123"
    let clientID = "test_client"
    
    // When
    let styleURL = try await offlineMapDownloadService.generateDynamicStyleJSON(forLayer: layerID, clientID: clientID)
    
    // Then
    let fm = FileManager.default
    XCTAssertTrue(fm.fileExists(atPath: styleURL.path), "Dynamic style JSON file should be created.")

    let data = try Data(contentsOf: styleURL)
    let jsonString = try XCTUnwrap(String(data: data, encoding: .utf8), "Le JSON devrait pouvoir être décodé en String")

    XCTAssertTrue(jsonString.contains("https://tiles.geogarage.com/\(clientID)/\(layerID)/{z}/{x}/{y}.png"), "L'URL dynamique est incorrecte.")
    XCTAssertTrue(jsonString.contains("GeoGarage Raster - \(layerID)"))
    
    // Cleanup
    try? fm.removeItem(at: styleURL)
  }
}

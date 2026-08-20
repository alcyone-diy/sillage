//
//  GeoGaragePackageModelsTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-16.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
@testable import Sillage

final class GeoGaragePackageModelsTests: XCTestCase {

  private func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    return decoder
  }

  // MARK: - PackageStatusResponse Decoding

  func testDecodePackageStatusResponse_progress() throws {
    let json = """
    {
      "version": "0.0.3",
      "uuid": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      "state": "PROGRESS",
      "tile_numbers": 1250,
      "tiles_per_sec": 42,
      "monitor": "1025/1250",
      "duration": null,
      "eta": 1737900000,
      "url": null,
      "md5": null,
      "size": null,
      "error": null
    }
    """.data(using: .utf8)!

    let response = try makeDecoder().decode(PackageStatusResponse.self, from: json)

    XCTAssertEqual(response.uuid, UUID(uuidString: "3FA85F64-5717-4562-B3FC-2C963F66AFA6"))
    XCTAssertEqual(response.state, .progress)
    XCTAssertEqual(response.tileNumbers, 1250)
    XCTAssertEqual(response.tilesPerSec, 42)
    XCTAssertEqual(response.monitor, "1025/1250")
    XCTAssertNil(response.url)
    XCTAssertNil(response.md5)
    XCTAssertNil(response.error)
    XCTAssertNotNil(response.eta)
    XCTAssertEqual(response.eta?.timeIntervalSince1970 ?? 0, 1_737_900_000, accuracy: 1.0)
  }

  func testDecodePackageStatusResponse_success() throws {
    let json = """
    {
      "uuid": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      "state": "SUCCESS",
      "tile_numbers": 1250,
      "tiles_per_sec": null,
      "monitor": null,
      "duration": 180,
      "eta": null,
      "url": "https://caas.geogarage.com/packages/3fa85f64/download",
      "md5": "d41d8cd98f00b204e9800998ecf8427e",
      "size": 52428800,
      "error": null
    }
    """.data(using: .utf8)!

    let response = try makeDecoder().decode(PackageStatusResponse.self, from: json)

    XCTAssertEqual(response.state, .success)
    XCTAssertEqual(response.url, "https://caas.geogarage.com/packages/3fa85f64/download")
    XCTAssertEqual(response.md5, "d41d8cd98f00b204e9800998ecf8427e")
    XCTAssertEqual(response.size, Int64(52_428_800))
    XCTAssertNil(response.eta)
    XCTAssertNil(response.monitor)
  }

  func testDecodePackageStatusResponse_largeSizeInt64() throws {
    let largeByteSize: Int64 = 8_589_934_592 // 8 GB
    let json = """
    {
      "uuid": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      "state": "SUCCESS",
      "size": \(largeByteSize)
    }
    """.data(using: .utf8)!

    let response = try makeDecoder().decode(PackageStatusResponse.self, from: json)
    XCTAssertEqual(response.size, largeByteSize, "Int64 must correctly decode large packages > 4GB without truncation")
  }

  func testDecodePackageStatusResponse_failure() throws {
    let json = """
    {
      "uuid": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      "state": "FAILURE",
      "tile_numbers": null,
      "tiles_per_sec": null,
      "monitor": null,
      "duration": null,
      "eta": null,
      "url": null,
      "md5": null,
      "size": null,
      "error": "Invalid zone WKT polygon."
    }
    """.data(using: .utf8)!

    let response = try makeDecoder().decode(PackageStatusResponse.self, from: json)

    XCTAssertEqual(response.state, .failure)
    XCTAssertEqual(response.error, "Invalid zone WKT polygon.")
    XCTAssertNil(response.url)
    XCTAssertNil(response.md5)
  }

  // MARK: - PackageStatusResponse.normalizedProgress

  func testNormalizedProgress_valid() throws {
    let json = """
    {
      "uuid": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      "state": "PROGRESS",
      "monitor": "500/1000"
    }
    """.data(using: .utf8)!

    let response = try makeDecoder().decode(PackageStatusResponse.self, from: json)
    let progress = try XCTUnwrap(response.normalizedProgress)
    XCTAssertEqual(progress, 0.5, accuracy: 0.001)
  }

  func testNormalizedProgress_nilWhenMonitorIsNil() throws {
    let json = """
    {
      "uuid": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      "state": "SUCCESS"
    }
    """.data(using: .utf8)!

    let response = try makeDecoder().decode(PackageStatusResponse.self, from: json)
    XCTAssertNil(response.normalizedProgress)
  }

  func testNormalizedProgress_nilWhenTotalIsZero() throws {
    let json = """
    {
      "uuid": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
      "state": "PROGRESS",
      "monitor": "0/0"
    }
    """.data(using: .utf8)!

    let response = try makeDecoder().decode(PackageStatusResponse.self, from: json)
    XCTAssertNil(response.normalizedProgress)
  }

  // MARK: - GeoGarageSettingsResponse Decoding

  func testDecodeSettingsResponse_includesCustomerID() throws {
    let json = """
    {
      "customer_id": "cus_ABCDEFGHIJ",
      "layers": [
        {
          "layer": "shom",
          "brand_name": "SHOM France",
          "version_date": "2025-01-14T22:11:39Z",
          "valid_until": "2026-12-31T23:59:59Z"
        }
      ]
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(GeoGarageSettingsResponse.self, from: json)

    XCTAssertEqual(response.customerID, "cus_ABCDEFGHIJ")
    XCTAssertEqual(response.layers.count, 1)
    XCTAssertEqual(response.layers[0].layer, "shom")
    XCTAssertEqual(response.layers[0].brandName, "SHOM France")
    XCTAssertEqual(response.layers[0].versionDate, "2025-01-14T22:11:39Z")
    XCTAssertEqual(response.layers[0].validUntil, "2026-12-31T23:59:59Z")
  }

  // MARK: - OfflineChartDownload Codable Round-Trip

  func testOfflineChartDownload_codableRoundTrip() throws {
    let id = UUID()
    let date = Date(timeIntervalSince1970: 1_737_900_000)
    let original = OfflineChartDownload(
      id: id,
      layerID: "shom",
      layerName: "SHOM France",
      downloadDate: date,
      relativePath: "Charts/shom_2026-08-16.mbtiles",
      md5: "d41d8cd98f00b204e9800998ecf8427e",
      zoomMax: 14,
      boundsWKT: "POLYGON((-5.0 47.0, 0.0 47.0, 0.0 50.0, -5.0 50.0, -5.0 47.0))"
    )

    let encoder = LocalFilePersistenceActor.defaultEncoder()
    let decoder = LocalFilePersistenceActor.defaultDecoder()

    let data = try encoder.encode(original)
    let decoded = try decoder.decode(OfflineChartDownload.self, from: data)

    XCTAssertEqual(decoded.id, original.id)
    XCTAssertEqual(decoded.layerID, original.layerID)
    XCTAssertEqual(decoded.layerName, original.layerName)
    XCTAssertEqual(decoded.relativePath, original.relativePath)
    XCTAssertEqual(decoded.md5, original.md5)
    XCTAssertEqual(decoded.zoomMax, original.zoomMax)
    XCTAssertEqual(decoded.boundsWKT, original.boundsWKT)
    XCTAssertEqual(decoded.downloadDate.timeIntervalSince1970, original.downloadDate.timeIntervalSince1970, accuracy: 1.0)
  }

  // MARK: - OfflineChartDownload.resolvedFileURL

  func testResolvedFileURL_isNotNilForValidRelativePath() {
    let download = OfflineChartDownload(
      id: UUID(),
      layerID: "noaa",
      layerName: "NOAA Charts",
      downloadDate: Date(),
      relativePath: "Charts/noaa_test.mbtiles",
      md5: "abc123",
      zoomMax: 12,
      boundsWKT: "POLYGON((0 0, 1 0, 1 1, 0 1, 0 0))"
    )
    XCTAssertNotNil(download.resolvedFileURL(), "resolvedFileURL() should return a non-nil URL for a valid relative path")
  }

  // MARK: - CaasError Localized Descriptions

  func testCaasError_md5MismatchHasDescription() {
    let error = CaasError.md5Mismatch(expected: "abc", actual: "xyz")
    XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
  }

  func testCaasError_pollingTimeoutHasDescription() {
    let error = CaasError.pollingTimeout
    XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
  }

  func testCaasError_authenticationRequiredHasDescription() {
    let error = CaasError.authenticationRequired
    XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
  }

  // MARK: - GeoGarageDownloadPhaseState Equatable

  func testDownloadPhaseState_equatable() {
    let idle: GeoGarageDownloadPhaseState = .idle
    let requesting: GeoGarageDownloadPhaseState = .requesting
    let generating1: GeoGarageDownloadPhaseState = .generating(progress: 0.5, message: "PROGRESS: 500/1000")
    let generating2: GeoGarageDownloadPhaseState = .generating(progress: 0.5, message: "PROGRESS: 500/1000")
    let downloading: GeoGarageDownloadPhaseState = .downloading(receivedBytes: 100, totalBytes: 200)
    let cancelled: GeoGarageDownloadPhaseState = .cancelled
    let failed: GeoGarageDownloadPhaseState = .failed(errorMessage: "Network error")

    XCTAssertEqual(idle, .idle)
    XCTAssertEqual(generating1, generating2)
    XCTAssertNotEqual(idle, requesting)
    XCTAssertNotEqual(downloading, cancelled)
    XCTAssertNotEqual(failed, cancelled)
  }
}

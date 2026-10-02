//
//  GeoGarageDownloadRecordTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
@testable import Sillage

@MainActor
final class GeoGarageDownloadRecordTests: XCTestCase {

  func testDomainToRecordMapping_withAllFieldsAndMeasurement() {
    let id = UUID()
    let downloadDate = Date(timeIntervalSince1970: 1_723_814_400)
    let fileSize = Measurement(value: 1_048_576, unit: UnitInformationStorage.bytes)

    let domain = OfflineChartDownload(
      id: id,
      layerID: "shom",
      layerName: "SHOM France",
      downloadDate: downloadDate,
      relativePath: "Charts/shom.mbtiles",
      md5: "d41d8cd98f00b204e9800998ecf8427e",
      zoomMax: 14,
      boundsWKT: "POLYGON((-5.0 47.0, 0.0 47.0, 0.0 50.0, -5.0 50.0, -5.0 47.0))",
      fileSize: fileSize,
      customName: "Bretagne Sud"
    )

    let record = GeoGarageDownloadRecord(domainModel: domain)

    XCTAssertEqual(record.id, id.uuidString)
    XCTAssertEqual(record.layer_id, "shom")
    XCTAssertEqual(record.layer_name, "SHOM France")
    XCTAssertEqual(record.download_timestamp_unix, 1_723_814_400, accuracy: 0.001)
    XCTAssertEqual(record.relative_path, "Charts/shom.mbtiles")
    XCTAssertEqual(record.md5, "d41d8cd98f00b204e9800998ecf8427e")
    XCTAssertEqual(record.zoom_max, 14)
    XCTAssertEqual(record.bounds_wkt, "POLYGON((-5.0 47.0, 0.0 47.0, 0.0 50.0, -5.0 50.0, -5.0 47.0))")
    XCTAssertEqual(record.custom_name, "Bretagne Sud")
    XCTAssertEqual(record.file_size_bytes, 1_048_576)

    // Round-trip conversion back to domain
    guard let mappedBack = record.toDomain() else {
      XCTFail("Failed to map valid record back to domain.")
      return
    }

    XCTAssertEqual(mappedBack, domain)
    XCTAssertEqual(mappedBack.fileSize, fileSize)
  }

  func testDomainToRecordMapping_withNilOptionals() {
    let id = UUID()
    let downloadDate = Date(timeIntervalSince1970: 1_600_000_000)

    let domain = OfflineChartDownload(
      id: id,
      layerID: "noaa",
      layerName: "NOAA Raster",
      downloadDate: downloadDate,
      relativePath: "Charts/noaa.mbtiles",
      md5: "0123456789abcdef0123456789abcdef",
      zoomMax: 12,
      boundsWKT: "POLYGON((0 0, 1 0, 1 1, 0 1, 0 0))",
      fileSize: nil,
      customName: nil
    )

    let record = GeoGarageDownloadRecord(domainModel: domain)

    XCTAssertNil(record.custom_name)
    XCTAssertNil(record.file_size_bytes)

    guard let mappedBack = record.toDomain() else {
      XCTFail("Failed to map record back to domain.")
      return
    }

    XCTAssertEqual(mappedBack, domain)
    XCTAssertNil(mappedBack.fileSize)
    XCTAssertNil(mappedBack.customName)
  }

  func testRecordToDomain_withInvalidUUIDReturnsNil() {
    let record = GeoGarageDownloadRecord(
      id: "this-is-not-a-valid-uuid",
      layer_id: "shom",
      layer_name: "SHOM",
      download_timestamp_unix: 1_700_000_000,
      relative_path: "Charts/shom.mbtiles",
      md5: "abc",
      zoom_max: 10,
      bounds_wkt: "POLYGON((0 0, 1 0, 1 1, 0 1, 0 0))"
    )

    XCTAssertNil(
      record.toDomain(),
      "toDomain() must return nil when the id string cannot be parsed as a UUID (nil-over-dummy pattern)."
    )
  }

  func testMeasurementUnitConversionPreservesValue() {
    let id = UUID()
    let sizeInKilobytes = Measurement(value: 500, unit: UnitInformationStorage.kilobytes)

    let domain = OfflineChartDownload(
      id: id,
      layerID: "ukho",
      layerName: "Admiralty UKHO",
      downloadDate: Date(),
      relativePath: "Charts/ukho.mbtiles",
      md5: "fedcba9876543210",
      zoomMax: 15,
      boundsWKT: "POLYGON((0 0, 1 0, 1 1, 0 1, 0 0))",
      fileSize: sizeInKilobytes
    )

    let record = GeoGarageDownloadRecord(domainModel: domain)
    let expectedBytes = Int64(sizeInKilobytes.converted(to: .bytes).value)
    XCTAssertEqual(record.file_size_bytes, expectedBytes)

    guard let mappedBack = record.toDomain() else {
      XCTFail("Failed to convert record to domain.")
      return
    }

    guard let mappedSize = mappedBack.fileSize else {
      XCTFail("Mapped size must not be nil.")
      return
    }

    XCTAssertEqual(
      mappedSize.converted(to: .bytes).value,
      sizeInKilobytes.converted(to: .bytes).value,
      accuracy: 0.001
    )
  }
}

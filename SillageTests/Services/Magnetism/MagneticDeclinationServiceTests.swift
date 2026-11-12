//
//  MagneticDeclinationServiceTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-11.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CoreLocation
@testable import Sillage

final class MagneticDeclinationServiceTests: XCTestCase {

  private var service: MagneticDeclinationService!

  override func setUp() async throws {
    try await super.setUp()
    service = MagneticDeclinationService()
  }

  override func tearDown() async throws {
    service = nil
    try await super.tearDown()
  }

  // MARK: - Helper to locate WMM.COF

  private func locateWMMFile() -> URL? {
    if let url = Bundle.main.url(forResource: "WMM", withExtension: "COF") {
      return url
    }
    if let url = Bundle(for: MagneticDeclinationServiceTests.self).url(forResource: "WMM", withExtension: "COF") {
      return url
    }
    let sourcePath = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent() // Services/Magnetism
      .deletingLastPathComponent() // Services
      .deletingLastPathComponent() // SillageTests
      .appendingPathComponent("Sillage/Resources/WMM.COF")
    if FileManager.default.fileExists(atPath: sourcePath.path) {
      return sourcePath
    }
    return nil
  }

  // MARK: - Unit Tests

  func testDecimalYearConversion() {
    let calendar = Calendar(identifier: .gregorian)

    guard let jan1 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 0, minute: 0, second: 0)),
          let midYear = calendar.date(from: DateComponents(year: 2026, month: 7, day: 2, hour: 12, minute: 0, second: 0)) else {
      XCTFail("Failed to construct test dates")
      return
    }

    let decimalJan1 = MagneticDeclinationService.decimalYear(from: jan1)
    XCTAssertNotNil(decimalJan1)
    XCTAssertEqual(decimalJan1 ?? 0, 2026.0, accuracy: 0.001)

    let decimalMidYear = MagneticDeclinationService.decimalYear(from: midYear)
    XCTAssertNotNil(decimalMidYear)
    XCTAssertEqual(decimalMidYear ?? 0, 2026.5, accuracy: 0.01)
  }

  func testMissingWMMFileReturnsNil() async {
    // When WMM.COF is absent from an empty bundle, calculateDeclination returns nil (never dummy values)
    let emptyService = MagneticDeclinationService(bundle: Bundle())
    let coordinate = CLLocationCoordinate2D(latitude: 46.1603, longitude: -1.1511) // La Rochelle
    let declination = await emptyService.calculateDeclination(for: coordinate, date: Date())

    XCTAssertNil(declination, "Declination must return nil when WMM.COF is absent from bundle, never 0.0 or a dummy value")
  }

  func testModelParsingAndCalculationWithSampleCoefficients() throws {
    // Minimal valid WMM.COF sample (Header + Dipole terms)
    let sampleWMMContent = """
        2025.0            WMM-2025        11/20/2024
      1   0   -29404.5       0.0       6.7       0.0
      1   1    -1450.7    4652.9       7.7     -25.1
    99999999999999999999999999999999999999999999999999
    """

    let model = try WorldMagneticModel.parse(content: sampleWMMContent)
    XCTAssertEqual(model.epoch, 2025.0)
    XCTAssertEqual(model.modelName, "WMM-2025")

    let declination = model.calculateDeclination(
      latitudeDegrees: 46.1603,
      longitudeDegrees: -1.1511,
      altitudeMeters: 0.0,
      decimalYear: 2026.0
    )

    XCTAssertNotNil(declination)
    if let dec = declination {
      XCTAssertTrue(dec >= -180.0 && dec <= 180.0)
    }
  }

  func testInvalidCoordinateReturnsNilAndNeverZero() async {
    let invalidCoord1 = CLLocationCoordinate2D(latitude: 95.0, longitude: 0.0)
    let declination1 = await service.calculateDeclination(for: invalidCoord1, date: Date())
    XCTAssertNil(declination1, "Invalid latitude should return nil, never 0.0")

    let invalidCoord2 = CLLocationCoordinate2D(latitude: -91.0, longitude: 0.0)
    let declination2 = await service.calculateDeclination(for: invalidCoord2, date: Date())
    XCTAssertNil(declination2, "Invalid latitude should return nil, never 0.0")

    let invalidCoord3 = CLLocationCoordinate2D(latitude: 0.0, longitude: 185.0)
    let declination3 = await service.calculateDeclination(for: invalidCoord3, date: Date())
    XCTAssertNil(declination3, "Invalid longitude should return nil, never 0.0")
  }

  func testConvenienceMethodMatches() async {
    let coordinate = CLLocationCoordinate2D(latitude: 43.2965, longitude: 5.3698) // Marseille
    let date = Date()

    let declination1 = await service.calculateDeclination(for: coordinate, date: date)
    let declination2 = await service.declination(for: coordinate, date: date)

    XCTAssertEqual(declination1, declination2)
  }

  // MARK: - Integration Tests with Real WMM.COF

  func testTrueDeclinationAtLaRochelle() async throws {
    guard let wmmURL = locateWMMFile() else {
      XCTFail("WMM.COF file not found in test or resource bundle.")
      return
    }

    let realService = MagneticDeclinationService(fileURL: wmmURL)

    // Port des Minimes, La Rochelle (Latitude: 46.147, Longitude: -1.168)
    let portDesMinimes = CLLocationCoordinate2D(latitude: 46.147, longitude: -1.168)
    let currentDate = Date()

    let declination = await realService.calculateDeclination(
      for: portDesMinimes,
      date: currentDate,
      altitudeMeters: 0.0
    )

    XCTAssertNotNil(declination, "Declination at La Rochelle must not be nil with valid WMM.COF")

    guard let declination else { return }

    // According to the official NOAA WMM-2025 model (2025-2030), the agonic line (0°) crossed
    // France around 2019-2020. At La Rochelle in 2026, the true declination is approximately
    // +1.08° E (moving eastward at ~ +0.15° / year).
    // Verified against official NOAA WMM2025 algorithm within accuracy margin 0.5°.
    let expectedDeclinationDegrees = 1.08
    XCTAssertEqual(
      declination.value,
      expectedDeclinationDegrees,
      accuracy: 0.5,
      "Declination at Port des Minimes (~1.08° E in 2026) must match true WMM2025 value within 0.5°"
    )
  }

  func testOfficialNOAAReferencePoint() async throws {
    guard let wmmURL = locateWMMFile() else {
      XCTFail("WMM.COF file not found.")
      return
    }

    let realService = MagneticDeclinationService(fileURL: wmmURL)

    // Official NOAA WMM-2025 test value from WMM2025_TestValues.txt:
    // Lat 43.0 N, Lon 93.0 E, Alt 65 km, Year 2025.0 -> Declination = 0.496358°
    let noaaCoord = CLLocationCoordinate2D(latitude: 43.0, longitude: 93.0)
    let calendar = Calendar(identifier: .gregorian)
    guard let epoch2025 = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1, hour: 0, minute: 0, second: 0)) else {
      XCTFail("Failed to create date for 2025.0")
      return
    }

    let declination = await realService.calculateDeclination(
      for: noaaCoord,
      date: epoch2025,
      altitudeMeters: 65_000.0
    )

    XCTAssertNotNil(declination)
    if let dec = declination {
      XCTAssertEqual(dec.value, 0.496358, accuracy: 0.001, "Must match NOAA WMM2025 test value to 3 decimal places")
    }
  }
}

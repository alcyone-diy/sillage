//
//  BarometerCoreTests.swift
//  SillageTests
//
//  Created by Alcyone on 2026-11-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
@testable import Sillage

final class BarometerCoreTests: XCTestCase {

  // MARK: - BarometricReading & Thresholds

  func testBarometricReadingNormalizesUnitToHectopascals() {
    let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    let fromKilopascals = BarometricReading(
      timestamp: timestamp,
      pressure: Measurement(value: 101.325, unit: .kilopascals)
    )

    XCTAssertEqual(fromKilopascals.pressure.unit, .hectopascals)
    XCTAssertEqual(fromKilopascals.pressure.value, 1013.25, accuracy: 1e-6)
  }

  func testBarometricThresholdsMatchMaritimeMeteorologicalStandards() {
    XCTAssertEqual(Measurement<UnitPressure>.highFastDropThreshold.converted(to: .hectopascals).value, -2.0, accuracy: 1e-9)
    XCTAssertEqual(Measurement<UnitPressure>.vigilanceThreshold.converted(to: .hectopascals).value, -1.5, accuracy: 1e-9)
    XCTAssertEqual(Measurement<UnitPressure>.galeThreshold.converted(to: .hectopascals).value, -3.0, accuracy: 1e-9)
    XCTAssertEqual(Measurement<UnitPressure>.stormThreshold.converted(to: .hectopascals).value, -5.0, accuracy: 1e-9)
    XCTAssertEqual(Measurement<UnitPressure>.minimumPlausiblePressure.converted(to: .hectopascals).value, 800.0, accuracy: 1e-9)
    XCTAssertEqual(Measurement<UnitPressure>.maximumPlausiblePressure.converted(to: .hectopascals).value, 1100.0, accuracy: 1e-9)
  }

  func testSensitivityAndWeatherAlarmMetadataArePopulated() {
    XCTAssertEqual(BaroAlarmSensitivity.allCases.count, 3)
    for sensitivity in BaroAlarmSensitivity.allCases {
      XCTAssertEqual(sensitivity.id, sensitivity.rawValue)
      XCTAssertFalse(sensitivity.localizedName.isEmpty)
      XCTAssertFalse(sensitivity.explanation.isEmpty)
    }

    let levels: [WeatherAlarmLevel] = [.vigilance, .gale, .storm, .squall]
    for level in levels {
      XCTAssertFalse(level.localizedName.isEmpty)
    }
  }

  // MARK: - PressureDropCalculator

  func testPressureDropCalculatorReturnsNilForInsufficientSamples() {
    let t0 = Date(timeIntervalSince1970: 0)
    XCTAssertNil(PressureDropCalculator.calculateMaxDrop(from: []))
    XCTAssertNil(
      PressureDropCalculator.calculateMaxDrop(
        from: [BarometricReading(timestamp: t0, pressure: Measurement(value: 1015.0, unit: .hectopascals))]
      )
    )
  }

  func testPressureDropCalculatorSortsChronologicallyAndComparesLatestAgainstPeak() throws {
    let t0 = Date(timeIntervalSince1970: 0)
    // Unsorted readings: t=0 -> 1015, t=1h -> 1021 (peak), t=2h -> 1017.5 (latest) => drop = 1017.5 - 1021.0 = -3.5 hPa
    let unsortedReadings = [
      BarometricReading(timestamp: t0.addingTimeInterval(7_200), pressure: Measurement(value: 1017.5, unit: .hectopascals)),
      BarometricReading(timestamp: t0, pressure: Measurement(value: 1015.0, unit: .hectopascals)),
      BarometricReading(timestamp: t0.addingTimeInterval(3_600), pressure: Measurement(value: 1021.0, unit: .hectopascals))
    ]

    let drop = try XCTUnwrap(PressureDropCalculator.calculateMaxDrop(from: unsortedReadings))
    XCTAssertEqual(drop.converted(to: .hectopascals).value, -3.5, accuracy: 1e-6)
  }

  func testPressureDropCalculatorReturnsZeroWhenLatestReadingIsPeak() throws {
    let t0 = Date(timeIntervalSince1970: 0)
    let risingReadings = [
      BarometricReading(timestamp: t0, pressure: Measurement(value: 1010.0, unit: .hectopascals)),
      BarometricReading(timestamp: t0.addingTimeInterval(1_800), pressure: Measurement(value: 1012.0, unit: .hectopascals)),
      BarometricReading(timestamp: t0.addingTimeInterval(3_600), pressure: Measurement(value: 1014.5, unit: .hectopascals))
    ]

    let drop = try XCTUnwrap(PressureDropCalculator.calculateMaxDrop(from: risingReadings))
    XCTAssertEqual(drop.converted(to: .hectopascals).value, 0.0, accuracy: 1e-9)
  }

  // MARK: - LinearRegressionCalculator

  func testLinearRegressionRejectsInsufficientCountZeroSpanAndUnder80PercentCoverage() {
    let t0 = Date(timeIntervalSince1970: 0)
    let threeHours: TimeInterval = 3 * 3_600

    // < 2 samples
    XCTAssertNil(LinearRegressionCalculator.calculateTrend(from: [], over: threeHours))
    XCTAssertNil(
      LinearRegressionCalculator.calculateTrend(
        from: [BarometricReading(timestamp: t0, pressure: Measurement(value: 1013.0, unit: .hectopascals))],
        over: threeHours
      )
    )

    // Identical timestamps (timeSpan == 0)
    let duplicateTimestamps = [
      BarometricReading(timestamp: t0, pressure: Measurement(value: 1013.0, unit: .hectopascals)),
      BarometricReading(timestamp: t0, pressure: Measurement(value: 1011.0, unit: .hectopascals))
    ]
    XCTAssertNil(LinearRegressionCalculator.calculateTrend(from: duplicateTimestamps, over: threeHours))

    // 79% coverage (< required 80% threshold) must return nil to prevent unsafe extrapolation
    let insufficientSpanReadings = [
      BarometricReading(timestamp: t0, pressure: Measurement(value: 1015.0, unit: .hectopascals)),
      BarometricReading(
        timestamp: t0.addingTimeInterval(threeHours * 0.79),
        pressure: Measurement(value: 1010.0, unit: .hectopascals)
      )
    ]
    XCTAssertNil(LinearRegressionCalculator.calculateTrend(from: insufficientSpanReadings, over: threeHours))
  }

  func testLinearRegressionComputesExactProjectedSlopeAt80PercentAndFullCoverage() throws {
    let t0 = Date(timeIntervalSince1970: 10_000)
    let threeHours: TimeInterval = 3 * 3_600

    // Exact -2.0 hPa/hour slope sampled over 2.4h (80% of 3h): projected 3h change = -6.0 hPa
    // Intentionally shuffled and using kilopascals on one entry to exercise sorting + unit conversion
    let readings = [
      BarometricReading(
        timestamp: t0.addingTimeInterval(2.4 * 3_600),
        pressure: Measurement(value: 1015.2, unit: .hectopascals)
      ),
      BarometricReading(
        timestamp: t0,
        pressure: Measurement(value: 102.0, unit: .kilopascals) // 1020.0 hPa
      ),
      BarometricReading(
        timestamp: t0.addingTimeInterval(1.2 * 3_600),
        pressure: Measurement(value: 1017.6, unit: .hectopascals)
      )
    ]

    let trend = try XCTUnwrap(LinearRegressionCalculator.calculateTrend(from: readings, over: threeHours))
    XCTAssertEqual(trend.converted(to: .hectopascals).value, -6.0, accuracy: 1e-6)
  }

  func testLinearRegressionHandlesRisingAndSteadyPressure() throws {
    let t0 = Date(timeIntervalSince1970: 50_000)
    let oneHour: TimeInterval = 3_600

    let steadyReadings = [
      BarometricReading(timestamp: t0, pressure: Measurement(value: 1013.25, unit: .hectopascals)),
      BarometricReading(timestamp: t0.addingTimeInterval(oneHour), pressure: Measurement(value: 1013.25, unit: .hectopascals))
    ]
    let steadyTrend = try XCTUnwrap(LinearRegressionCalculator.calculateTrend(from: steadyReadings, over: oneHour))
    XCTAssertEqual(steadyTrend.converted(to: .hectopascals).value, 0.0, accuracy: 1e-9)

    let risingReadings = [
      BarometricReading(timestamp: t0, pressure: Measurement(value: 1010.0, unit: .hectopascals)),
      BarometricReading(timestamp: t0.addingTimeInterval(oneHour), pressure: Measurement(value: 1012.5, unit: .hectopascals))
    ]
    let risingTrend = try XCTUnwrap(LinearRegressionCalculator.calculateTrend(from: risingReadings, over: oneHour))
    XCTAssertEqual(risingTrend.converted(to: .hectopascals).value, 2.5, accuracy: 1e-6)
  }

  func testLinearRegressionComputesAnalyticalOLSOnNoisyNonCollinearReadings() throws {
    let t0 = Date(timeIntervalSince1970: 100_000)
    let threeHours: TimeInterval = 10_800

    // 5 non-collinear noisy readings spaced by 2,700s (0.75h) across 3h:
    // x = [0, 2700, 5400, 8100, 10800] (mean x = 5400, sum((x - meanX)^2) = 10 * 2700^2)
    // y = [1018.4, 1016.5, 1016.3, 1014.6, 1014.2] hPa (mean y = 1016.0 hPa)
    // sum((x - meanX) * (y - meanY)) = 2700 * ((-2)*(2.4) + (-1)*(0.5) + 0*(0.3) + 1*(-1.4) + 2*(-1.8)) = 2700 * (-10.3)
    // Exact analytical OLS slope = -10.3 / (10 * 2700) hPa/s -> 3h projected change = -10.3 * 0.4 = -4.12 hPa
    // (Notably distinct from naive endpoint difference 1014.2 - 1018.4 = -4.20 hPa).
    let noisyReadings = [
      BarometricReading(timestamp: t0, pressure: Measurement(value: 1018.4, unit: .hectopascals)),
      BarometricReading(timestamp: t0.addingTimeInterval(2_700), pressure: Measurement(value: 1016.5, unit: .hectopascals)),
      BarometricReading(timestamp: t0.addingTimeInterval(5_400), pressure: Measurement(value: 1016.3, unit: .hectopascals)),
      BarometricReading(timestamp: t0.addingTimeInterval(8_100), pressure: Measurement(value: 1014.6, unit: .hectopascals)),
      BarometricReading(timestamp: t0.addingTimeInterval(10_800), pressure: Measurement(value: 1014.2, unit: .hectopascals))
    ]

    let olsTrend = try XCTUnwrap(LinearRegressionCalculator.calculateTrend(from: noisyReadings, over: threeHours))
    let olsValue = olsTrend.converted(to: .hectopascals).value

    XCTAssertEqual(olsValue, -4.12, accuracy: 1e-6)
    XCTAssertNotEqual(olsValue, -4.20, accuracy: 0.05)
  }
}

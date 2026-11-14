//
//  SimulatedAltimeterProvider.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-14.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

#if DEBUG
import Foundation
import CoreMotion

/// Synthetic `CMAltitudeData` subclass returning a deterministic pressure in kilopascals.
final class SimulatedCMAltitudeData: CMAltitudeData {
  private let simulatedPressureKPa: Double

  init(pressureKPa: Double) {
    self.simulatedPressureKPa = pressureKPa
    super.init()
  }

  required init?(coder: NSCoder) {
    self.simulatedPressureKPa = 101.325
    super.init(coder: coder)
  }

  override var pressure: NSNumber {
    NSNumber(value: simulatedPressureKPa)
  }

  override var relativeAltitude: NSNumber {
    NSNumber(value: 0.0)
  }
}

/// Simulated `AltimeterProvider` for `-screenshot-mode` so the barometer works on the iOS Simulator
/// and displays a consistent pressure reading.
final class SimulatedAltimeterProvider: AltimeterProvider {
  private let scenario: ScreenshotScenario

  init(scenario: ScreenshotScenario) {
    self.scenario = scenario
  }

  var isAvailable: Bool {
    true
  }

  func startRelativeAltitudeUpdates(to queue: OperationQueue, withHandler handler: @escaping CMAltitudeHandler) {
    let kpa = scenario.currentPressure.converted(to: .kilopascals).value
    let data = SimulatedCMAltitudeData(pressureKPa: kpa)
    queue.addOperation {
      handler(data, nil)
    }
  }

  func stopRelativeAltitudeUpdates() {}
}
#endif

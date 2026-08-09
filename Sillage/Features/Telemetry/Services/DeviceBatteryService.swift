//
//  DeviceBatteryService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-09.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import UIKit
import Observation
import OSLog

/// Protocol defining device battery monitoring capabilities for dependency injection and testing.
@MainActor
public protocol DeviceBatteryServiceProtocol: AnyObject, Sendable {
  var batteryLevel: Float? { get }
  var batteryState: UIDevice.BatteryState { get }
}

/// Hardware service providing real-time device battery monitoring using Swift 6 Concurrency and NotificationCenter async sequences.
@Observable
@MainActor
public final class DeviceBatteryService: DeviceBatteryServiceProtocol {
  public private(set) var batteryLevel: Float?
  public private(set) var batteryState: UIDevice.BatteryState

  public init() {
    UIDevice.current.isBatteryMonitoringEnabled = true

    let rawLevel = UIDevice.current.batteryLevel
    let state = UIDevice.current.batteryState

    self.batteryState = state
    self.batteryLevel = (state == .unknown || rawLevel < 0) ? nil : rawLevel

    Logger.telemetry.debug("DeviceBatteryService initialized. State: \(String(describing: state), privacy: .public), level: \(rawLevel, privacy: .public)")

    setupNotificationObservations()
  }

  private func setupNotificationObservations() {
    let levelSequence = NotificationCenter.default.notifications(named: UIDevice.batteryLevelDidChangeNotification)
    let stateSequence = NotificationCenter.default.notifications(named: UIDevice.batteryStateDidChangeNotification)

    Task { [weak self] in
      for await _ in levelSequence {
        guard let self else { break }
        self.updateBatteryStatus()
      }
    }

    Task { [weak self] in
      for await _ in stateSequence {
        guard let self else { break }
        self.updateBatteryStatus()
      }
    }
  }

  private func updateBatteryStatus() {
    let rawLevel = UIDevice.current.batteryLevel
    let state = UIDevice.current.batteryState

    self.batteryState = state
    self.batteryLevel = (state == .unknown || rawLevel < 0) ? nil : rawLevel

    Logger.telemetry.debug("Battery status updated. State: \(String(describing: state), privacy: .public), level: \(rawLevel, privacy: .public)")
  }
}

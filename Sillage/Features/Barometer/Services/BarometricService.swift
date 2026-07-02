//
//  BarometricService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreMotion
import OSLog
import Observation

@Observable
@MainActor
public final class BarometricService {
  
  // MARK: - State (Exposed)
  
  public private(set) var currentPressure: Measurement<UnitPressure>?
  public private(set) var trend3Hours: Measurement<UnitPressure>?
  public private(set) var sensorState: SensorHealth = .idle
  
  /// Calibration offset applied to the raw sensor data.
  public var offset: Measurement<UnitPressure> = Measurement(value: 0, unit: .hectopascals)
  
  // MARK: - Dependencies
  
  private let historyStore: BarometricHistoryStore
  private let altimeter: AltimeterProvider
  private let dateProvider: @Sendable () -> Date
  
  // MARK: - Internal State
  
  /// Dedicated queue for CoreMotion hardware updates
  private let updatesQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "com.alcyone.sillage.barometer.updates"
    queue.qualityOfService = .utility
    return queue
  }()
  
  /// Temporary buffer for the 2-minute moving average (moving window)
  private var microBuffer: [(timestamp: Date, pressure: Measurement<UnitPressure>)] = []
  
  /// Defines the duration of the micro-window for smoothing wave noise (120 seconds)
  private let microWindowDuration: TimeInterval = 120
  
  /// Tracks the last time data was saved to the store to throttle disk I/O
  private var lastSaveTimestamp: Date = .distantPast
  
  public init(
    historyStore: BarometricHistoryStore,
    altimeter: AltimeterProvider = CMAltimeter(),
    dateProvider: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.historyStore = historyStore
    self.altimeter = altimeter
    self.dateProvider = dateProvider
  }
  
  // MARK: - Operations
  
  public func startUpdates() {
    guard sensorState == .idle || sensorState == .degraded else {
      Logger.barometer.debug("Update already in progress. Ignoring start request.")
      return
    }
    
    guard altimeter.isAvailable else {
      sensorState = .degraded
      Logger.barometer.error("Altimeter is not available on this device.")
      return
    }
    
    sensorState = .calibrating
    microBuffer.removeAll()
    lastSaveTimestamp = .distantPast
    
    Logger.barometer.info("Starting CMAltimeter updates.")
    
    altimeter.startRelativeAltitudeUpdates(to: updatesQueue) { [weak self] data, error in
      guard let self else { return }
      
      if let error {
        Logger.barometer.error("Altimeter error: \(error.localizedDescription, privacy: .public)")
        Task { @MainActor in
          self.sensorState = .degraded
        }
        return
      }
      
      guard let data else { return }
      
      // CoreMotion provides pressure in kilopascals (kPa).
      let rawPressure = Measurement(value: data.pressure.doubleValue, unit: UnitPressure.kilopascals)
      
      // Route the background callback back to the MainActor securely
      Task { @MainActor in
        self.processRawPressure(rawPressure)
      }
    }
  }
  
  public func stopUpdates() {
    Logger.barometer.info("Stopping CMAltimeter updates.")
    altimeter.stopRelativeAltitudeUpdates()
    sensorState = .idle
    microBuffer.removeAll()
  }
  
  // MARK: - Data Processing
  
  private func processRawPressure(_ rawPressure: Measurement<UnitPressure>) {
    // Trace every hardware wake-up as requested
    Logger.barometer.debug("Hardware wake-up: received raw pressure \(rawPressure.value, privacy: .public) kPa")
    
    let now = dateProvider()
    
    // Convert to hectopascals immediately to establish a single base unit
    let pressureHPa = rawPressure.converted(to: .hectopascals)
    let correctedPressure = pressureHPa + offset
    
    // Add to micro-buffer
    microBuffer.append((timestamp: now, pressure: correctedPressure))
    
    // Prune data older than 2 minutes to maintain the moving window
    let cutoff = now.addingTimeInterval(-microWindowDuration)
    microBuffer = microBuffer.filter { $0.timestamp >= cutoff }
    
    // Calculate moving average to smooth out wave noise (micro-fluctuations in altitude).
    // Uses simple Double addition to avoid high-frequency Measurement allocations.
    let sum = microBuffer.reduce(0.0) { $0 + $1.pressure.value }
    let averageValue = sum / Double(microBuffer.count)
    let averagePressure = Measurement(value: averageValue, unit: UnitPressure.hectopascals)
    
    // Expose the smoothed value to the UI using a deadband filter to prevent UI fatigue and CPU drain
    let deadbandHPa: Double = 0.05
    
    if let currentHPa = currentPressure?.converted(to: .hectopascals).value {
      if abs(averageValue - currentHPa) >= deadbandHPa {
        currentPressure = averagePressure
      }
    } else {
      currentPressure = averagePressure
    }
    
    if sensorState != .active {
      sensorState = .active
    }
    
    // Write to the persistence layer ONLY once every 2 minutes or on the first recorded point
    if lastSaveTimestamp == .distantPast || now.timeIntervalSince(lastSaveTimestamp) >= microWindowDuration {
      let reading = BarometricReading(timestamp: now, pressure: averagePressure)
      let store = self.historyStore
      
      Task {
        await store.add(reading: reading)
        await self.updateTrend()
      }
      
      lastSaveTimestamp = now
    }
  }
  
  private func updateTrend() async {
    // 3 hours = 10800 seconds
    let duration: TimeInterval = 3 * 3600
    let readings = await historyStore.getReadings(for: 3)
    
    // Update the trend on the MainActor
    self.trend3Hours = LinearRegressionCalculator.calculateTrend(from: readings, over: duration)
  }
}

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
  public private(set) var trend1Hour: Measurement<UnitPressure>?
  public private(set) var trend3Hours: Measurement<UnitPressure>?
  public private(set) var sensorState: SensorHealth = .idle
  public private(set) var activeAlarm: WeatherAlarmLevel?
  public private(set) var lastHistoryUpdate: Date = .distantPast
  // MARK: - Dependencies
  
  private let historyStore: BarometricHistoryStore
  private let preferencesService: PreferencesServiceProtocol
  private let notificationService: NotificationService
  private let altimeter: AltimeterProvider
  private let dateProvider: @Sendable () -> Date
  
  private var lastNotifiedAlarmLevel: WeatherAlarmLevel?
  
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
  
  init(
    historyStore: BarometricHistoryStore,
    preferencesService: PreferencesServiceProtocol,
    notificationService: NotificationService,
    altimeter: AltimeterProvider = CMAltimeter(),
    dateProvider: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.historyStore = historyStore
    self.preferencesService = preferencesService
    self.notificationService = notificationService
    self.altimeter = altimeter
    self.dateProvider = dateProvider
    
    observeAlarmToggle()
  }
  
  private func observeAlarmToggle() {
    // Request permission immediately if the alarm is already ON at launch
    if preferencesService.isBaroAlarmEnabled {
       Task { @MainActor in
           _ = try? await notificationService.requestAuthorization()
       }
    }
    
    withObservationTracking {
      _ = preferencesService.isBaroAlarmEnabled
    } onChange: {
      Task { @MainActor [weak self] in
        guard let self else { return }
        // The recursive call will handle the initial check again when re-arming
        self.observeAlarmToggle()
      }
    }
  }
  
  // MARK: - Operations
  
  /// Retrieves the barometric history for the specified number of past hours.
  public func getHistoryReadings(lastHours: Int) async -> [BarometricReading] {
    return await historyStore.getReadings(for: lastHours)
  }
  
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
    let offsetMeasurement = preferencesService.barometerOffset
    let correctedPressure = pressureHPa + offsetMeasurement
    
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
    let duration3h: TimeInterval = 3 * 3600
    let readings3h = await historyStore.getReadings(for: 3)
    
    // Atomically derive 1-hour readings from the 3-hour snapshot to prevent data races
    let now = dateProvider()
    let cutoff1h = now.addingTimeInterval(-3600)
    let readings1h = readings3h.filter { $0.timestamp >= cutoff1h }
    let duration1h: TimeInterval = 3600
    
    // Update the trend on the MainActor
    self.trend3Hours = LinearRegressionCalculator.calculateTrend(from: readings3h, over: duration3h)
    self.trend1Hour = LinearRegressionCalculator.calculateTrend(from: readings1h, over: duration1h)
    
    self.evaluateAlarms()
    self.lastHistoryUpdate = now
  }
  
  private func evaluateAlarms() {
    guard preferencesService.isBaroAlarmEnabled else {
      activeAlarm = WeatherAlarmLevel.none
      lastNotifiedAlarmLevel = nil
      return
    }
    
    let t1 = trend1Hour
    let t3 = trend3Hours
    
    if t1 == nil && t3 == nil {
      activeAlarm = nil
      return
    }
    
    switch preferencesService.baroAlarmSensitivity {
    case .high:
      if let t1 = t1, t1 <= .highFastDropThreshold {
        activeAlarm = .squall
      } else if let t3 = t3, t3 <= .vigilanceThreshold {
        activeAlarm = .vigilance
      } else {
        activeAlarm = WeatherAlarmLevel.none
      }
    case .medium:
      guard let t3 = t3 else {
        activeAlarm = nil
        return
      }
      activeAlarm = t3 <= .galeThreshold ? .gale : WeatherAlarmLevel.none
    case .low:
      guard let t3 = t3 else {
        activeAlarm = nil
        return
      }
      activeAlarm = t3 <= .stormThreshold ? .storm : WeatherAlarmLevel.none
    }
    
    if let newAlarm = activeAlarm, newAlarm != WeatherAlarmLevel.none, newAlarm != lastNotifiedAlarmLevel {
      lastNotifiedAlarmLevel = newAlarm
      
      let title = "Weather Alarm: \(newAlarm.localizedName)"
      let body = "A rapid pressure drop has been detected. Prepare for worsening conditions."
      let identifier = "sillage.barometer.\(String(describing: newAlarm))"
      
      Task {
        await notificationService.sendNotification(title: title, body: body, identifier: identifier)
      }
    } else if activeAlarm == WeatherAlarmLevel.none {
      lastNotifiedAlarmLevel = WeatherAlarmLevel.none
    }
  }
}

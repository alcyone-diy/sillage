//
//  BarometerViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Observation
import OSLog

@Observable
@MainActor
public final class BarometerViewModel {
  
  // MARK: - Dependencies
  public let service: BarometricService
  private var preferencesService: PreferencesService
  
  // MARK: - Internal Tasks
  nonisolated(unsafe) private var fetchTask: Task<Void, Never>?
  
  // MARK: - Settings Bindings
  public var isAlarmEnabled: Bool {
    get { preferencesService.isBaroAlarmEnabled }
    set { preferencesService.isBaroAlarmEnabled = newValue }
  }
  
  public var sensitivity: BaroAlarmSensitivity {
    get { preferencesService.baroAlarmSensitivity }
    set { preferencesService.baroAlarmSensitivity = newValue }
  }
  
  public var offsetValueForStepper: Double {
    get { preferencesService.barometerOffset.converted(to: .hectopascals).value }
    set { preferencesService.barometerOffset = Measurement(value: newValue, unit: .hectopascals) }
  }
  
  /// Provides raw uncalibrated pressure for UI display
  public var rawPressureFormatted: String? {
    guard let current = service.currentPressure else { return nil }
    // Subtract current offset via Measurement API to preserve type safety and precision
    let offsetMeasurement = preferencesService.barometerOffset
    let rawMeasurement = current - offsetMeasurement
    return pressureFormatter.string(from: rawMeasurement)
  }
  
  // MARK: - Private Formatters
  
  private let pressureFormatter: MeasurementFormatter = {
    let fmt = MeasurementFormatter()
    fmt.unitOptions = .providedUnit 
    fmt.numberFormatter.minimumFractionDigits = 1
    fmt.numberFormatter.maximumFractionDigits = 1
    fmt.numberFormatter.usesGroupingSeparator = false 
    return fmt
  }()
  
  private let trendFormatter: MeasurementFormatter = {
    let fmt = MeasurementFormatter()
    fmt.unitOptions = .providedUnit 
    fmt.numberFormatter.minimumFractionDigits = 1
    fmt.numberFormatter.maximumFractionDigits = 1
    fmt.numberFormatter.usesGroupingSeparator = false 
    // Delegate sign rendering to Foundation to ensure proper localization support
    fmt.numberFormatter.positivePrefix = "+"
    return fmt
  }()
  
  // MARK: - Initialization
  init(service: BarometricService, preferencesService: PreferencesService) {
    self.service = service
    self.preferencesService = preferencesService
  }
  
  deinit {
    fetchTask?.cancel()
  }
  
  // MARK: - History State
  
  /// Holds the active lookback window barometric history (defaults to 24 hours) for chart rendering.
  public var history24h: [BarometricReading] = []
  
  /// Wrapper for graph data to properly break the line across missing data gaps.
  public struct ChartDataPoint: Identifiable, Sendable {
    public let id = UUID()
    public let reading: BarometricReading
    public let segmentId: Int
  }
  
  public var chartData: [ChartDataPoint] = []
  
  /// Asynchronously refreshes the barometric history for a specific lookback window (defaults to 24 hours)
  /// without loading the full 7-day database into memory.
  public func refreshHistory(lastHours: Int = 24) async {
    let readings = await service.getHistoryReadings(lastHours: lastHours)
    processHistoryReadings(readings)
  }
  
  /// Asynchronously refreshes the barometric history for an explicit date interval.
  public func refreshHistory(in interval: DateInterval) async {
    do {
      let readings = try await service.getHistoryReadings(in: interval)
      processHistoryReadings(readings)
    } catch {
      Logger.barometer.error("Failed to load barometric history for custom interval: \(error.localizedDescription, privacy: .public)")
    }
  }
  
  /// Asynchronously refreshes the barometric history for an explicit date interval with debouncing (150ms)
  /// and formal Task cancellation checks to protect against saturating SQLite during rapid scrolling or zooming.
  public func refreshHistoryDebounced(in interval: DateInterval) {
    fetchTask?.cancel()
    fetchTask = Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        try await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }
        
        let readings = try await self.service.getHistoryReadings(in: interval)
        guard !Task.isCancelled else { return }
        
        self.processHistoryReadings(readings)
      } catch is CancellationError {
        // Silently ignore task cancellation to prevent log noise
      } catch {
        Logger.barometer.error("Failed to load debounced barometric history: \(error.localizedDescription, privacy: .public)")
      }
    }
  }
  
  /// Asynchronously refreshes the barometric history for a specific lookback window with debouncing (150ms).
  public func refreshHistoryDebounced(lastHours: Int = 24) {
    let now = Date.now
    let interval = DateInterval(start: now.addingTimeInterval(-Double(lastHours) * 3600), end: now)
    refreshHistoryDebounced(in: interval)
  }
  
  private func processHistoryReadings(_ readings: [BarometricReading]) {
    var newChartData: [ChartDataPoint] = []
    var currentSegment = 0
    var lastTimestamp: Date?
    
    // Segregate data into disconnected lines if gaps > 5 minutes are found
    for reading in readings.sorted(by: { $0.timestamp < $1.timestamp }) {
      if let last = lastTimestamp {
        if reading.timestamp.timeIntervalSince(last) > 300 {
          currentSegment += 1
        }
      }
      newChartData.append(ChartDataPoint(reading: reading, segmentId: currentSegment))
      lastTimestamp = reading.timestamp
    }
    
    self.history24h = readings
    self.chartData = newChartData
  }
  
  // MARK: - Lifecycle Actions
  
  /// Starts barometric updates if not already running.
  public func startUpdates() {
    service.startUpdates()
  }
  
  // MARK: - Permissions
  
  var permissionGateType: PermissionGateType? = nil
  private var pendingAction: (@MainActor () -> Void)? = nil
  
  func requestToggleAlarm(isOn: Bool, in service: PermissionService) {
    if isOn {
      let status = service.notificationStatus
      if status == .authorized {
        self.isAlarmEnabled = true
      } else {
        self.pendingAction = { [weak self] in self?.isAlarmEnabled = true }
        self.permissionGateType = .notification(trigger: .baroAlarm)
      }
    } else {
      self.isAlarmEnabled = false
    }
  }
  
  func finalizePendingAction() {
    pendingAction?()
    pendingAction = nil
  }
  
  // MARK: - Presentation State (Computed)
  
  /// Formatted current pressure, strictly nil if data is unavailable.
  public var formattedPressure: String? {
    guard let pressure = service.currentPressure else { return nil }
    return pressureFormatter.string(from: pressure)
  }
  
  /// Formatted trend over 3 hours, strictly nil if buffer is insufficient.
  public var formattedTrend: String? {
    guard let trend = service.trend3Hours else { return nil }
    let trendString = trendFormatter.string(from: trend)
    return String(localized: "\(trendString)/3h", comment: "Format for 3-hour barometric trend suffix")
  }
  
  public var sensorState: SensorHealth {
    return service.sensorState
  }
  
  /// Evaluates the 3-hour trend to return a mutually exclusive weather alarm level.
  /// Strictly returns nil if the trend buffer is insufficient to evaluate the weather state.
  public var alarmLevel: WeatherAlarmLevel? {
    return service.activeAlarm
  }
}

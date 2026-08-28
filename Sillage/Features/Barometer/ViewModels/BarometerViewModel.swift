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
  private let clock: any Clock<Duration>
  private let dateProvider: @Sendable () -> Date
  
  // MARK: - Internal Tasks
  @ObservationIgnored
  private var fetchTask: Task<Void, Never>?
  
  // MARK: - Settings Bindings
  public var isAlarmEnabled: Bool {
    get { preferencesService.isBaroAlarmEnabled }
    set { preferencesService.isBaroAlarmEnabled = newValue }
  }
  
  public var sensitivity: BaroAlarmSensitivity {
    get { preferencesService.baroAlarmSensitivity }
    set { preferencesService.baroAlarmSensitivity = newValue }
  }
  
  // MARK: - Sensor Offset Calibration
  
  public var offsetValueForStepper: Double {
    get { preferencesService.barometerOffset.converted(to: .hectopascals).value }
    set { preferencesService.barometerOffset = Measurement(value: newValue, unit: .hectopascals) }
  }
  
  public var sensorOffset: Measurement<UnitPressure> {
    get { preferencesService.barometerOffset }
    set { preferencesService.barometerOffset = newValue }
  }
  
  /// Provides raw uncalibrated pressure for UI display
  public var rawPressureFormatted: String? {
    guard let current = service.currentPressure else { return nil }
    // Subtract current offset via Measurement API to preserve type safety and precision
    let offsetMeasurement = sensorOffset
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
  
  init(
    service: BarometricService,
    preferencesService: PreferencesService,
    clock: any Clock<Duration> = ContinuousClock(),
    dateProvider: @escaping @Sendable () -> Date = { Date.now }
  ) {
    self.service = service
    self.preferencesService = preferencesService
    self.clock = clock
    self.dateProvider = dateProvider
    self.latestTimestamp = dateProvider()
  }
  
  /// Awaits completion of ongoing debounced tasks for deterministic unit testing.
  public func waitUntilIdle() async {
    await fetchTask?.value
  }
  
  // MARK: - History State
  
  /// Maximum history duration in hours to load into memory for continuous chart scrolling (7 days = 168 hours)
  public static let maxHistoryHours: Int = 7 * 24

  /// Holds the cached barometric history for the chart.
  public var historyReadings: [BarometricReading] = []
  
  /// Backwards-compatible alias for existing consumers
  public var history24h: [BarometricReading] {
    get { historyReadings }
    set { historyReadings = newValue }
  }
  
  /// Stable anchor timestamp representing the current time reference for the chart.
  /// Used by UI views to bound chart scales up to the current date and time.
  public private(set) var latestTimestamp: Date
  
  /// Explicitly updates the chart scale reference timestamp to current time.
  public func updateLatestTimestamp() {
    self.latestTimestamp = dateProvider()
  }
  
  /// Wrapper for graph data to properly break the line across missing data gaps.
  public struct ChartDataPoint: Identifiable, Sendable {
    public let id = UUID()
    public let reading: BarometricReading
    public let segmentId: Int
  }
  
  public var chartData: [ChartDataPoint] = []
  
  /// Persistent accumulated Y-axis domain envelope ensuring the scale only expands (upper bound never decreases, lower bound never increases) during scrolling.
  private var accumulatedChartDomain: ClosedRange<Double>?
  
  /// The active Y-axis domain for chart rendering.
  public var chartDomain: ClosedRange<Double> {
    accumulatedChartDomain ?? computeSliceDomain(for: historyReadings)
  }
  
  /// Resets the accumulated chart domain envelope back to the initial state.
  public func resetChartDomain() {
    accumulatedChartDomain = nil
  }
  
  /// Updates the dynamic accumulated chart domain based on in-memory readings within the currently visible window.
  public func updateVisibleWindow(start: Date, duration: TimeInterval = 24 * 3600) {
    let windowEnd = start.addingTimeInterval(duration)
    let visibleSlice = historyReadings.filter { $0.timestamp >= start && $0.timestamp <= windowEnd }
    guard !visibleSlice.isEmpty else { return }
    
    let sliceDomain = computeSliceDomain(for: visibleSlice)
    if let current = accumulatedChartDomain {
      let newLower = min(current.lowerBound, sliceDomain.lowerBound)
      let newUpper = max(current.upperBound, sliceDomain.upperBound)
      self.accumulatedChartDomain = newLower...newUpper
    } else {
      self.accumulatedChartDomain = sliceDomain
    }
  }
  
  /// Computes a Y-axis domain that spans at least 5 hPa for a given slice of readings to avoid exaggerating micro-fluctuations.
  private func computeSliceDomain(for readings: [BarometricReading]) -> ClosedRange<Double> {
    guard let minReading = readings.min(by: { $0.pressure < $1.pressure }),
          let maxReading = readings.max(by: { $0.pressure < $1.pressure }) else {
      let defaultCenter = service.currentPressure?.converted(to: .hectopascals).value ?? 1013.25
      return (defaultCenter - 2.5)...(defaultCenter + 2.5)
    }
    
    let minVal = minReading.pressure.converted(to: .hectopascals).value
    let maxVal = maxReading.pressure.converted(to: .hectopascals).value
    let range = maxVal - minVal
    
    // Ensure a minimum 5 hPa span so normal diurnal tides (2-3 hPa) fit without exaggerating small drops.
    if range < 5.0 {
      let center = (minVal + maxVal) / 2.0
      return (center - 2.5)...(center + 2.5)
    } else {
      let padding = range * 0.1
      return (minVal - padding)...(maxVal + padding)
    }
  }
  
  /// Asynchronously loads the full 7-day barometric history into memory for seamless, real-time scrolling without SQLite thrashing.
  public func refreshFullHistory() async {
    await refreshHistory(lastHours: Self.maxHistoryHours)
  }
  
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
        try await self.clock.sleep(for: .milliseconds(150))
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
    let now = dateProvider()
    let interval = DateInterval(start: now.addingTimeInterval(-Double(lastHours) * 3600), end: now)
    refreshHistoryDebounced(in: interval)
  }
  
  private func processHistoryReadings(_ readings: [BarometricReading]) {
    var newChartData: [ChartDataPoint] = []
    var currentSegment = 0
    var lastTimestamp: Date?
    
    let sortedReadings = readings.sorted(by: { $0.timestamp < $1.timestamp })
    
    // Segregate data into disconnected lines if gaps > 5 minutes are found
    for reading in sortedReadings {
      if let last = lastTimestamp {
        if reading.timestamp.timeIntervalSince(last) > 300 {
          currentSegment += 1
        }
      }
      newChartData.append(ChartDataPoint(reading: reading, segmentId: currentSegment))
      lastTimestamp = reading.timestamp
    }
    
    self.historyReadings = readings
    self.chartData = newChartData
    
    // Update expanding accumulated Y-domain envelope so bounds monotonically widen
    if !readings.isEmpty {
      let now = dateProvider()
      let recentSlice = readings.filter { $0.timestamp >= now.addingTimeInterval(-24 * 3600) }
      let sliceToUse = recentSlice.isEmpty ? readings : recentSlice
      let sliceDomain = computeSliceDomain(for: sliceToUse)
      
      if let current = accumulatedChartDomain {
        let newLower = min(current.lowerBound, sliceDomain.lowerBound)
        let newUpper = max(current.upperBound, sliceDomain.upperBound)
        self.accumulatedChartDomain = newLower...newUpper
      } else {
        self.accumulatedChartDomain = sliceDomain
      }
    }
    
    // Keep latestTimestamp anchored to current time so the user can always scroll right to the present
    let now = dateProvider()
    if now > self.latestTimestamp {
      self.latestTimestamp = now
    }
  }
  
  // MARK: - Lifecycle Actions
  
  /// Starts barometric updates and resets the chart domain envelope for a fresh session.
  public func startUpdates() {
    resetChartDomain()
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

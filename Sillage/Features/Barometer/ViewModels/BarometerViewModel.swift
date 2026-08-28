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
  @ObservationIgnored
  private var anchorUpdateTask: Task<Void, Never>?
  
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
  /// Cached localized strings to avoid re-evaluating localization on every frame
  private let todayLocalized = String(localized: "Today")
  private let yesterdayLocalized = String(localized: "Yesterday")
  
  /// Safe time margin from midnight boundaries to keep day labels centered within their day zone
  public static let labelTimeMargin: TimeInterval = 3 * 3600
  
  /// Information structure pairing each day anchor date coordinate with its formatted label.
  public struct DayAnchorItem: Identifiable, Equatable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let label: String
    
    public init(date: Date, label: String) {
      self.date = date
      self.label = label
    }
  }
  
  /// Precomputed day boundary anchors for the top axis of the barometric chart.
  public private(set) var visibleDayAnchors: [DayAnchorItem] = []
  
  /// Precomputed midnight timestamps across the 7-day span for chart vertical separator lines.
  public private(set) var midnightBoundaries: [Date] = []
  
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
    let now = dateProvider()
    self.latestTimestamp = now
    let calendar = Calendar.current
    let startOfToday = calendar.startOfDay(for: now)
    self.midnightBoundaries = (0...7).compactMap { daysAgo in
      calendar.date(byAdding: .day, value: -daysAgo, to: startOfToday)
    }
  }
  
  /// Awaits completion of ongoing debounced tasks (history fetch and anchor update) for deterministic unit testing.
  public func waitUntilIdle() async {
    await fetchTask?.value
    await anchorUpdateTask?.value
  }
  
  // MARK: - Day Boundary & Label Calculations
  
  /// Formats a legible day label in English: "Today", "Yesterday", or "<Weekday> (D-<N>)"
  public func dayLabel(for date: Date) -> String {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: latestTimestamp)
    let dateDay = calendar.startOfDay(for: date)
    
    let daysAgo = calendar.dateComponents([.day], from: dateDay, to: today).day ?? 0
    let fullWeekday = date.formatted(.dateTime.weekday(.wide))
    
    if daysAgo == 0 {
      return todayLocalized
    } else if daysAgo == 1 {
      return yesterdayLocalized
    } else {
      return "\(fullWeekday) (D-\(daysAgo))"
    }
  }
  
  /// Calculates the day anchors dynamically centered within each day's visible section in the pure time domain.
  public func computeVisibleDayAnchors(scrollPosition: Date, visibleDurationSeconds: TimeInterval) -> [DayAnchorItem] {
    let calendar = Calendar.current
    let visibleStart = scrollPosition
    let visibleEnd = scrollPosition.addingTimeInterval(visibleDurationSeconds)
    let startOfToday = calendar.startOfDay(for: latestTimestamp)
    let margin = Self.labelTimeMargin
    
    return (0...7).compactMap { daysAgo -> DayAnchorItem? in
      guard let dayStart = calendar.date(byAdding: .day, value: -daysAgo, to: startOfToday),
            let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
        return nil
      }
      
      // Upper bound of the calendar day (clamped to latest available timestamp for today)
      let dayEnd = min(nextDayStart, latestTimestamp)
      
      // Intersection between this day and the active 24-hour viewport
      let segmentStart = max(dayStart, visibleStart)
      let segmentEnd = min(dayEnd, visibleEnd)
      
      let visibleDuration = segmentEnd.timeIntervalSince(segmentStart)
      // Hide label if the visible portion is smaller than the safety margin
      guard visibleDuration >= margin else {
        return nil
      }
      
      let fullDayDuration = dayEnd.timeIntervalSince(dayStart)
      let anchorDate: Date
      if fullDayDuration < margin * 2 {
        // When the day duration itself is shorter than twice the margin (e.g. early morning of today),
        // place anchor at the center of the available day
        anchorDate = dayStart.addingTimeInterval(fullDayDuration / 2.0)
      } else {
        // Geometric center of the visible portion of this day on screen
        let visibleMidpoint = segmentStart.addingTimeInterval(visibleDuration / 2.0)
        
        // Clamping bounds to guarantee zero character overflow beyond midnight lines
        let minAnchor = dayStart.addingTimeInterval(margin)
        let maxAnchor = dayEnd.addingTimeInterval(-margin)
        anchorDate = min(max(visibleMidpoint, minAnchor), maxAnchor)
      }
      
      let label = dayLabel(for: dayStart.addingTimeInterval(12 * 3600))
      return DayAnchorItem(date: anchorDate, label: label)
    }
  }
  
  /// Immediately updates visible day anchors without debouncing (e.g. on view appear or initial orientation layout).
  public func updateVisibleDayAnchors(scrollPosition: Date, visibleDurationSeconds: TimeInterval) {
    anchorUpdateTask?.cancel()
    self.visibleDayAnchors = computeVisibleDayAnchors(
      scrollPosition: scrollPosition,
      visibleDurationSeconds: visibleDurationSeconds
    )
  }
  
  /// Updates visible day anchors with throttling/debouncing (50ms) to conserve CPU during high-frequency scrolling.
  public func updateVisibleDayAnchorsDebounced(scrollPosition: Date, visibleDurationSeconds: TimeInterval) {
    anchorUpdateTask?.cancel()
    anchorUpdateTask = Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        try await self.clock.sleep(for: .milliseconds(50))
        guard !Task.isCancelled else { return }
        self.visibleDayAnchors = self.computeVisibleDayAnchors(
          scrollPosition: scrollPosition,
          visibleDurationSeconds: visibleDurationSeconds
        )
      } catch {
        // Task cancelled
      }
    }
  }
  
  // MARK: - History State
  
  /// Holds the active lookback window barometric history (defaults to 24 hours) for chart rendering.
  public var history24h: [BarometricReading] = []
  
  /// Stable anchor timestamp representing the current time reference for the chart.
  /// Used by UI views to bound chart scales up to the current date and time.
  public private(set) var latestTimestamp: Date
  
  /// Explicitly updates the chart scale reference timestamp to current time and refreshes day boundaries.
  public func updateLatestTimestamp() {
    self.latestTimestamp = dateProvider()
    let calendar = Calendar.current
    let startOfToday = calendar.startOfDay(for: latestTimestamp)
    self.midnightBoundaries = (0...7).compactMap { daysAgo in
      calendar.date(byAdding: .day, value: -daysAgo, to: startOfToday)
    }
  }
  
  /// Wrapper for graph data to properly break the line across missing data gaps.
  public struct ChartDataPoint: Identifiable, Sendable {
    public let id = UUID()
    public let reading: BarometricReading
    public let segmentId: Int
  }
  
  public var chartData: [ChartDataPoint] = []
  
  /// Computes a Y-axis domain that spans at least 5 hPa to avoid exaggerating micro-fluctuations
  public var chartDomain: ClosedRange<Double> {
    guard let minReading = history24h.min(by: { $0.pressure < $1.pressure }),
          let maxReading = history24h.max(by: { $0.pressure < $1.pressure }) else {
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
    
    self.history24h = readings
    self.chartData = newChartData
    // Keep latestTimestamp anchored to current time so the user can always scroll right to the present
    let now = dateProvider()
    if now > self.latestTimestamp {
      self.latestTimestamp = now
    }
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

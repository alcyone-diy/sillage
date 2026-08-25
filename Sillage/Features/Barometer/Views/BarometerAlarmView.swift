//
//  BarometerAlarmView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import Charts

/// The main presentation widget for Barometric Telemetry.
/// It observes the BarometerViewModel and renders current pressure and a horizontally scrollable 7-day history chart.
public struct BarometerAlarmView: View {
  @Bindable var viewModel: BarometerViewModel
  @Environment(PermissionService.self) private var permissionService
  @Environment(\.marineTheme) private var marineTheme
  
  /// Total duration visible on screen at any given time (24 hours in seconds)
  private let visibleDurationSeconds: TimeInterval = 24 * 3600
  
  /// Maximum history span available in SQLite (7 days in seconds)
  private let maxHistorySpanSeconds: TimeInterval = 7 * 24 * 3600
  
  /// Current horizontal scroll anchor position (defaults to the start of the latest 24-hour slice)
  @State private var scrollPosition: Date = Date.now.addingTimeInterval(-24 * 3600)
  
  public init(viewModel: BarometerViewModel) {
    self.viewModel = viewModel
  }
  
  public var body: some View {
    Form {
      // MARK: - Vital Information (Socle)
      Section(header: Text("Pressure")) {
        VStack(spacing: MarineTheme.Spacing.medium) {
          HStack {
            VStack(alignment: .leading) {
              if let pressure = viewModel.formattedPressure {
                Text(pressure)
                  .marineFont(.instrumentData)
                  .foregroundColor(alarmColor)
              } else {
                Text("Acquiring...")
                  .marineFont(.body)
                  .foregroundColor(marineTheme.colors.textSecondary)
              }
            }
            
            Spacer()
            
            // 3-hour trend & Alarm Name
            VStack(alignment: .trailing, spacing: 4) {
              if let trend = viewModel.formattedTrend {
                Text(trend)
                  .marineFont(.title3)
                  .foregroundColor(alarmColor)
              }
              if let alarm = viewModel.alarmLevel, alarm != .none {
                Text(alarm.localizedName)
                  .font(.caption.bold())
                  .foregroundColor(alarmColor)
              }
            }
          }
          
          // MARK: - Horizontally Scrollable 7-Day History Chart (Persistent)
          Chart {
            // 1. Midnight vertical day separators
            ForEach(midnightBoundaries, id: \.self) { midnight in
              RuleMark(x: .value("Day Boundary", midnight))
                .foregroundStyle(marineTheme.colors.textSecondary.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }
            
            // 2. Pressure curve data points
            ForEach(viewModel.chartData) { dataPoint in
              LineMark(
                x: .value("Time", dataPoint.reading.timestamp),
                y: .value("hPa", dataPoint.reading.pressure.value),
                series: .value("Segment", dataPoint.segmentId)
              )
              .foregroundStyle(alarmColor)
            }
          }
          .chartScrollableAxes(.horizontal)
          .chartXVisibleDomain(length: visibleDurationSeconds)
          .chartScrollPosition(x: $scrollPosition)
          .chartXScale(domain: viewModel.latestTimestamp.addingTimeInterval(-maxHistorySpanSeconds)...viewModel.latestTimestamp)
          .chartYScale(domain: chartDomain)
          .chartYAxis {
            AxisMarks(position: .leading) { value in
              AxisGridLine()
              AxisTick()
              AxisValueLabel {
                if let hpa = value.as(Double.self) {
                  Text(String(format: "%.1f", hpa))
                }
              }
            }
          }
          .chartXAxis {
            // Top axis: Clear day labels positioned at midday (12:00)
            AxisMarks(position: .top, values: middayAnchors) { value in
              AxisValueLabel {
                if let date = value.as(Date.self) {
                  Text(dayLabel(for: date))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(marineTheme.colors.textSecondary)
                }
              }
            }
            
            // Bottom axis: Standard hour markers
            AxisMarks(position: .bottom, values: .automatic(desiredCount: 6)) { value in
              AxisGridLine()
              AxisTick()
              AxisValueLabel(format: .dateTime.hour().minute())
            }
          }
          .frame(height: 175)
          .overlay {
            if viewModel.chartData.isEmpty {
              Text("No data recorded for this time period")
                .marineFont(.caption)
                .foregroundColor(marineTheme.colors.textSecondary)
            }
          }
        }
        .padding(.vertical, MarineTheme.Spacing.small)
      }
      .listRowBackground(marineTheme.colors.surfaceBackground)
      
      // MARK: - Settings
      Section(header: Text("Configuration")) {
        Toggle("Weather Alarms", isOn: Binding(
          get: { viewModel.isAlarmEnabled },
          set: { newValue in
            viewModel.requestToggleAlarm(isOn: newValue, in: permissionService)
          }
        ))
        .tint(marineTheme.colors.accent)
        
        if viewModel.isAlarmEnabled {
          VStack(alignment: .leading, spacing: 6) {
            Picker("Alert Level", selection: $viewModel.sensitivity) {
              ForEach(BaroAlarmSensitivity.allCases) { sensitivity in
                Text(sensitivity.localizedName).tag(sensitivity)
              }
            }
            .pickerStyle(.segmented)
            
            Text(viewModel.sensitivity.explanation)
              .font(.caption)
              .foregroundColor(marineTheme.colors.textSecondary)
            
            Text("Note: The alarm only works in the background if you are recording a track or the anchor alarm is active.")
              .font(.caption)
              .foregroundColor(.primary)
              .padding(.top, 4)
          }
          .padding(.vertical, 4)
        }
        
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Text("Sensor Offset")
            Spacer()
            Stepper(value: $viewModel.offsetValueForStepper, in: -50...50, step: 0.1) {
              Text(String(format: "%+.1f hPa", viewModel.offsetValueForStepper))
                .foregroundColor(marineTheme.colors.accent)
            }
          }
          if let raw = viewModel.rawPressureFormatted {
            Text("Raw sensor: \(raw)")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }
        .padding(.vertical, 4)
      }
      .listRowBackground(marineTheme.colors.surfaceBackground)
    }
    .marineListBackground()
    .navigationTitle("Barometer Alarm")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      viewModel.startUpdates()
      loadVisibleData(around: scrollPosition)
    }
    .onChange(of: scrollPosition) { _, newPosition in
      loadVisibleData(around: newPosition)
    }
    .task(id: viewModel.service.lastHistoryUpdate) {
      loadVisibleData(around: scrollPosition)
    }
    .sheet(item: $viewModel.permissionGateType) { gateType in
      PermissionGateView(type: gateType)
        .presentationDetents([.medium, .large])
    }
    .onChange(of: permissionService.notificationStatus) { _, status in
      if status == .authorized {
        viewModel.finalizePendingAction()
        viewModel.permissionGateType = nil
      }
    }
  }
  
  // MARK: - Dynamic Pagination / Debounced Load
  
  /// Computes the active visible DateInterval from the scroll position (with 1-hour prefetch margin)
  /// and triggers a debounced load from SQLite via BarometerViewModel.
  private func loadVisibleData(around position: Date) {
    let anchor = viewModel.latestTimestamp
    let historyLimit = anchor.addingTimeInterval(-maxHistorySpanSeconds)
    
    // Add 1 hour padding on both ends to ensure uninterrupted line drawing during active scrolling
    let paddedStart = max(historyLimit, position.addingTimeInterval(-3600))
    let paddedEnd = min(anchor, position.addingTimeInterval(visibleDurationSeconds + 3600))
    
    guard paddedEnd > paddedStart else { return }
    let interval = DateInterval(start: paddedStart, end: paddedEnd)
    
    viewModel.refreshHistoryDebounced(in: interval)
  }
  
  // MARK: - Day Boundary & Label Helpers
  
  /// Midnight timestamps across the 7-day span for vertical separator lines
  private var midnightBoundaries: [Date] {
    let calendar = Calendar.current
    let startOfToday = calendar.startOfDay(for: viewModel.latestTimestamp)
    return (0...7).compactMap { daysAgo in
      calendar.date(byAdding: .day, value: -daysAgo, to: startOfToday)
    }
  }
  
  /// Midday (12:00) timestamps across the 7-day span for day badge placement
  private var middayAnchors: [Date] {
    let calendar = Calendar.current
    let startOfToday = calendar.startOfDay(for: viewModel.latestTimestamp)
    return (0...7).compactMap { daysAgo in
      guard let dayStart = calendar.date(byAdding: .day, value: -daysAgo, to: startOfToday) else { return nil }
      return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: dayStart)
    }
  }
  
  /// Formats a legible day label in English combining relative offset and weekday (e.g. "Today", "Yesterday (Mon.)", "Sun. 23 (D-2)")
  private func dayLabel(for date: Date) -> String {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: viewModel.latestTimestamp)
    let dateDay = calendar.startOfDay(for: date)
    
    let daysAgo = calendar.dateComponents([.day], from: dateDay, to: today).day ?? 0
    let weekday = date.formatted(.dateTime.weekday(.short))
    
    if daysAgo == 0 {
      return String(localized: "Today")
    } else if daysAgo == 1 {
      return "\(String(localized: "Yesterday")) (\(weekday))"
    } else {
      let dayNumber = date.formatted(.dateTime.day())
      return "\(weekday) \(dayNumber) (D-\(daysAgo))"
    }
  }
  
  // MARK: - UI Logic
  
  /// Computes a Y-axis domain that spans at least 5 hPa to avoid exaggerating micro-fluctuations
  private var chartDomain: ClosedRange<Double> {
    let history = viewModel.history24h
    guard let minReading = history.min(by: { $0.pressure.value < $1.pressure.value }),
          let maxReading = history.max(by: { $0.pressure.value < $1.pressure.value }) else {
      let defaultCenter = viewModel.service.currentPressure?.converted(to: .hectopascals).value ?? 1013.25
      return (defaultCenter - 2.5)...(defaultCenter + 2.5)
    }
    
    let minVal = minReading.pressure.value
    let maxVal = maxReading.pressure.value
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
  
  /// Computes the thematic color based on the strict weather alarm level.
  private var alarmColor: Color {
    switch viewModel.alarmLevel {
    case .gale, .storm, .squall:
      return marineTheme.colors.destructive
    case .vigilance:
      return marineTheme.colors.warning
    default:
      return marineTheme.colors.primary
    }
  }
}

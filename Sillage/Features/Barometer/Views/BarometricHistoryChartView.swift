//
//  BarometricHistoryChartView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-28.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import Charts

/// A dedicated presentation view for the horizontally scrollable 7-day barometric history chart.
public struct BarometricHistoryChartView: View {
  let viewModel: BarometerViewModel
  @Environment(\.marineTheme) private var marineTheme
  
  /// Total duration visible on screen at any given time (24 hours in seconds)
  private let visibleDurationSeconds: TimeInterval = 24 * 3600
  
  /// Maximum history span available in SQLite (7 days in seconds)
  private let maxHistorySpanSeconds: TimeInterval = 7 * 24 * 3600
  
  /// Tolerance window (in seconds) to consider the scroll position attached to the rightmost trailing edge
  private let trailingEdgeToleranceSeconds: TimeInterval = 60
  
  /// Current horizontal scroll anchor position (defaults to the start of the latest 24-hour slice)
  @State private var scrollPosition: Date = Date.now.addingTimeInterval(-24 * 3600)
  
  public init(viewModel: BarometerViewModel) {
    self.viewModel = viewModel
  }
  
  public var body: some View {
    Chart {
      // 1. Midnight vertical day separators
      ForEach(viewModel.midnightBoundaries, id: \.self) { midnight in
        RuleMark(x: .value("Day Boundary", midnight))
          .foregroundStyle(marineTheme.colors.textSecondary.opacity(0.45))
          .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
      }
      
      // 2. Pressure curve data points
      ForEach(viewModel.chartData) { dataPoint in
        LineMark(
          x: .value("Time", dataPoint.reading.timestamp),
          y: .value("hPa", dataPoint.reading.pressure.converted(to: .hectopascals).value),
          series: .value("Segment", dataPoint.segmentId)
        )
        .foregroundStyle(alarmColor)
      }
    }
    .chartScrollableAxes(.horizontal)
    .chartXVisibleDomain(length: visibleDurationSeconds)
    .chartScrollPosition(x: $scrollPosition)
    .chartXScale(domain: viewModel.latestTimestamp.addingTimeInterval(-maxHistorySpanSeconds)...viewModel.latestTimestamp)
    .chartYScale(domain: viewModel.chartDomain)
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
      topDayAxisMarks
      
      // Bottom axis: Standard hour markers
      AxisMarks(position: .bottom, values: .automatic(desiredCount: 6)) { value in
        AxisGridLine()
        AxisTick()
        AxisValueLabel(format: .dateTime.hour().minute())
      }
    }
    .overlay {
      if viewModel.chartData.isEmpty {
        Text("No data recorded for this time period")
          .marineFont(.caption)
          .foregroundColor(marineTheme.colors.textSecondary)
      }
    }
    .onAppear {
      viewModel.updateVisibleDayAnchors(scrollPosition: scrollPosition, visibleDurationSeconds: visibleDurationSeconds)
      loadVisibleData(around: scrollPosition)
    }
    .onChange(of: scrollPosition) { _, newPosition in
      loadVisibleData(around: newPosition)
      viewModel.updateVisibleDayAnchorsDebounced(scrollPosition: newPosition, visibleDurationSeconds: visibleDurationSeconds)
    }
    .onChange(of: viewModel.latestTimestamp) { oldTimestamp, newTimestamp in
      // When anchored to the rightmost trailing edge (present time), automatically advance the scroll window
      let wasAtTrailingEdge = scrollPosition >= oldTimestamp.addingTimeInterval(-visibleDurationSeconds - trailingEdgeToleranceSeconds)
      if wasAtTrailingEdge {
        scrollPosition = newTimestamp.addingTimeInterval(-visibleDurationSeconds)
        viewModel.updateVisibleDayAnchors(scrollPosition: scrollPosition, visibleDurationSeconds: visibleDurationSeconds)
      }
    }
    .task {
      // Periodically refresh the time anchor every minute while active so the user can always scroll right to the present
      while !Task.isCancelled {
        viewModel.updateLatestTimestamp()
        viewModel.updateVisibleDayAnchors(scrollPosition: scrollPosition, visibleDurationSeconds: visibleDurationSeconds)
        do {
          try await Task.sleep(for: .seconds(60))
        } catch {
          break
        }
      }
    }
    .task(id: viewModel.service.lastHistoryUpdate) {
      loadVisibleData(around: scrollPosition)
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
  
  private var visibleAnchorDates: [Date] {
    viewModel.visibleDayAnchors.map(\.date)
  }
  
  private func labelForAnchorDate(_ date: Date) -> String? {
    viewModel.visibleDayAnchors.first(where: { $0.date == date })?.label
  }
  
  /// Top axis day markers with explicit collisionResolution: .disabled to guarantee zero position drift
  @AxisContentBuilder
  private var topDayAxisMarks: some AxisContent {
    AxisMarks(position: .top, values: visibleAnchorDates) { (value: AxisValue) in
      if let date = value.as(Date.self),
         let label = labelForAnchorDate(date) {
        AxisValueLabel(anchor: .bottom, collisionResolution: .disabled) {
          Text(label)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(marineTheme.colors.textSecondary)
        }
      }
    }
  }
  
  // MARK: - UI Logic
  
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

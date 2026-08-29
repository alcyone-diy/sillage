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
import UIKit

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
  
  /// Currently tapped / scrubbed date on the chart for point inspection
  @State private var selectedDate: Date?
  
  /// Width of the chart plot area in points, dynamically updated on geometry change
  @State private var chartWidth: CGFloat = 360.0
  
  /// UI font matching the Day AxisValueLabel for exact typographical width measurement
  private let labelFont = UIFont.systemFont(ofSize: 11, weight: .bold)
  
  /// UI fonts matching selectionCalloutView for exact typographical measurement
  private let calloutTitleFont = UIFont.systemFont(ofSize: 15, weight: .bold)
  private let calloutSubtitleFont = UIFont.systemFont(ofSize: 12)
  
  public init(viewModel: BarometerViewModel) {
    self.viewModel = viewModel
  }
  
  public var body: some View {
    Chart {
      pressureLineMarks
      inspectionMarks
    }
    .chartScrollableAxes(.horizontal)
    .chartXVisibleDomain(length: visibleDurationSeconds)
    .chartScrollPosition(x: $scrollPosition)
    .chartXSelection(value: $selectedDate)
    .chartXScale(domain: viewModel.latestTimestamp.addingTimeInterval(-maxHistorySpanSeconds)...viewModel.latestTimestamp)
    .chartYScale(domain: viewModel.chartDomain)
    .chartYAxis {
      leadingPressureAxisMarks
    }
    .chartXAxis {
      topMidnightGridMarks
      topDayLabelMarks
      bottomHourAxisMarks
    }
    .overlay {
      if viewModel.chartData.isEmpty {
        Text("No data recorded for this time period")
          .marineFont(.caption)
          .foregroundColor(marineTheme.colors.textSecondary)
      }
    }
    .onGeometryChange(for: CGFloat.self) { proxy in
      proxy.size.width
    } action: { newWidth in
      if newWidth > 0 && newWidth != chartWidth {
        chartWidth = newWidth
      }
    }
    .onAppear {
      Task {
        await viewModel.refreshFullHistory()
      }
    }
    .onChange(of: scrollPosition) { _, newPosition in
      viewModel.updateVisibleWindow(start: newPosition, duration: visibleDurationSeconds)
      // Dismiss selection callout if the selected point scrolls out of the visible viewport
      if let selDate = selectedDate {
        let visibleEnd = newPosition.addingTimeInterval(visibleDurationSeconds)
        if selDate < newPosition || selDate > visibleEnd {
          selectedDate = nil
        }
      }
    }
    .onChange(of: viewModel.latestTimestamp) { oldTimestamp, newTimestamp in
      // When anchored to the rightmost trailing edge (present time), automatically advance the scroll window
      let wasAtTrailingEdge = scrollPosition >= oldTimestamp.addingTimeInterval(-visibleDurationSeconds - trailingEdgeToleranceSeconds)
      if wasAtTrailingEdge {
        scrollPosition = newTimestamp.addingTimeInterval(-visibleDurationSeconds)
      }
    }
    .task {
      // Periodically refresh the time anchor every minute while active so the user can always scroll right to the present
      while !Task.isCancelled {
        viewModel.updateLatestTimestamp()
        await viewModel.refreshFullHistory()
        do {
          try await Task.sleep(for: .seconds(60))
        } catch {
          break
        }
      }
    }
    .task(id: viewModel.service.lastHistoryUpdate) {
      await viewModel.refreshFullHistory()
    }
  }
  
  // MARK: - Chart Content Builders
  
  /// Pressure curve continuous line marks
  @ChartContentBuilder
  private var pressureLineMarks: some ChartContent {
    ForEach(viewModel.chartData) { dataPoint in
      LineMark(
        x: .value("Time", dataPoint.reading.timestamp),
        y: .value("hPa", dataPoint.reading.pressure.converted(to: .hectopascals).value),
        series: .value("Segment", dataPoint.segmentId)
      )
      .foregroundStyle(alarmColor)
    }
  }
  
  /// Selected inspection point callout and vertical cursor line.
  /// Renders in strict Z-order so the floating badge always appears on top of the curve.
  @ChartContentBuilder
  private var inspectionMarks: some ChartContent {
    if let selectedDate,
       let point = closestReading(to: selectedDate) {
      let reading = point.reading
      let pressureHPa = reading.pressure.converted(to: .hectopascals).value
      
      // 1. Vertical cursor line (drawn in the background)
      RuleMark(x: .value("Time", reading.timestamp))
        .foregroundStyle(marineTheme.colors.textSecondary.opacity(0.6))
        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
      
      // 2. Highlighted point on the pressure curve (drawn below the callout bubble)
      PointMark(
        x: .value("Time", reading.timestamp),
        y: .value("hPa", pressureHPa)
      )
      .symbolSize(60)
      .foregroundStyle(marineTheme.colors.primary)
      
      // 3. Top anchor for the floating inspection badge.
      // The badge is centered on the point in the viewport, but clamps continuously to the
      // edges using its exact typographical width so it remains smoothly blocked against the screen limits.
      let clampedDate = clampedCalloutDate(for: reading)
      PointMark(
        x: .value("Time", clampedDate),
        y: .value("hPa", viewModel.chartDomain.upperBound)
      )
      .opacity(0)
      .annotation(
        position: .bottom,
        spacing: 6
      ) {
        selectionCalloutView(for: reading)
      }
    }
  }
  
  // MARK: - Axis Marks Builders
  
  /// Midnight vertical grid lines aligned strictly to startOfDay (00:00:00)
  @AxisContentBuilder
  private var topMidnightGridMarks: some AxisContent {
    AxisMarks(position: .top, values: .stride(by: .day)) { (_: AxisValue) in
      AxisGridLine(stroke: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        .foregroundStyle(marineTheme.colors.textSecondary.opacity(0.45))
    }
  }
  
  /// Day name labels dynamically positioned following rules:
  /// 1. Never crosses day boundaries (previous/next day)
  /// 2. If insufficient visible space, placed at day edge and clipped by chart bounds
  /// 3. When sufficient space is available, centered in the visible day section
  @AxisContentBuilder
  private var topDayLabelMarks: some AxisContent {
    AxisMarks(position: .top, values: visibleDayAnchors.map(\.date)) { (value: AxisValue) in
      if let date = value.as(Date.self),
         let label = visibleDayAnchors.first(where: { $0.date == date })?.label {
        AxisValueLabel(anchor: .bottom, collisionResolution: .disabled) {
          Text(label)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(marineTheme.colors.textSecondary)
        }
      }
    }
  }
  
  /// Bottom axis standard hour markers
  @AxisContentBuilder
  private var bottomHourAxisMarks: some AxisContent {
    AxisMarks(position: .bottom, values: .automatic(desiredCount: 6)) { (_: AxisValue) in
      AxisGridLine()
      AxisTick()
      AxisValueLabel(format: .dateTime.hour().minute())
    }
  }
  
  /// Leading Y-axis pressure markers
  @AxisContentBuilder
  private var leadingPressureAxisMarks: some AxisContent {
    AxisMarks(position: .leading) { (value: AxisValue) in
      AxisGridLine()
      AxisTick()
      AxisValueLabel {
        if let hpa = value.as(Double.self) {
          Text(String(format: "%.1f", hpa))
        }
      }
    }
  }
  
  /// Finds the closest recorded barometric reading point within a 1-hour proximity of the selected timestamp,
  /// strictly bounded within the currently visible viewport.
  /// Uses a single-pass O(N) search to guarantee fluid 60/120 FPS scrubbing.
  private func closestReading(to targetDate: Date) -> BarometerViewModel.ChartDataPoint? {
    let visibleStart = scrollPosition
    let visibleEnd = scrollPosition.addingTimeInterval(visibleDurationSeconds)
    
    // 1. Ensure the user's touch coordinate is within the current visible 24-hour viewport
    guard targetDate >= visibleStart && targetDate <= visibleEnd else {
      return nil
    }
    
    let maxThresholdSeconds: TimeInterval = 3600
    // 2. Find the candidate point with minimum absolute time delta in a single pass
    guard let closest = viewModel.chartData.min(by: {
      abs($0.reading.timestamp.timeIntervalSince(targetDate)) < abs($1.reading.timestamp.timeIntervalSince(targetDate))
    }) else { return nil }
    
    // 3. Strictly ensure the resolved point is visible on screen and within the 1-hour tolerance
    let pointTimestamp = closest.reading.timestamp
    guard pointTimestamp >= visibleStart && pointTimestamp <= visibleEnd else {
      return nil
    }
    
    if abs(pointTimestamp.timeIntervalSince(targetDate)) <= maxThresholdSeconds {
      return closest
    }
    return nil
  }
  
  /// High-contrast MarineTheme callout badge displaying the exact pressure value and formatted timestamp.
  @ViewBuilder
  private func selectionCalloutView(for reading: BarometricReading) -> some View {
    VStack(alignment: .center, spacing: 2) {
      Text(String(format: "%.1f hPa", reading.pressure.converted(to: .hectopascals).value))
        .marineFont(.subheadline)
        .fontWeight(.bold)
        .foregroundColor(marineTheme.colors.textPrimary)
      Text(reading.timestamp.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
        .marineFont(.caption)
        .foregroundColor(marineTheme.colors.textSecondary)
    }
    .fixedSize()
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(
      RoundedRectangle(cornerRadius: 6)
        .fill(marineTheme.colors.panelBackground)
        .overlay(
          RoundedRectangle(cornerRadius: 6)
            .stroke(marineTheme.colors.border, lineWidth: 1)
        )
        .shadow(color: marineTheme.colors.shadow, radius: 3, x: 0, y: 2)
    )
    .onTapGesture {
      selectedDate = nil
    }
  }
  
  /// Computes the exact time duration corresponding to the half-width of the callout badge.
  ///
  /// 1. Measures the exact typographical pixel width of both title ("1013.2 hPa") and subtitle ("Wed. 14:30")
  /// 2. Adds inner container padding (16pt total) and outer screen boundary clearance (4pt)
  /// 3. Converts the resulting point half-width into a TimeInterval proportion of the active 24-hour viewport
  private func calloutHalfWidthDuration(for reading: BarometricReading) -> TimeInterval {
    let title = String(format: "%.1f hPa", reading.pressure.converted(to: .hectopascals).value)
    let subtitle = reading.timestamp.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    
    let titleWidth = (title as NSString).size(withAttributes: [.font: calloutTitleFont]).width
    let subtitleWidth = (subtitle as NSString).size(withAttributes: [.font: calloutSubtitleFont]).width
    
    let contentWidth = max(titleWidth, subtitleWidth)
    let totalBadgeWidth = contentWidth + 16.0 // 8pt horizontal padding on each side
    let halfWidthPoints = (totalBadgeWidth / 2.0) + 4.0 // + 4pt screen edge clearance
    
    let effectiveWidth = max(chartWidth, 100.0)
    return (Double(halfWidthPoints) / Double(effectiveWidth)) * visibleDurationSeconds
  }
  
  /// Computes a continuous time anchor for the callout badge using its exact typographical width.
  /// The badge stays centered on the point as long as possible, and smoothly clamps against the
  /// visible edge only when it would otherwise touch the screen boundary.
  private func clampedCalloutDate(for reading: BarometricReading) -> Date {
    let halfWidthDuration = calloutHalfWidthDuration(for: reading)
    let minCenterDate = scrollPosition.addingTimeInterval(halfWidthDuration)
    let maxCenterDate = scrollPosition.addingTimeInterval(visibleDurationSeconds - halfWidthDuration)
    
    return min(max(reading.timestamp, minCenterDate), maxCenterDate)
  }
  
  // MARK: - Day Label Positioning Helpers
  
  private struct DayAnchorItem: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let label: String
  }
  
  /// Converts the exact typographic point width of a label into a TimeInterval in the 24-hour viewport
  private func labelWidthTime(for label: String) -> TimeInterval {
    let size = (label as NSString).size(withAttributes: [.font: labelFont])
    let widthInPoints = size.width
    let effectiveChartWidth = max(chartWidth, 100.0)
    return (Double(widthInPoints) / Double(effectiveChartWidth)) * visibleDurationSeconds
  }
  
  /// Computes the dynamic horizontal anchors for day labels adhering to rules 1, 2, and 3
  private var visibleDayAnchors: [DayAnchorItem] {
    let calendar = Calendar.current
    let visibleStart = scrollPosition
    let visibleEnd = scrollPosition.addingTimeInterval(visibleDurationSeconds)
    let startOfToday = calendar.startOfDay(for: viewModel.latestTimestamp)
    
    return (0...7).compactMap { daysAgo -> DayAnchorItem? in
      guard let dayStart = calendar.date(byAdding: .day, value: -daysAgo, to: startOfToday),
            let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
        return nil
      }
      
      let dayEnd = min(nextDayStart, viewModel.latestTimestamp)
      let segmentStart = max(dayStart, visibleStart)
      let segmentEnd = min(dayEnd, visibleEnd)
      
      // Ensure the day intersects the current viewport
      guard segmentEnd > segmentStart else {
        return nil
      }
      
      let label = formatDayLabel(dayStart)
      // Exact typographic half-width converted to time domain
      let exactLabelDuration = labelWidthTime(for: label)
      let labelMargin: TimeInterval = exactLabelDuration / 2.0
      
      let fullDayDuration = dayEnd.timeIntervalSince(dayStart)
      let visibleDuration = segmentEnd.timeIntervalSince(segmentStart)
      let visibleMidpoint = segmentStart.addingTimeInterval(visibleDuration / 2.0)
      let minAnchor = dayStart.addingTimeInterval(labelMargin)
      let maxAnchor = dayEnd.addingTimeInterval(-labelMargin)
      
      let anchorDate: Date
      if fullDayDuration < labelMargin * 2 {
        anchorDate = dayStart.addingTimeInterval(fullDayDuration / 2.0)
      } else {
        anchorDate = min(max(visibleMidpoint, minAnchor), maxAnchor)
      }
      
      return DayAnchorItem(date: anchorDate, label: label)
    }
  }
  
  /// Formats a legible day label for a given midnight boundary date ("Today", "Yesterday", or "<Weekday> (D-<N>)").
  private func formatDayLabel(_ date: Date) -> String {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: viewModel.latestTimestamp)
    let dateDay = calendar.startOfDay(for: date)
    
    let daysAgo = calendar.dateComponents([.day], from: dateDay, to: today).day ?? 0
    let fullWeekday = date.formatted(.dateTime.weekday(.wide))
    
    if daysAgo == 0 {
      return String(localized: "Today")
    } else if daysAgo == 1 {
      return String(localized: "Yesterday")
    } else {
      return "\(fullWeekday) (D-\(daysAgo))"
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

//
//  BarometerWidgetView.swift
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
/// It observes the BarometerViewModel and renders the current pressure and the 12-hour history chart.
public struct BarometerAlarmView: View {
    @Bindable var viewModel: BarometerViewModel
    @Environment(PermissionService.self) private var permissionService
    
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
                                    .foregroundColor(MarineTheme.Colors.textSecondary)
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
                    
                    // MARK: - 24h History Chart
                    if !viewModel.chartData.isEmpty {
                        Chart(viewModel.chartData) { dataPoint in
                            LineMark(
                                x: .value("Time", dataPoint.reading.timestamp),
                                y: .value("hPa", dataPoint.reading.pressure.value),
                                series: .value("Segment", dataPoint.segmentId)
                            )
                            .foregroundStyle(alarmColor)
                        }
                        // Ensure the vertical scale spans at least 1 hPa
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
                        .frame(height: 150)
                    }
                }
                .padding(.vertical, MarineTheme.Spacing.small)
            }
            .listRowBackground(MarineTheme.Colors.surfaceBackground)
            
            // MARK: - Settings
            Section(header: Text("Configuration")) {
                Toggle("Weather Alarms", isOn: Binding(
                    get: { viewModel.isAlarmEnabled },
                    set: { newValue in
                        viewModel.requestToggleAlarm(isOn: newValue, in: permissionService)
                    }
                ))
                    .tint(MarineTheme.Colors.accent)
                
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
                            .foregroundColor(MarineTheme.Colors.textSecondary)
                        
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
                                .foregroundColor(MarineTheme.Colors.accent)
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
            .listRowBackground(MarineTheme.Colors.surfaceBackground)
        }
        .marineListBackground()
        .navigationTitle("Barometer Alarm")
        .onAppear {
            viewModel.startUpdates()
        }
        .task(id: viewModel.service.lastHistoryUpdate) {
            // Automatically re-evaluates and refreshes the history chart 
            // the exact moment the service commits a new point to the database.
            await viewModel.refreshHistory()
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
    
    // MARK: - UI Logic
    
    /// Computes a Y-axis domain that spans at least 1 hPa to avoid exaggerating micro-fluctuations
    private var chartDomain: ClosedRange<Double> {
        let history = viewModel.history24h
        guard let minReading = history.min(by: { $0.pressure.value < $1.pressure.value }),
              let maxReading = history.max(by: { $0.pressure.value < $1.pressure.value }) else {
            return 1010.0...1011.0
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
            return MarineTheme.Colors.destructive
        case .vigilance:
            return MarineTheme.Colors.warning
        default:
            return MarineTheme.Colors.primary
        }
    }
}

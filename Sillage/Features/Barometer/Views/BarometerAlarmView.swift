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
    
    public init(viewModel: BarometerViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        Form {
            // MARK: - Vital Information (Socle)
            Section {
                VStack(spacing: MarineTheme.Spacing.medium) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Pressure")
                                .marineFont(.instrumentLabel)
                                .foregroundColor(MarineTheme.Colors.textSecondary)
                            
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
                    
                    // MARK: - 12h History Chart
                    if !viewModel.history12h.isEmpty {
                        Chart(viewModel.history12h, id: \.timestamp) { reading in
                            LineMark(
                                x: .value("Time", reading.timestamp),
                                y: .value("hPa", reading.pressure.value)
                            )
                            .foregroundStyle(alarmColor)
                        }
                        // We do not include zero to ensure the wave fluctuations are highly visible
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 150)
                    }
                }
                .padding(.vertical, MarineTheme.Spacing.small)
            }
            .listRowBackground(MarineTheme.Colors.surfaceBackground)
            
            // MARK: - Settings
            Section(header: Text("Configuration")) {
                Toggle("Weather Alarms", isOn: $viewModel.isAlarmEnabled)
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
        .scrollContentBackground(.hidden)
        .background(MarineTheme.Colors.panelBackground)
        .navigationTitle("Barometer Alarm")
        .task(id: viewModel.service.lastHistoryUpdate) {
            // Automatically re-evaluates and refreshes the history chart 
            // the exact moment the service commits a new point to the database.
            await viewModel.refreshHistory()
        }
    }
    
    // MARK: - UI Logic
    
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

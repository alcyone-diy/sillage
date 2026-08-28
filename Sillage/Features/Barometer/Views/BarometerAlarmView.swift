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

/// The main presentation widget for Barometric Telemetry.
/// It observes the BarometerViewModel and renders current pressure, a history chart, and alarm configurations.
public struct BarometerAlarmView: View {
  @Bindable var viewModel: BarometerViewModel
  @Environment(PermissionService.self) private var permissionService
  @Environment(\.marineTheme) private var marineTheme
  
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
          
          // MARK: - Horizontally Scrollable 7-Day History Chart
          BarometricHistoryChartView(viewModel: viewModel)
            .frame(height: 175)
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

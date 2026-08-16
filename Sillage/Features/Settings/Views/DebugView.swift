//
//  DebugView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-04.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

private struct AlertError: Identifiable {
  let id = UUID()
  let error: Error
}

struct DebugView: View {
  @Environment(\.marineTheme) private var marineTheme
  @Environment(ChartViewModel.self) private var chartViewModel
  @Environment(AppEnvironment.self) private var appEnvironment
  @Environment(PermissionService.self) private var permissionService
  
  @State private var viewModel = DebugViewModel()
  
  @State private var activeError: AlertError? = nil
  @State private var showClearCacheConfirmation: Bool = false
  
  var body: some View {
    Form {
      Section(header: Text("System Information")) {
        HStack {
          Text("Startup Time")
            .marineFont(.body)
          Spacer()
          Text(appEnvironment.bootDate.formatted(date: .abbreviated, time: .standard))
            .marineFont(.body)
            .foregroundColor(.secondary)
        }
        .marineListCell()
      }
      
      Section(header: Text("GPS Information")) {
        HStack {
          Text("Position")
            .marineFont(.body)
          Spacer()
          Text(positionText)
            .marineFont(.body)
            .foregroundColor(positionColor)
        }
        .marineListCell()
        
        HStack {
          Text("Accuracy")
            .marineFont(.body)
          Spacer()
          Text("± \(horizontalAccuracyText)")
            .marineFont(.body)
            .foregroundColor(positionColor)
        }
        .marineListCell()
        
        HStack {
          Text("GPS State")
            .marineFont(.body)
          Spacer()
          Text(gpsStateText)
            .marineFont(.body)
            .foregroundColor(gpsStateColor)
        }
        .marineListCell()

        if case .ready(let container) = appEnvironment.state {
          Picker(
            selection: Binding(
              get: { container.preferencesService.gpsAccuracyMode },
              set: { viewModel.setGPSAccuracyMode($0, appEnvironment: appEnvironment) }
            ),
            label: Text("Desired Accuracy")
              .marineFont(.body)
          ) {
            ForEach(GPSAccuracyMode.allCases, id: \.self) { mode in
              Text(mode.displayName).tag(mode)
            }
          }
          .pickerStyle(.menu)
          .marineListCell()
        }
      }
      
      Section(header: Text("Course Over Ground (COG)")) {
        HStack {
          Text("COG")
            .marineFont(.body)
          Spacer()
          Text(cogText)
            .marineFont(.body)
        }
        .marineListCell()
        
        HStack {
          Text("COG State")
            .marineFont(.body)
          Spacer()
          Text(cogStateText)
            .marineFont(.body)
            .foregroundColor(cogStateColor)
        }
        .marineListCell()
      }
      
      Section(header: Text("Map Cache")) {
        Button(role: .destructive) {
          showClearCacheConfirmation = true
        } label: {
          HStack {
            Text("Clear Map Cache")
              .marineFont(.body)
            Spacer()
            if appEnvironment.offlineMapManager.isClearingCache {
              ProgressView()
                .tint(.primary)
            } else {
              Image(systemName: "trash")
            }
          }
        }
        .disabled(appEnvironment.offlineMapManager.isClearingCache)
        .marineListCell()
        .confirmationDialog("Clear Map Cache", isPresented: $showClearCacheConfirmation, titleVisibility: .visible) {
          Button("Clear Cache", role: .destructive) {
            Task {
              do {
                try await appEnvironment.offlineMapManager.clearAmbientCache()
              } catch {
                activeError = AlertError(error: error)
              }
            }
          }
          Button("Cancel", role: .cancel) { }
        } message: {
          Text("This will delete all temporary data and force the network to reload.")
        }
      }
      
      Section(header: Text("GeoGarage Testing")) {
        Button(role: .destructive) {
          viewModel.invalidateGeoGarageToken()
        } label: {
          Text("Corrupt GeoGarage Token")
            .marineFont(.body)
        }
        .marineListCell()
      }
      
      Section(header: Text("Notification Testing")) {
        Button {
          Task {
            if case .ready(let container) = appEnvironment.state {
              do {
                try await viewModel.scheduleDebugBarometerNotification(
                  permissionService: permissionService,
                  notificationService: container.notificationService
                )
              } catch {
                activeError = AlertError(error: error)
              }
            }
          }
        } label: {
          Text("Trigger Barometer Alarm (5s)")
            .marineFont(.body)
        }
        .marineListCell()
        
        Button {
          Task {
            if case .ready(let container) = appEnvironment.state {
              do {
                try await viewModel.scheduleDebugAnchorNotification(
                  permissionService: permissionService,
                  notificationService: container.notificationService,
                  anchorService: container.anchorService
                )

              } catch {
                activeError = AlertError(error: error)
              }
            }
          }
        } label: {
          Text("Trigger Anchor Dragging Alarm (5s)")
            .marineFont(.body)
        }
        .marineListCell()
      }

    }
    .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
    .marineListBackground()
    .navigationTitle("Debug")
    .navigationBarTitleDisplayMode(.inline)
    .alert("Error",
           isPresented: Binding(
             get: { activeError != nil },
             set: { if !$0 { activeError = nil } }
           ),
           presenting: activeError) { alertError in
      if let notifError = alertError.error as? NotificationError, notifError == .permissionDenied {
        Button("Open Settings") {
          if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
          }
        }
        Button("Cancel", role: .cancel) { }
      } else {
        Button("OK", role: .cancel) { }
      }
    } message: { alertError in
      Text(alertError.error.localizedDescription)
    }
  }
}

// MARK: - Formatting Logic
extension DebugView {
  
  private var positionText: String {
    if let coordinate = chartViewModel.currentCoordinate {
      return coordinate.formatted(.marineCoordinate)
    }
    return "Unknown"
  }
  
  private var horizontalAccuracyText: String {
    guard let accuracy = chartViewModel.horizontalAccuracy else {
      return "--"
    }
    return accuracy.converted(to: .meters).formatted(
      .measurement(
        width: .abbreviated,
        usage: .asProvided,
        numberFormatStyle: .number.precision(.fractionLength(0))
      )
    )
  }
  
  private var positionColor: Color {
    guard let gpsState = chartViewModel.gpsState else { return .orange }
    switch gpsState {
    case .lost: return .red
    case .active: return .primary
    case .degraded: return .orange
    case .stale: return .orange
    }
  }
  
  private var gpsStateText: String {
    guard let gpsState = chartViewModel.gpsState else { return "Waiting" }
    switch gpsState {
    case .active: return "Active"
    case .degraded: return "Degraded"
    case .lost: return "Lost"
    case .stale: return "Stale"
    }
  }
  
  private var gpsStateColor: Color {
    guard let gpsState = chartViewModel.gpsState else { return .orange }
    switch gpsState {
    case .active: return .green
    case .degraded: return .orange
    case .lost: return .red
    case .stale: return .yellow
    }
  }
  
  private var cogText: String {
    if let cog = chartViewModel.smoothedCOG {
      return cog.converted(to: .degrees).formatted(
        .measurement(
          width: .narrow,
          usage: .asProvided,
          numberFormatStyle: .number.precision(.fractionLength(1))
        )
      )
    }
    return "--"
  }
  
  private var cogStateText: String {
    guard let courseState = chartViewModel.courseState else { return "Waiting" }
    switch courseState {
    case .active: return chartViewModel.smoothedCOG != nil ? "Valid" : "Invalid"
    case .stopped: return "Stopped"
    case .invalid: return "Invalid"
    }
  }
  
  private var cogStateColor: Color {
    guard let courseState = chartViewModel.courseState else { return .orange }
    switch courseState {
    case .active: return chartViewModel.smoothedCOG != nil ? .green : .red
    case .stopped: return .orange
    case .invalid: return .red
    }
  }
}

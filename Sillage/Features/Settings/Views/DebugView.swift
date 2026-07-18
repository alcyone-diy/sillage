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
           presenting: activeError) { _ in
      Button("OK", role: .cancel) { }
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
    switch chartViewModel.gpsState {
    case .stale, .lost: return .red
    case .waiting, .active: return .primary
    }
  }
  
  private var gpsStateText: String {
    switch chartViewModel.gpsState {
    case .waiting: return "Waiting"
    case .active: return "Active"
    case .stale: return "Stale"
    case .lost: return "Lost"
    }
  }
  
  private var gpsStateColor: Color {
    switch chartViewModel.gpsState {
    case .waiting: return .orange
    case .active: return .green
    case .stale: return .orange
    case .lost: return .red
    }
  }
  
  private var cogText: String {
    if let cog = chartViewModel.courseOverGround {
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
    guard let state = chartViewModel.courseState else {
      return "Waiting"
    }
    switch state {
    case .active: return "Valid"
    case .stopped: return "Stopped"
    case .invalid: return "Invalid"
    }
  }
  
  private var cogStateColor: Color {
    guard let state = chartViewModel.courseState else {
      return .orange
    }
    switch state {
    case .active: return .green
    case .stopped: return .orange
    case .invalid: return .red
    }
  }
}

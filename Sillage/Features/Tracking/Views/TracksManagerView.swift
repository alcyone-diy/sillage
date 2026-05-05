//
//  TracksManagerView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-05.
//

import SwiftUI
import CoreLocation

@MainActor
struct TracksManagerView: View {
  @Environment(TrackRecordingService.self) private var trackRecordingService
  @Environment(\.marineTheme) private var marineTheme
  
  var totalDistance: Measurement<UnitLength> {
    let points = trackRecordingService.trackPoints
    guard points.count >= 2 else { return Measurement(value: 0, unit: .meters) }
    
    var distance: Double = 0
    for i in 1..<points.count {
      let p1 = points[i-1]
      let p2 = points[i]
      let loc1 = CoreLocation.CLLocation(latitude: p1.latitude, longitude: p1.longitude)
      let loc2 = CoreLocation.CLLocation(latitude: p2.latitude, longitude: p2.longitude)
      distance += loc2.distance(from: loc1)
    }
    return Measurement(value: distance, unit: UnitLength.meters)
  }

  var totalDuration: String {
    let points = trackRecordingService.trackPoints
    guard let first = points.first, let last = points.last else { return "00:00:00" }
    
    let diff = last.timestamp.timeIntervalSince(first.timestamp)
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute, .second]
    formatter.unitsStyle = .positional
    formatter.zeroFormattingBehavior = .pad
    return formatter.string(from: diff) ?? "00:00:00"
  }

  var body: some View {
    @Bindable var bindableTrackService = trackRecordingService
    
    List {
      Section(header: Text("Active Trace")) {
        HStack {
          Text("Recording Status")
          Spacer()
          Toggle("", isOn: $bindableTrackService.isRecording)
            .labelsHidden()
        }
        .marineListCell()
        .marineFont(.body)
        
        HStack {
          Text("Duration")
          Spacer()
          Text(totalDuration)
            .foregroundStyle(.secondary)
        }
        .marineListCell()
        .marineFont(.body)
        
        HStack {
          Text("Distance")
          Spacer()
          let nm = totalDistance.converted(to: .nauticalMiles).value
          Text(String(format: "%.2f NM", nm))
            .foregroundStyle(.secondary)
        }
        .marineListCell()
        .marineFont(.body)
        
      }
      
      Section(header: Text("Saved Traces")) {
        Text("Coming soon...")
          .foregroundStyle(.secondary)
          .marineListCell()
          .marineFont(.body)
      }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(MarineTheme.Colors.panelBackground)
    .navigationTitle("Track Manager")
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview {
  NavigationStack {
    TracksManagerView()
      .environment(TrackRecordingService())
      .environment(\.marineTheme, .standard)
  }
}

//
//  WaypointListView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-06-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

@MainActor
struct WaypointListView: View {
  @Environment(\.marineTheme) private var marineTheme
  @Bindable var viewModel: WaypointListViewModel
  @State private var waypointToDelete: Waypoint?
  
  var body: some View {
    List {
      Section(header: Text("Saved Waypoints")) {
        if viewModel.waypoints.isEmpty {
          Text("No saved waypoints yet")
            .foregroundStyle(.secondary)
            .marineFont(.body)
            .listRowBackground(Color.clear)
            .marineListCell()
        } else {
          ForEach(viewModel.waypoints) { waypoint in
            WaypointRowView(waypoint: waypoint)
              .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button {
                  waypointToDelete = waypoint
                } label: {
                  Label("Delete", systemImage: "trash")
                }
                .tint(.red)
              }
              .marineListCell()
          }
        }
      }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(MarineTheme.Colors.panelBackground)
    .navigationTitle("Waypoints")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          // TODO: Implement add waypoint
        } label: {
          Image(systemName: "plus")
        }
      }
    }
    .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
    .alert(
      "Delete Waypoint?",
      isPresented: Binding(
        get: { waypointToDelete != nil },
        set: { if !$0 { waypointToDelete = nil } }
      ),
      presenting: waypointToDelete
    ) { waypoint in
      Button("Delete", role: .destructive) {
        viewModel.deleteWaypoint(waypoint)
      }
      Button("Cancel", role: .cancel) {
        waypointToDelete = nil
      }
    } message: { _ in
      Text("Are you sure you want to delete this waypoint? This action cannot be undone.")
    }
    .alert(
      "Error",
      isPresented: Binding(
        get: { viewModel.activeError != nil },
        set: { if !$0 { viewModel.activeError = nil } }
      ),
      presenting: viewModel.activeError
    ) { _ in
      Button("OK", role: .cancel) { }
    } message: { error in
      Text(error.localizedDescription)
    }
    .task {
      await viewModel.observe()
    }
  }
}

@MainActor
struct WaypointRowView: View {
  let waypoint: Waypoint
  
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(waypoint.name)
        .marineFont(.body)
      
      Text("\(waypoint.latitude.marineFormatted), \(waypoint.longitude.marineFormatted)")
        .foregroundStyle(.secondary)
        .marineFont(.caption)
    }
  }
}

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
import CoreLocation
struct CoordinateWrapper: Identifiable {
  let id = UUID()
  let coordinate: CLLocationCoordinate2D
  let defaultName: String?
}

@MainActor
struct WaypointListView: View {
  @Environment(\.marineTheme) private var marineTheme
  @Environment(\.waypointService) private var waypointService
  @Environment(MapViewModel.self) private var mapViewModel
  @Bindable var viewModel: WaypointListViewModel
  @State private var waypointToDelete: Waypoint?
  @State private var newWaypointItem: CoordinateWrapper?
  @State private var editingWaypoint: Waypoint?
  
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
            WaypointRowView(
              waypoint: waypoint,
              isSelected: viewModel.selectedWaypointId == waypoint.id
            )
              .contentShape(Rectangle())
              .onTapGesture {
                let newId = viewModel.selectedWaypointId == waypoint.id ? nil : waypoint.id
                viewModel.selectedWaypointId = newId
                viewModel.selectWaypoint(id: newId)
              }
              .swipeActions(edge: .leading) {
                Button {
                  editingWaypoint = waypoint
                } label: {
                  Label("Edit", systemImage: "pencil")
                }
                .tint(.blue)
              }
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
          if let service = waypointService {
            Task {
              var defaultName: String? = nil
              do {
                defaultName = try await service.fetchNextDefaultName()
              } catch {
                defaultName = "\(String(localized: "Waypoint")) \(viewModel.waypoints.count + 1)"
              }
              newWaypointItem = CoordinateWrapper(coordinate: mapViewModel.centerCoordinate, defaultName: defaultName)
            }
          }
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
    .sheet(item: $newWaypointItem) { item in
      if let waypointService {
        let editVM = WaypointEditViewModel(
          waypointService: waypointService,
          defaultName: item.defaultName,
          initialCoordinate: item.coordinate
        )
        WaypointEditView(viewModel: editVM)
      }
    }
    .sheet(item: $editingWaypoint) { waypoint in
      if let waypointService {
        let editVM = WaypointEditViewModel(
          waypointService: waypointService,
          editingWaypoint: waypoint
        )
        WaypointEditView(viewModel: editVM)
      }
    }
    .task {
      await viewModel.observe()
    }
  }
}

@MainActor
struct WaypointRowView: View {
  let waypoint: Waypoint
  let isSelected: Bool
  
  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text(waypoint.name)
          .marineFont(.body)
        
        Text(CLLocationCoordinate2D(latitude: waypoint.latitude.converted(to: .degrees).value, longitude: waypoint.longitude.converted(to: .degrees).value).formatted())
          .foregroundStyle(.secondary)
          .marineFont(.caption)
      }
      
      Spacer()
      
      if isSelected {
        Image(systemName: "checkmark")
          .foregroundColor(.blue)
      }
    }
  }
}

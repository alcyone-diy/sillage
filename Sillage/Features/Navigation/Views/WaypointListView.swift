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
  @Environment(ChartViewModel.self) private var chartViewModel
  @Environment(PanelManagerViewModel.self) private var panelManager
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
            NavigationLink(value: PanelManagerViewModel.CommandDestination.waypointDetail(waypoint.id)) {
              WaypointRowView(
                waypoint: waypoint,
                isSelected: viewModel.selectedWaypointId == waypoint.id
              )
            }
              .swipeActions(edge: .leading) {
                Button {
                  chartViewModel.selectWaypoint(id: waypoint.id)
                  panelManager.closePanel()
                } label: {
                  Label("Go To", systemImage: "map")
                }
                .tint(.green)
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
              newWaypointItem = CoordinateWrapper(coordinate: chartViewModel.centerCoordinate, defaultName: defaultName)
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
        NavigationStack {
          let viewModel = WaypointDetailViewModel(
            waypointService: waypointService,
            defaultName: item.defaultName,
            initialCoordinate: item.coordinate
          )
          WaypointDetailView(viewModel: viewModel) { waypointId in
            newWaypointItem = nil
            chartViewModel.selectWaypoint(id: waypointId)
            panelManager.closePanel()
          }
        }
      }
    }
    .sheet(item: $editingWaypoint) { waypoint in
      if let waypointService {
        NavigationStack {
          let viewModel = WaypointDetailViewModel(
            waypointService: waypointService,
            editingWaypoint: waypoint,
            startEditable: true
          )
          WaypointDetailView(viewModel: viewModel) { waypointId in
            editingWaypoint = nil
            chartViewModel.selectWaypoint(id: waypointId)
            panelManager.closePanel()
          }
        }
      }
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
        
        Text(waypoint.coordinate.formatted())
          .foregroundStyle(.secondary)
          .marineFont(.caption)
      }
      
      Spacer()
      
      if isSelected {
        Image(systemName: "mappin.circle.fill")
          .foregroundColor(.blue)
      }
    }
  }
}

@MainActor
struct WaypointDetailContainer: View {
  enum LoadState {
    case loading
    case loaded(WaypointDetailViewModel)
    case error(Error)
  }

  let waypointId: String
  @Environment(\.waypointService) private var waypointService
  @Environment(ChartViewModel.self) private var chartViewModel
  @Environment(PanelManagerViewModel.self) private var panelManager
  @State private var state: LoadState = .loading

  var body: some View {
    Group {
      switch state {
      case .loading:
        ProgressView("Loading Waypoint...")
          .marineFont(.body)
          .task {
            await loadData()
          }
      case .loaded(let viewModel):
        WaypointDetailView(viewModel: viewModel) { waypointId in
          chartViewModel.selectWaypoint(id: waypointId)
          panelManager.closePanel()
        }
      case .error(let error):
        VStack(spacing: 16) {
          Image(systemName: "exclamationmark.triangle")
            .font(.largeTitle)
            .foregroundColor(.red)
          
          Text("Failed to load waypoint")
            .marineFont(.title3)
            
          Text(error.localizedDescription)
            .marineFont(.caption)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
          
          Button("Retry") {
            state = .loading
          }
          .buttonStyle(MarineButtonStyle())
        }
        .padding()
      }
    }
  }

  private func loadData() async {
    guard let service = waypointService else {
      state = .error(WaypointError.serviceUnavailable)
      return
    }
    
    do {
      if let waypoint = try await service.fetchWaypoint(id: waypointId) {
        let vm = WaypointDetailViewModel(
          waypointService: service,
          editingWaypoint: waypoint,
          startEditable: false
        )
        state = .loaded(vm)
      } else {
        state = .error(WaypointError.notFound)
      }
    } catch {
      state = .error(error)
    }
  }
}

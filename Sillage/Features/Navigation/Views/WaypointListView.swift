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


@MainActor
struct WaypointListView: View {
  @Environment(\.marineTheme) private var marineTheme
  @Environment(\.waypointService) private var waypointService
  @Environment(ChartViewModel.self) private var chartViewModel
  @Environment(PanelManagerViewModel.self) private var panelManager
  @Bindable var viewModel: WaypointListViewModel
  @State private var waypointToDelete: Waypoint?
  @State private var isCreatingDraft = false
  @State private var creationTask: Task<Void, Never>?
  
  var body: some View {
    List {
      Section {
        if viewModel.waypoints.isEmpty {
          Text("No saved waypoints yet")
            .foregroundStyle(.secondary)
            .marineFont(.body)
            .listRowBackground(Color.clear)
            .marineListCell()
        } else {
          ForEach(viewModel.waypoints) { waypoint in
            NavigationLink(value: PanelManagerViewModel.CommandDestination.waypointDetail(waypoint.id, waypoint: waypoint)) {
              WaypointRowView(
                waypoint: waypoint,
                isGoTo: viewModel.goToWaypointID == waypoint.id
              )
            }
              .swipeActions(edge: .leading) {
                if viewModel.goToWaypointID == waypoint.id {
                  Button {
                    viewModel.setDestination(waypointID: nil)
                  } label: {
                    Label("Cancel", systemImage: MarineIcon.cancelAction.rawValue)
                  }
                  .tint(marineTheme.colors.cancelAction)
                } else {
                  Button {
                    viewModel.setDestination(waypointID: waypoint.id)
                    panelManager.closePanel()
                  } label: {
                    Label("Go To", systemImage: MarineIcon.waypoint.rawValue)
                  }
                  .tint(.blue)
                }
              }
              .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                  waypointToDelete = waypoint
                } label: {
                  Label("Delete", systemImage: MarineIcon.delete.rawValue)
                }
                .tint(.red)
              }
              .marineListCell()
          }
        }
      } header: {
        Text("Saved Waypoints").marineSectionHeader()
      }
    }
    .listStyle(.insetGrouped)
    .marineListBackground()
    .navigationTitle("Waypoints")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          guard !isCreatingDraft, let service = waypointService else { return }
          isCreatingDraft = true
          creationTask = Task {
            defer { isCreatingDraft = false }
            let defaultName = await service.generateDefaultName()
            guard !Task.isCancelled else { return }
            let item = CoordinateWrapper(coordinate: chartViewModel.centerCoordinate, defaultName: defaultName)
            panelManager.commandPath.append(.waypointDraft(item))
          }
        } label: {
          Image(marineIcon: .add)
        }
        .disabled(isCreatingDraft)
      }
    }
    .onDisappear {
      creationTask?.cancel()
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
  }
}

@MainActor
struct WaypointRowView: View {
  let waypoint: Waypoint
  let isGoTo: Bool
  
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
      
      if isGoTo {
        Image(marineIcon: .waypoint)
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

  let waypointID: String
  let initialWaypoint: Waypoint?
  @Environment(\.waypointService) private var waypointService
  @Environment(ChartViewModel.self) private var chartViewModel
  @Environment(PanelManagerViewModel.self) private var panelManager
  @State private var state: LoadState = .loading

  init(waypointID: String, waypoint: Waypoint? = nil) {
    self.waypointID = waypointID
    self.initialWaypoint = waypoint
  }

  var body: some View {
    Group {
      switch state {
      case .loading:
        if initialWaypoint != nil {
          Color.clear
        } else {
          ProgressView("Loading Waypoint...")
            .marineFont(.body)
        }
      case .loaded(let viewModel):
        WaypointDetailView(
          viewModel: viewModel,
          onGoToRequested: { waypointID in
            waypointService?.setDestination(waypointID: waypointID)
            panelManager.closePanel()
          },
          onCancelNavigationRequested: {
            waypointService?.setDestination(waypointID: nil)
          },
          onModifyPositionRequested: {
            chartViewModel.startWaypointPositionAdjustment(
              viewModel: viewModel,
              onCancel: {
                panelManager.resumePanel()
              },
              onConfirm: { newCoord in
                viewModel.updateCoordinate(newCoord)
                panelManager.resumePanel()
              }
            )
            panelManager.suspendPanel()
          }
        )
      case .error(let error):
        VStack(spacing: 16) {
          Image(marineIcon: .warning)
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
          .buttonStyle(MarineButtonStyle(.primary))
        }
        .padding()
      }
    }
    .task(id: waypointID) {
      await loadData()
    }
  }

  private func loadData() async {
    if let cachedVM = chartViewModel.activeWaypointDetailViewModel, cachedVM.editingWaypointID == waypointID {
      self.state = .loaded(cachedVM)
      return
    }

    if case .loaded(let currentVM) = state, currentVM.editingWaypointID == waypointID {
      return
    }

    guard let service = waypointService else {
      state = .error(WaypointError.serviceUnavailable)
      return
    }
    
    do {
      let waypointToUse: Waypoint
      if let initialWaypoint, initialWaypoint.id == waypointID {
        waypointToUse = initialWaypoint
      } else if let fetched = try await service.fetchWaypoint(id: waypointID) {
        waypointToUse = fetched
      } else {
        state = .error(WaypointError.notFound)
        return
      }
      let vm = WaypointDetailViewModel(
        waypointService: service,
        editingWaypoint: waypointToUse,
        startEditable: false
      )
      chartViewModel.activeWaypointDetailViewModel = vm
      state = .loaded(vm)
    } catch {
      state = .error(error)
    }
  }
}

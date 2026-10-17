//
//  WaypointDraftContainerView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-17.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import CoreLocation

/// Encapsulates the lifecycle of creating a new waypoint draft in a presentation sheet.
/// Guarantees that `WaypointDetailViewModel` is initialized exactly once per draft session,
/// eliminating redundant side-effects and input resets on parent view evaluations.
@MainActor
struct WaypointDraftContainerView: View {
  let item: CoordinateWrapper
  let waypointService: WaypointService
  var onGoToRequested: ((String) -> Void)?
  var onCancelNavigationRequested: (() -> Void)?
  var onModifyPositionRequested: ((WaypointDetailViewModel) -> Void)?

  @Environment(ChartViewModel.self) private var chartViewModel
  @State private var viewModel: WaypointDetailViewModel?

  var body: some View {
    Group {
      if let viewModel {
        WaypointDetailView(
          viewModel: viewModel,
          onGoToRequested: onGoToRequested,
          onCancelNavigationRequested: onCancelNavigationRequested,
          onModifyPositionRequested: {
            onModifyPositionRequested?(viewModel)
          }
        )
      } else {
        Color.clear
      }
    }
    .task {
      initializeViewModelIfNeeded()
    }
  }

  private func initializeViewModelIfNeeded() {
    if let cached = chartViewModel.activeWaypointDetailViewModel,
       cached.editingWaypointID == nil,
       let cachedCoord = cached.currentCoordinate,
       abs(cachedCoord.latitude - item.coordinate.latitude) < 0.000001,
       abs(cachedCoord.longitude - item.coordinate.longitude) < 0.000001 {
      self.viewModel = cached
      return
    }

    let newVM = WaypointDetailViewModel(
      waypointService: waypointService,
      defaultName: item.defaultName,
      initialCoordinate: item.coordinate
    )
    chartViewModel.activeWaypointDetailViewModel = newVM
    self.viewModel = newVM
  }
}

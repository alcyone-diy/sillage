//
//  WaypointListViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-06-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Observation

@MainActor
@Observable
public final class WaypointListViewModel {
  public private(set) var waypoints: [Waypoint] = []
  public var activeError: Error?
  public var selectedWaypointId: String?
  
  private let waypointService: WaypointService
  
  public init(waypointService: WaypointService) {
    self.waypointService = waypointService
  }
  
  public func observe() async {
    async let waypointsTask: Void = observeWaypointsList()
    async let selectionTask: Void = observeSelectionState()
    _ = await (waypointsTask, selectionTask)
  }
  
  private func observeWaypointsList() async {
    do {
      for try await waypoints in waypointService.observeWaypoints() {
        guard !Task.isCancelled else { break }
        self.waypoints = waypoints
      }
    } catch {
      if !Task.isCancelled {
        self.activeError = error
      }
    }
  }
  
  private func observeSelectionState() async {
    let stream = await waypointService.observeSelectedWaypoint()
    for await id in stream {
      guard !Task.isCancelled else { break }
      if self.selectedWaypointId != id {
        self.selectedWaypointId = id
      }
    }
  }
  
  public func deleteWaypoint(_ waypoint: Waypoint) {
    Task { [weak self] in
      do {
        try await self?.waypointService.deleteWaypoint(id: waypoint.id)
      } catch {
        self?.activeError = error
      }
    }
  }
  
  public func selectWaypoint(id: String?) {
    Task { [weak self] in
      await self?.waypointService.selectWaypoint(id: id)
    }
  }
  
}

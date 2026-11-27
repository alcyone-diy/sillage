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
  private let waypointService: WaypointService
  private let activeNavigationService: ActiveNavigationService
  public var activeError: Error?
  
  public var waypoints: [Waypoint] {
    waypointService.currentWaypoints
  }
  
  public var goToWaypointID: String? {
    activeNavigationService.goToWaypointID
  }
  
  public init(
    waypointService: WaypointService,
    activeNavigationService: ActiveNavigationService
  ) {
    self.waypointService = waypointService
    self.activeNavigationService = activeNavigationService
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
  
  public func setDestination(waypointID: String?) {
    Task { [weak self] in
      do {
        try await self?.activeNavigationService.setDestination(waypointID: waypointID)
      } catch {
        self?.activeError = error
      }
    }
  }
}

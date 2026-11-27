//
//  ActiveNavigationLeg.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

/// Represents the vessel's currently active point-to-point navigation leg ("Go To").
/// Holds both the destination `Waypoint` and the locked `originCoordinate` from which
/// Cross-Track Error (`XTE`) is measured across the entire leg, surviving app restarts.
public struct ActiveNavigationLeg: Sendable, Equatable {
  public let waypoint: Waypoint
  public let originCoordinate: CLLocationCoordinate2D?
  public let activatedAt: Date

  nonisolated public init(
    waypoint: Waypoint,
    originCoordinate: CLLocationCoordinate2D?,
    activatedAt: Date
  ) {
    self.waypoint = waypoint
    self.originCoordinate = originCoordinate
    self.activatedAt = activatedAt
  }

  /// Returns a copy of the leg with `originCoordinate` locked to the provided coordinate.
  nonisolated public func withOrigin(_ coordinate: CLLocationCoordinate2D) -> ActiveNavigationLeg {
    ActiveNavigationLeg(
      waypoint: waypoint,
      originCoordinate: coordinate,
      activatedAt: activatedAt
    )
  }
}

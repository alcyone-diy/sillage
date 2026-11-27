//
//  AnchorVisualState.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

enum AnchorVisualStatus: String, Equatable, Sendable {
  case setup
  case dropped
  case armed
  case dragging
}

struct AnchorVisualState: Equatable, Sendable {
  let status: AnchorVisualStatus
  let pointCoordinate: CLLocationCoordinate2D
  let radius: Measurement<UnitLength>?
  let vesselCoordinate: CLLocationCoordinate2D?
  let swingCoordinates: [CLLocationCoordinate2D]

  init(
    status: AnchorVisualStatus,
    pointCoordinate: CLLocationCoordinate2D,
    radius: Measurement<UnitLength>?,
    vesselCoordinate: CLLocationCoordinate2D?,
    swingCoordinates: [CLLocationCoordinate2D] = []
  ) {
    self.status = status
    self.pointCoordinate = pointCoordinate
    self.radius = radius
    self.vesselCoordinate = vesselCoordinate
    self.swingCoordinates = swingCoordinates
  }
}


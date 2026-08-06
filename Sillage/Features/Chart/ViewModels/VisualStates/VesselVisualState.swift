//
//  VesselVisualState.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-06.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

/// Represents the visual representation parameters for the vessel cursor on the chart.
public struct VesselVisualState: Equatable, Sendable {
  public let coordinate: CLLocationCoordinate2D
  public let course: Measurement<UnitAngle>?
  public let isStale: Bool
  public let isDegraded: Bool
  
  public init(
    coordinate: CLLocationCoordinate2D,
    course: Measurement<UnitAngle>?,
    isStale: Bool,
    isDegraded: Bool
  ) {
    self.coordinate = coordinate
    self.course = course
    self.isStale = isStale
    self.isDegraded = isDegraded
  }
}

//
//  InstrumentState.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-23.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

public enum MovementState: Sendable, Equatable {
  case moving
  case stopped
}

public enum InstrumentGPSState: Sendable, Equatable {
  case active
  case degraded
  case lost
}

public struct InstrumentState: Sendable, Equatable {
  public let coordinate: CLLocationCoordinate2D?
  public let horizontalAccuracy: Measurement<UnitLength>?
  
  public let smoothedSOG: Measurement<UnitSpeed>?
  public let smoothedCOG: Measurement<UnitAngle>?
  
  public let movementState: MovementState
  public let sensorTimestamp: Date
  public let systemDate: Date
  public let gpsState: InstrumentGPSState
  
  public init(
    coordinate: CLLocationCoordinate2D?,
    horizontalAccuracy: Measurement<UnitLength>?,
    smoothedSOG: Measurement<UnitSpeed>?,
    smoothedCOG: Measurement<UnitAngle>?,
    movementState: MovementState,
    sensorTimestamp: Date,
    systemDate: Date,
    gpsState: InstrumentGPSState
  ) {
    self.coordinate = coordinate
    self.horizontalAccuracy = horizontalAccuracy
    self.smoothedSOG = smoothedSOG
    self.smoothedCOG = smoothedCOG
    self.movementState = movementState
    self.sensorTimestamp = sensorTimestamp
    self.systemDate = systemDate
    self.gpsState = gpsState
  }
}

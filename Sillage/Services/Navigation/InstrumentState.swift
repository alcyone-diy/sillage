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

public struct InstrumentState: Sendable, Equatable {
  public let rawCoordinate: CLLocationCoordinate2D
  public let rawAccuracy: Measurement<UnitLength>
  
  public let smoothedSOG: Measurement<UnitSpeed>?
  public let smoothedCOG: Measurement<UnitAngle>?
  
  public let movementState: MovementState
  public let sensorTimestamp: Date
  public let systemDate: Date
  
  public init(
    rawCoordinate: CLLocationCoordinate2D,
    rawAccuracy: Measurement<UnitLength>,
    smoothedSOG: Measurement<UnitSpeed>?,
    smoothedCOG: Measurement<UnitAngle>?,
    movementState: MovementState,
    sensorTimestamp: Date,
    systemDate: Date
  ) {
    self.rawCoordinate = rawCoordinate
    self.rawAccuracy = rawAccuracy
    self.smoothedSOG = smoothedSOG
    self.smoothedCOG = smoothedCOG
    self.movementState = movementState
    self.sensorTimestamp = sensorTimestamp
    self.systemDate = systemDate
  }
}

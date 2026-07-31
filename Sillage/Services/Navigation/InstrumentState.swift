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

public enum CourseState: Sendable, Equatable {
  case active
  case stopped
  case invalid
}

public enum GPSState: Sendable, Equatable {
  case active
  case degraded
  case stale
  case lost
}

public struct InstrumentState: Sendable, Equatable {
  public let coordinate: CLLocationCoordinate2D?
  public let horizontalAccuracy: Measurement<UnitLength>?
  
  public let smoothedSOG: Measurement<UnitSpeed>?
  public let smoothedCOG: Measurement<UnitAngle>?
  
  public let courseState: CourseState
  public let gpsState: GPSState
  public let sensorTimestamp: Date
  public let systemDate: Date
  
  public init(
    coordinate: CLLocationCoordinate2D?,
    horizontalAccuracy: Measurement<UnitLength>?,
    smoothedSOG: Measurement<UnitSpeed>?,
    smoothedCOG: Measurement<UnitAngle>?,
    courseState: CourseState,
    gpsState: GPSState,
    sensorTimestamp: Date,
    systemDate: Date
  ) {
    self.coordinate = coordinate
    self.horizontalAccuracy = horizontalAccuracy
    self.smoothedSOG = smoothedSOG
    self.smoothedCOG = smoothedCOG
    self.courseState = courseState
    self.gpsState = gpsState
    self.sensorTimestamp = sensorTimestamp
    self.systemDate = systemDate
  }
}

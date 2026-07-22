//
//  CodableCoordinate.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-04.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

/// Intermediate structure to handle the serialization of CLLocationCoordinate2D
public struct CodableCoordinate: Codable, Sendable, Equatable {
  public let latitude: CLLocationDegrees
  public let longitude: CLLocationDegrees
  
  public init(_ coordinate: CLLocationCoordinate2D) {
    self.latitude = coordinate.latitude
    self.longitude = coordinate.longitude
  }
  
  public init(latitude: CLLocationDegrees, longitude: CLLocationDegrees) {
    self.latitude = latitude
    self.longitude = longitude
  }
  
  public var coordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }
}

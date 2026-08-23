//
//  CLLocationCoordinate2D+Extensions.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-06-07.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

//
//  CLLocationCoordinate2D+Extensions.swift
//  Alcyone Sillage
//

import Foundation
import CoreLocation

extension CLLocationCoordinate2D: @retroactive Equatable {
  public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
    return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
  }
}

extension CLLocationCoordinate2D: @retroactive Codable {
  enum CodingKeys: String, CodingKey {
    case latitude
    case longitude
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let latitude = try container.decode(CLLocationDegrees.self, forKey: .latitude)
    let longitude = try container.decode(CLLocationDegrees.self, forKey: .longitude)
    self.init(latitude: latitude, longitude: longitude)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(latitude, forKey: .latitude)
    try container.encode(longitude, forKey: .longitude)
  }
}

extension CLLocationCoordinate2D {
  private static let earthRadius = Measurement<UnitLength>(value: 6371000.0, unit: .meters)

  /// Calculates the Great Circle distance from this coordinate to another coordinate using the Haversine formula.
  /// Pure value-type calculation avoiding heap allocations of `CLLocation`.
  /// - Parameter destination: The target coordinate.
  /// - Returns: Physical distance as a `Measurement<UnitLength>`.
  public func distance(to destination: CLLocationCoordinate2D) -> Measurement<UnitLength> {
    let lat1 = Measurement(value: self.latitude, unit: UnitAngle.degrees).converted(to: .radians).value
    let lon1 = Measurement(value: self.longitude, unit: UnitAngle.degrees).converted(to: .radians).value
    let lat2 = Measurement(value: destination.latitude, unit: UnitAngle.degrees).converted(to: .radians).value
    let lon2 = Measurement(value: destination.longitude, unit: UnitAngle.degrees).converted(to: .radians).value

    let dLat = lat2 - lat1
    let dLon = lon2 - lon1

    let a = sin(dLat / 2.0) * sin(dLat / 2.0) + cos(lat1) * cos(lat2) * sin(dLon / 2.0) * sin(dLon / 2.0)
    let c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a))

    let distanceInMeters = Self.earthRadius.value * c
    return Measurement(value: distanceInMeters, unit: .meters)
  }
}

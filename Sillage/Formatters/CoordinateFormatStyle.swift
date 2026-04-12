//
//  CoordinateFormatStyle.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

public struct CoordinateFormatStyle: FormatStyle {
  public typealias FormatInput = CLLocationCoordinate2D
  public typealias FormatOutput = String

  public func format(_ value: CLLocationCoordinate2D) -> String {
    let lat = formatComponent(value.latitude, isLatitude: true)
    let lon = formatComponent(value.longitude, isLatitude: false)
    return "\(lat) / \(lon)"
  }

  private func formatComponent(_ degrees: CLLocationDegrees, isLatitude: Bool) -> String {
    let direction = isLatitude ? (degrees >= 0 ? "N" : "S") : (degrees >= 0 ? "E" : "W")
    let absDegrees = abs(degrees)
    let intDegrees = Int(absDegrees)
    let minutes = (absDegrees - Double(intDegrees)) * 60.0

    return String(format: "%02d°%06.3f' %@", intDegrees, minutes, direction)
  }
}

public extension FormatStyle where Self == CoordinateFormatStyle {
  static var marineCoordinate: CoordinateFormatStyle { .init() }
}

public extension CLLocationCoordinate2D {
  func formatted(_ style: CoordinateFormatStyle = .init()) -> String {
    return style.format(self)
  }
}

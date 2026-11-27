//
//  CLLocationCoordinate2D+Extensions.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-06-07.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

extension CLLocationCoordinate2D: @retroactive Equatable {
  nonisolated public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
    return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
  }
}

extension CLLocationCoordinate2D: @retroactive Hashable {
  nonisolated public func hash(into hasher: inout Hasher) {
    hasher.combine(latitude)
    hasher.combine(longitude)
  }
}

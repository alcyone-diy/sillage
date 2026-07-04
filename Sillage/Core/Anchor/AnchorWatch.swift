//
//  AnchorWatch.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-04.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

public struct AnchorWatch: Codable, Sendable, Equatable {
  // Stockage interne sérialisable
  private let storedCoordinate: CodableCoordinate
  public let radius: Measurement<UnitLength>
  public let createdAt: Date
  
  // Accesseur public pour le domaine
  public var coordinate: CLLocationCoordinate2D {
    storedCoordinate.coordinate
  }
  
  public init(coordinate: CLLocationCoordinate2D, radius: Measurement<UnitLength>, createdAt: Date = Date()) {
    self.storedCoordinate = CodableCoordinate(coordinate)
    self.radius = radius
    self.createdAt = createdAt
  }
  
  private enum CodingKeys: String, CodingKey {
    case storedCoordinate = "coordinate"
    case radius
    case createdAt
  }
}

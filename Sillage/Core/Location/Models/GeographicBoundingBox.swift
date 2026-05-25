//
//  GeographicBoundingBox.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-25.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

public struct GeographicBoundingBox: Sendable, Equatable {
  
  // MARK: - Properties
  
  public private(set) var southLatitude: Measurement<UnitAngle>
  public private(set) var northLatitude: Measurement<UnitAngle>
  public private(set) var westLongitude: Measurement<UnitAngle>
  public private(set) var eastLongitude: Measurement<UnitAngle>
  
  // MARK: - Initialization
  
  public init(southLatitude: Measurement<UnitAngle>,
              northLatitude: Measurement<UnitAngle>,
              westLongitude: Measurement<UnitAngle>,
              eastLongitude: Measurement<UnitAngle>) {
    self.southLatitude = southLatitude
    self.northLatitude = northLatitude
    self.westLongitude = westLongitude
    self.eastLongitude = eastLongitude
  }
  
  public init(latitude: Measurement<UnitAngle>, longitude: Measurement<UnitAngle>) {
    self.southLatitude = latitude
    self.northLatitude = latitude
    self.westLongitude = longitude
    self.eastLongitude = longitude
  }
  
  // MARK: - Public
  
  public mutating func expand(toIncludeLatitude latitude: Measurement<UnitAngle>, longitude: Measurement<UnitAngle>) {
    if latitude < southLatitude { southLatitude = latitude }
    if latitude > northLatitude { northLatitude = latitude }
    
    let isInside: Bool
    if westLongitude <= eastLongitude {
      isInside = (longitude >= westLongitude) && (longitude <= eastLongitude)
    } else {
      isInside = (longitude >= westLongitude) || (longitude <= eastLongitude)
    }
    
    if !isInside {
      let expandEast = degreesDistance(from: eastLongitude, to: longitude)
      let expandWest = degreesDistance(from: longitude, to: westLongitude)
      
      if expandEast < expandWest {
        eastLongitude = longitude
      } else {
        westLongitude = longitude
      }
    }
  }
  
  // MARK: - Private Math
  
  private func degreesDistance(from start: Measurement<UnitAngle>, to end: Measurement<UnitAngle>) -> Measurement<UnitAngle> {
    var diff = end - start
    let fullCircle = Measurement<UnitAngle>(value: 360.0, unit: .degrees)
    let zero = Measurement<UnitAngle>(value: 0.0, unit: .degrees)
    
    while diff < zero {
      diff = diff + fullCircle
    }
    while diff >= fullCircle {
      diff = diff - fullCircle
    }
    return diff
  }
}

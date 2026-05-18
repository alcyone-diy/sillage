//
//  TrackSession.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-19.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// A representation of a recorded track session.
public struct TrackSession: Sendable, Codable, Identifiable {
  public let id: String
  public let startTime: Date
  public let endTime: Date?
  public let name: String?
  public let duration: Duration?
  public let totalDistance: Measurement<UnitLength>?

  public init(
    id: String,
    startTime: Date,
    endTime: Date? = nil,
    name: String? = nil,
    duration: Duration? = nil,
    totalDistance: Measurement<UnitLength>? = nil
  ) {
    self.id = id
    self.startTime = startTime
    self.endTime = endTime
    self.name = name
    self.duration = duration
    self.totalDistance = totalDistance
  }
}

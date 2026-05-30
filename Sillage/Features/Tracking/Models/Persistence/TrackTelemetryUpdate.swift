//
//  TrackTelemetryUpdate.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-30.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// An immutable DTO strictly used for transporting track session telemetry
/// without overwriting metadata like name or description.
public struct TrackTelemetryUpdate: Sendable {
  public let id: String
  public let endTimestamp_unix: Double?
  public let totalDuration_s: Double?
  public let totalDistance_m: Double?
  public let southLatitude_deg: Double?
  public let northLatitude_deg: Double?
  public let westLongitude_deg: Double?
  public let eastLongitude_deg: Double?
  public let maxSpeed_mps: Double?
  public let pointsCount: Int?
  public let segmentCount: Int?
}

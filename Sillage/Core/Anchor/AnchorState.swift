//
//  AnchorState.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-23.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

/// Pure domain state snapshot representing an active or inactive anchor watch session.
/// Immutable, thread-safe, and Sendable across concurrent service boundaries.
public struct AnchorState: Sendable, Equatable {
  public let activeWatch: AnchorWatch?
  public let status: AnchorStatus
  public let triggerReason: AnchorTriggerReason?
  public let currentDistance: Measurement<UnitLength>?
  public let latestFix: NavigationFix?
  public let gpsAccuracy: Measurement<UnitLength>?
  public let isMuted: Bool
  public let isSensorDegraded: Bool
  
  public init(
    activeWatch: AnchorWatch? = nil,
    status: AnchorStatus = .inactive,
    triggerReason: AnchorTriggerReason? = nil,
    currentDistance: Measurement<UnitLength>? = nil,
    latestFix: NavigationFix? = nil,
    gpsAccuracy: Measurement<UnitLength>? = nil,
    isMuted: Bool = false,
    isSensorDegraded: Bool = false
  ) {
    self.activeWatch = activeWatch
    self.status = status
    self.triggerReason = triggerReason
    self.currentDistance = currentDistance
    self.latestFix = latestFix
    self.gpsAccuracy = gpsAccuracy
    self.isMuted = isMuted
    self.isSensorDegraded = isSensorDegraded
  }
}

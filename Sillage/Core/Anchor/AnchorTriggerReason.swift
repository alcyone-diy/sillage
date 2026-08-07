//
//  AnchorTriggerReason.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-07.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// A pure domain data model specifying the reason for an anchor alarm trigger.
/// Must NOT contain any UI dependencies, localization logic, or formatted strings.
public enum AnchorTriggerReason: Codable, Sendable, Equatable {
  case distanceExceeded(distance: Measurement<UnitLength>, radius: Measurement<UnitLength>)
  case poorAccuracy(accuracy: Measurement<UnitLength>, requiredAccuracy: Measurement<UnitLength>)
  case gpsSignalLost
  case debugSimulation
}

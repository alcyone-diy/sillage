//
//  AnchorEvaluator.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-07.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation
import os

/// The domain evaluation result specifying whether to trigger, resolve, or maintain an anchor alarm.
public enum AnchorEvaluationResult: Equatable {
  case maintainState
  case triggerAlarm(distance: Measurement<UnitLength>, radius: Measurement<UnitLength>)
  case autoResolveAlarm(reason: ResolutionReason)

  public enum ResolutionReason: Equatable {
    case vesselReturnedInCircle(distance: Measurement<UnitLength>)
  }
}

/// A pure domain evaluation engine responsible for evaluating vessel telemetry against an active anchor watch.
public struct AnchorEvaluator {
  public init() {}

  /// Evaluates a new GPS fix against the active watch and current watch status.
  /// - Parameters:
  ///   - fix: The incoming domain GPS fix containing coordinates, SOG, COG, and horizontal accuracy.
  ///   - watch: The active anchor watch containing target anchor coordinate and configured radius.
  ///   - currentStatus: The current anchor watch status (.armed, .dragging, etc.).
  /// - Returns: An `AnchorEvaluationResult` indicating the state transition decision.
  public func evaluate(
    fix: NavigationFix,
    watch: AnchorWatch,
    currentStatus: AnchorStatus
  ) -> AnchorEvaluationResult {


    let anchorLocation = CLLocation(
      latitude: watch.coordinate.latitude,
      longitude: watch.coordinate.longitude
    )
    let fixLocation = CLLocation(
      latitude: fix.coordinate.latitude,
      longitude: fix.coordinate.longitude
    )

    let distanceInMeters = fixLocation.distance(from: anchorLocation)
    let radiusInMeters = watch.radius.converted(to: .meters).value

    // 1. Strict Anti-False-Positive GPS Accuracy Filter:
    // Only evaluate if accuracy is valid and within half the configured radius.
    let accuracyInMeters = fix.horizontalAccuracy.converted(to: .meters).value
    let requiredAccuracy = radiusInMeters / 2.0

    if accuracyInMeters <= 0 || accuracyInMeters > requiredAccuracy {
      Logger.anchor.warning(
        "⚓️ Poor GPS accuracy (\(accuracyInMeters, privacy: .public)m). Required: <= \(requiredAccuracy, privacy: .public)m. Skipping evaluation."
      )
      return .maintainState
    }

    let currentDistance = Measurement(value: distanceInMeters, unit: UnitLength.meters)

    // 2. State Transition Rules:
    if distanceInMeters > radiusInMeters {
      if currentStatus == .armed {
        return .triggerAlarm(distance: currentDistance, radius: watch.radius)
      }
    } else {
      if currentStatus == .dragging {
        return .autoResolveAlarm(reason: .vesselReturnedInCircle(distance: currentDistance))
      }
    }

    return .maintainState
  }
}

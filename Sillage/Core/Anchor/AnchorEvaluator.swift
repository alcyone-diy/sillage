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
  case triggerAlarm(reason: AnchorTriggerReason)
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
    guard let targetCoordinate = watch.coordinate else {
      return .maintainState
    }
    let anchorLocation = CLLocation(
      latitude: targetCoordinate.latitude,
      longitude: targetCoordinate.longitude
    )
    let fixLocation = CLLocation(
      latitude: fix.coordinate.latitude,
      longitude: fix.coordinate.longitude
    )

    let distanceInMeters = fixLocation.distance(from: anchorLocation)
    let radiusInMeters = watch.radius.converted(to: .meters).value

    let accuracyInMeters = fix.horizontalAccuracy.converted(to: .meters).value
    let requiredAccuracy = radiusInMeters / 2.0
    let requiredAccuracyMeasurement = Measurement(value: requiredAccuracy, unit: UnitLength.meters)

    if accuracyInMeters > requiredAccuracy {
      Logger.anchor.warning(
        "⚓️ Poor GPS accuracy (\(accuracyInMeters, privacy: .public)m). Required: <= \(requiredAccuracy, privacy: .public)m."
      )
      if currentStatus == .armed {
        return .triggerAlarm(reason: .poorAccuracy(accuracy: fix.horizontalAccuracy, requiredAccuracy: requiredAccuracyMeasurement))
      }
      return .maintainState
    }

    if accuracyInMeters <= 0 {
      Logger.anchor.warning("⚓️ Invalid GPS accuracy (\(accuracyInMeters, privacy: .public)m).")
      if currentStatus == .armed {
        return .triggerAlarm(reason: .gpsSignalLost)
      }
      return .maintainState
    }

    let currentDistance = Measurement(value: distanceInMeters, unit: UnitLength.meters)

    // 2. State Transition Rules:
    if distanceInMeters > radiusInMeters {
      if currentStatus == .armed {
        return .triggerAlarm(reason: .distanceExceeded(distance: currentDistance, radius: watch.radius))
      }
    } else {
      if currentStatus == .dragging {
        return .autoResolveAlarm(reason: .vesselReturnedInCircle(distance: currentDistance))
      }
    }

    return .maintainState
  }
}

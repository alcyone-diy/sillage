//
//  ActiveNavigationEvaluator.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

/// Snapshot of real-time navigation leg metrics strictly typed using `Foundation.Measurement`.
public struct ActiveNavigationMetrics: Sendable, Equatable {
  public let bearingToWaypoint: Measurement<UnitAngle>?
  public let rangeToWaypoint: Measurement<UnitLength>?
  public let crossTrackError: Measurement<UnitLength>?

  nonisolated public static let empty = ActiveNavigationMetrics(
    bearingToWaypoint: nil,
    rangeToWaypoint: nil,
    crossTrackError: nil
  )

  nonisolated public init(
    bearingToWaypoint: Measurement<UnitAngle>?,
    rangeToWaypoint: Measurement<UnitLength>?,
    crossTrackError: Measurement<UnitLength>?
  ) {
    self.bearingToWaypoint = bearingToWaypoint
    self.rangeToWaypoint = rangeToWaypoint
    self.crossTrackError = crossTrackError
  }
}

/// Pure, stateless domain evaluator for active GoTo navigation legs.
/// Enforces deterministic origin locking and GPS degradation/loss safety rules.
public enum ActiveNavigationEvaluator {

  /// Determines whether the provided `InstrumentState` qualifies to lock an unset `originCoordinate`.
  ///
  /// Marine Safety Rule:
  /// - Only an `.active` GPS state may lock the leg origin (accepting stationary vessels within `distanceFilter`).
  /// - `.degraded`, `.stale`, and `.lost` states must never lock the origin onto an inaccurate or cached coordinate.
  nonisolated public static func eligibleOriginCoordinate(from state: InstrumentState?) -> CLLocationCoordinate2D? {
    guard let state,
          state.gpsState == .active,
          let coordinate = state.coordinate,
          CLLocationCoordinate2DIsValid(coordinate) else {
      return nil
    }
    return coordinate
  }

  /// Evaluates BTW, RNG, and XTE according to the strict GPS state truth table:
  /// - `.active`: computes BTW, RNG, and XTE (when `originCoordinate` is locked).
  /// - `.degraded`: computes BTW, RNG, and XTE (if `originCoordinate` was already locked) per No Silent Filtering;
  ///   visual degradation warning is rendered on the chart via the accuracy polygon and degraded vessel icon.
  /// - `.stale` / `.lost` / `nil`: returns `nil` for all metrics so frozen values are never displayed as live in HUDs.
  nonisolated public static func evaluate(
    leg: ActiveNavigationLeg?,
    state: InstrumentState?
  ) -> ActiveNavigationMetrics {
    guard let leg, let state else {
      return .empty
    }

    switch state.gpsState {
    case .stale, .lost:
      return .empty

    case .active, .degraded:
      guard let current = state.coordinate,
            CLLocationCoordinate2DIsValid(current) else {
        return .empty
      }

      let destination = leg.waypoint.coordinate
      let btw = current.greatCircleBearing(to: destination)
      let rng = current.geodesicDistance(to: destination)
      let xte = leg.originCoordinate.flatMap { origin in
        current.crossTrackError(from: origin, to: destination)
      }

      return ActiveNavigationMetrics(
        bearingToWaypoint: btw,
        rangeToWaypoint: rng,
        crossTrackError: xte
      )
    }
  }
}

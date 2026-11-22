//
//  WaypointMagneticSnap.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-22.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import CoreGraphics
import CoreLocation

/// Projected waypoint candidate evaluated for magnetic reticle snapping.
struct WaypointSnapCandidate: Sendable {
  let id: String
  let coordinate: CLLocationCoordinate2D
  let screenPoint: CGPoint
}

/// Magnetic snap outcome describing the locked waypoint and visual pull offset from the nominal reticle position.
struct WaypointSnapResult: Equatable, Sendable {
  let waypointID: String
  let coordinate: CLLocationCoordinate2D
  let visualOffset: CGSize
}

/// Pure screen-space evaluator for light magnetic reticle snapping to visible waypoints with detach hysteresis.
enum WaypointMagneticSnap {
  /// Evaluates whether the reticle at `reticlePoint` should magnetically attach to or stay locked on a waypoint.
  /// Hysteresis prevents rapid attach/detach oscillation at the boundary in rough marine conditions.
  static func evaluate(
    reticlePoint: CGPoint,
    candidates: [WaypointSnapCandidate],
    currentlySnappedID: String?,
    attachRadius: CGFloat,
    detachHysteresis: CGFloat
  ) -> WaypointSnapResult? {
    guard !candidates.isEmpty, attachRadius >= 0 else { return nil }

    let hysteresis = max(0, detachHysteresis)
    let detachRadius = attachRadius + hysteresis

    var closestWithinAttach: (candidate: WaypointSnapCandidate, distance: CGFloat)? = nil
    var currentCandidate: (candidate: WaypointSnapCandidate, distance: CGFloat)? = nil

    for candidate in candidates {
      let dist = hypot(candidate.screenPoint.x - reticlePoint.x, candidate.screenPoint.y - reticlePoint.y)

      if candidate.id == currentlySnappedID {
        currentCandidate = (candidate, dist)
      }

      if dist <= attachRadius {
        if let existing = closestWithinAttach {
          if dist < existing.distance {
            closestWithinAttach = (candidate, dist)
          }
        } else {
          closestWithinAttach = (candidate, dist)
        }
      }
    }

    // While locked within the detach hysteresis margin, only transfer lock to a different waypoint
    // if it is decisively closer by at least `hysteresis`, preventing ping-pong oscillation in dense harbors.
    if let current = currentCandidate, current.distance <= detachRadius {
      if let best = closestWithinAttach,
         best.candidate.id != current.candidate.id,
         best.distance + hysteresis < current.distance {
        return makeResult(for: best.candidate, from: reticlePoint)
      }
      return makeResult(for: current.candidate, from: reticlePoint)
    }

    if let best = closestWithinAttach {
      return makeResult(for: best.candidate, from: reticlePoint)
    }

    return nil
  }

  private static func makeResult(
    for candidate: WaypointSnapCandidate,
    from reticlePoint: CGPoint
  ) -> WaypointSnapResult {
    WaypointSnapResult(
      waypointID: candidate.id,
      coordinate: candidate.coordinate,
      visualOffset: CGSize(
        width: candidate.screenPoint.x - reticlePoint.x,
        height: candidate.screenPoint.y - reticlePoint.y
      )
    )
  }
}

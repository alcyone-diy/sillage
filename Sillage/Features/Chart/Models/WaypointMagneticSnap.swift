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
struct WaypointSnapCandidate: Equatable, Sendable {
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

/// Pure screen-space evaluator and candidate builder for light magnetic reticle snapping to visible waypoints.
enum WaypointMagneticSnap {

  /// Returns whether `coordinate` lies within the visible geographic bounds expanded by a 10% safety margin,
  /// handling viewports that cross the ±180° antimeridian.
  static func isCoordinateNearVisibleBounds(
    _ coordinate: CLLocationCoordinate2D,
    southWest: CLLocationCoordinate2D,
    northEast: CLLocationCoordinate2D
  ) -> Bool {
    let latSpan = max(northEast.latitude - southWest.latitude, 0.0)
    let latMargin = latSpan * 0.1
    guard coordinate.latitude >= southWest.latitude - latMargin &&
          coordinate.latitude <= northEast.latitude + latMargin else {
      return false
    }

    if southWest.longitude <= northEast.longitude {
      let lonSpan = northEast.longitude - southWest.longitude
      let lonMargin = lonSpan * 0.1
      return coordinate.longitude >= southWest.longitude - lonMargin &&
             coordinate.longitude <= northEast.longitude + lonMargin
    } else {
      // Viewport crosses the antimeridian: accept either side
      return coordinate.longitude >= southWest.longitude ||
             coordinate.longitude <= northEast.longitude
    }
  }

  /// Builds projected snap candidates from visible and GoTo waypoints, excluding active drafts and deduplicating IDs.
  static func makeCandidates(
    visibleWaypoints: [WaypointVisualState],
    goToWaypoint: WaypointVisualState?,
    draftWaypointID: String?,
    southWest: CLLocationCoordinate2D,
    northEast: CLLocationCoordinate2D,
    project: (CLLocationCoordinate2D) -> CGPoint
  ) -> [WaypointSnapCandidate] {
    var candidates: [WaypointSnapCandidate] = []

    for wp in visibleWaypoints where !wp.isDraft && wp.id != draftWaypointID {
      guard isCoordinateNearVisibleBounds(wp.coordinate, southWest: southWest, northEast: northEast) else {
        continue
      }
      candidates.append(
        WaypointSnapCandidate(
          id: wp.id,
          coordinate: wp.coordinate,
          screenPoint: project(wp.coordinate)
        )
      )
    }

    if let goTo = goToWaypoint,
       !goTo.isDraft,
       goTo.id != draftWaypointID,
       isCoordinateNearVisibleBounds(goTo.coordinate, southWest: southWest, northEast: northEast),
       !candidates.contains(where: { $0.id == goTo.id }) {
      candidates.append(
        WaypointSnapCandidate(
          id: goTo.id,
          coordinate: goTo.coordinate,
          screenPoint: project(goTo.coordinate)
        )
      )
    }

    return candidates
  }

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

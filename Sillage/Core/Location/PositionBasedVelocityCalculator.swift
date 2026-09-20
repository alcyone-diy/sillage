//
//  PositionBasedVelocityCalculator.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-19.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

/// Kinematic calculator actor estimating Course Over Ground (COG) and
/// Speed Over Ground (SOG) strictly from successive GPS coordinates and timestamps.
///
/// Concurrency & Performance Design:
/// Isolated as an independent `actor` to offload spherical/trigonometric projections and
/// internal buffer mutations off the MainActor (UI thread).
/// Uses local Euclidean flat-Earth projection (Pythagoras and atan2) instead of
/// computationally expensive Great Circle geodesics (Haversine/Vincenty), which are
/// wasteful and unnecessary over micro-displacements (1–20 meters).
public actor PositionBasedVelocityCalculator {

  public struct VelocityEstimate: Sendable, Equatable {
    public let speedOverGround: Measurement<UnitSpeed>?
    public let speedOverGroundAccuracy: Measurement<UnitSpeed>?
    public let courseOverGround: Measurement<UnitAngle>?
    public let courseOverGroundAccuracy: Measurement<UnitAngle>?

    public init(
      speedOverGround: Measurement<UnitSpeed>?,
      speedOverGroundAccuracy: Measurement<UnitSpeed>?,
      courseOverGround: Measurement<UnitAngle>?,
      courseOverGroundAccuracy: Measurement<UnitAngle>?
    ) {
      self.speedOverGround = speedOverGround
      self.speedOverGroundAccuracy = speedOverGroundAccuracy
      self.courseOverGround = courseOverGround
      self.courseOverGroundAccuracy = courseOverGroundAccuracy
    }
  }

  private struct FixEntry: Sendable {
    let coordinate: CLLocationCoordinate2D
    let accuracy: Measurement<UnitLength>
    let timestamp: Date
  }

  private static let earthRadiusMeters: Double = 6371000.0

  private var history: [FixEntry] = []
  private var wasMoving: Bool = false
  private let windowDuration: TimeInterval
  private let maxGapDuration: TimeInterval

  public init(
    windowDuration: TimeInterval = 6.0,
    maxGapDuration: TimeInterval = 10.0
  ) {
    self.windowDuration = windowDuration
    self.maxGapDuration = maxGapDuration
  }

  /// Calculates the velocity estimate for the newly received position.
  /// - Parameters:
  ///   - coordinate: The current geographic coordinate.
  ///   - horizontalAccuracy: Horizontal accuracy of the fix.
  ///   - timestamp: Acquisition timestamp.
  ///   - noiseMultiplier: Dynamic multiplier applied to the combined fix uncertainty (sigmaD).
  ///   - windowDuration: Optional overriding time window duration in seconds.
  /// - Returns: Velocity estimate with SOG and COG (or nil if stationary/indeterminate).
  public func calculate(
    coordinate: CLLocationCoordinate2D,
    horizontalAccuracy: Measurement<UnitLength>,
    timestamp: Date,
    noiseMultiplier: Double,
    windowDuration: TimeInterval? = nil
  ) -> VelocityEstimate {
    if let last = history.last {
      let dtImmediate = timestamp.timeIntervalSince(last.timestamp)
      if dtImmediate <= 0 {
        return VelocityEstimate(
          speedOverGround: nil,
          speedOverGroundAccuracy: nil,
          courseOverGround: nil,
          courseOverGroundAccuracy: nil
        )
      }
      if dtImmediate > maxGapDuration {
        history.removeAll()
        wasMoving = false
      }
    }

    let currentEntry = FixEntry(
      coordinate: coordinate,
      accuracy: horizontalAccuracy,
      timestamp: timestamp
    )
    history.append(currentEntry)

    // Drop coarse initial fixes (e.g. > 20m) only if we retain at least 2 accurate fixes
    if currentEntry.accuracy.converted(to: .meters).value <= 15.0 {
      let accurateCount = history.filter { $0.accuracy.converted(to: .meters).value <= 20.0 }.count
      if accurateCount >= 2 {
        history.removeAll { $0.accuracy.converted(to: .meters).value > 20.0 }
      }
    }

    // Prune entries older than effective window duration (using parameter or actor fallback)
    let effectiveWindowDuration = max(windowDuration ?? self.windowDuration, 0.5)
    let windowCutoff = timestamp.addingTimeInterval(-effectiveWindowDuration)
    history.removeAll { $0.timestamp < windowCutoff }

    guard history.count >= 2 else {
      return VelocityEstimate(
        speedOverGround: nil,
        speedOverGroundAccuracy: nil,
        courseOverGround: nil,
        courseOverGroundAccuracy: nil
      )
    }

    let lat2 = coordinate.latitude
    let lon2 = coordinate.longitude
    let acc1 = horizontalAccuracy.converted(to: .meters).value

    var selectedBaseline: FixEntry?
    var selectedDx: Double = 0
    var selectedDy: Double = 0
    var selectedDist: Double = 0
    var selectedSigmaD: Double = 0
    var selectedDt: TimeInterval = 0

    // Adaptive Baseline Selection:
    // Evaluate prior fixes from most recent to oldest within effectiveWindowDuration.
    // The most recent fix whose displacement clears the dynamic noise threshold is selected.
    // This minimizes group delay at high SNR / higher speeds while maintaining stability at low speeds.
    for candidate in history.dropLast().reversed() {
      let dtCand = timestamp.timeIntervalSince(candidate.timestamp)
      guard dtCand > 0 && dtCand <= effectiveWindowDuration else { continue }

      let lat1 = candidate.coordinate.latitude
      let lon1 = candidate.coordinate.longitude

      let meanLatRad = Measurement(value: (lat1 + lat2) / 2.0, unit: UnitAngle.degrees).converted(to: .radians).value
      let dLatRad = Measurement(value: lat2 - lat1, unit: UnitAngle.degrees).converted(to: .radians).value

      var dLonDeg = lon2 - lon1
      while dLonDeg > 180.0 { dLonDeg -= 360.0 }
      while dLonDeg < -180.0 { dLonDeg += 360.0 }
      let dLonRad = Measurement(value: dLonDeg, unit: UnitAngle.degrees).converted(to: .radians).value

      let dx = Self.earthRadiusMeters * dLonRad * cos(meanLatRad)
      let dy = Self.earthRadiusMeters * dLatRad
      let dist = sqrt(dx * dx + dy * dy)

      let acc0 = candidate.accuracy.converted(to: .meters).value
      let sigmaD = sqrt(acc0 * acc0 + acc1 * acc1)
      let threshold = sigmaD * noiseMultiplier

      if dist >= threshold && dist > 0 {
        selectedBaseline = candidate
        selectedDx = dx
        selectedDy = dy
        selectedDist = dist
        selectedSigmaD = sigmaD
        selectedDt = dtCand
        break
      }
    }

    guard let baseline = selectedBaseline else {
      // All prior fixes in the window show displacement below the dynamic noise threshold.
      // Vessel is stationary or indeterminate.
      let oldest = history.first ?? currentEntry
      let dtOldest = max(timestamp.timeIntervalSince(oldest.timestamp), 0.001)
      let acc0 = oldest.accuracy.converted(to: .meters).value
      let sigmaD = sqrt(acc0 * acc0 + acc1 * acc1)
      let sigmaV = sigmaD / dtOldest
      let speedAccuracy = Measurement(value: sigmaV, unit: UnitSpeed.metersPerSecond)
      if wasMoving {
        // Vessel was in active motion: an isolated noisy fix or transient accuracy spike is treated
        // as indeterminate (coasting). We return nil instead of abruptly forcing 0.0 kn, preventing
        // downstream services from prematurely aborting vessel motion and clearing COG.
        wasMoving = false
        return VelocityEstimate(
          speedOverGround: nil,
          speedOverGroundAccuracy: speedAccuracy,
          courseOverGround: nil,
          courseOverGroundAccuracy: nil
        )
      }

      return VelocityEstimate(
        speedOverGround: Measurement(value: 0.0, unit: .metersPerSecond),
        speedOverGroundAccuracy: speedAccuracy,
        courseOverGround: nil,
        courseOverGroundAccuracy: nil
      )
    }

    wasMoving = true

    let sigmaV = selectedSigmaD / selectedDt
    let speedAccuracy = Measurement(value: sigmaV, unit: UnitSpeed.metersPerSecond)
    let speedMps = selectedDist / selectedDt
    let speedOverGround = Measurement(value: speedMps, unit: UnitSpeed.metersPerSecond)

    // Navigation bearing from True North clockwise: theta = atan2(dx, dy)
    let bearingRad = atan2(selectedDx, selectedDy)
    var bearingDeg = Measurement(value: bearingRad, unit: UnitAngle.radians).converted(to: .degrees).value
    bearingDeg = (bearingDeg + 360.0).truncatingRemainder(dividingBy: 360.0)
    let courseOverGround = Measurement(value: bearingDeg, unit: UnitAngle.degrees)

    // Angular uncertainty: sigma_theta ~ atan2(min(sigmaD, d), d)
    let sigmaThetaRad = atan2(min(selectedSigmaD, selectedDist), selectedDist)
    let sigmaThetaDeg = Measurement(value: sigmaThetaRad, unit: UnitAngle.radians).converted(to: .degrees).value
    let courseOverGroundAccuracy = Measurement(value: sigmaThetaDeg, unit: UnitAngle.degrees)

    return VelocityEstimate(
      speedOverGround: speedOverGround,
      speedOverGroundAccuracy: speedAccuracy,
      courseOverGround: courseOverGround,
      courseOverGroundAccuracy: courseOverGroundAccuracy
    )
  }

  /// Resets the internal history buffer (e.g., when signal is interrupted or mode is switched).
  public func reset() {
    history.removeAll()
    wasMoving = false
  }
}

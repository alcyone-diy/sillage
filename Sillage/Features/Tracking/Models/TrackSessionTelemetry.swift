//
//  TrackSessionTelemetry.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-23.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

/// Encapsulates the ongoing telemetry state of a track recording session.
public struct TrackSessionTelemetry: Sendable {
  public private(set) var sessionStartTime: Date?
  public private(set) var lastTimeUpdated: Date?
  public private(set) var lastSessionDurationUpdateMonotonicTime: ContinuousClock.Instant?
  public private(set) var sessionDistance: Measurement<UnitLength>?
  public private(set) var sessionDuration: Duration?
  
  public private(set) var minLatitude: Measurement<UnitAngle>?
  public private(set) var maxLatitude: Measurement<UnitAngle>?
  public private(set) var minLongitude: Measurement<UnitAngle>?
  public private(set) var maxLongitude: Measurement<UnitAngle>?
  public private(set) var maxSpeedOverGround: Measurement<UnitSpeed>?
  public private(set) var pointsCount: Int?
  
  public private(set) var lastRecordedNavigationFix: NavigationFix?
  public private(set) var lastReceivedNavigationFix: NavigationFix?

  public init() {}
  
  // As long as the first fix is not received, there is no values.
  // The trace recording is in pending mode.
  public mutating func start() {
    sessionStartTime = nil
    lastTimeUpdated = nil
    lastSessionDurationUpdateMonotonicTime = nil
    sessionDistance = nil
    sessionDuration = nil
    minLatitude = nil
    maxLatitude = nil
    minLongitude = nil
    maxLongitude = nil
    maxSpeedOverGround = nil
    pointsCount = 0
    lastRecordedNavigationFix = nil
    lastReceivedNavigationFix = nil
  }
  
  public mutating func stop() -> NavigationFix? {
    guard lastRecordedNavigationFix != nil &&
          lastReceivedNavigationFix != nil &&
          lastRecordedNavigationFix != lastReceivedNavigationFix else {
      return nil
    }
    if let lastNavigationFix = lastReceivedNavigationFix,
       let lastMonotonicTime = lastSessionDurationUpdateMonotonicTime {
      _ = self.process(
        fix: lastNavigationFix,
        filters: nil,
        now:lastMonotonicTime
      )
    }
    return lastReceivedNavigationFix
  }
  
  public mutating func restore(
    from session: TrackSession,
  ) {
    sessionStartTime = session.startTime
    // We treat a restore like a pause: we don't want
    // to accumulate time during the app-killed gap.
    lastTimeUpdated = nil
    sessionDistance = session.totalDistance ?? Measurement(value: 0, unit: UnitLength.meters)
    sessionDuration = session.duration
    minLatitude = session.minLatitude
    maxLatitude = session.maxLatitude
    minLongitude = session.minLongitude
    maxLongitude = session.maxLongitude
    maxSpeedOverGround = session.maxSpeed
    pointsCount = session.pointsCount
    lastSessionDurationUpdateMonotonicTime = nil
  }
  
  public mutating func process(
    fix: NavigationFix,
    filters: TrackFilters?,
    now: ContinuousClock.Instant = ContinuousClock().now
  ) -> Bool {
    let validFix = self.append(fix: fix, filters: filters)
    if validFix {
      self.updateTime(with: fix, now: now)
    }
    return validFix
  }
  
  public func activeDuration(
    isRecording: Bool,
    now: ContinuousClock.Instant = ContinuousClock().now
  ) -> Duration? {
    guard let lastReceiveTime = lastSessionDurationUpdateMonotonicTime else {
      return sessionDuration
    }
    
    if isRecording {
      // Use the injected 'now' parameter instead of hardcoded ContinuousClock()
      let timeSinceLastLocation = now - lastReceiveTime
      let currentSessionDuration = sessionDuration ?? .seconds(0)
      return currentSessionDuration + timeSinceLastLocation
    } else {
      return sessionDuration
    }
  }
  
  public mutating func startNewSegment() {
    lastSessionDurationUpdateMonotonicTime = nil
    lastTimeUpdated = nil
    lastReceivedNavigationFix = nil
    lastRecordedNavigationFix = nil
  }
  
  // MARK: - Private
  
  private mutating func updateTime(
    with fix: NavigationFix,
    now: ContinuousClock.Instant = ContinuousClock().now
  ) {
    if let lastUpdate = lastTimeUpdated {
      let timeSinceLast = max(0, fix.timestamp.timeIntervalSince(lastUpdate))
      let currentDuration = sessionDuration ?? .seconds(0)
      sessionDuration = currentDuration + .seconds(timeSinceLast)
    }
    if sessionStartTime == nil {
      sessionStartTime = fix.timestamp
    }
    lastTimeUpdated = fix.timestamp
    lastSessionDurationUpdateMonotonicTime = now
    if sessionDuration == nil {
      sessionDuration = .seconds(0)
    }
  }
  
  private mutating func append(fix: NavigationFix, filters: TrackFilters?) -> Bool {
    lastReceivedNavigationFix = fix
    let distanceSinceLast: Measurement<UnitLength>
    if let lastLoc = lastRecordedNavigationFix {
      distanceSinceLast = fix.distance(from: lastLoc)
      let timeSinceLast = fix.timestamp.timeIntervalSince(lastLoc.timestamp)
      
      let hasMovedSignificantly = filters == nil || distanceSinceLast > (filters?.minDistance ?? Measurement(value: 0, unit: .meters))
      let hasSufficientTimePassed = filters == nil || timeSinceLast > (filters?.minTimeIntervalSeconds ?? 0)
      
      guard hasMovedSignificantly || hasSufficientTimePassed else { return false }
    } else {
      distanceSinceLast = Measurement(value: 0, unit: .meters)
    }
    let currentDistance = sessionDistance ?? Measurement(value: 0, unit: UnitLength.meters)
    sessionDistance = currentDistance + distanceSinceLast

    // Bounding Box
    let latitude = Measurement(value: fix.coordinate.latitude, unit: UnitAngle.degrees)
    let longitude = Measurement(value: fix.coordinate.longitude, unit: UnitAngle.degrees)
    
    minLatitude = min(minLatitude ?? latitude, latitude)
    maxLatitude = max(maxLatitude ?? latitude, latitude)
    minLongitude = min(minLongitude ?? longitude, longitude)
    maxLongitude = max(maxLongitude ?? longitude, longitude)
    
    // Speed
    if let speedOverGround = fix.speedOverGround {
      maxSpeedOverGround = max(maxSpeedOverGround ?? speedOverGround, speedOverGround)
    }
    
    // Points count
    pointsCount = (pointsCount ?? 0) + 1
    
    lastRecordedNavigationFix = fix
    return true
  }
}

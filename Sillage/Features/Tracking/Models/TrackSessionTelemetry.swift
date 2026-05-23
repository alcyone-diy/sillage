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
  
  public init() {}
  
  public mutating func start(at navigationFix: NavigationFix) {
    self.sessionStartTime = navigationFix.timestamp
    self.lastTimeUpdated = nil
    self.sessionDistance = Measurement(value: 0, unit: UnitLength.meters)
    self.sessionDuration = nil
    self.lastSessionDurationUpdateMonotonicTime = .now
    // No need to update those parameters, updateTime(with:) and
    // append(fix:distanceSinceLast:) need to be called with this
    // navigationFix.
    self.minLatitude = nil
    self.maxLatitude = nil
    self.minLongitude = nil
    self.maxLongitude = nil
    self.maxSpeedOverGround = nil
    self.pointsCount = 0
  }
  
  public mutating func restore(
    from session: TrackSession,
  ) {
    sessionStartTime = session.startTime
    // We treat a restore like a pause: we don't want
    // to accumulate time during the app-killed gap.
    lastTimeUpdated = nil
    sessionDistance = session.totalDistance
    sessionDuration = session.duration
    minLatitude = session.minLatitude
    maxLatitude = session.maxLatitude
    minLongitude = session.minLongitude
    maxLongitude = session.maxLongitude
    maxSpeedOverGround = session.maxSpeed
    pointsCount = session.pointsCount
    lastSessionDurationUpdateMonotonicTime = nil
  }
  
  public mutating func updateTime(with fix: NavigationFix) {
    if let lastUpdate = lastTimeUpdated {
      let timeSinceLast = max(0, fix.timestamp.timeIntervalSince(lastUpdate))
      let currentDuration = sessionDuration ?? .seconds(0)
      sessionDuration = currentDuration + .seconds(timeSinceLast)
    }
    lastTimeUpdated = fix.timestamp
    lastSessionDurationUpdateMonotonicTime = .now
  }
  
  public mutating func append(fix: NavigationFix, filters: TrackFilters) -> Bool {
    var distanceToAppend: Measurement<UnitLength>? = nil
    
    if let lastLoc = lastRecordedNavigationFix {
      let distanceSinceLast = fix.distance(from: lastLoc)
      let timeSinceLast = fix.timestamp.timeIntervalSince(lastLoc.timestamp)
      
      let hasMovedSignificantly = distanceSinceLast > filters.minDistance
      let hasSufficientTimePassed = timeSinceLast > filters.minTimeIntervalSeconds
      
      guard hasMovedSignificantly || hasSufficientTimePassed else { return false }
      
      distanceToAppend = distanceSinceLast
    }
    
    // Distance
    if let distanceSinceLast = distanceToAppend, let currentDistance = sessionDistance {
      sessionDistance = currentDistance + distanceSinceLast
    }
    
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
  
  public func activeDuration(isRecording: Bool) -> Duration? {
    guard let lastReceiveTime = lastSessionDurationUpdateMonotonicTime else {
      return sessionDuration
    }
    
    if isRecording {
      let clock = ContinuousClock()
      let timeSinceLastLocation = clock.now - lastReceiveTime
      let currentSessionDuration = sessionDuration ?? .seconds(0)
      return currentSessionDuration + timeSinceLastLocation
    } else {
      return sessionDuration
    }
  }
  
  public mutating func startNewSegment() {
    lastSessionDurationUpdateMonotonicTime = nil
    lastTimeUpdated = nil
    lastRecordedNavigationFix = nil
  }
  
  public mutating func clear() {
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
    pointsCount = nil
    lastRecordedNavigationFix = nil
  }
}

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
@MainActor
public struct TrackSessionTelemetry: Sendable {
  public enum State: Sendable, Equatable {
    // Not recording.
    case stopped
    // Waiting for the first fix.
    // When receiving a fix, state updates to recording.
    case pending
    // First fix was recorded, waiting for other fixes.
    case recording
    // Waiting for other fixes, but the time doesn't increase,
    // and the distance won't be updated on the next fix.
    // When receiving a fix, state updates to recording.
    case paused
  }
  
  public enum ProcessError: Error, Equatable {
    case invalidState
    case invalidTimestamp
    case filteredOut
  }
  
  // MARK: - Properties
  public private(set) var state: State = .stopped
  public private(set) var startTime: Date?
  public private(set) var lastTimeUpdated: Date?
  public private(set) var segmentIndex: Int?
  public private(set) var totalPointCount: Int = 0

  public private(set) var totalDuration: Duration?
  public private(set) var totalDistanceOverGround: Measurement<UnitLength>?
  public private(set) var geographicBoundingBox: GeographicBoundingBox?
  public private(set) var maxSpeedOverGround: Measurement<UnitSpeed>?
  
  public private(set) var lastReceivedNavigationFix: NavigationFix?
  public private(set) var lastRecordedNavigationFix: NavigationFix?
  public private(set) var lastRecordedNavigationFixMonotonicTime: ContinuousClock.Instant?

  // MARK: - Public
  public init() {}
  
  // As long as the first fix is not received, there is no values.
  // The trace recording is in pending mode.
  public mutating func start() {
    guard state == .stopped else {
      return
    }
    state = .pending
    startTime = nil
    lastTimeUpdated = nil
    segmentIndex = nil
    totalPointCount = 0
    totalDuration = nil
    totalDistanceOverGround = nil
    geographicBoundingBox = nil
    maxSpeedOverGround = nil
    lastReceivedNavigationFix = nil
    lastRecordedNavigationFix = nil
    lastRecordedNavigationFixMonotonicTime = nil
  }
  
  public mutating func stop() -> NavigationFix? {
    guard lastRecordedNavigationFix != nil &&
          lastReceivedNavigationFix != nil &&
          lastRecordedNavigationFix != lastReceivedNavigationFix else {
      lastRecordedNavigationFixMonotonicTime = nil
      state = .stopped
      return nil
    }
    if let lastNavigationFix = lastReceivedNavigationFix,
       let lastMonotonicTime = lastRecordedNavigationFixMonotonicTime {
      // Set no filter to make sure the last navigation is accepted.
      try? self.process(
        fix: lastNavigationFix,
        filters: nil,
        now:lastMonotonicTime
      )
    }
    state = .stopped
    lastRecordedNavigationFixMonotonicTime = nil
    return lastReceivedNavigationFix
  }
  
  public mutating func pause() {
    guard state == .pending || state == .recording else {
      return
    }
    state = .paused
    lastRecordedNavigationFixMonotonicTime = nil
    lastTimeUpdated = nil
    lastReceivedNavigationFix = nil
    lastRecordedNavigationFix = nil
  }

  public mutating func resume() {
    state = .pending
  }
  
  public mutating func restore(
    from session: TrackSession,
    lastSegmentIndex: Int?
  ) {
    guard state == .stopped else {
      return
    }
    state = .pending
    startTime = session.startTime
    // We treat a restore like a pause: we don't want
    // to accumulate time during the app-killed gap.
    lastTimeUpdated = nil
    totalDuration = session.totalDuration
    totalDistanceOverGround = session.totalDistanceOverGround
    if let southLatitude = session.southLatitude,
       let northLatitude = session.northLatitude,
       let westLongitude = session.westLongitude,
       let eastLongitude = session.eastLongitude {
      geographicBoundingBox = GeographicBoundingBox(
        southLatitude: southLatitude,
        northLatitude: northLatitude,
        westLongitude: westLongitude,
        eastLongitude: eastLongitude
      )
    } else {
      geographicBoundingBox = nil
    }
    maxSpeedOverGround = session.maxSpeedOverGround
    segmentIndex = (lastSegmentIndex == nil) ? 0 : lastSegmentIndex
    totalPointCount = session.totalPointCount
    lastRecordedNavigationFixMonotonicTime = nil
  }
  
  public mutating func process(
    fix: NavigationFix,
    filters: TrackFilters?,
    now: ContinuousClock.Instant = ContinuousClock().now
  ) throws {
    guard state == .pending || state == .recording else {
      throw ProcessError.invalidState
    }
    try self.append(fix: fix, filters: filters, now: now)
    self.updateTime(with: fix)
    state = .recording
  }
  
  public func activeTotalDuration(
    now: ContinuousClock.Instant = ContinuousClock().now
  ) -> Duration? {
    guard let lastReceiveTime = lastRecordedNavigationFixMonotonicTime else {
      return totalDuration
    }
    // Add the difference between now and timeSinceLastLocation,
    // to show that time is still progressing.
    // But duration is never updated with `ContinuousClock`.
    let timeSinceLastLocation = now - lastReceiveTime
    let currentDuration = totalDuration ?? .seconds(0)
    return currentDuration + timeSinceLastLocation
  }
  
  public func totalAverageSpeedOverGround() -> Measurement<UnitSpeed>? {
    guard let totalDistanceOverGround = totalDistanceOverGround?.converted(to: .meters).value,
          let durationDuration = totalDuration?.timeInterval,
          durationDuration > 0 else {
      return nil
    }
    return Measurement(value: totalDistanceOverGround / durationDuration, unit: .metersPerSecond)
  }
  
  // MARK: - Private
  
  private mutating func updateTime(with fix: NavigationFix) {
    if let lastUpdate = lastTimeUpdated {
      let timeSinceLast = max(0, fix.timestamp.timeIntervalSince(lastUpdate))
      let currentDuration = totalDuration ?? .seconds(0)
      // There is no fractions lost since Duration.seconds takes Double type.
      totalDuration = currentDuration + .seconds(timeSinceLast)
    }
    if startTime == nil {
      startTime = fix.timestamp
    }
    lastTimeUpdated = fix.timestamp
    if totalDuration == nil {
      totalDuration = .seconds(0)
    }
  }
  
  private mutating func append(
    fix: NavigationFix,
    filters: TrackFilters?,
    now: ContinuousClock.Instant = ContinuousClock().now
  ) throws {
    lastReceivedNavigationFix = fix
    let distanceSinceLast: Measurement<UnitLength>
    if let lastLoc = lastRecordedNavigationFix {
      distanceSinceLast = fix.distance(from: lastLoc)
      let timeSinceLast = fix.timestamp.timeIntervalSince(lastLoc.timestamp)
      
      let isFixValid: Bool
      if let filters = filters {
        let hasDistanceFilter = filters.minDistance.value > 0
        let hasTimeFilter = filters.minTimeIntervalSeconds > 0
        if !hasDistanceFilter && !hasTimeFilter {
          isFixValid = true
        } else {
          let hasMovedSignificantly = hasDistanceFilter && distanceSinceLast > filters.minDistance
          let hasSufficientTimePassed = hasTimeFilter && timeSinceLast > filters.minTimeIntervalSeconds
          isFixValid = hasMovedSignificantly || hasSufficientTimePassed
        }
      } else {
        isFixValid = true
      }
      guard timeSinceLast > 0 else { throw ProcessError.invalidTimestamp }
      guard isFixValid else { throw ProcessError.filteredOut }
    } else {
      distanceSinceLast = Measurement(value: 0, unit: .meters)
    }
    let currentDistance = totalDistanceOverGround ?? Measurement(value: 0, unit: UnitLength.meters)
    totalDistanceOverGround = currentDistance + distanceSinceLast
    
    // Bounding Box
    let fixLat = Measurement(value: fix.coordinate.latitude, unit: UnitAngle.degrees)
    let fixLon = Measurement(value: fix.coordinate.longitude, unit: UnitAngle.degrees)
    if var box = geographicBoundingBox {
      box.expand(toIncludeLatitude: fixLat, longitude: fixLon)
      geographicBoundingBox = box
    } else {
      geographicBoundingBox = GeographicBoundingBox(latitude: fixLat, longitude: fixLon)
    }
    
    // Speed
    if let speedOverGround = fix.speedOverGround {
      maxSpeedOverGround = max(maxSpeedOverGround ?? speedOverGround, speedOverGround)
    }
    
    // Points count
    totalPointCount = totalPointCount + 1
    if state == .pending {
      // Increase the index only when there is a new fix (not in the resume method).
      segmentIndex = segmentIndex.map { $0 + 1 } ?? 0
    }
    
    lastRecordedNavigationFix = fix
    lastRecordedNavigationFixMonotonicTime = now
  }
}

//
//  TrackSessionTelemetryTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-24.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Testing
import CoreLocation
@testable import Sillage

@Suite("Track Session Telemetry Tests")
struct TrackSessionTelemetryTests {
  
  @Test("Initial state")
  func testInit() {
    let telemetry = TrackSessionTelemetry()
    #expect(telemetry.sessionStartTime == nil)
    #expect(telemetry.lastTimeUpdated == nil)
    #expect(telemetry.sessionDistance == nil)
    #expect(telemetry.sessionDuration == nil)
    #expect(telemetry.minLatitude == nil)
    #expect(telemetry.maxLatitude == nil)
    #expect(telemetry.minLongitude == nil)
    #expect(telemetry.maxLongitude == nil)
    #expect(telemetry.maxSpeedOverGround == nil)
    #expect(telemetry.pointsCount == nil)
    #expect(telemetry.lastRecordedNavigationFix == nil)
  }
  
  @Test("Start telemetry")
  func testStart() {
    var telemetry = TrackSessionTelemetry()
    let fix = createNavigationFix(latitude: 46.16, longitude: -1.15, timestamp: Date(timeIntervalSince1970: 1000))
    telemetry.start(at: fix)
    
    #expect(telemetry.sessionStartTime == fix.timestamp)
    #expect(telemetry.lastTimeUpdated == nil)
    #expect(telemetry.sessionDistance?.value == 0)
    #expect(telemetry.sessionDuration == nil)
    #expect(telemetry.lastSessionDurationUpdateMonotonicTime != nil)
    #expect(telemetry.pointsCount == 0)
    #expect(telemetry.lastRecordedNavigationFix == nil)
  }
  
  @Test("Restore telemetry")
  func testRestore() {
    var telemetry = TrackSessionTelemetry()
    let session = TrackSession(
      id: "test-id",
      startTime: Date(timeIntervalSince1970: 1000),
      duration: .seconds(3600),
      totalDistance: Measurement(value: 5000, unit: .meters),
      minLatitude: Measurement(value: 45.0, unit: .degrees),
      maxLatitude: Measurement(value: 46.0, unit: .degrees),
      minLongitude: Measurement(value: -1.0, unit: .degrees),
      maxLongitude: Measurement(value: 1.0, unit: .degrees),
      maxSpeed: Measurement(value: 10, unit: .metersPerSecond),
      pointsCount: 150
    )
    
    telemetry.restore(from: session)
    
    #expect(telemetry.sessionStartTime == session.startTime)
    #expect(telemetry.lastTimeUpdated == nil)
    #expect(telemetry.sessionDistance == session.totalDistance)
    #expect(telemetry.sessionDuration == session.duration)
    #expect(telemetry.minLatitude == session.minLatitude)
    #expect(telemetry.maxLatitude == session.maxLatitude)
    #expect(telemetry.minLongitude == session.minLongitude)
    #expect(telemetry.maxLongitude == session.maxLongitude)
    #expect(telemetry.maxSpeedOverGround == session.maxSpeed)
    #expect(telemetry.pointsCount == session.pointsCount)
    #expect(telemetry.lastSessionDurationUpdateMonotonicTime == nil)
  }
  
  @Test("Update time")
  func testUpdateTime() {
    var telemetry = TrackSessionTelemetry()
    let startTime = Date(timeIntervalSince1970: 1000)
    let fix1 = createNavigationFix(latitude: 46.16, longitude: -1.15, timestamp: startTime)
    
    // updateTime needs lastTimeUpdated to be non-nil to accumulate
    telemetry.start(at: fix1)
    telemetry.updateTime(with: fix1) // Sets lastTimeUpdated to fix1.timestamp
    
    let fix2 = createNavigationFix(latitude: 46.16, longitude: -1.15, timestamp: startTime.addingTimeInterval(10))
    telemetry.updateTime(with: fix2)
    
    #expect(telemetry.lastTimeUpdated == fix2.timestamp)
    #expect(telemetry.sessionDuration == .seconds(10))
  }
  
  @Test("Append first fix")
  func testAppendWithFirstFix() {
    var telemetry = TrackSessionTelemetry()
    let fix = createNavigationFix(
      latitude: 45.0,
      longitude: -1.0,
      speed: 5.0,
      timestamp: Date()
    )
    let filters = TrackFilters.default
    
    telemetry.start(at: fix)
    let appended = telemetry.append(fix: fix, filters: filters)
    
    #expect(appended)
    #expect(telemetry.pointsCount == 1)
    #expect(telemetry.sessionDistance?.value == 0)
    #expect(telemetry.minLatitude?.value == 45.0)
    #expect(telemetry.maxLatitude?.value == 45.0)
    #expect(telemetry.maxSpeedOverGround?.value == 5.0)
    #expect(telemetry.lastRecordedNavigationFix == fix)
  }
  
  @Test("Filter rejection")
  func testAppendWithFilterRejection() {
    var telemetry = TrackSessionTelemetry()
    let time1 = Date(timeIntervalSince1970: 1000)
    let fix1 = createNavigationFix(latitude: 45.0, longitude: -1.0, timestamp: time1)
    let filters = TrackFilters(
      minDistance: Measurement(value: 10, unit: .meters),
      minTimeInterval: Measurement(value: 60, unit: .seconds),
      maxHorizontalAccuracy: Measurement(value: 50, unit: .meters)
    )
    
    telemetry.start(at: fix1)
    _ = telemetry.append(fix: fix1, filters: filters)
    
    // Very close in distance and time
    let time2 = time1.addingTimeInterval(10) // 10s < 60s
    let fix2 = createNavigationFix(latitude: 45.0, longitude: -1.0, timestamp: time2)
    
    let appended = telemetry.append(fix: fix2, filters: filters)
    #expect(!appended)
    #expect(telemetry.pointsCount == 1)
  }
  
  @Test("Filter acceptance by time")
  func testAppendWithFilterAcceptanceByTime() {
    var telemetry = TrackSessionTelemetry()
    let time1 = Date(timeIntervalSince1970: 1000)
    let fix1 = createNavigationFix(latitude: 45.0, longitude: -1.0, timestamp: time1)
    let filters = TrackFilters(
      minDistance: Measurement(value: 10, unit: .meters),
      minTimeInterval: Measurement(value: 60, unit: .seconds),
      maxHorizontalAccuracy: Measurement(value: 50, unit: .meters)
    )
    
    telemetry.start(at: fix1)
    _ = telemetry.append(fix: fix1, filters: filters)
    
    // More than 60 seconds passed
    let time2 = time1.addingTimeInterval(65)
    let fix2 = createNavigationFix(latitude: 45.0, longitude: -1.0, timestamp: time2)
    
    let appended = telemetry.append(fix: fix2, filters: filters)
    #expect(appended)
    #expect(telemetry.pointsCount == 2)
  }
  
  @Test("Filter acceptance by distance")
  func testAppendWithFilterAcceptanceByDistance() throws {
    var telemetry = TrackSessionTelemetry()
    let time1 = Date(timeIntervalSince1970: 1000)
    let fix1 = createNavigationFix(latitude: 45.0, longitude: -1.0, timestamp: time1)
    let filters = TrackFilters(
      minDistance: Measurement(value: 10, unit: .meters),
      minTimeInterval: Measurement(value: 60, unit: .seconds),
      maxHorizontalAccuracy: Measurement(value: 50, unit: .meters)
    )
    
    telemetry.start(at: fix1)
    _ = telemetry.append(fix: fix1, filters: filters)
    
    // Less than 60s, but significantly different location
    let time2 = time1.addingTimeInterval(5)
    // 0.001 degree is approx 111 meters, which is > 10m minDistance
    let fix2 = createNavigationFix(latitude: 45.001, longitude: -1.0, timestamp: time2)
    
    let appended = telemetry.append(fix: fix2, filters: filters)
    #expect(appended)
    #expect(telemetry.pointsCount == 2)
    let distance = try #require(telemetry.sessionDistance)
    #expect(distance.value > 100)
  }
  
  @Test("Clear telemetry")
  func testClear() {
    var telemetry = TrackSessionTelemetry()
    let fix = createNavigationFix(latitude: 46.16, longitude: -1.15, timestamp: Date())
    telemetry.start(at: fix)
    telemetry.updateTime(with: fix)
    _ = telemetry.append(fix: fix, filters: .default)
    
    telemetry.clear()
    
    #expect(telemetry.sessionStartTime == nil)
    #expect(telemetry.lastTimeUpdated == nil)
    #expect(telemetry.sessionDistance == nil)
    #expect(telemetry.sessionDuration == nil)
    #expect(telemetry.minLatitude == nil)
    #expect(telemetry.maxLatitude == nil)
    #expect(telemetry.minLongitude == nil)
    #expect(telemetry.maxLongitude == nil)
    #expect(telemetry.maxSpeedOverGround == nil)
    #expect(telemetry.pointsCount == nil)
    #expect(telemetry.lastRecordedNavigationFix == nil)
  }
  
  @Test("Start new segment")
  func testStartNewSegment() {
    var telemetry = TrackSessionTelemetry()
    let fix = createNavigationFix(latitude: 46.16, longitude: -1.15, timestamp: Date())
    telemetry.start(at: fix)
    telemetry.updateTime(with: fix)
    _ = telemetry.append(fix: fix, filters: .default)
    
    telemetry.startNewSegment()
    
    #expect(telemetry.lastTimeUpdated == nil)
    #expect(telemetry.lastRecordedNavigationFix == nil)
    #expect(telemetry.lastSessionDurationUpdateMonotonicTime == nil)
    
    // Other properties should be kept
    #expect(telemetry.sessionStartTime != nil)
    #expect(telemetry.pointsCount == 1)
  }
  
  @Test("Active duration when recording")
  func testActiveDurationWhenRecording() {
    var telemetry = TrackSessionTelemetry()
    let fix = createNavigationFix(latitude: 46.16, longitude: -1.15, timestamp: Date())
    telemetry.start(at: fix) // Sets lastSessionDurationUpdateMonotonicTime to .now
    
    let duration = telemetry.activeDuration(isRecording: true)
    #expect(duration != nil)
  }
  
  @Test("Active duration when not recording")
  func testActiveDurationWhenNotRecording() {
    var telemetry = TrackSessionTelemetry()
    let session = TrackSession(id: "test", startTime: Date(), duration: .seconds(100))
    telemetry.restore(from: session) // Sets lastSessionDurationUpdateMonotonicTime to nil
    
    let duration = telemetry.activeDuration(isRecording: false)
    #expect(duration == .seconds(100))
  }
  
  @Test("Filter acceptance at Null Island (0,0)")
  func testAppendWithNullIslandEdgeCase() {
    var telemetry = TrackSessionTelemetry()
    let fix = createNavigationFix(
      latitude: 0,
      longitude: 0,
      speed: 2.0,
      timestamp: Date()
    )
    
    telemetry.start(at: fix)
    let appended = telemetry.append(fix: fix, filters: .default)
    
    #expect(appended)
    #expect(telemetry.pointsCount == 1)
    #expect(telemetry.minLatitude?.value == 0)
    #expect(telemetry.maxLatitude?.value == 0)
    #expect(telemetry.minLongitude?.value == 0)
    #expect(telemetry.maxLongitude?.value == 0)
  }
  
  @Test("Distance calculation towards Null Island (0,0)")
  func testDistanceCalculationToNullIsland() throws {
    var telemetry = TrackSessionTelemetry()
    let time1 = Date(timeIntervalSince1970: 1000)
    // Start approx 111 meters north of Null Island
    let fix1 = createNavigationFix(latitude: 0.001, longitude: 0, timestamp: time1)
    let filters = TrackFilters(
      minDistance: Measurement(value: 10, unit: .meters),
      minTimeInterval: Measurement(value: 60, unit: .seconds),
      maxHorizontalAccuracy: Measurement(value: 50, unit: .meters)
    )
    
    telemetry.start(at: fix1)
    _ = telemetry.append(fix: fix1, filters: filters)
    
    let time2 = time1.addingTimeInterval(5)
    // Move precisely to Null Island
    let fix2 = createNavigationFix(latitude: 0, longitude: 0, timestamp: time2)
    
    let appended = telemetry.append(fix: fix2, filters: filters)
    
    #expect(appended)
    #expect(telemetry.pointsCount == 2)
    
    let distance = try #require(telemetry.sessionDistance)
    // 0.001 degrees of latitude is roughly 110.57 meters on the WGS 84 ellipsoid.
    #expect(distance.value > 110)
    #expect(distance.value < 112)
  }
  
  // MARK: - Helpers
  
  private func createNavigationFix(
    latitude: CLLocationDegrees,
    longitude: CLLocationDegrees,
    speed: Double = 0,
    timestamp: Date
  ) -> NavigationFix {
    return NavigationFix(
      coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
      horizontalAccuracy: Measurement(value: 5, unit: .meters),
      courseOverGround: nil,
      courseOverGroundAccuracy: nil,
      speedOverGround: Measurement(value: speed, unit: .metersPerSecond),
      speedOverGroundAccuracy: nil,
      timestamp: timestamp
    )
  }
}

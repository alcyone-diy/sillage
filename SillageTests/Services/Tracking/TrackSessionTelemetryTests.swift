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
@MainActor
struct TrackSessionTelemetryTests {
  
  @Test("Initial state")
  func testInit() {
    let telemetry = TrackSessionTelemetry()
    #expect(telemetry.startTime == nil)
    #expect(telemetry.lastTimeUpdated == nil)
    #expect(telemetry.distance == nil)
    #expect(telemetry.duration == nil)
    #expect(telemetry.minLatitude == nil)
    #expect(telemetry.maxLatitude == nil)
    #expect(telemetry.minLongitude == nil)
    #expect(telemetry.maxLongitude == nil)
    #expect(telemetry.maxSpeedOverGround == nil)
    #expect(telemetry.pointsCount == nil)
    #expect(telemetry.lastRecordedNavigationFix == nil)
    #expect(telemetry.lastReceivedNavigationFix == nil)
  }
  
  @Test("Start telemetry")
  func testStart() {
    var telemetry = TrackSessionTelemetry()
    telemetry.start()
    #expect(telemetry.startTime == nil)
    #expect(telemetry.lastTimeUpdated == nil)
    #expect(telemetry.distance == nil)
    #expect(telemetry.duration == nil)
    #expect(telemetry.lastRecordedNavigationFixMonotonicTime == nil)
    #expect(telemetry.pointsCount == 0)
    #expect(telemetry.lastRecordedNavigationFix == nil)
    #expect(telemetry.lastReceivedNavigationFix == nil)
    
    let activeDuration = telemetry.activeDuration()
    #expect(activeDuration == nil)
  }
  
  @Test("First fix")
  func testFirstFix() {
    var telemetry = TrackSessionTelemetry()
    telemetry.start()
    
    let fix = createNavigationFix(
      latitude: 46.16,
      longitude: -1.15,
      timestamp: Date(timeIntervalSince1970: 1000)
    )
    let baseMonotonicTime = ContinuousClock().now
    let appendedFix = telemetry.process(fix: fix, filters: .default, now: baseMonotonicTime)
    #expect(appendedFix)
    #expect(telemetry.startTime == fix.timestamp)
    #expect(telemetry.lastTimeUpdated == fix.timestamp)
    #expect(telemetry.distance?.value == 0)
    #expect(telemetry.duration == .seconds(0))
    #expect(telemetry.lastRecordedNavigationFixMonotonicTime == baseMonotonicTime)
    #expect(telemetry.pointsCount == 1)
    #expect(telemetry.lastRecordedNavigationFix == fix)
    #expect(telemetry.lastReceivedNavigationFix == fix)
  }

  @Test("Second fix")
  func testSecondFix() {
    let filters = TrackFilters.default
    var telemetry = TrackSessionTelemetry()
    telemetry.start()

    // First fix.
    let fix1Timestamp: Double = 1000
    let fix1 = createNavigationFix(
      latitude: 46.16,
      longitude: -1.15,
      timestamp: Date(timeIntervalSince1970: fix1Timestamp)
    )
    let baseMonotonicTime = ContinuousClock().now
    _ = telemetry.process(fix: fix1, filters: filters, now: baseMonotonicTime)

    // Second fix.
    let durationForSecondFix = TimeInterval(10)
    let fix2 = createNavigationFix(
      latitude: 46.16,
      longitude: -2.15,
      timestamp: Date(timeIntervalSince1970: fix1Timestamp + durationForSecondFix)
    )
    let simulatedFutureNow = baseMonotonicTime.advanced(by: .seconds(10))
    let appendedFix2 = telemetry.process(fix: fix2, filters: filters, now: simulatedFutureNow)
    #expect(appendedFix2)
    #expect(telemetry.startTime == fix1.timestamp)
    #expect(telemetry.lastTimeUpdated == fix2.timestamp)
    #expect(telemetry.distance != nil)
    if let distance = telemetry.distance {
      #expect(distance.converted(to: .meters).value > 0)
    }
    #expect(telemetry.duration?.components.seconds == Int64(durationForSecondFix))
    #expect(telemetry.lastRecordedNavigationFixMonotonicTime == simulatedFutureNow)
    #expect(telemetry.pointsCount == 2)
    #expect(telemetry.lastRecordedNavigationFix == fix2)
    #expect(telemetry.lastReceivedNavigationFix == fix2)
  }

  @Test("Stop after second fix")
  func testStopAfterSecondFix() {
    let filters = TrackFilters.default
    var telemetry = TrackSessionTelemetry()
    telemetry.start()

    // First fix.
    let fix1Timestamp: Double = 1000
    let fix1 = createNavigationFix(
      latitude: 46.16,
      longitude: -1.15,
      timestamp: Date(timeIntervalSince1970: fix1Timestamp)
    )
    let baseMonotonicTime = ContinuousClock().now
    _ = telemetry.process(fix: fix1, filters: filters, now: baseMonotonicTime)

    // Second fix.
    let durationForSecondFix = TimeInterval(10)
    let fix2 = createNavigationFix(
      latitude: 46.16,
      longitude: -2.15,
      timestamp: Date(timeIntervalSince1970: fix1Timestamp + durationForSecondFix)
    )
    let simulatedFutureNow = baseMonotonicTime.advanced(by: .seconds(10))
    let appendedFix2 = telemetry.process(fix: fix2, filters: filters, now: simulatedFutureNow)
    #expect(appendedFix2)
    
    // Stop
    let lastFix = telemetry.stop()
    #expect(lastFix == nil)
    #expect(telemetry.startTime == fix1.timestamp)
    #expect(telemetry.lastTimeUpdated == fix2.timestamp)
    #expect(telemetry.distance != nil)
    if let distance = telemetry.distance {
      #expect(distance.converted(to: .meters).value > 0)
    }
    #expect(telemetry.duration?.components.seconds == Int64(durationForSecondFix))
    #expect(telemetry.lastRecordedNavigationFixMonotonicTime == nil)
    #expect(telemetry.pointsCount == 2)
    #expect(telemetry.lastRecordedNavigationFix == fix2)
    #expect(telemetry.lastReceivedNavigationFix == fix2)
  }

  @Test("Second fix ignored")
  func testSecondFixIgnored() {
    let filters = TrackFilters.default
    var telemetry = TrackSessionTelemetry()
    telemetry.start()

    // First fix.
    let fix1Timestamp: Double = 1000
    let fix1 = createNavigationFix(
      latitude: 46.16,
      longitude: -1.15,
      timestamp: Date(timeIntervalSince1970: fix1Timestamp)
    )
    let baseMonotonicTime = ContinuousClock().now
    _ = telemetry.process(fix: fix1, filters: filters, now: baseMonotonicTime)

    // Second fix.
    let durationForSecondFix = TimeInterval(10)
    let fix2 = createNavigationFix(
      latitude: 46.16,
      longitude: -1.15,
      timestamp: Date(timeIntervalSince1970: fix1Timestamp + durationForSecondFix)
    )
    let simulatedFutureNow = baseMonotonicTime.advanced(by: .seconds(10))
    let appendedFix2 = telemetry.process(fix: fix2, filters: filters, now: simulatedFutureNow)
    #expect(!appendedFix2)
    #expect(telemetry.startTime == fix1.timestamp)
    #expect(telemetry.lastTimeUpdated == fix1.timestamp)
    #expect(telemetry.distance?.value == 0)
    #expect(telemetry.duration?.components.seconds == 0)
    #expect(telemetry.lastRecordedNavigationFixMonotonicTime == baseMonotonicTime)
    #expect(telemetry.pointsCount == 1)
    #expect(telemetry.lastReceivedNavigationFix == fix2)
    #expect(telemetry.lastRecordedNavigationFix == fix1)
  }

  @Test("Stop after second fix ignored")
  func testStopAfterSecondFixIgnored() {
    let filters = TrackFilters.default
    var telemetry = TrackSessionTelemetry()
    telemetry.start()

    // First fix.
    let fix1Timestamp: Double = 1000
    let fix1 = createNavigationFix(
      latitude: 46.16,
      longitude: -1.15,
      timestamp: Date(timeIntervalSince1970: fix1Timestamp)
    )
    let baseMonotonicTime = ContinuousClock().now
    _ = telemetry.process(fix: fix1, filters: filters, now: baseMonotonicTime)

    // Second fix.
    let durationForSecondFix = TimeInterval(10)
    let fix2 = createNavigationFix(
      latitude: 46.16,
      longitude: -1.1501,
      timestamp: Date(timeIntervalSince1970: fix1Timestamp + durationForSecondFix)
    )
    let simulatedFutureNow = baseMonotonicTime.advanced(by: .seconds(10))
    let appendedFix2 = telemetry.process(fix: fix2, filters: filters, now: simulatedFutureNow)
    #expect(appendedFix2 == false)

    // Stop
    let lastFix = telemetry.stop()
    #expect(lastFix == fix2)
    #expect(telemetry.startTime == fix1.timestamp)
    #expect(telemetry.lastTimeUpdated == fix2.timestamp)
    #expect(telemetry.distance != nil)
    if let distance = telemetry.distance {
      #expect(distance.converted(to: .meters).value > 0)
    }
    #expect(telemetry.duration?.components.seconds == Int64(durationForSecondFix))
    #expect(telemetry.lastRecordedNavigationFixMonotonicTime == nil)
    #expect(telemetry.pointsCount == 2)
    #expect(telemetry.lastRecordedNavigationFix == fix2)
    #expect(telemetry.lastReceivedNavigationFix == fix2)
  }
  
  @Test("Test active duration")
  func testActiveDuration() {
    var telemetry = TrackSessionTelemetry()
    let startDate = Date()
    telemetry.start()
    
    // Step 1.
    // Add first fix after 10s from start.
    let startMonotonicTime = ContinuousClock().now
    let fix1 = createNavigationFix(
      latitude: 46.16,
      longitude: -1.15,
      timestamp: startDate + TimeInterval(10)
    )
    _ = telemetry.process(fix: fix1, filters: .default, now: startMonotonicTime)
    #expect(telemetry.duration?.components.seconds == 0)
    let activeDuration1 = telemetry.activeDuration(now: startMonotonicTime)
    #expect(activeDuration1?.components.seconds == 0)
    
    // Step 2.
    // Wait 10s after start, and ask for the duration.
    let delay2 = 10
    let simulatedFuture2 = startMonotonicTime.advanced(by: .seconds(delay2))
    #expect(telemetry.duration?.components.seconds == 0)
    let activeDurationFuture2 = telemetry.activeDuration(now: simulatedFuture2)
    #expect(activeDurationFuture2?.components.seconds == Int64(delay2))
    
    // Step 3.
    // Add second fix (valid), after 20s from the start.
    let delay3 = delay2 + 10
    let fix3 = createNavigationFix(
      latitude: 46.16,
      longitude: -2.15,
      timestamp: fix1.timestamp + TimeInterval(delay3)
    )
    let simulatedFuture3 = startMonotonicTime.advanced(by: .seconds(delay3))
    _ = telemetry.process(fix: fix3, filters: .default, now: simulatedFuture3)
    #expect(telemetry.duration?.components.seconds == Int64(delay3))
    let activeDuration3 = telemetry.activeDuration(now: simulatedFuture3)
    #expect(activeDuration3?.components.seconds == Int64(delay3))

    // Step 4.
    // Get duration 30s after the start.
    let delay4 = delay2 + 10
    let simulatedFuture4 = startMonotonicTime.advanced(by: .seconds(delay4))
    let activeDurationFuture4 = telemetry.activeDuration(now: simulatedFuture4)
    #expect(activeDurationFuture4?.components.seconds == Int64(delay4))
    
    // Add third fix (valid), after 20s from the start.
    let delay5 = delay4 + 10
    let fix5 = createNavigationFix(
      latitude: 46.16,
      longitude: -2.15,
      timestamp: fix1.timestamp + TimeInterval(delay5)
    )
    let simulatedFuture5 = startMonotonicTime.advanced(by: .seconds(delay5))
    _ = telemetry.process(fix: fix5, filters: .default, now: simulatedFuture5)
    let activeDuration5 = telemetry.activeDuration(now: simulatedFuture5)
    #expect(activeDuration5?.components.seconds == Int64(delay5))
  }

  @Test("Stop and start telemetry")
  func testStopAndStart() {
    var telemetry = TrackSessionTelemetry()
    telemetry.start()
    
    let fix = createNavigationFix(latitude: 46.16, longitude: -1.15, timestamp: Date())
    _ = telemetry.process(fix: fix, filters: .default)
    #expect(telemetry.pointsCount == 1)

    _ = telemetry.stop()
    telemetry.start()
    
    #expect(telemetry.startTime == nil)
    #expect(telemetry.lastTimeUpdated == nil)
    #expect(telemetry.distance == nil)
    #expect(telemetry.duration == nil)
    #expect(telemetry.minLatitude == nil)
    #expect(telemetry.maxLatitude == nil)
    #expect(telemetry.minLongitude == nil)
    #expect(telemetry.maxLongitude == nil)
    #expect(telemetry.maxSpeedOverGround == nil)
    #expect(telemetry.pointsCount == 0)
    #expect(telemetry.lastRecordedNavigationFix == nil)
    #expect(telemetry.lastReceivedNavigationFix == nil)
  }

  @Test("Restore telemetry")
  func testRestore() {
    var telemetry = TrackSessionTelemetry()
    let startDate = Date()
    let firstSegmentDuration = Duration.seconds(3600)
    let session = TrackSession(
      id: "test-id",
      startTime: startDate,
      duration: firstSegmentDuration,
      totalDistance: Measurement(value: 5000, unit: .meters),
      minLatitude: Measurement(value: 45.0, unit: .degrees),
      maxLatitude: Measurement(value: 46.0, unit: .degrees),
      minLongitude: Measurement(value: -1.0, unit: .degrees),
      maxLongitude: Measurement(value: 1.0, unit: .degrees),
      maxSpeed: Measurement(value: 10, unit: .metersPerSecond),
      pointsCount: 150
    )
    
    telemetry.restore(from: session)
    #expect(telemetry.startTime == session.startTime)
    #expect(telemetry.lastTimeUpdated == nil)
    #expect(telemetry.distance == session.totalDistance)
    #expect(telemetry.duration == session.duration)
    #expect(telemetry.minLatitude == session.minLatitude)
    #expect(telemetry.maxLatitude == session.maxLatitude)
    #expect(telemetry.minLongitude == session.minLongitude)
    #expect(telemetry.maxLongitude == session.maxLongitude)
    #expect(telemetry.maxSpeedOverGround == session.maxSpeed)
    #expect(telemetry.pointsCount == session.pointsCount)
    #expect(telemetry.lastReceivedNavigationFix == nil)
    #expect(telemetry.lastRecordedNavigationFix == nil)
    #expect(telemetry.lastRecordedNavigationFixMonotonicTime == nil)
    let activeDurationAfterRestore = telemetry.activeDuration()
    #expect(activeDurationAfterRestore == firstSegmentDuration)

    // Resume the track by adding first fix.
    let delay1 = 10
    let date1 = startDate + TimeInterval(firstSegmentDuration.components.seconds) + TimeInterval(delay1)
    let secondSegmentMonotonicTime = ContinuousClock().now
    let fix1 = createNavigationFix(
      latitude: 45.16,
      longitude: 0,
      timestamp: date1
    )
    _ = telemetry.process(fix: fix1, filters: .default, now: secondSegmentMonotonicTime)
    #expect(telemetry.startTime == session.startTime)
    #expect(telemetry.lastTimeUpdated == date1)
    #expect(telemetry.distance == session.totalDistance)
    #expect(telemetry.duration == session.duration)
    #expect(telemetry.minLatitude == session.minLatitude)
    #expect(telemetry.maxLatitude == session.maxLatitude)
    #expect(telemetry.minLongitude == session.minLongitude)
    #expect(telemetry.maxLongitude == session.maxLongitude)
    #expect(telemetry.maxSpeedOverGround == session.maxSpeed)
    #expect(telemetry.pointsCount == session.pointsCount! + 1)
    #expect(telemetry.lastReceivedNavigationFix == fix1)
    #expect(telemetry.lastRecordedNavigationFix == fix1)
    #expect(telemetry.lastRecordedNavigationFixMonotonicTime == secondSegmentMonotonicTime)
  }
  
  @Test("Pause and resume")
  func testPauseAndResume() {
    var telemetry = TrackSessionTelemetry()
    telemetry.start()
    
    let baseMonotonicTime = ContinuousClock().now
    let fix1 = createNavigationFix(latitude: 46.16, longitude: -1.15, timestamp: Date())
    _ = telemetry.process(fix: fix1, filters: .default, now: baseMonotonicTime)
    
    let delay2 = 10
    let simulatedFuture2 = baseMonotonicTime.advanced(by: .seconds(delay2))
    let fix2 = createNavigationFix(latitude: 46.16, longitude: -3.15, timestamp: fix1.timestamp + TimeInterval(delay2))
    _ = telemetry.process(fix: fix2, filters: .default, now: simulatedFuture2)
    
    let distance2 = telemetry.distance
    if let distance = distance2 {
      #expect(distance.converted(to: .meters).value > 0)
    }
    #expect(telemetry.duration?.components.seconds == Int64(delay2))

    telemetry.pause()
    #expect(telemetry.lastTimeUpdated == nil)
    #expect(telemetry.lastRecordedNavigationFix == nil)
    #expect(telemetry.lastReceivedNavigationFix == nil)
    #expect(telemetry.lastRecordedNavigationFixMonotonicTime == nil)
    #expect(telemetry.startTime != nil)
    #expect(telemetry.pointsCount == 2)
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
    
    telemetry.start()
    let appended = telemetry.process(fix: fix, filters: .default)
    
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
    
    telemetry.start()
    _ = telemetry.process(fix: fix1, filters: filters)
    
    let time2 = time1.addingTimeInterval(5)
    // Move precisely to Null Island
    let fix2 = createNavigationFix(latitude: 0, longitude: 0, timestamp: time2)
    
    let appended = telemetry.process(fix: fix2, filters: filters)
    
    #expect(appended)
    #expect(telemetry.pointsCount == 2)
    
    let distance = try #require(telemetry.distance)
    // 0.001 degrees of latitude is roughly 110.57 meters on the WGS 84 ellipsoid.
    #expect(distance.value > 110)
    #expect(distance.value < 112)
  }
  
  @Test("activeDuration returns baseline duration when not recording")
  func testActiveDuration_WhenNotRecording_ReturnsStaticDuration() async throws {
    // Given
    var telemetry = TrackSessionTelemetry()
    telemetry.start()
    
    // When
    // Even if some monotonic time is captured, if we are not recording,
    // it should just return the current recorded sessionDuration (which is nil or 0 at start)
    let duration = telemetry.activeDuration()
    
    // Then
    #expect(duration == nil)
  }
  
  @Test("activeDuration returns nil if session was never started (no monotonic time reference)")
  func testActiveDuration_WhenNeverStarted_ReturnsNil() async throws {
    // Given
    let telemetry = TrackSessionTelemetry() // Raw empty telemetry
    let simulatedNow = ContinuousClock().now
    
    // When
    let duration = telemetry.activeDuration(now: simulatedNow)
    
    // Then
    #expect(duration == nil)
  }
  
  @Test("activeDuration accumulates elapsed time dynamically when recording")
  func testActiveDuration_WhenRecording_AccumulatesTimeSinceLastMonotonicAnchor() async throws {
    // Given
    var telemetry = TrackSessionTelemetry()
    
    telemetry.start()
    let initialFix = makeMockFix()
    let baseMonotonicTime = ContinuousClock().now
    _ = telemetry.process(fix: initialFix, filters: .default, now: baseMonotonicTime)

    // The start() method inside telemetry internaly sets `lastRecordedNavigationFixMonotonicTime = .now`.
    // In our test context, `.now` is extremely close to our `baseMonotonicTime`.
    // We simulate that 42 seconds have passed in the future.
    let simulatedFutureNow = baseMonotonicTime.advanced(by: .seconds(42))
    
    // When
    let duration = telemetry.activeDuration(now: simulatedFutureNow)
    
    // Then
    // The expected duration should be the 42 seconds that elapsed since start()
    #expect(duration != nil)
    if let duration {
      let expectedDuration = Duration.seconds(42)
      let tolerance = Duration.milliseconds(100)
      
      #expect(duration > expectedDuration - tolerance)
      #expect(duration < expectedDuration + tolerance)
    }
  }
  
  @Test("activeDuration correctly adds elapsed time on top of already existing session duration")
  func testActiveDuration_WithPreExistingDuration_AddsElapsedTime() async throws {
    // Given
    var telemetry = TrackSessionTelemetry()
    let startTime = Date()
    
    // 1. Start the telemetry
    let baseMonotonicTime = ContinuousClock().now
    telemetry.start()
    // Always call updateTime() with the first fix.
    _ = telemetry.process(fix: makeMockFix(at: startTime), filters: .default, now: baseMonotonicTime)

    // 2. Simulate a GPS fix update 10 seconds later.
    // This will push 10 seconds into `sessionDuration`
    let simulatedFutureNow1 = baseMonotonicTime.advanced(by: .seconds(10))
    let tenSecondsLater = startTime.addingTimeInterval(10)
    _ = telemetry.process(fix: makeMockFix(at: tenSecondsLater), filters: .default, now: simulatedFutureNow1)
    
    // 4. Simulate moving 5 seconds further into the future from that anchor point
    let simulatedFutureNow2 = simulatedFutureNow1.advanced(by: .seconds(5))
    
    // When
    let totalDuration = telemetry.activeDuration(now: simulatedFutureNow2)
    
    // Then
    // Expected: 10 seconds (from the updateTime fix) + 5 seconds (virtual elapsed time) = 15 seconds
    #expect(totalDuration != nil)
    if let totalDuration {
      #expect(totalDuration >= .seconds(15))
      #expect(totalDuration < .seconds(16))
    }
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
  
  // Mock NavigationFix helper to clean up test setup
    private func makeMockFix(at date: Date = Date()) -> NavigationFix {
      return NavigationFix(
        coordinate: CLLocationCoordinate2D(latitude: 46.15, longitude: -1.15), // Near La Rochelle
        horizontalAccuracy: Measurement(value: 5.0, unit: .meters),
        courseOverGround: nil,
        courseOverGroundAccuracy: nil,
        speedOverGround: nil,
        speedOverGroundAccuracy: nil,
        timestamp: date
      )
    }
}

//
//  CoreLocationPositioningServiceTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-22.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Testing
import Foundation
import CoreLocation
@testable import Sillage

@MainActor
struct CoreLocationPositioningServiceTests {

  @Test("CoreLocationPositioningService initializes with default pausesLocationUpdatesAutomatically")
  func testDefaultPausesLocationUpdatesAutomatically() {
    let service = CoreLocationPositioningService(initialAccuracyMode: .best)
    #expect(service.pausesLocationUpdatesAutomatically == false)
  }

  @Test("CoreLocationPositioningService initializes and updates pausesLocationUpdatesAutomatically")
  func testCoreLocationPositioningServicePausesUpdates() {
    let service = CoreLocationPositioningService(
      initialAccuracyMode: .best,
      initialPausesLocationUpdatesAutomatically: true
    )
    #expect(service.pausesLocationUpdatesAutomatically == true)

    service.setPausesLocationUpdatesAutomatically(false)
    #expect(service.pausesLocationUpdatesAutomatically == false)

    service.setPausesLocationUpdatesAutomatically(true)
    #expect(service.pausesLocationUpdatesAutomatically == true)
  }

  @Test("CoreLocationPositioningService activityType is configured according to iOS version")
  func testActivityTypeAccordingToIOSVersion() {
    let service = CoreLocationPositioningService(initialAccuracyMode: .best)
    if #available(iOS 27.0, *) {
      #expect(service.activityType == .maritime)
    } else {
      #expect(service.activityType == .otherNavigation)
    }
  }

  @Test("Sentinel -1 speed does not leak when speedAccuracy is non-negative")
  func testNegativeSpeedSentinelMappedToNil() async {
    let service = CoreLocationPositioningService(initialAccuracyMode: .best)
    var iterator = service.locationUpdates.makeAsyncIterator()

    let location = makeLocation(
      horizontalAccuracy: 5.0,
      course: 120.0,
      courseAccuracy: 4.0,
      speed: -1.0,
      speedAccuracy: 0.5
    )
    service.processLocation(location)

    let state = await iterator.next()
    guard case .active(let fix) = state else {
      Issue.record("Expected .active state, got \(String(describing: state))")
      return
    }
    #expect(fix.speedOverGround == nil)
    #expect(fix.speedOverGroundAccuracy == nil)
    #expect(fix.courseOverGround == Measurement(value: 120.0, unit: .degrees))
    #expect(fix.courseOverGroundAccuracy == Measurement(value: 4.0, unit: .degrees))
  }

  @Test("Valid speed with negative speedAccuracy maps both to nil")
  func testNegativeSpeedAccuracyCouplesBothToNil() async {
    let service = CoreLocationPositioningService(initialAccuracyMode: .best)
    var iterator = service.locationUpdates.makeAsyncIterator()

    let location = makeLocation(
      horizontalAccuracy: 5.0,
      course: 120.0,
      courseAccuracy: 4.0,
      speed: 3.5,
      speedAccuracy: -1.0
    )
    service.processLocation(location)

    let state = await iterator.next()
    guard case .active(let fix) = state else {
      Issue.record("Expected .active state, got \(String(describing: state))")
      return
    }
    #expect(fix.speedOverGround == nil)
    #expect(fix.speedOverGroundAccuracy == nil)
  }

  @Test("Course and courseOverGroundAccuracy are strictly coupled (both valid or none)")
  func testCourseAndCourseAccuracyCoupling() async {
    let service = CoreLocationPositioningService(initialAccuracyMode: .best)
    var iterator = service.locationUpdates.makeAsyncIterator()

    // Invalid course (-1.0) with non-negative courseAccuracy must yield nil for BOTH
    service.processLocation(makeLocation(
      horizontalAccuracy: 8.0,
      course: -1.0,
      courseAccuracy: 6.0,
      speed: 2.0,
      speedAccuracy: 0.2
    ))
    guard case .active(let fixInvalidCourse) = await iterator.next() else {
      Issue.record("Expected .active state for fixInvalidCourse")
      return
    }
    #expect(fixInvalidCourse.courseOverGround == nil)
    #expect(fixInvalidCourse.courseOverGroundAccuracy == nil)

    // Valid course with invalid courseAccuracy (-1.0) must yield nil for BOTH
    service.processLocation(makeLocation(
      horizontalAccuracy: 8.0,
      course: 90.0,
      courseAccuracy: -1.0,
      speed: 2.0,
      speedAccuracy: 0.2
    ))
    guard case .active(let fixInvalidAccuracy) = await iterator.next() else {
      Issue.record("Expected .active state for fixInvalidAccuracy")
      return
    }
    #expect(fixInvalidAccuracy.courseOverGround == nil)
    #expect(fixInvalidAccuracy.courseOverGroundAccuracy == nil)

    // Boundary course 360.0 normalizes to 0.0 to satisfy < 360 invariant
    service.processLocation(makeLocation(
      horizontalAccuracy: 8.0,
      course: 360.0,
      courseAccuracy: 3.0,
      speed: 2.0,
      speedAccuracy: 0.2
    ))
    guard case .active(let fixNormalized) = await iterator.next() else {
      Issue.record("Expected .active state for fixNormalized")
      return
    }
    #expect(fixNormalized.courseOverGround == Measurement(value: 0.0, unit: .degrees))
    #expect(fixNormalized.courseOverGroundAccuracy == Measurement(value: 3.0, unit: .degrees))
  }

  @Test("Degraded accuracy (> 50m) emits .degraded; transient invalid fixes are dropped without emitting .lost")
  func testDegradedAndInvalidLocationStates() async {
    let service = CoreLocationPositioningService(initialAccuracyMode: .best)
    var iterator = service.locationUpdates.makeAsyncIterator()

    // 1. Degraded (> 50m)
    service.processLocation(makeLocation(horizontalAccuracy: 51.0))
    guard case .degraded(let degradedFix) = await iterator.next() else {
      Issue.record("Expected .degraded state")
      return
    }
    #expect(degradedFix.horizontalAccuracy == Measurement(value: 51.0, unit: .meters))
    #expect(service.lastKnownLocation == degradedFix)

    // 2. Negative/non-finite horizontalAccuracy and invalid coordinate are dropped without emitting .lost
    service.processLocation(makeLocation(horizontalAccuracy: -1.0))
    service.processLocation(makeLocation(horizontalAccuracy: .nan))
    let invalidCoordLocation = CLLocation(
      coordinate: kCLLocationCoordinate2DInvalid,
      altitude: 0,
      horizontalAccuracy: 10.0,
      verticalAccuracy: -1.0,
      course: -1.0,
      courseAccuracy: -1.0,
      speed: -1.0,
      speedAccuracy: -1.0,
      timestamp: Date(timeIntervalSince1970: 1_700_000_010)
    )
    service.processLocation(invalidCoordLocation)
    #expect(service.lastKnownLocation == degradedFix)

    // 3. The very next stream event must be the subsequent valid fix (proving no .lost was emitted)
    let followUpTime = Date(timeIntervalSince1970: 1_700_000_020)
    service.processLocation(makeLocation(horizontalAccuracy: 8.0, timestamp: followUpTime))
    guard case .active(let followUpFix) = await iterator.next() else {
      Issue.record("Expected .active follow-up fix with no intervening .lost state")
      return
    }
    #expect(followUpFix.timestamp == followUpTime)
    #expect(service.lastKnownLocation == followUpFix)
  }

  @Test("System didFailWithError emits .lost to subscribers")
  func testDelegateDidFailWithErrorEmitsLost() async {
    let service = CoreLocationPositioningService(initialAccuracyMode: .best)
    var iterator = service.locationUpdates.makeAsyncIterator()

    service.locationManager(CLLocationManager(), didFailWithError: CLError(.locationUnknown))

    guard case .lost(let error) = await iterator.next() else {
      Issue.record("Expected .lost state when didFailWithError is called")
      return
    }
    #expect((error as? CLError)?.code == .locationUnknown)
  }

  @Test("Delegate didUpdateLocations funnels chronological fixes through single CLLocationManager stream")
  func testDelegateDidUpdateLocationsFunnel() async {
    let service = CoreLocationPositioningService(initialAccuracyMode: .best)
    var iterator = service.locationUpdates.makeAsyncIterator()

    let t1 = Date(timeIntervalSince1970: 1_700_000_001)
    let t2 = Date(timeIntervalSince1970: 1_700_000_002)
    let loc1 = makeLocation(latitude: 48.1, longitude: -4.1, horizontalAccuracy: 6.0, speed: 3.0, speedAccuracy: 0.1, timestamp: t1)
    let loc2 = makeLocation(latitude: 48.2, longitude: -4.2, horizontalAccuracy: 7.0, speed: 4.0, speedAccuracy: 0.1, timestamp: t2)

    service.locationManager(CLLocationManager(), didUpdateLocations: [loc1, loc2])

    guard case .active(let first) = await iterator.next(),
          case .active(let second) = await iterator.next() else {
      Issue.record("Expected two sequential .active fixes from didUpdateLocations funnel")
      return
    }
    #expect(first.timestamp == t1)
    #expect(first.coordinate.latitude == 48.1)
    #expect(second.timestamp == t2)
    #expect(second.coordinate.latitude == 48.2)
  }

  @Test("Background tokens dynamically manage allowsBackgroundLocationUpdates and showsBackgroundLocationIndicator")
  func testBackgroundTokensConfigureLocationManager() async throws {
    let service = CoreLocationPositioningService(initialAccuracyMode: .best)

    #expect(service.allowsBackgroundLocationUpdates == false)
    #expect(service.showsBackgroundLocationIndicator == false)

    let token1 = service.requestBackgroundLocation()
    let token2 = service.requestBackgroundLocation()
    #expect(service.allowsBackgroundLocationUpdates == true)
    #expect(service.showsBackgroundLocationIndicator == true)

    token1.invalidate()
    #expect(service.allowsBackgroundLocationUpdates == true)
    #expect(service.showsBackgroundLocationIndicator == true)

    token2.invalidate()
    #expect(service.allowsBackgroundLocationUpdates == false)
    #expect(service.showsBackgroundLocationIndicator == false)

    // Verify RAII fallback cleanup on deinit when invalidate() is not explicitly called
    withExtendedLifetime(service.requestBackgroundLocation()) {
      #expect(service.allowsBackgroundLocationUpdates == true)
      #expect(service.showsBackgroundLocationIndicator == true)
    }
    try await waitUntil {
      !service.allowsBackgroundLocationUpdates && !service.showsBackgroundLocationIndicator
    }
    #expect(service.allowsBackgroundLocationUpdates == false)
    #expect(service.showsBackgroundLocationIndicator == false)
  }

  @Test("Distance filter arbitration and desiredAccuracy update underlying CLLocationManager")
  func testDistanceFilterAndDesiredAccuracy() {
    let service = CoreLocationPositioningService(initialAccuracyMode: .bestForNavigation)
    #expect(service.desiredAccuracy == kCLLocationAccuracyBestForNavigation)
    #expect(service.currentDistanceFilter == Measurement(value: 10.0, unit: .meters))

    service.setDesiredAccuracy(.hundredMeters)
    #expect(service.desiredAccuracy == kCLLocationAccuracyHundredMeters)

    // Invalid <= 0m filter is ignored
    service.requestDistanceFilter(Measurement(value: 0, unit: .meters), for: "Invalid")
    #expect(service.currentDistanceFilter == Measurement(value: 10.0, unit: .meters))

    service.requestDistanceFilter(Measurement(value: 5.0, unit: .meters), for: "TrackRecording")
    #expect(service.currentDistanceFilter == Measurement(value: 5.0, unit: .meters))

    service.requestDistanceFilter(Measurement(value: 1.0, unit: .meters), for: "AnchorWatch")
    #expect(service.currentDistanceFilter == Measurement(value: 1.0, unit: .meters))

    service.removeDistanceFilter(for: "AnchorWatch")
    #expect(service.currentDistanceFilter == Measurement(value: 5.0, unit: .meters))

    service.removeDistanceFilter(for: "TrackRecording")
    #expect(service.currentDistanceFilter == Measurement(value: 10.0, unit: .meters))
  }

  // MARK: - Helpers

  private func makeLocation(
    latitude: CLLocationDegrees = 48.3904,
    longitude: CLLocationDegrees = -4.4861,
    horizontalAccuracy: CLLocationAccuracy = 5.0,
    course: CLLocationDirection = 180.0,
    courseAccuracy: CLLocationDirectionAccuracy = 5.0,
    speed: CLLocationSpeed = 2.5,
    speedAccuracy: CLLocationSpeedAccuracy = 0.2,
    timestamp: Date = Date(timeIntervalSince1970: 1_700_000_000)
  ) -> CLLocation {
    CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
      altitude: 0,
      horizontalAccuracy: horizontalAccuracy,
      verticalAccuracy: -1.0,
      course: course,
      courseAccuracy: courseAccuracy,
      speed: speed,
      speedAccuracy: speedAccuracy,
      timestamp: timestamp
    )
  }
}

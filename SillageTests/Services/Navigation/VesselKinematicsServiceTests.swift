//
//  VesselKinematicsServiceTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-19.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Testing
import Foundation
import CoreLocation
@testable import Sillage

@MainActor
struct VesselKinematicsServiceTests {

  private final class MockPositioningService: PositioningService, @unchecked Sendable {
    var currentAuthorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    var authorizationStatusStream: AsyncStream<CLAuthorizationStatus> { AsyncStream { _ in } }
    var currentDistanceFilter: Measurement<UnitLength> = Measurement(value: 5.0, unit: .meters)

    let continuation: AsyncStream<PositioningState>.Continuation
    let locationUpdates: AsyncStream<PositioningState>
    var lastKnownLocation: NavigationFix?

    private final class MockLocationUpdateToken: LocationUpdateToken {
      let onInvalidate: () -> Void
      init(onInvalidate: @escaping () -> Void) {
        self.onInvalidate = onInvalidate
      }
      func invalidate() {
        onInvalidate()
      }
    }

    private final class MockBackgroundToken: BackgroundLocationToken {
      func invalidate() {}
    }

    var requestLocationUpdatesCallCount = 0
    var tokenInvalidateCallCount = 0

    init() {
      let (stream, cont) = AsyncStream<PositioningState>.makeStream()
      self.locationUpdates = stream
      self.continuation = cont
    }

    func requestAuthorization() {}
    func requestLocationUpdates() -> any LocationUpdateToken {
      requestLocationUpdatesCallCount += 1
      return MockLocationUpdateToken { [weak self] in
        self?.tokenInvalidateCallCount += 1
      }
    }
    func requestBackgroundLocation() -> any BackgroundLocationToken { MockBackgroundToken() }
    func requestDistanceFilter(_ distance: Measurement<UnitLength>, for identifier: String) {}
    func removeDistanceFilter(for identifier: String) {}
  }

  private func makeTestDefaults() -> UserDefaults {
    let suite = "test.kinematics.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
  }

  @Test("Lifecycle: Acquires and releases upstream token")
  func testLifecycleTokens() async {
    let mockPositioning = MockPositioningService()
    let developerSettings = DeveloperSettingsService(defaults: makeTestDefaults())
    let service = VesselKinematicsService(
      positioningService: mockPositioning,
      developerSettingsService: developerSettings
    )

    #expect(mockPositioning.requestLocationUpdatesCallCount == 0)

    let token = service.requestLocationUpdates()
    #expect(mockPositioning.requestLocationUpdatesCallCount == 1)

    token.invalidate()
    #expect(mockPositioning.tokenInvalidateCallCount == 1)
  }

  @Test("iOS Mode: Preserves native iOS course and speed")
  func testIOSModePreservesNativeValues() async throws {
    let mockPositioning = MockPositioningService()
    let defaults = makeTestDefaults()
    let developerSettings = DeveloperSettingsService(defaults: defaults)
    developerSettings.cogSogCalculationSource = .iOS

    let service = VesselKinematicsService(
      positioningService: mockPositioning,
      developerSettingsService: developerSettings
    )

    let token = service.requestLocationUpdates()
    defer { token.invalidate() }

    var iterator = service.locationUpdates.makeAsyncIterator()

    let rawFix = NavigationFix(
      coordinate: CLLocationCoordinate2D(latitude: 46.15, longitude: -1.15),
      horizontalAccuracy: Measurement(value: 5.0, unit: .meters),
      courseOverGround: Measurement(value: 123.0, unit: .degrees),
      courseOverGroundAccuracy: Measurement(value: 2.0, unit: .degrees),
      speedOverGround: Measurement(value: 8.5, unit: .knots),
      speedOverGroundAccuracy: Measurement(value: 0.5, unit: .knots),
      timestamp: Date()
    )

    mockPositioning.continuation.yield(.active(rawFix))

    let received = await iterator.next()
    guard case .active(let fix) = received else {
      Issue.record("Expected active fix")
      return
    }

    #expect(fix.courseOverGround?.value == 123.0)
    #expect(fix.speedOverGround?.value == 8.5)
  }

  @Test("Sillage Mode: Computes COG and SOG strictly from positions, ignoring raw values")
  func testSillageModeComputesVelocityFromPositions() async throws {
    let mockPositioning = MockPositioningService()
    let defaults = makeTestDefaults()
    let developerSettings = DeveloperSettingsService(defaults: defaults)
    developerSettings.cogSogCalculationSource = .sillage

    let service = VesselKinematicsService(
      positioningService: mockPositioning,
      developerSettingsService: developerSettings
    )

    let token = service.requestLocationUpdates()
    defer { token.invalidate() }

    var iterator = service.locationUpdates.makeAsyncIterator()
    let t0 = Date()

    // Fix 1: baseline
    let fix1 = NavigationFix(
      coordinate: CLLocationCoordinate2D(latitude: 46.0, longitude: -1.0),
      horizontalAccuracy: Measurement(value: 3.0, unit: .meters),
      courseOverGround: Measurement(value: 999.0, unit: .degrees), // Bogus iOS value
      courseOverGroundAccuracy: nil,
      speedOverGround: Measurement(value: 999.0, unit: .knots), // Bogus iOS value
      speedOverGroundAccuracy: nil,
      timestamp: t0
    )
    mockPositioning.continuation.yield(.active(fix1))
    let firstState = await iterator.next()
    guard case .active(let outFix1) = firstState else {
      Issue.record("Expected active fix1")
      return
    }
    // First fix has no delta yet
    #expect(outFix1.courseOverGround == nil)
    #expect(outFix1.speedOverGround == nil)

    // Fix 2: Moved ~11.1 meters North in 1 second (~21.6 kn, bearing ~0°)
    let dLatDeg = 11.1 / 111195.0
    let fix2 = NavigationFix(
      coordinate: CLLocationCoordinate2D(latitude: 46.0 + dLatDeg, longitude: -1.0),
      horizontalAccuracy: Measurement(value: 3.0, unit: .meters),
      courseOverGround: Measurement(value: 888.0, unit: .degrees), // Bogus iOS value
      courseOverGroundAccuracy: nil,
      speedOverGround: Measurement(value: 888.0, unit: .knots), // Bogus iOS value
      speedOverGroundAccuracy: nil,
      timestamp: t0.addingTimeInterval(1.0)
    )
    mockPositioning.continuation.yield(.active(fix2))
    let secondState = await iterator.next()
    guard case .active(let outFix2) = secondState else {
      Issue.record("Expected active fix2")
      return
    }

    // Velocity must be computed, NOT using bogus iOS 888.0 values!
    #expect(outFix2.courseOverGround != nil)
    #expect(outFix2.speedOverGround != nil)
    if let cog = outFix2.courseOverGround {
      let deg = cog.converted(to: .degrees).value
      #expect(abs(deg - 0.0) < 1.5 || abs(deg - 360.0) < 1.5)
    }
    if let sog = outFix2.speedOverGround {
      let mps = sog.converted(to: .metersPerSecond).value
      #expect(abs(mps - 11.1) < 0.5)
    }
  }

  @Test("Runtime switch between Sillage and iOS mode")
  func testRuntimeSwitching() async throws {
    let mockPositioning = MockPositioningService()
    let defaults = makeTestDefaults()
    let developerSettings = DeveloperSettingsService(defaults: defaults)
    developerSettings.cogSogCalculationSource = .iOS

    let service = VesselKinematicsService(
      positioningService: mockPositioning,
      developerSettingsService: developerSettings
    )

    let token = service.requestLocationUpdates()
    defer { token.invalidate() }

    var iterator = service.locationUpdates.makeAsyncIterator()

    // 1. Emit fix in iOS mode
    let iosFix = NavigationFix(
      coordinate: CLLocationCoordinate2D(latitude: 46.0, longitude: -1.0),
      horizontalAccuracy: Measurement(value: 3.0, unit: .meters),
      courseOverGround: Measurement(value: 42.0, unit: .degrees),
      courseOverGroundAccuracy: nil,
      speedOverGround: Measurement(value: 5.0, unit: .knots),
      speedOverGroundAccuracy: nil,
      timestamp: Date()
    )
    mockPositioning.continuation.yield(.active(iosFix))
    let received1 = await iterator.next()
    guard case .active(let out1) = received1 else {
      Issue.record("Expected active out1")
      return
    }
    #expect(out1.courseOverGround?.value == 42.0)

    // 2. Switch to Sillage mode
    developerSettings.cogSogCalculationSource = .sillage

    let sillageFix1 = NavigationFix(
      coordinate: CLLocationCoordinate2D(latitude: 46.0, longitude: -1.0),
      horizontalAccuracy: Measurement(value: 3.0, unit: .meters),
      courseOverGround: Measurement(value: 42.0, unit: .degrees),
      courseOverGroundAccuracy: nil,
      speedOverGround: Measurement(value: 5.0, unit: .knots),
      speedOverGroundAccuracy: nil,
      timestamp: Date().addingTimeInterval(10)
    )
    mockPositioning.continuation.yield(.active(sillageFix1))
    let received2 = await iterator.next()
    guard case .active(let out2) = received2 else {
      Issue.record("Expected active out2")
      return
    }
    // After switch, buffer was reset so first fix has nil velocity
    #expect(out2.courseOverGround == nil)
  }
}

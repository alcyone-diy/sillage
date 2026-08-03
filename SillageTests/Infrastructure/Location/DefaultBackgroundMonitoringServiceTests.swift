//
//  DefaultBackgroundMonitoringServiceTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CoreLocation
import os
@testable import Sillage

@MainActor
final class DefaultBackgroundMonitoringServiceTests: XCTestCase {
  
  final class MockNotificationService: NotificationService, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    var checkInCallCount = 0
    var cancelWatchdogCallCount = 0
    
    func sendNotification(title: String, body: String, identifier: String, delay: TimeInterval?) async throws {}
    func sendCriticalNotification(title: String, body: String, identifier: String) async {}
    func clearAllNotifications() {}
    func cancelNotification(identifier: String) {}
    
    func checkIn(identifier: String, title: String, body: String, timeout: TimeInterval) async {
      lock.withLock { checkInCallCount += 1 }
    }
    
    func cancelWatchdog(identifier: String) async {
      lock.withLock { cancelWatchdogCallCount += 1 }
    }
  }
  
  private final class MockLocationUpdateToken: LocationUpdateToken {
    var invalidateCallCount = 0
    func invalidate() { invalidateCallCount += 1 }
  }
  
  private final class MockBackgroundLocationToken: BackgroundLocationToken {
    var invalidateCallCount = 0
    func invalidate() { invalidateCallCount += 1 }
  }
  
  private final class MockPositioningService: PositioningService {
    var currentAuthorizationStatus: CLAuthorizationStatus = .authorizedAlways
    var locationContinuation: AsyncStream<PositioningState>.Continuation!
    var locationUpdates: AsyncStream<PositioningState>
    var authorizationStatusStream: AsyncStream<CLAuthorizationStatus>
    var currentDistanceFilter: Measurement<UnitLength> = Measurement(value: 10, unit: .meters)
    var lastKnownLocation: NavigationFix?
    
    var requestLocationUpdatesCallCount = 0
    var requestBackgroundLocationCallCount = 0
    var lastUpdateToken: MockLocationUpdateToken?
    var lastBackgroundToken: MockBackgroundLocationToken?
    
    init() {
      let (locStream, locCont) = AsyncStream.makeStream(of: PositioningState.self)
      self.locationUpdates = locStream
      self.locationContinuation = locCont
      
      let (authStream, _) = AsyncStream.makeStream(of: CLAuthorizationStatus.self)
      self.authorizationStatusStream = authStream
    }
    
    func requestAuthorization() {}
    func requestDistanceFilter(_ distance: Measurement<UnitLength>, for identifier: String) {}
    func removeDistanceFilter(for identifier: String) {}
    
    func requestBackgroundLocation() -> any BackgroundLocationToken {
      requestBackgroundLocationCallCount += 1
      let token = MockBackgroundLocationToken()
      lastBackgroundToken = token
      return token
    }
    
    func requestLocationUpdates() -> any LocationUpdateToken {
      requestLocationUpdatesCallCount += 1
      let token = MockLocationUpdateToken()
      lastUpdateToken = token
      return token
    }
  }
  
  func testStartMonitoring_requestsTokensAndSchedulesGPSLoop() async throws {
    let mockPositioning = MockPositioningService()
    let mockNotification = MockNotificationService()
    let service = DefaultBackgroundMonitoringService(positioningService: mockPositioning, notificationService: mockNotification)
    
    let watchdog = WatchdogConfiguration(identifier: "testWatchdog", title: "Test", body: "Test body", timeout: 300)
    
    // Act
    let token = service.startMonitoring(ownerIdentifier: "test", distanceFilter: Measurement(value: 1, unit: .meters), watchdog: watchdog)
    
    // Assert
    XCTAssertEqual(mockPositioning.requestBackgroundLocationCallCount, 1)
    XCTAssertEqual(mockPositioning.requestLocationUpdatesCallCount, 1)
    XCTAssertNotNil(token)
    
    // Invalidate
    token.invalidate()
    
    // Wait for the async task inside invalidateToken to finish
    try await Task.sleep(nanoseconds: 500_000_000)
    
    // Assert Cleanup
    XCTAssertEqual(mockPositioning.lastBackgroundToken?.invalidateCallCount, 1)
    XCTAssertEqual(mockPositioning.lastUpdateToken?.invalidateCallCount, 1)
    
    let cancelCount = mockNotification.cancelWatchdogCallCount
    XCTAssertEqual(cancelCount, 1)
  }
  
  func testGPSUpdate_pingsWatchdogs() async throws {
    let mockPositioning = MockPositioningService()
    let mockNotification = MockNotificationService()
    let service = DefaultBackgroundMonitoringService(positioningService: mockPositioning, notificationService: mockNotification)
    
    let watchdog = WatchdogConfiguration(identifier: "testWatchdog", title: "Test", body: "Test body", timeout: 300)
    
    // Start monitoring so it hooks up to locationUpdates
    let token = service.startMonitoring(ownerIdentifier: "test", distanceFilter: Measurement(value: 1, unit: .meters), watchdog: watchdog)
    
    // Yield a fix
    let fix = NavigationFix(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), horizontalAccuracy: Measurement(value: 1, unit: .meters), courseOverGround: nil, courseOverGroundAccuracy: nil, speedOverGround: nil, speedOverGroundAccuracy: nil, timestamp: Date())
    mockPositioning.locationContinuation.yield(.active(fix))
    
    // Wait for internal async loops
    try await Task.sleep(nanoseconds: 500_000_000)
    
    // Assert
    let checkInCount = mockNotification.checkInCallCount
    XCTAssertEqual(checkInCount, 1)
    
    _ = token
  }
}

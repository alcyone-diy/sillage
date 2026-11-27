//
//  AnchorSwingTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-08.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CoreLocation
import os
@testable import Sillage

@MainActor
final class AnchorSwingTests: XCTestCase {

  func testAnchorWatch_appendsSwingPoint_andPurgesOlderThan24Hours() {
    let now = Date()
    let oldDate = now.addingTimeInterval(-25 * 3600) // 25 hours ago
    let recentDate = now.addingTimeInterval(-10 * 3600) // 10 hours ago

    let pointOld = AnchorSwingPoint(latitude: 47.2, longitude: -1.5, timestamp: oldDate)
    let pointRecent = AnchorSwingPoint(latitude: 47.2001, longitude: -1.5001, timestamp: recentDate)

    var watch = AnchorWatch(
      coordinate: CLLocationCoordinate2D(latitude: 47.2, longitude: -1.5),
      radius: Measurement(value: 30, unit: .meters),
      swingHistory: [pointOld, pointRecent]
    )

    let newPoint = AnchorSwingPoint(latitude: 47.2002, longitude: -1.5002, timestamp: now)
    watch.appendSwingPoint(newPoint)

    // pointOld (25h ago) must be purged, keeping pointRecent and newPoint
    XCTAssertEqual(watch.swingHistory.count, 2)
    XCTAssertEqual(watch.swingHistory.first?.timestamp, recentDate)
    XCTAssertEqual(watch.swingHistory.last?.timestamp, now)
  }

  func testAnchorWatch_boundsCapacityToMaxPoints() {
    let now = Date()
    var watch = AnchorWatch(
      coordinate: CLLocationCoordinate2D(latitude: 47.2, longitude: -1.5),
      radius: Measurement(value: 30, unit: .meters)
    )

    // Append 1050 points
    for i in 0..<1050 {
      let pt = AnchorSwingPoint(
        latitude: 47.2 + Double(i) * 0.0001,
        longitude: -1.5,
        timestamp: now.addingTimeInterval(Double(i))
      )
      watch.appendSwingPoint(pt, maxAge: 24 * 3600, maxPoints: 1000)
    }

    XCTAssertEqual(watch.swingHistory.count, 1000)
  }

  func testAnchorStateStore_persistsAndRestoresSwingHistory() throws {
    let now = Date()
    let pt1 = AnchorSwingPoint(latitude: 47.218, longitude: -1.553, timestamp: now)
    let pt2 = AnchorSwingPoint(latitude: 47.219, longitude: -1.554, timestamp: now.addingTimeInterval(30))

    let watch = AnchorWatch(
      coordinate: CLLocationCoordinate2D(latitude: 47.218, longitude: -1.553),
      radius: Measurement(value: 40, unit: .meters),
      swingHistory: [pt1, pt2]
    )
    let session = AnchorSessionData(activeWatch: watch, status: .armed, triggerReason: nil)

    let encoder = JSONEncoder()
    let data = try encoder.encode(session)

    let decoder = JSONDecoder()
    let restoredSession = try decoder.decode(AnchorSessionData.self, from: data)

    XCTAssertEqual(restoredSession.status, .armed)
    XCTAssertEqual(restoredSession.activeWatch?.swingHistory.count, 2)
    XCTAssertEqual(restoredSession.activeWatch?.swingHistory.first?.coordinate.latitude, 47.218)
    XCTAssertEqual(restoredSession.activeWatch?.swingHistory.last?.coordinate.latitude, 47.219)
  }

  func testAnchorWatch_decodesLegacyEvitementHistoryJSONKey() throws {
    // Verify backwards compatibility with persisted sessions written before the `evitementHistory` -> `swingHistory` rename.
    let legacyJSON = """
    {
      "coordinate": { "latitude": 47.218, "longitude": -1.553 },
      "radius": { "value": 35.0, "unit": { "symbol": "m", "converter": { "coefficient": 1.0, "constant": 0.0 } } },
      "createdAt": 1000000,
      "evitementHistory": [
        { "storedCoordinate": { "latitude": 47.2181, "longitude": -1.5531 }, "timestamp": 1000010 }
      ]
    }
    """
    let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
    let decoded = try JSONDecoder().decode(AnchorWatch.self, from: data)

    XCTAssertEqual(decoded.swingHistory.count, 1)
    XCTAssertEqual(decoded.swingHistory.first?.coordinate.latitude, 47.2181)
  }

  func testDisarm_flushesStateToDiskDeterministically() async throws {
    let mockStore = SwingMockStateStore()
    let positioningService = MockPositioningService()
    let preferencesService = MockPreferencesService()
    let notificationService = LocalNotificationService()
    let permissionService = MockPermissionService()
    let backgroundMonitoringService = MockBackgroundMonitoringService()

    let service = AnchorService(
      positioningService: positioningService,
      preferencesService: preferencesService,
      notificationService: notificationService,
      permissionService: permissionService,
      backgroundMonitoringService: backgroundMonitoringService,
      stateStore: mockStore
    )

    let coord = CLLocationCoordinate2D(latitude: 47.218371, longitude: -1.553621)
    service.arm(coordinate: coord, radius: Measurement(value: 30, unit: UnitLength.meters))
    XCTAssertEqual(mockStore.savedSession?.status, .armed)

    // Disarm watch must flush state immediately and deterministically to disk
    service.disarm()
    XCTAssertEqual(mockStore.savedSession?.status, .dropped)
  }
}

// MARK: - Test Mocks

private final class SwingMockStateStore: AnchorStateStoreProtocol, Sendable {
  private let sessionLock = OSAllocatedUnfairLock(initialState: AnchorSessionData())

  var savedSession: AnchorSessionData? {
    sessionLock.withLock { $0 }
  }

  func loadSession() -> AnchorSessionData {
    sessionLock.withLock { $0 }
  }

  func saveSession(_ session: AnchorSessionData) {
    sessionLock.withLock { $0 = session }
  }
}

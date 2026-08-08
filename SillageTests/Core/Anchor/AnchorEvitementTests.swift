//
//  AnchorEvitementTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-08.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CoreLocation
@testable import Sillage

@MainActor
final class AnchorEvitementTests: XCTestCase {
  
  func testAnchorWatch_appendsEvitementPoint_andPurgesOlderThan24Hours() {
    let now = Date()
    let oldDate = now.addingTimeInterval(-25 * 3600) // 25 hours ago
    let recentDate = now.addingTimeInterval(-10 * 3600) // 10 hours ago
    
    let pointOld = AnchorEvitementPoint(latitude: 47.2, longitude: -1.5, timestamp: oldDate)
    let pointRecent = AnchorEvitementPoint(latitude: 47.2001, longitude: -1.5001, timestamp: recentDate)
    
    var watch = AnchorWatch(
      coordinate: CLLocationCoordinate2D(latitude: 47.2, longitude: -1.5),
      radius: Measurement(value: 30, unit: .meters),
      evitementHistory: [pointOld, pointRecent]
    )
    
    let newPoint = AnchorEvitementPoint(latitude: 47.2002, longitude: -1.5002, timestamp: now)
    watch.appendEvitementPoint(newPoint)
    
    // pointOld (25h ago) must be purged, keeping pointRecent and newPoint
    XCTAssertEqual(watch.evitementHistory.count, 2)
    XCTAssertEqual(watch.evitementHistory.first?.timestamp, recentDate)
    XCTAssertEqual(watch.evitementHistory.last?.timestamp, now)
  }
  
  func testAnchorWatch_boundsCapacityToMaxPoints() {
    let now = Date()
    var watch = AnchorWatch(
      coordinate: CLLocationCoordinate2D(latitude: 47.2, longitude: -1.5),
      radius: Measurement(value: 30, unit: .meters)
    )
    
    // Append 1050 points
    for i in 0..<1050 {
      let pt = AnchorEvitementPoint(
        latitude: 47.2 + Double(i) * 0.0001,
        longitude: -1.5,
        timestamp: now.addingTimeInterval(Double(i))
      )
      watch.appendEvitementPoint(pt, maxAge: 24 * 3600, maxPoints: 1000)
    }
    
    XCTAssertEqual(watch.evitementHistory.count, 1000)
  }

  func testAnchorStateStore_persistsAndRestoresEvitementHistory() throws {
    let fileManager = FileManager.default
    let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: tempDir) }
    
    let now = Date()
    let pt1 = AnchorEvitementPoint(latitude: 47.218, longitude: -1.553, timestamp: now)
    let pt2 = AnchorEvitementPoint(latitude: 47.219, longitude: -1.554, timestamp: now.addingTimeInterval(30))
    
    let watch = AnchorWatch(
      coordinate: CLLocationCoordinate2D(latitude: 47.218, longitude: -1.553),
      radius: Measurement(value: 40, unit: .meters),
      evitementHistory: [pt1, pt2]
    )
    let session = AnchorSessionData(activeWatch: watch, status: .armed, triggerReason: nil)
    
    let encoder = JSONEncoder()
    let data = try encoder.encode(session)
    
    let decoder = JSONDecoder()
    let restoredSession = try decoder.decode(AnchorSessionData.self, from: data)
    
    XCTAssertEqual(restoredSession.status, .armed)
    XCTAssertEqual(restoredSession.activeWatch?.evitementHistory.count, 2)
    XCTAssertEqual(restoredSession.activeWatch?.evitementHistory.first?.coordinate.latitude, 47.218)
    XCTAssertEqual(restoredSession.activeWatch?.evitementHistory.last?.coordinate.latitude, 47.219)
  }

  func testDisarm_flushesStateToDiskDeterministically() async throws {
    let mockStore = EvitementMockStateStore()
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

private final class EvitementMockStateStore: AnchorStateStoreProtocol, @unchecked Sendable {
  private let lock = NSLock()
  private var session = AnchorSessionData()

  var savedSession: AnchorSessionData? {
    lock.withLock { session }
  }

  func loadSession() -> AnchorSessionData {
    lock.withLock { session }
  }

  func saveSession(_ session: AnchorSessionData) {
    lock.withLock { self.session = session }
  }
}



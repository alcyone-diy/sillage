//
//  AnchorStateStoreTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-15.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CoreLocation
@testable import Sillage

final class AnchorStateStoreTests: XCTestCase {

  private var tempDir: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if let tempDir {
      try? FileManager.default.removeItem(at: tempDir)
    }
    try super.tearDownWithError()
  }

  func testSaveSession_persistsLatestStateInStrictFIFOOrder() async throws {
    let store = AnchorStateStore(directoryURL: tempDir)
    let coord = CLLocationCoordinate2D(latitude: 47.218371, longitude: -1.553621)

    // Rapidly enqueue state transitions across 50 cycles ending in .inactive
    for index in 0..<50 {
      let radius = Measurement(value: Double(25 + index), unit: UnitLength.meters)
      let watch = AnchorWatch(coordinate: coord, radius: radius)
      store.saveSession(AnchorSessionData(activeWatch: watch, status: .dropped, triggerReason: nil))
      store.saveSession(AnchorSessionData(activeWatch: watch, status: .armed, triggerReason: nil))
      store.saveSession(AnchorSessionData(activeWatch: watch, status: .dragging, triggerReason: .gpsSignalLost))
    }
    let finalSession = AnchorSessionData(activeWatch: nil, status: .inactive, triggerReason: nil)
    store.saveSession(finalSession)

    await store.flush()

    // Reload from disk with a fresh store instance
    let reloaded = AnchorStateStore(directoryURL: tempDir)
    XCTAssertEqual(reloaded.loadSession(), finalSession)
  }

  func testSaveSession_persistsAndRestoresWatchAndAccuracy() async throws {
    let store = AnchorStateStore(directoryURL: tempDir)
    let watch = AnchorWatch(
      coordinate: CLLocationCoordinate2D(latitude: 48.123, longitude: -4.456),
      radius: Measurement(value: 45, unit: .meters),
      initialAccuracy: Measurement(value: 19, unit: .meters)
    )
    let session = AnchorSessionData(activeWatch: watch, status: .armed, triggerReason: nil)

    store.saveSession(session)
    await store.flush()

    let reloaded = AnchorStateStore(directoryURL: tempDir)
    let restored = reloaded.loadSession()
    XCTAssertEqual(restored.status, .armed)
    XCTAssertEqual(restored.activeWatch?.coordinate?.latitude, 48.123)
    XCTAssertEqual(restored.activeWatch?.coordinate?.longitude, -4.456)
    XCTAssertEqual(restored.activeWatch?.radius, Measurement(value: 45, unit: .meters))
    XCTAssertEqual(restored.activeWatch?.initialAccuracy, Measurement(value: 19, unit: .meters))
  }
}

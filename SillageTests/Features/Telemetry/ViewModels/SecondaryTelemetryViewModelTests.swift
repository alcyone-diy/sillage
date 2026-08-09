//
//  SecondaryTelemetryViewModelTests.swift
//  Alcyone SillageTests
//
//  Created by Alcyone on 2026-08-09.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import UIKit
@testable import Sillage

@MainActor
private final class MockDeviceBatteryService: DeviceBatteryServiceProtocol {
  var batteryLevel: Float?
  var batteryState: UIDevice.BatteryState

  init(batteryLevel: Float? = 0.85, batteryState: UIDevice.BatteryState = .unplugged) {
    self.batteryLevel = batteryLevel
    self.batteryState = batteryState
  }
}

@MainActor
final class SecondaryTelemetryViewModelTests: XCTestCase {

  func testBatteryItem_WhenValidLevel_FormatsPercentage() {
    let mockService = MockDeviceBatteryService(batteryLevel: 0.85, batteryState: .unplugged)
    let viewModel = SecondaryTelemetryViewModel(batteryService: mockService)

    let items = viewModel.items
    guard let batteryItem = items.first(where: { $0.id == "BATTERY" }) else {
      XCTFail("Expected BATTERY telemetry item")
      return
    }

    XCTAssertEqual(batteryItem.value, "85%")
    XCTAssertFalse(batteryItem.isPlaceholder)
  }

  func testBatteryItem_WhenFullCharge_FormatsOneHundredPercent() {
    let mockService = MockDeviceBatteryService(batteryLevel: 1.0, batteryState: .full)
    let viewModel = SecondaryTelemetryViewModel(batteryService: mockService)

    let items = viewModel.items
    guard let batteryItem = items.first(where: { $0.id == "BATTERY" }) else {
      XCTFail("Expected BATTERY telemetry item")
      return
    }

    XCTAssertEqual(batteryItem.value, "100%")
    XCTAssertFalse(batteryItem.isPlaceholder)
  }

  func testBatteryItem_WhenUnknownState_DisplaysPlaceholder() {
    let mockService = MockDeviceBatteryService(batteryLevel: 0.85, batteryState: .unknown)
    let viewModel = SecondaryTelemetryViewModel(batteryService: mockService)

    let items = viewModel.items
    guard let batteryItem = items.first(where: { $0.id == "BATTERY" }) else {
      XCTFail("Expected BATTERY telemetry item")
      return
    }

    XCTAssertEqual(batteryItem.value, "---")
    XCTAssertTrue(batteryItem.isPlaceholder)
  }

  func testBatteryItem_WhenNilLevel_DisplaysPlaceholder() {
    let mockService = MockDeviceBatteryService(batteryLevel: nil, batteryState: .unplugged)
    let viewModel = SecondaryTelemetryViewModel(batteryService: mockService)

    let items = viewModel.items
    guard let batteryItem = items.first(where: { $0.id == "BATTERY" }) else {
      XCTFail("Expected BATTERY telemetry item")
      return
    }

    XCTAssertEqual(batteryItem.value, "---")
    XCTAssertTrue(batteryItem.isPlaceholder)
  }

  func testBatteryItem_WhenNegativeLevel_DisplaysPlaceholder() {
    let mockService = MockDeviceBatteryService(batteryLevel: -1.0, batteryState: .unplugged)
    let viewModel = SecondaryTelemetryViewModel(batteryService: mockService)

    let items = viewModel.items
    guard let batteryItem = items.first(where: { $0.id == "BATTERY" }) else {
      XCTFail("Expected BATTERY telemetry item")
      return
    }

    XCTAssertEqual(batteryItem.value, "---")
    XCTAssertTrue(batteryItem.isPlaceholder)
  }

  func testWindItem_DisplaysPlaceholder() {
    let mockService = MockDeviceBatteryService()
    let viewModel = SecondaryTelemetryViewModel(batteryService: mockService)

    let items = viewModel.items
    guard let windItem = items.first(where: { $0.id == "WIND" }) else {
      XCTFail("Expected WIND telemetry item")
      return
    }

    XCTAssertEqual(windItem.value, "---")
    XCTAssertTrue(windItem.isPlaceholder)
  }
}

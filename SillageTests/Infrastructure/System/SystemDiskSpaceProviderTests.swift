//
//  SystemDiskSpaceProviderTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-22.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import XCTest
@testable import Sillage

final class SystemDiskSpaceProviderTests: XCTestCase {

  func testResolveAvailableSpace_prefersPositiveImportantUsageOverRegular() {
    let result = SystemDiskSpaceProvider.resolveAvailableSpace(
      importantUsageBytes: 2_000_000,
      regularBytes: 1_000_000
    )

    XCTAssertEqual(result, Measurement(value: 2_000_000, unit: .bytes))
  }

  func testResolveAvailableSpace_fallsBackToRegularWhenImportantIsZero() {
    let result = SystemDiskSpaceProvider.resolveAvailableSpace(
      importantUsageBytes: 0,
      regularBytes: 500_000
    )

    XCTAssertEqual(result, Measurement(value: 500_000, unit: .bytes))
  }

  func testResolveAvailableSpace_fallsBackToRegularWhenImportantIsNil() {
    let result = SystemDiskSpaceProvider.resolveAvailableSpace(
      importantUsageBytes: nil,
      regularBytes: 500_000
    )

    XCTAssertEqual(result, Measurement(value: 500_000, unit: .bytes))
  }

  func testResolveAvailableSpace_returnsZeroBytesWhenBothAreZero() {
    let result = SystemDiskSpaceProvider.resolveAvailableSpace(
      importantUsageBytes: 0,
      regularBytes: 0
    )

    XCTAssertEqual(result, Measurement(value: 0, unit: .bytes))
  }

  func testResolveAvailableSpace_returnsZeroBytesWhenImportantIsNilAndRegularIsZero() {
    let result = SystemDiskSpaceProvider.resolveAvailableSpace(
      importantUsageBytes: nil,
      regularBytes: 0
    )

    XCTAssertEqual(result, Measurement(value: 0, unit: .bytes))
  }

  func testResolveAvailableSpace_returnsZeroBytesWhenImportantIsZeroAndRegularIsNil() {
    let result = SystemDiskSpaceProvider.resolveAvailableSpace(
      importantUsageBytes: 0,
      regularBytes: nil
    )

    XCTAssertEqual(result, Measurement(value: 0, unit: .bytes))
  }

  func testResolveAvailableSpace_returnsNilForNegativeOrMissingValues() {
    XCTAssertNil(SystemDiskSpaceProvider.resolveAvailableSpace(importantUsageBytes: nil, regularBytes: nil))
    XCTAssertNil(SystemDiskSpaceProvider.resolveAvailableSpace(importantUsageBytes: -1, regularBytes: nil))
    XCTAssertNil(SystemDiskSpaceProvider.resolveAvailableSpace(importantUsageBytes: nil, regularBytes: -1))
    XCTAssertNil(SystemDiskSpaceProvider.resolveAvailableSpace(importantUsageBytes: -100, regularBytes: -50))
  }
}

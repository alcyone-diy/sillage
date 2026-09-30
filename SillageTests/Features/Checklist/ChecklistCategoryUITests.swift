//
//  ChecklistCategoryUITests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-01.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
@testable import Sillage

@MainActor
final class ChecklistCategoryUITests: XCTestCase {
  func testCategoryColor() {
    let theme = MarineTheme(
      minTouchTarget: 44,
      isGloveMode: false,
      colors: MarineTheme.dayColors
    )

    XCTAssertEqual(ChecklistCategory.safetyEmergency.color(for: theme), theme.colors.warning)
    XCTAssertEqual(ChecklistCategory.navigationManeuver.color(for: theme), theme.colors.accent)
    XCTAssertEqual(ChecklistCategory.routine.color(for: theme), theme.colors.primary)
    XCTAssertEqual(ChecklistCategory.engineTechnical.color(for: theme), theme.colors.textSecondary)
    XCTAssertEqual(ChecklistCategory.winteringMaintenance.color(for: theme), theme.colors.inactive)
  }
}

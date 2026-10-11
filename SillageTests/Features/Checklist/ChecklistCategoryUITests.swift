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
  func testCategoryItemDisplaySystemImage() {
    let itemWithIcon = ChecklistCategoryItem(
      id: "safety_emergency",
      name: "Safety & Emergency",
      icon: "exclamationmark.shield.fill"
    )
    XCTAssertEqual(itemWithIcon.displaySystemImage, "exclamationmark.shield.fill")

    let customItem = ChecklistCategoryItem(
      id: "custom_electronics",
      name: "Electronics",
      icon: "antenna.radiowaves.left.and.right"
    )
    XCTAssertEqual(customItem.displaySystemImage, "antenna.radiowaves.left.and.right")

    let itemWithoutIcon = ChecklistCategoryItem(
      id: "custom_other",
      name: "Other"
    )
    XCTAssertEqual(itemWithoutIcon.displaySystemImage, "checklist")

    let itemWithEmptyIcon = ChecklistCategoryItem(
      id: "custom_empty",
      name: "Empty",
      icon: ""
    )
    XCTAssertEqual(itemWithEmptyIcon.displaySystemImage, "checklist")
  }
}

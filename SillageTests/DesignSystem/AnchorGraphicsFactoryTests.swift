//
//  AnchorGraphicsFactoryTests.swift
//  Alcyone SillageTests
//
//  Created by Alcyone on 2026-08-07.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import UIKit
@testable import Sillage

@MainActor
final class AnchorGraphicsFactoryTests: XCTestCase {

  func testCreateAnchorImage_returnsValidImage() {
    let size = CGSize(width: 32, height: 32)
    let color = UIColor.cyan

    let image = AnchorGraphicsFactory.createAnchorImage(size: size, color: color)

    XCTAssertNotNil(image)
    XCTAssertEqual(image?.size.width, 32)
    XCTAssertEqual(image?.size.height, 32)
  }

  func testCreateAnchorImage_usesCacheForSameParameters() {
    let size = CGSize(width: 32, height: 32)
    let color = UIColor.green

    let image1 = AnchorGraphicsFactory.createAnchorImage(size: size, color: color)
    let image2 = AnchorGraphicsFactory.createAnchorImage(size: size, color: color)

    XCTAssertNotNil(image1)
    XCTAssertNotNil(image2)
    XCTAssertTrue(image1 === image2, "AnchorGraphicsFactory should return cached image instance for identical color and size")
  }
}

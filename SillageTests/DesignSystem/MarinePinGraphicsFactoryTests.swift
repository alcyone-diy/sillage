//
//  MarinePinGraphicsFactoryTests.swift
//  Alcyone SillageTests
//
//  Created by Alcyone on 2026-10-14.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import UIKit
@testable import Sillage

@MainActor
final class MarinePinGraphicsFactoryTests: XCTestCase {

  func testCanvasDimensionsAre52x84() {
    XCTAssertEqual(MarinePinGraphicsFactory.canvasSize.width, 52.0)
    XCTAssertEqual(MarinePinGraphicsFactory.canvasSize.height, 84.0)
  }

  func testCreateMeasurePinImage_returnsValidDimensions() {
    let theme = MarineTheme.standard
    let imageA = MarinePinGraphicsFactory.createMeasurePinImage(for: .start, isSelected: false, theme: theme)
    let imageB = MarinePinGraphicsFactory.createMeasurePinImage(for: .end, isSelected: true, theme: theme)

    XCTAssertNotNil(imageA)
    XCTAssertNotNil(imageB)
    XCTAssertEqual(imageA?.size.width, 52.0)
    XCTAssertEqual(imageA?.size.height, 84.0)
    XCTAssertEqual(imageB?.size.width, 52.0)
    XCTAssertEqual(imageB?.size.height, 84.0)
  }

  func testCreateTargetPinImage_returnsValidDimensions() {
    let theme = MarineTheme.standard
    let idleImage = MarinePinGraphicsFactory.createTargetPinImage(isDragging: false, theme: theme)
    let dragImage = MarinePinGraphicsFactory.createTargetPinImage(isDragging: true, theme: theme)

    XCTAssertNotNil(idleImage)
    XCTAssertNotNil(dragImage)
    XCTAssertEqual(idleImage?.size.width, 52.0)
    XCTAssertEqual(idleImage?.size.height, 84.0)
    XCTAssertEqual(dragImage?.size.width, 52.0)
    XCTAssertEqual(dragImage?.size.height, 84.0)
  }

  func testCreatePinImage_cachingMechanism() {
    let theme = MarineTheme.standard
    let img1 = MarinePinGraphicsFactory.createTargetPinImage(isDragging: false, theme: theme)
    let img2 = MarinePinGraphicsFactory.createTargetPinImage(isDragging: false, theme: theme)

    XCTAssertNotNil(img1)
    XCTAssertNotNil(img2)
    XCTAssertTrue(img1 === img2, "MarinePinGraphicsFactory should return cached image pointer for identical parameters")
  }

  func testCreatePinImage_differentStylesProduceDifferentImages() {
    let style1 = MarinePinGraphicsFactory.Style(
      fillColor: .white,
      strokeColor: .blue,
      badgeColor: .blue,
      reticleColor: .blue,
      centerDotColor: .blue
    )
    let style2 = MarinePinGraphicsFactory.Style(
      fillColor: .black,
      strokeColor: .red,
      badgeColor: .red,
      reticleColor: .red,
      centerDotColor: .red
    )

    let img1 = MarinePinGraphicsFactory.createPinImage(badge: .icon(.crosshair), style: style1, cacheKey: "test-style1-\(style1.colorSignature)")
    let img2 = MarinePinGraphicsFactory.createPinImage(badge: .icon(.crosshair), style: style2, cacheKey: "test-style2-\(style2.colorSignature)")

    XCTAssertNotNil(img1)
    XCTAssertNotNil(img2)
    XCTAssertFalse(img1 === img2, "Different styles must not return the same cached instance")
  }

  func testColorSignatureIncludesCenterDotColorAndScale() {
    let style = MarinePinGraphicsFactory.Style(
      fillColor: .white,
      strokeColor: .blue,
      badgeColor: .blue,
      reticleColor: .cyan,
      centerDotColor: .yellow,
      scale: 1.08
    )

    let signature = style.colorSignature
    XCTAssertTrue(signature.contains("1.08"), "Signature must include scale")
    XCTAssertTrue(signature.contains(UIColor.yellow.description), "Signature must include centerDotColor")
  }
}

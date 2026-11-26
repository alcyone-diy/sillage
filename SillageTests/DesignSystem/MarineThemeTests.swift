//
//  MarineThemeTests.swift
//  Alcyone SillageTests
//
//  Created by Alcyone on 2026-11-22.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import SwiftUI
@testable import Sillage

@MainActor
final class MarineThemeTests: XCTestCase {

  func testFontSettings_AllStylesResolveConsistently() {
    for style in MarineTextStyle.allCases {
      let settings = MarineTheme.fontSettings(for: style)

      switch style {
      case .instrumentData:
        XCTAssertEqual(settings.size, .title3)
        XCTAssertEqual(settings.weight, .semibold)
      case .instrumentLabel:
        XCTAssertEqual(settings.size, .caption2)
        XCTAssertEqual(settings.weight, .bold)
      case .largeTitle:
        XCTAssertEqual(settings.size, .largeTitle)
        XCTAssertNil(settings.weight)
      case .title:
        XCTAssertEqual(settings.size, .title)
        XCTAssertNil(settings.weight)
      case .title2:
        XCTAssertEqual(settings.size, .title2)
        XCTAssertNil(settings.weight)
      case .title3:
        XCTAssertEqual(settings.size, .title3)
        XCTAssertNil(settings.weight)
      case .headline:
        XCTAssertEqual(settings.size, .headline)
        XCTAssertNil(settings.weight)
      case .body:
        XCTAssertEqual(settings.size, .body)
        XCTAssertNil(settings.weight)
      case .callout:
        XCTAssertEqual(settings.size, .callout)
        XCTAssertNil(settings.weight)
      case .subheadline:
        XCTAssertEqual(settings.size, .subheadline)
        XCTAssertNil(settings.weight)
      case .footnote:
        XCTAssertEqual(settings.size, .footnote)
        XCTAssertNil(settings.weight)
      case .caption:
        XCTAssertEqual(settings.size, .caption)
        XCTAssertNil(settings.weight)
      case .caption2:
        XCTAssertEqual(settings.size, .caption2)
        XCTAssertNil(settings.weight)
      }
    }
  }

  func testFontSettings_HeadlineUsesNativeSemanticStyle() {
    let settings = MarineTheme.fontSettings(for: .headline)
    XCTAssertEqual(settings.size, .headline)
    XCTAssertNil(settings.weight)
  }

  func testFontSettings_InstrumentStylesPreserveExplicitWeights() {
    let dataSettings = MarineTheme.fontSettings(for: .instrumentData)
    XCTAssertEqual(dataSettings.size, .title3)
    XCTAssertEqual(dataSettings.weight, .semibold)

    let labelSettings = MarineTheme.fontSettings(for: .instrumentLabel)
    XCTAssertEqual(labelSettings.size, .caption2)
    XCTAssertEqual(labelSettings.weight, .bold)
  }

  func testGloveMode_IncreasesTouchTargetOnly() {
    XCTAssertFalse(MarineTheme.standard.isGloveMode)
    XCTAssertEqual(MarineTheme.standard.minTouchTarget, 44)

    XCTAssertTrue(MarineTheme.gloveMode.isGloveMode)
    XCTAssertEqual(MarineTheme.gloveMode.minTouchTarget, 66)
  }

  func testEquatableAndHashable_DifferentiatesGloveModeWithPresetIdentity() {
    XCTAssertEqual(MarineTheme.standard, MarineTheme.standard)
    XCTAssertEqual(MarineTheme.gloveMode, MarineTheme.gloveMode)
    XCTAssertNotEqual(MarineTheme.standard, MarineTheme.gloveMode)

    let set: Set<MarineTheme> = [.standard, .gloveMode, .standard]
    XCTAssertEqual(set.count, 2)
  }

  func testCartographicTokens_AreDefinedForTracksAndSymbolHalos() {
    let colors = MarineTheme.standard.colors
    XCTAssertNotEqual(colors.trackActive, colors.trackSaved)
    XCTAssertEqual(colors.chartSymbolHalo, .white)
  }
}

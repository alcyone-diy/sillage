//
//  MeasureMapInteractionControllerTests.swift
//  Alcyone SillageTests
//
//  Created by Alcyone on 2026-11-26.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import CoreGraphics
import Foundation
import Testing
@testable import Sillage

@MainActor
@Suite("MeasureMapInteractionController Tests")
struct MeasureMapInteractionControllerTests {

  // MARK: - Inverted Pin Hit-Testing

  @Test("hitTestPin detects touches on both needle tip and offset circular head, returning nil outside hitRadius")
  func hitTestInvertedPinTipAndHead() {
    let pinA = CGPoint(x: 100, y: 200)
    let pinB = CGPoint(x: 300, y: 200)
    let headOffset = MarineMapPinShape.needleToHeadCenterOffset // 44pt below tip
    let standardRadius = MarineTheme.standard.metrics.mapHandleHitRadius // 36pt

    // 1. Direct touch near needle tip of Pin A
    #expect(
      MeasureMapInteractionController.hitTestPin(
        at: CGPoint(x: 100, y: 170), // 30pt above tip (<= 36pt from tip, 74pt from head)
        startTip: pinA,
        endTip: pinB,
        activePin: .end,
        hitRadius: standardRadius
      ) == .start
    )

    // 2. Touch on circular head of Pin B (44pt below tip + 30pt further down = 74pt from tip, 30pt from head center!)
    let belowHeadB = CGPoint(x: 300, y: 200 + headOffset + 30)
    #expect(
      MeasureMapInteractionController.hitTestPin(
        at: belowHeadB,
        startTip: pinA,
        endTip: pinB,
        activePin: .start,
        hitRadius: standardRadius
      ) == .end
    )

    // 3. Touch outside both tip and head radii -> nil
    let outOfRange = CGPoint(x: 200, y: 200)
    #expect(
      MeasureMapInteractionController.hitTestPin(
        at: outOfRange,
        startTip: pinA,
        endTip: pinB,
        activePin: .end,
        hitRadius: standardRadius
      ) == nil
    )
  }

  @Test("hitTestPin prioritizes currently selected activePin when Pin A and Pin B overlap")
  func hitTestOverlappingPinsPrioritizesActivePin() {
    let pinA = CGPoint(x: 200, y: 200)
    let pinB = CGPoint(x: 210, y: 200) // 10pt apart: both well inside 36pt hitRadius
    let touchNearA = CGPoint(x: 201, y: 200)

    // Even when touch is slightly closer to A, if `.end` is active, `.end` wins so stacked pins can be separated predictably
    #expect(
      MeasureMapInteractionController.hitTestPin(
        at: touchNearA,
        startTip: pinA,
        endTip: pinB,
        activePin: .end,
        hitRadius: 36.0
      ) == .end
    )

    // Conversely when `.start` is active, `.start` wins
    #expect(
      MeasureMapInteractionController.hitTestPin(
        at: CGPoint(x: 209, y: 200),
        startTip: pinA,
        endTip: pinB,
        activePin: .start,
        hitRadius: 36.0
      ) == .start
    )
  }

  // MARK: - Vertical Camera Framing Calculation

  @Test("verticalShiftToFitRange returns 0 when both pins fit comfortably inside visibleVerticalRange")
  func verticalShiftZeroWhenAlreadyVisible() {
    let shift = MeasureMapInteractionController.verticalShiftToFitRange(
      minY: 220,
      maxY: 420,
      fallbackPointY: 350,
      fallbackBottomOffset: 62,
      visibleVerticalRange: 160...520
    )
    #expect(shift == 0.0)
  }

  @Test("verticalShiftToFitRange shifts camera down (positive deltaY) when pin is obscured by bottom obstruction")
  func verticalShiftUpWhenObscuredAtBottom() {
    // Visible band: 160...500. Pin range: 300...560 -> needs +60pt shift so maxY lands at 500 (and 300 - 60 = 240 >= 160)
    let shift = MeasureMapInteractionController.verticalShiftToFitRange(
      minY: 300,
      maxY: 560,
      fallbackPointY: 498,
      fallbackBottomOffset: 62,
      visibleVerticalRange: 160...500
    )
    #expect(shift == 60.0)
  }

  @Test("verticalShiftToFitRange shifts camera up (negative deltaY) when pin is obscured by top HUD clearance")
  func verticalShiftDownWhenObscuredAtTop() {
    // Visible band: 160...500. Pin range: 110...320 -> needs -50pt shift so minY lands at 160 (and 320 - (-50) = 370 <= 500)
    let shift = MeasureMapInteractionController.verticalShiftToFitRange(
      minY: 110,
      maxY: 320,
      fallbackPointY: 110,
      fallbackBottomOffset: 62,
      visibleVerticalRange: 160...500
    )
    #expect(shift == -50.0)
  }

  @Test("verticalShiftToFitRange falls back to keeping activePin visible when A-B span exceeds visibleVerticalRange")
  func verticalShiftUsesFallbackActivePinWhenSpanExceedsViewport() {
    // Visible band: 160...500 (height 340). Pin span: 100...600 (height 500 > 340, both cannot fit simultaneously!).
    // Active pin tip is at y = 538 (bottom at 538 + 62 = 600) -> fallback shifts +100pt so active pin bottom lands at 500.
    let shift = MeasureMapInteractionController.verticalShiftToFitRange(
      minY: 100,
      maxY: 600,
      fallbackPointY: 538,
      fallbackBottomOffset: 62,
      visibleVerticalRange: 160...500
    )
    #expect(shift == 100.0)
  }

  @Test("clampPoint constrains out-of-bounds coordinates to map viewport")
  func clampPointToViewportBounds() {
    let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
    #expect(MeasureMapInteractionController.clampPoint(CGPoint(x: -25, y: 900), to: bounds) == CGPoint(x: 0, y: 844))
    #expect(MeasureMapInteractionController.clampPoint(CGPoint(x: 500, y: -10), to: bounds) == CGPoint(x: 390, y: 0))
  }
}

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

  @Test("hitTestPin detects touches on both needle tip and offset circular head, returning nil outside hitRadius")
  func hitTestInvertedPinTipAndHead() {
    let pinA = CGPoint(x: 100, y: 200)
    let pinB = CGPoint(x: 300, y: 200)
    let headOffset = MarineMapPinShape.needleToHeadCenterOffset // 44pt below tip
    let standardRadius = MarineTheme.standard.metrics.mapHandleHitRadius // 36pt

    // 1. Direct touch near needle tip of Pin A
    #expect(
      MeasureMapInteractionController.hitTestPin(
        at: CGPoint(x: 100, y: 170),
        startTip: pinA,
        endTip: pinB,
        activePin: .end,
        hitRadius: standardRadius
      ) == .start
    )

    // 2. Touch on circular head of Pin B (44pt below tip + 30pt further down = 74pt from tip, 30pt from head center)
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
    #expect(
      MeasureMapInteractionController.hitTestPin(
        at: CGPoint(x: 200, y: 200),
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
    let pinB = CGPoint(x: 210, y: 200)
    let touchNearA = CGPoint(x: 201, y: 200)

    #expect(
      MeasureMapInteractionController.hitTestPin(
        at: touchNearA,
        startTip: pinA,
        endTip: pinB,
        activePin: .end,
        hitRadius: 36.0
      ) == .end
    )

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

  @Test("makeFramingRequest spans both pins including pinHeight and selects activePin as fallback")
  func makeFramingRequestEnvelopeAndFallback() {
    let startTip = CGPoint(x: 120, y: 180)
    let endTip = CGPoint(x: 260, y: 340)
    let request = MeasureMapInteractionController.makeFramingRequest(
      startTip: startTip,
      endTip: endTip,
      activePin: .start,
      pinHeight: 62.0
    )

    #expect(request.minY == 180.0)
    #expect(request.maxY == 402.0)
    #expect(request.fallbackPoint == startTip)
    #expect(request.fallbackBottomOffset == 62.0)
  }

  @Test("clampPoint constrains out-of-bounds coordinates to map viewport")
  func clampPointToViewportBounds() {
    let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
    #expect(MeasureMapInteractionController.clampPoint(CGPoint(x: -25, y: 900), to: bounds) == CGPoint(x: 0, y: 844))
    #expect(MeasureMapInteractionController.clampPoint(CGPoint(x: 500, y: -10), to: bounds) == CGPoint(x: 390, y: 0))
  }
}

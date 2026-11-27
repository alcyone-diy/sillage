//
//  MapCameraControllerTests.swift
//  Alcyone SillageTests
//
//  Created by Alcyone on 2026-11-26.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import CoreGraphics
import CoreLocation
import Foundation
import MapLibre
import Testing
import UIKit
@testable import Sillage

@MainActor
@Suite("MapCameraController Tests")
struct MapCameraControllerTests {

  private static let laRochelle = CLLocationCoordinate2D(latitude: 46.1591, longitude: -1.1520)

  // MARK: - Rough-Sea Tracking Tolerance & Gesture Classification

  @Test("Zoom gestures never break vessel tracking, whereas pure pan or rotate gestures are tracking-breaking candidates")
  func trackingBreakGestureClassification() {
    #expect(MapCameraController.isZoomReason(.gesturePinch) == true)
    #expect(MapCameraController.isZoomReason(.gestureZoomIn) == true)
    #expect(MapCameraController.isZoomReason(.gestureZoomOut) == true)
    #expect(MapCameraController.isZoomReason(.gestureOneFingerZoom) == true)
    #expect(MapCameraController.isZoomReason(.gesturePan) == false)

    // Pure pan or rotate -> candidate to break tracking
    #expect(MapCameraController.shouldBreakTracking(for: .gesturePan) == true)
    #expect(MapCameraController.shouldBreakTracking(for: .gestureRotate) == true)

    // Pure zoom or combined pinch+pan -> preserves tracking
    #expect(MapCameraController.shouldBreakTracking(for: .gesturePinch) == false)
    #expect(MapCameraController.shouldBreakTracking(for: [.gesturePinch, .gesturePan]) == false)
    #expect(MapCameraController.shouldBreakTracking(for: .programmatic) == false)
  }

  @Test("Sub-margin pan preserves tracking in rough seas, while exceeding threshold latches break (40pt standard / 60pt Glove Mode)")
  func trackingToleranceMarginEvaluation() {
    let sut = MapCameraController()
    let origin = CGPoint(x: 200, y: 400)

    sut.beginTrackingPanEvaluation(coordinate: Self.laRochelle, screenPoint: origin)
    #expect(sut.hasExceededTrackingMargin == false)

    // 35pt pan: below both standard (40pt) and Glove Mode (60pt) thresholds
    #expect(sut.evaluateTrackingDisplacement(currentScreenPoint: CGPoint(x: 235, y: 400), isGloveMode: false) == false)
    #expect(sut.hasExceededTrackingMargin == false)

    // 45pt pan: breaks tracking in standard mode, but NOT in Glove Mode
    #expect(sut.evaluateTrackingDisplacement(currentScreenPoint: CGPoint(x: 245, y: 400), isGloveMode: true) == false)
    #expect(sut.hasExceededTrackingMargin == false)

    #expect(sut.evaluateTrackingDisplacement(currentScreenPoint: CGPoint(x: 245, y: 400), isGloveMode: false) == true)
    #expect(sut.hasExceededTrackingMargin == true)

    // Subsequent samples stay latched and do not fire duplicate break transitions
    #expect(sut.evaluateTrackingDisplacement(currentScreenPoint: CGPoint(x: 300, y: 400), isGloveMode: false) == false)

    sut.resetTrackingPanEvaluation()
    #expect(sut.hasExceededTrackingMargin == false)
    #expect(sut.initialPanCenterCoordinate == nil)
    #expect(sut.initialPanScreenPoint == nil)
  }

  // MARK: - Course-Up Look-Ahead Content Inset

  @Test("courseUpContentInset offsets top by 1/3 height only in .courseUp on non-empty bounds")
  func courseUpContentInsetCalculation() {
    let viewport = CGRect(x: 0, y: 0, width: 390, height: 840)

    #expect(
      MapCameraController.courseUpContentInset(for: viewport, trackingMode: .courseUp) ==
      UIEdgeInsets(top: 280, left: 0, bottom: 0, right: 0)
    )
    #expect(MapCameraController.courseUpContentInset(for: viewport, trackingMode: .northUp) == .zero)
    #expect(MapCameraController.courseUpContentInset(for: viewport, trackingMode: .free) == .zero)
    #expect(MapCameraController.courseUpContentInset(for: .zero, trackingMode: .courseUp) == .zero)
  }

  // MARK: - Screen-Space Center Offset & Vertical Range Framing

  @Test("centerScreenPointForTarget shifts camera center by exact inverse delta between coordinate and target point")
  func centerScreenPointForTargetCalculation() {
    // Coordinate is currently at (260, 500), target reticle is at (195, 336), current camera center is at (195, 420)
    // Camera center must shift by (+65, +164) -> (260, 584) so the coordinate moves by (-65, -164) onto (195, 336).
    let shiftedCenter = MapCameraController.centerScreenPointForTarget(
      CGPoint(x: 260, y: 500),
      toAppearAt: CGPoint(x: 195, y: 336),
      currentCenterScreenPoint: CGPoint(x: 195, y: 420)
    )
    #expect(shiftedCenter == CGPoint(x: 260, y: 584))
  }

  @Test("verticalShiftToFitRange returns 0 when range fits inside visibleVerticalRange")
  func verticalShiftZeroWhenAlreadyVisible() {
    let shift = MapCameraController.verticalShiftToFitRange(
      minY: 220,
      maxY: 420,
      fallbackPointY: 350,
      fallbackBottomOffset: 62,
      visibleVerticalRange: 160...520
    )
    #expect(shift == 0.0)
  }

  @Test("verticalShiftToFitRange shifts camera down (positive deltaY) when obscured at bottom")
  func verticalShiftUpWhenObscuredAtBottom() {
    let shift = MapCameraController.verticalShiftToFitRange(
      minY: 300,
      maxY: 560,
      fallbackPointY: 498,
      fallbackBottomOffset: 62,
      visibleVerticalRange: 160...500
    )
    #expect(shift == 60.0)
  }

  @Test("verticalShiftToFitRange shifts camera up (negative deltaY) when obscured at top")
  func verticalShiftDownWhenObscuredAtTop() {
    let shift = MapCameraController.verticalShiftToFitRange(
      minY: 110,
      maxY: 320,
      fallbackPointY: 110,
      fallbackBottomOffset: 62,
      visibleVerticalRange: 160...500
    )
    #expect(shift == -50.0)
  }

  @Test("verticalShiftToFitRange falls back to keeping active point visible when span exceeds visibleVerticalRange")
  func verticalShiftUsesFallbackWhenSpanExceedsViewport() {
    let shift = MapCameraController.verticalShiftToFitRange(
      minY: 100,
      maxY: 600,
      fallbackPointY: 538,
      fallbackBottomOffset: 62,
      visibleVerticalRange: 160...500
    )
    #expect(shift == 100.0)
  }

  // MARK: - Style Reload Camera Snapshot Lifecycle

  @Test("pendingReloadCamera is ignored before initial camera boot, then captured and consumed once")
  func pendingReloadCameraCaptureAndSingleConsumption() {
    let sut = MapCameraController()
    let snapshot = SavedMapCameraSnapshot(center: Self.laRochelle, zoomLevel: 14.5, direction: 275.0)

    // Before initial boot camera is applied, network reconnect must not capture a (0,0) blank-style camera
    sut.captureReloadCamera(snapshot)
    #expect(sut.pendingReloadCamera == nil)

    sut.markInitialCameraApplied()
    sut.captureReloadCamera(snapshot)
    #expect(sut.pendingReloadCamera == snapshot)

    // Consumed once on didFinishLoading, then cleared
    #expect(sut.consumePendingReloadCamera() == snapshot)
    #expect(sut.consumePendingReloadCamera() == nil)
  }
}

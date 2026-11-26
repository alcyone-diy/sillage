//
//  OfflineSelectionInteractionControllerTests.swift
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
import Testing
@testable import Sillage

@MainActor
@Suite("OfflineSelectionInteractionController Tests")
struct OfflineSelectionInteractionControllerTests {

  private static let sampleCorners = ProjectedSelectionCorners(
    topLeft: CGPoint(x: 100, y: 100),
    topRight: CGPoint(x: 300, y: 100),
    bottomRight: CGPoint(x: 300, y: 250),
    bottomLeft: CGPoint(x: 100, y: 250)
  )

  @Test("computeUpdatedBounds scales minimum longitude span by cos(latitude) across all 4 corners")
  func computeUpdatedBoundsScalesMinimumLongitudeSpanByCosineLatitude() {
    let equatorialBox = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: -0.05, longitude: 0.0),
      northEast: CLLocationCoordinate2D(latitude: 0.05, longitude: 0.1)
    )
    let highLatBox = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 59.95, longitude: 10.0),
      northEast: CLLocationCoordinate2D(latitude: 60.05, longitude: 10.1)
    )

    // Attempt to invert both boxes by dragging NE far south-west of SW
    let clampedEquatorial = OfflineSelectionInteractionController.computeUpdatedBounds(
      from: equatorialBox,
      dragging: .topRight,
      to: CLLocationCoordinate2D(latitude: -1.0, longitude: -1.0)
    )
    let clampedHighLat = OfflineSelectionInteractionController.computeUpdatedBounds(
      from: highLatBox,
      dragging: .topRight,
      to: CLLocationCoordinate2D(latitude: 59.0, longitude: 9.0)
    )

    let eqLatSpan = clampedEquatorial.northEast.latitude - clampedEquatorial.southWest.latitude
    let eqLonSpan = clampedEquatorial.northEast.longitude - clampedEquatorial.southWest.longitude
    let highLatSpan = clampedHighLat.northEast.latitude - clampedHighLat.southWest.latitude
    let highLonSpan = clampedHighLat.northEast.longitude - clampedHighLat.southWest.longitude

    // Latitude span corresponds to ~500m everywhere (~0.0045°), whereas at 60°N cos(60°) = 0.5 doubles longitude span
    #expect(abs(eqLatSpan - highLatSpan) < 1e-6)
    #expect(abs(eqLonSpan - eqLatSpan) < 1e-6)
    #expect(abs(highLonSpan - eqLonSpan * 2.0) < 1e-4)

    // Verify remaining 3 corners update their respective axes cleanly
    let movedNW = OfflineSelectionInteractionController.computeUpdatedBounds(
      from: equatorialBox,
      dragging: .topLeft,
      to: CLLocationCoordinate2D(latitude: 0.2, longitude: -0.2)
    )
    #expect(movedNW.northEast.latitude == 0.2)
    #expect(movedNW.southWest.longitude == -0.2)

    let movedSW = OfflineSelectionInteractionController.computeUpdatedBounds(
      from: equatorialBox,
      dragging: .bottomLeft,
      to: CLLocationCoordinate2D(latitude: -0.2, longitude: -0.2)
    )
    #expect(movedSW.southWest.latitude == -0.2)
    #expect(movedSW.southWest.longitude == -0.2)

    let movedSE = OfflineSelectionInteractionController.computeUpdatedBounds(
      from: equatorialBox,
      dragging: .bottomRight,
      to: CLLocationCoordinate2D(latitude: -0.2, longitude: 0.3)
    )
    #expect(movedSE.southWest.latitude == -0.2)
    #expect(movedSE.northEast.longitude == 0.3)
  }

  @Test("hitTestCorner identifies each corner within hitRadius and returns nil outside")
  func hitTestCornerRespectsStandardAndGloveHitRadius() {
    let standardRadius = MarineTheme.standard.metrics.mapHandleHitRadius // 36pt
    let gloveRadius = MarineTheme.gloveMode.metrics.mapHandleHitRadius   // 48pt

    // Exact hits on all 4 corners
    #expect(OfflineSelectionInteractionController.hitTestCorner(at: CGPoint(x: 100, y: 100), corners: Self.sampleCorners, hitRadius: standardRadius) == .topLeft)
    #expect(OfflineSelectionInteractionController.hitTestCorner(at: CGPoint(x: 300, y: 100), corners: Self.sampleCorners, hitRadius: standardRadius) == .topRight)
    #expect(OfflineSelectionInteractionController.hitTestCorner(at: CGPoint(x: 300, y: 250), corners: Self.sampleCorners, hitRadius: standardRadius) == .bottomRight)
    #expect(OfflineSelectionInteractionController.hitTestCorner(at: CGPoint(x: 100, y: 250), corners: Self.sampleCorners, hitRadius: standardRadius) == .bottomLeft)

    // 42pt away from topLeft: outside standard 36pt radius, inside Glove Mode 48pt radius
    let pointAt42pt = CGPoint(x: 100, y: 58)
    #expect(OfflineSelectionInteractionController.hitTestCorner(at: pointAt42pt, corners: Self.sampleCorners, hitRadius: standardRadius) == nil)
    #expect(OfflineSelectionInteractionController.hitTestCorner(at: pointAt42pt, corners: Self.sampleCorners, hitRadius: gloveRadius) == .topLeft)

    // Center of rectangle (far from all 4 corners) -> nil
    #expect(OfflineSelectionInteractionController.hitTestCorner(at: CGPoint(x: 200, y: 175), corners: Self.sampleCorners, hitRadius: gloveRadius) == nil)
  }

  @Test("hitTestCorner picks the strictly closest corner when touch zones overlap")
  func hitTestCornerPicksClosestWhenOverlapping() {
    let tightCorners = ProjectedSelectionCorners(
      topLeft: CGPoint(x: 100, y: 100),
      topRight: CGPoint(x: 140, y: 100),
      bottomRight: CGPoint(x: 140, y: 140),
      bottomLeft: CGPoint(x: 100, y: 140)
    )
    // Touch at (126, 100): 26pt from topLeft, 14pt from topRight (both <= 36pt) -> must select topRight
    let hit = OfflineSelectionInteractionController.hitTestCorner(
      at: CGPoint(x: 126, y: 100),
      corners: tightCorners,
      hitRadius: 36.0
    )
    #expect(hit == .topRight)
  }

  @Test("defaultCropRect centers box according to widthRatio and aspect, returning nil on empty viewport")
  func defaultCropRectCalculation() {
    #expect(OfflineSelectionInteractionController.defaultCropRect(in: .zero, widthRatio: 0.7, aspect: 0.75) == nil)

    let viewport = CGRect(x: 0, y: 0, width: 400, height: 800)
    let rect = OfflineSelectionInteractionController.defaultCropRect(in: viewport, widthRatio: 0.7, aspect: 0.75)
    #expect(rect == CGRect(x: 60, y: 295, width: 280, height: 210))
  }

  @Test("resolvedBounds returns nil when inactive and committedBounds when idle")
  func resolvedBoundsBehavior() {
    let sync = MapStyleStateSynchronizer()
    let sut = OfflineSelectionInteractionController(styleSynchronizer: sync)
    let committed = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: 46.0, longitude: -1.3),
      northEast: CLLocationCoordinate2D(latitude: 46.2, longitude: -1.1)
    )

    #expect(sut.isInteracting == false)
    #expect(sut.resolvedBounds(isSelectionModeActive: false, committedBounds: committed) == nil)
    #expect(sut.resolvedBounds(isSelectionModeActive: true, committedBounds: committed) == committed)
    #expect(sut.resolvedBounds(isSelectionModeActive: true, committedBounds: nil) == nil)
  }
}

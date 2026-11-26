//
//  MapStyleControllerTests.swift
//  Alcyone SillageTests
//
//  Created by Alcyone on 2026-11-26.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import MapLibre
import XCTest
@testable import Sillage

@MainActor
final class MapStyleControllerTests: XCTestCase {

  func testMapLayerIdentifier_ZIndexOrderingAndUniqueness() {
    let allLayers = MapLayerIdentifier.allCases
    let uniqueRawValues = Set(allLayers.map(\.rawValue))
    XCTAssertEqual(uniqueRawValues.count, allLayers.count, "Every MapLayerIdentifier must have a unique raw string")

    for (index, identifier) in allLayers.enumerated() {
      XCTAssertEqual(identifier.zIndex, index)
      if index > 0 {
        XCTAssertLessThan(allLayers[index - 1], identifier)
      }
    }

    // Critical nautical stacking invariants:
    // 1. Base raster & seamark overlay sit at the bottom
    XCTAssertLessThan(MapLayerIdentifier.baseRaster, .seamarkOverlay)
    XCTAssertLessThan(MapLayerIdentifier.seamarkOverlay, .offlineMask)

    // 2. GPS accuracy sits below tracks, waypoints, and anchor watch
    XCTAssertLessThan(MapLayerIdentifier.gpsAccuracyStroke, .savedTrack)
    XCTAssertLessThan(MapLayerIdentifier.savedTrack, .activeTrack)
    XCTAssertLessThan(MapLayerIdentifier.visibleWaypoints, .goToWaypoint)

    // 3. Vessel cursor & COG vector render above tracks, waypoints, and anchor watch
    XCTAssertLessThan(MapLayerIdentifier.anchorPoint, .headingLine)
    XCTAssertLessThan(MapLayerIdentifier.headingTick, .vesselSymbol)

    // 4. Interactive measure pins & aiming crosshair sit at the very top
    XCTAssertLessThan(MapLayerIdentifier.vesselSymbol, .measurePins)
    XCTAssertLessThan(MapLayerIdentifier.measurePins, .targetAimingCrosshair)
  }

  func testMapSourceIdentifier_AllRawValuesAreUnique() {
    let allSources = MapSourceIdentifier.allCases
    let uniqueRawValues = Set(allSources.map(\.rawValue))
    XCTAssertEqual(uniqueRawValues.count, allSources.count)
  }

  func testMapSpriteIdentifier_GeneratesExpectedDeterministicNames() {
    XCTAssertEqual(MapSpriteIdentifier.anchorIcon(for: .setup), "anchor-icon-setup")
    XCTAssertEqual(MapSpriteIdentifier.anchorIcon(for: .dropped), "anchor-icon-dropped")
    XCTAssertEqual(MapSpriteIdentifier.anchorIcon(for: .armed), "anchor-icon-armed")
    XCTAssertEqual(MapSpriteIdentifier.anchorIcon(for: .dragging), "anchor-icon-dragging")

    XCTAssertEqual(MapSpriteIdentifier.measurePinIcon(for: .start, isSelected: true), "measure-pin-a-selected")
    XCTAssertEqual(MapSpriteIdentifier.measurePinIcon(for: .start, isSelected: false), "measure-pin-a-idle")
    XCTAssertEqual(MapSpriteIdentifier.measurePinIcon(for: .end, isSelected: true), "measure-pin-b-selected")
    XCTAssertEqual(MapSpriteIdentifier.measurePinIcon(for: .end, isSelected: false), "measure-pin-b-idle")
  }

  func testAnchorStyleRenderer_RodeDashPatternVariesStructurallyByStatus() {
    XCTAssertEqual(AnchorStyleRenderer.rodeDashPattern(for: .setup), AnchorStyleMetrics.standardDashPattern)
    XCTAssertEqual(AnchorStyleRenderer.rodeDashPattern(for: .dropped), AnchorStyleMetrics.standardDashPattern)
    XCTAssertEqual(AnchorStyleRenderer.rodeDashPattern(for: .armed), AnchorStyleMetrics.armedRodeDashPattern)
    XCTAssertNil(AnchorStyleRenderer.rodeDashPattern(for: .dragging), "Dragging alarm rode must render as a solid line")
  }

  func testAnchorStyleRenderer_BuildStyleExpressionsProducesValidMapLibreJSONMatchExpressions() {
    let expressions = AnchorStyleRenderer.buildStyleExpressions(for: .standard)

    let allExpressions: [NSExpression] = [
      expressions.pointIconImageName,
      expressions.fillColor,
      expressions.fillOpacity,
      expressions.dashedStrokeColor,
      expressions.dashedStrokeOpacity,
      expressions.solidStrokeColor,
      expressions.solidStrokeWidth,
      expressions.solidStrokeOpacity,
      expressions.rodeLineColor,
      expressions.rodeLineWidth,
      expressions.rodeLineOpacity,
      expressions.evitementLineColor,
      expressions.evitementLineWidth,
      expressions.evitementLineOpacity
    ]

    for expression in allExpressions {
      // `mgl_jsonExpressionObject` runs MapLibre Native's C++ expression serializer;
      // verifies zero Objective-C runtime exceptions and valid Style Spec `match` output.
      guard let jsonArray = expression.mgl_jsonExpressionObject as? [Any] else {
        XCTFail("Expected MapLibre JSON array expression for \(expression)")
        continue
      }
      XCTAssertEqual(jsonArray.first as? String, "match")
      if jsonArray.count > 1, let getOp = jsonArray[1] as? [String] {
        XCTAssertEqual(getOp, ["get", MapFeatureKey.status.rawValue])
      } else {
        XCTFail("Expected ['get', 'status'] input expression in \(jsonArray)")
      }
    }
  }

  func testTelemetryStyleRenderer_ConditionalExpressionsProduceValidMapLibreJSONCaseExpressions() {
    let tickRadiusExpr = TelemetryStyleRenderer.headingTickRadiusExpression()
    guard let tickJSON = tickRadiusExpr.mgl_jsonExpressionObject as? [Any] else {
      XCTFail("Expected MapLibre JSON array for headingTickRadiusExpression")
      return
    }
    XCTAssertEqual(tickJSON.first as? String, "case")

    let rotationExpr = TelemetryStyleRenderer.vesselIconRotationExpression()
    guard let rotationJSON = rotationExpr.mgl_jsonExpressionObject as? [Any] else {
      XCTFail("Expected MapLibre JSON array for vesselIconRotationExpression")
      return
    }
    XCTAssertEqual(rotationJSON.first as? String, "case")
  }
}

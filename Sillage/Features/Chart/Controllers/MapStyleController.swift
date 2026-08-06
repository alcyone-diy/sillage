//
//  MapStyleController.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-06.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import MapLibre
import OSLog
import UIKit

/// Identifiants typés et ordonnés des calques de la carte avec leur niveau de Z-Index sémantique.
enum MapLayerIdentifier: String, CaseIterable, Comparable {
  case baseRaster = "base-raster-layer"
  case seamarkOverlay = "seamark-overlay-layer"
  case gpsAccuracyFill = "gps-accuracy-layer"
  case gpsAccuracyStroke = "gps-accuracy-stroke-layer"
  case savedTrack = "saved-track-layer"
  case activeTrack = "active-track-layer"
  case bearingLine = "bearing-line-layer"
  case visibleWaypoints = "visible-waypoints-layer"
  case goToWaypoint = "goto-waypoint-layer"
  case anchorRadiusFill = "anchor-radius-layer"
  case anchorRadiusStroke = "anchor-radius-stroke-layer"
  case anchorPoint = "anchor-point-layer"
  case headingLine = "heading-vector-layer"
  case headingTick = "heading-vector-tick-layer"
  case vesselSymbol = "vessel-layer"

  var zIndex: Int {
    Self.allCases.firstIndex(of: self) ?? 0
  }

  static func < (lhs: MapLayerIdentifier, rhs: MapLayerIdentifier) -> Bool {
    lhs.zIndex < rhs.zIndex
  }
}

/// Identifiants typés des sources de données de la carte.
enum MapSourceIdentifier: String, CaseIterable {
  case baseRaster = "base-raster-source"
  case gpsAccuracy = "gps-accuracy-source"
  case savedTrack = "saved-track-source"
  case activeTrack = "active-track-source"
  case bearingLine = "bearing-line-source"
  case visibleWaypoints = "visible-waypoints-source"
  case goToWaypoint = "goto-waypoint-source"
  case heading = "heading-vector-source"
  case vessel = "vessel-source"
  case anchorRadius = "anchor-radius-source"
  case anchorPoint = "anchor-point-source"
}

/// Contrôleur de style MapLibre sans état (stateless struct worker).
/// Toutes ses opérations sont isolées sur le `@MainActor`.
@MainActor
struct MapStyleController {

  /// Insère un calque dans le style MapLibre à sa position Z-Index correcte.
  /// L'algorithme recherche dans `style` le premier calque existant ayant un Z-Index
  /// immédiatement supérieur à celui du calque à insérer. Si aucun n'existe, il l'ajoute au sommet.
  static func insertLayer(_ layer: MLNStyleLayer, identifier: MapLayerIdentifier, into style: MLNStyle) {
    assert(layer.identifier == identifier.rawValue, "FATAL: L'identifiant du MLNStyleLayer (\(layer.identifier)) ne correspond pas au MapLayerIdentifier (\(identifier.rawValue)).")

    guard style.layer(withIdentifier: identifier.rawValue) == nil else {
      Logger.mapStyle.debug("Layer already present in style: \(identifier.rawValue, privacy: .public)")
      return
    }


    // Trouver les calques ordonnés de Z-index supérieur
    let higherIdentifiers = MapLayerIdentifier.allCases.filter { $0 > identifier }

    for higherID in higherIdentifiers {
      if let higherLayer = style.layer(withIdentifier: higherID.rawValue) {
        style.insertLayer(layer, below: higherLayer)
        Logger.mapStyle.debug("Inserted layer '\(identifier.rawValue, privacy: .public)' below '\(higherID.rawValue, privacy: .public)'")
        return
      }
    }

    // Si aucun calque supérieur n'existe encore dans le style, l'ajouter au sommet
    style.addLayer(layer)
    Logger.mapStyle.debug("Added layer '\(identifier.rawValue, privacy: .public)' at top of style stack")
  }
}

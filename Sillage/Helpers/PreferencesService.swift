//
//  PreferencesService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation
import Observation

@MainActor
protocol PreferencesServiceProtocol {
  var savedMapSource: String? { get set }
  var savedGeoGarageLayerID: String? { get set }
  var savedLatitude: Double? { get set }
  var savedLongitude: Double? { get set }
  var savedZoom: Double? { get set }
  var savedDirection: Double? { get set }
  var gloveModeEnabled: Bool { get set }
  var hasAcceptedDisclaimer: Bool { get set }
  var isOpenSeaMapOverlayEnabled: Bool { get set }

  var isCOGVectorEnabled: Bool { get set }
  var cogVectorTimeHorizon: Measurement<UnitDuration> { get set }
  var isCOGVectorTicksEnabled: Bool { get set }

  func saveCameraState(coordinate: CLLocationCoordinate2D, zoom: Double, direction: Double)
  func loadCameraState() -> (coordinate: CLLocationCoordinate2D, zoom: Double, direction: Double)?
}

@Observable
@MainActor
class PreferencesService: PreferencesServiceProtocol {
  @ObservationIgnored static let shared = PreferencesService()

  @ObservationIgnored private let mapSourceKey = "selectedMapSource"
  @ObservationIgnored private let savedGeoGarageLayerIDKey = "savedGeoGarageLayerID"
  @ObservationIgnored private let savedLatitudeKey = "savedLatitude"
  @ObservationIgnored private let savedLongitudeKey = "savedLongitude"
  @ObservationIgnored private let savedZoomKey = "savedZoom"
  @ObservationIgnored private let savedDirectionKey = "savedDirection"
  @ObservationIgnored private let gloveModeEnabledKey = "gloveModeEnabled"
  @ObservationIgnored private let hasAcceptedDisclaimerKey = "hasAcceptedDisclaimer"
  @ObservationIgnored private let isOpenSeaMapOverlayEnabledKey = "isOpenSeaMapOverlayEnabled"

  @ObservationIgnored private let isCOGVectorEnabledKey = "isCOGVectorEnabled"
  @ObservationIgnored private let cogVectorTimeHorizonSecondsKey = "cogVectorTimeHorizonSeconds"
  @ObservationIgnored private let isCOGVectorTicksEnabledKey = "isCOGVectorTicksEnabled"

  @ObservationIgnored private let defaults = UserDefaults.standard

  var savedMapSource: String? {
    didSet { defaults.set(savedMapSource, forKey: mapSourceKey) }
  }

  var savedGeoGarageLayerID: String? {
    didSet { defaults.set(savedGeoGarageLayerID, forKey: savedGeoGarageLayerIDKey) }
  }

  var savedLatitude: Double? {
    didSet { defaults.set(savedLatitude, forKey: savedLatitudeKey) }
  }

  var savedLongitude: Double? {
    didSet { defaults.set(savedLongitude, forKey: savedLongitudeKey) }
  }

  var savedZoom: Double? {
    didSet { defaults.set(savedZoom, forKey: savedZoomKey) }
  }

  var savedDirection: Double? {
    didSet { defaults.set(savedDirection, forKey: savedDirectionKey) }
  }

  var gloveModeEnabled: Bool {
    didSet { defaults.set(gloveModeEnabled, forKey: gloveModeEnabledKey) }
  }

  var hasAcceptedDisclaimer: Bool {
    didSet { defaults.set(hasAcceptedDisclaimer, forKey: hasAcceptedDisclaimerKey) }
  }

  var isOpenSeaMapOverlayEnabled: Bool {
    didSet { defaults.set(isOpenSeaMapOverlayEnabled, forKey: isOpenSeaMapOverlayEnabledKey) }
  }

  var isCOGVectorEnabled: Bool {
    didSet { defaults.set(isCOGVectorEnabled, forKey: isCOGVectorEnabledKey) }
  }

  var isCOGVectorTicksEnabled: Bool {
    didSet { defaults.set(isCOGVectorTicksEnabled, forKey: isCOGVectorTicksEnabledKey) }
  }

  private var rawCogVectorTimeHorizonSeconds: Double {
    didSet { defaults.set(rawCogVectorTimeHorizonSeconds, forKey: cogVectorTimeHorizonSecondsKey) }
  }

  var cogVectorTimeHorizon: Measurement<UnitDuration> {
    get {
      Measurement(value: rawCogVectorTimeHorizonSeconds, unit: .seconds)
    }
    set {
      rawCogVectorTimeHorizonSeconds = newValue.converted(to: .seconds).value
    }
  }

  init() {
    self.savedMapSource = defaults.string(forKey: mapSourceKey)
    self.savedGeoGarageLayerID = defaults.string(forKey: savedGeoGarageLayerIDKey)
    self.savedLatitude = defaults.object(forKey: savedLatitudeKey) as? Double
    self.savedLongitude = defaults.object(forKey: savedLongitudeKey) as? Double
    self.savedZoom = defaults.object(forKey: savedZoomKey) as? Double
    self.savedDirection = defaults.object(forKey: savedDirectionKey) as? Double
    self.gloveModeEnabled = defaults.bool(forKey: gloveModeEnabledKey)
    self.hasAcceptedDisclaimer = defaults.bool(forKey: hasAcceptedDisclaimerKey)
    self.isOpenSeaMapOverlayEnabled = defaults.bool(forKey: isOpenSeaMapOverlayEnabledKey)

    self.isCOGVectorEnabled = defaults.object(forKey: isCOGVectorEnabledKey) as? Bool ?? true
    self.isCOGVectorTicksEnabled = defaults.object(forKey: isCOGVectorTicksEnabledKey) as? Bool ?? true
    self.rawCogVectorTimeHorizonSeconds = defaults.object(forKey: cogVectorTimeHorizonSecondsKey) as? Double ?? 3600.0
  }

  func saveCameraState(coordinate: CLLocationCoordinate2D, zoom: Double, direction: Double) {
    savedLatitude = coordinate.latitude
    savedLongitude = coordinate.longitude
    savedZoom = zoom
    savedDirection = direction
  }

  func loadCameraState() -> (coordinate: CLLocationCoordinate2D, zoom: Double, direction: Double)? {
    if let lat = savedLatitude, let lon = savedLongitude, let zoom = savedZoom {
      let direction = savedDirection ?? 0.0 // Default to 0 (North) if not saved
      return (CLLocationCoordinate2D(latitude: lat, longitude: lon), zoom, direction)
    }
    return nil
  }
}

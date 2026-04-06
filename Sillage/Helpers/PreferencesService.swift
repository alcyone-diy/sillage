//
//  PreferencesService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

protocol PreferencesServiceProtocol {
  var savedMapSource: String? { get set }
  var savedGeoGarageLayerID: String? { get set }
  var savedLatitude: Double? { get set }
  var savedLongitude: Double? { get set }
  var savedZoom: Double? { get set }
  var savedDirection: Double? { get set }
  var gloveModeEnabled: Bool { get set }
  var hasAcceptedDisclaimer: Bool { get set }

  func saveCameraState(coordinate: CLLocationCoordinate2D, zoom: Double, direction: Double)
  func loadCameraState() -> (coordinate: CLLocationCoordinate2D, zoom: Double, direction: Double)?
}

class PreferencesService: PreferencesServiceProtocol {
  static let shared = PreferencesService()

  private let mapSourceKey = "selectedMapSource"
  private let savedGeoGarageLayerIDKey = "savedGeoGarageLayerID"
  private let savedLatitudeKey = "savedLatitude"
  private let savedLongitudeKey = "savedLongitude"
  private let savedZoomKey = "savedZoom"
  private let savedDirectionKey = "savedDirection"
  private let gloveModeEnabledKey = "gloveModeEnabled"
  private let hasAcceptedDisclaimerKey = "hasAcceptedDisclaimer"

  private let defaults = UserDefaults.standard

  var savedMapSource: String? {
    get { defaults.string(forKey: mapSourceKey) }
    set { defaults.set(newValue, forKey: mapSourceKey) }
  }

  var savedGeoGarageLayerID: String? {
    get { defaults.string(forKey: savedGeoGarageLayerIDKey) }
    set { defaults.set(newValue, forKey: savedGeoGarageLayerIDKey) }
  }

  var savedLatitude: Double? {
    get { defaults.object(forKey: savedLatitudeKey) as? Double }
    set { defaults.set(newValue, forKey: savedLatitudeKey) }
  }

  var savedLongitude: Double? {
    get { defaults.object(forKey: savedLongitudeKey) as? Double }
    set { defaults.set(newValue, forKey: savedLongitudeKey) }
  }

  var savedZoom: Double? {
    get { defaults.object(forKey: savedZoomKey) as? Double }
    set { defaults.set(newValue, forKey: savedZoomKey) }
  }

  var savedDirection: Double? {
    get { defaults.object(forKey: savedDirectionKey) as? Double }
    set { defaults.set(newValue, forKey: savedDirectionKey) }
  }

  var gloveModeEnabled: Bool {
    get { defaults.bool(forKey: gloveModeEnabledKey) }
    set { defaults.set(newValue, forKey: gloveModeEnabledKey) }
  }

  var hasAcceptedDisclaimer: Bool {
    get { defaults.bool(forKey: hasAcceptedDisclaimerKey) }
    set { defaults.set(newValue, forKey: hasAcceptedDisclaimerKey) }
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

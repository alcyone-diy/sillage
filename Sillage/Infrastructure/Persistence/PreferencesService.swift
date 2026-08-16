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

// MARK: - GPS Accuracy Mode

/// Available GPS accuracy levels. Mapped to CLLocationAccuracy exclusively
/// inside CoreLocationPositioningService, keeping this type free of CoreLocation.
enum GPSAccuracyMode: String, CaseIterable, Sendable {
  case bestForNavigation = "bestForNavigation"
  case best             = "best"
  case tenMeters        = "tenMeters"
  case hundredMeters    = "hundredMeters"

  var displayName: String {
    switch self {
    case .bestForNavigation: return "Best for Navigation"
    case .best:              return "Best"
    case .tenMeters:         return "~10 m"
    case .hundredMeters:     return "~100 m"
    }
  }
}

@MainActor
protocol PreferencesServiceProtocol {
  var savedChartSource: String? { get set }
  var savedGeoGarageLayerID: String? { get set }
  var savedLatitude: Double? { get set }
  var savedLongitude: Double? { get set }
  var savedZoom: Double? { get set }
  var savedDirection: Double? { get set }
  var savedTrackingMode: ChartTrackingMode { get set }
  var gloveModeEnabled: Bool { get set }
  var hasAcceptedDisclaimer: Bool { get set }
  var isOpenSeaMapOverlayEnabled: Bool { get set }
  var geoGarageUsername: String? { get set }
  /// Unique GeoGarage customer account identifier. Non-sensitive — used to reconstruct
  /// the SQLCipher decryption key dynamically at runtime (never stored alongside the shared secret).
  var geoGarageCustomerID: String? { get set }

  var isCOGVectorEnabled: Bool { get set }
  var cogVectorTimeHorizon: Measurement<UnitDuration> { get set }
  var isCOGVectorTicksEnabled: Bool { get set }

  func saveCameraState(coordinate: CLLocationCoordinate2D, zoom: Double, direction: Double)
  func loadCameraState() -> (coordinate: CLLocationCoordinate2D, zoom: Double, direction: Double)?

  var activeTrackSessionID: String? { get }
  func saveActiveTrackSessionID(_ id: String)
  func clearActiveTrackSessionID()

  var goToWaypointID: String? { get set }
  var displayedTrackSessionID: String? { get set }

  // MARK: - Barometer Settings
  var isBaroAlarmEnabled: Bool { get set }
  var baroAlarmSensitivity: BaroAlarmSensitivity { get set }
  var barometerOffset: Measurement<UnitPressure> { get set }

  // MARK: - Anchor Watch Settings
  var savedAnchorRadius: Measurement<UnitLength> { get set }

  // MARK: - HUD Settings
  var hudEditOpenCount: Int { get set }

  // MARK: - GPS Debug Settings
  var gpsAccuracyMode: GPSAccuracyMode { get set }
}

@Observable
@MainActor
class PreferencesService: PreferencesServiceProtocol {
  @ObservationIgnored private let chartSourceKey = "chartSource"
  @ObservationIgnored private let savedGeoGarageLayerIDKey = "savedGeoGarageLayerID"
  @ObservationIgnored private let savedLatitudeKey = "savedLatitude"
  @ObservationIgnored private let savedLongitudeKey = "savedLongitude"
  @ObservationIgnored private let savedZoomKey = "savedZoom"
  @ObservationIgnored private let savedDirectionKey = "savedDirection"
  @ObservationIgnored private let savedTrackingModeKey = "savedTrackingMode"
  @ObservationIgnored private let gloveModeEnabledKey = "gloveModeEnabled"
  @ObservationIgnored private let hasAcceptedDisclaimerKey = "hasAcceptedDisclaimer"
  @ObservationIgnored private let isOpenSeaMapOverlayEnabledKey = "isOpenSeaMapOverlayEnabled"
  @ObservationIgnored private let geoGarageUsernameKey = "geogarage_username"
  @ObservationIgnored private let geoGarageCustomerIDKey = "geogarage_customer_id"

  @ObservationIgnored private let isCOGVectorEnabledKey = "isCOGVectorEnabled"
  @ObservationIgnored private let cogVectorTimeHorizonSecondsKey = "cogVectorTimeHorizonSeconds"
  @ObservationIgnored private let isCOGVectorTicksEnabledKey = "isCOGVectorTicksEnabled"
  @ObservationIgnored private let activeTrackSessionIDKey = "activeTrackSessionID"
  @ObservationIgnored private let goToWaypointIDKey = "goToWaypointID"
  @ObservationIgnored private let displayedTrackSessionIDKey = "displayedTrackSessionID"
  @ObservationIgnored private let isBaroAlarmEnabledKey = "isBaroAlarmEnabled"
  @ObservationIgnored private let baroAlarmSensitivityKey = "baroAlarmSensitivity"
  @ObservationIgnored private let barometerOffsetHPaKey = "barometerOffsetHPa"

  @ObservationIgnored private let savedAnchorRadiusMetersKey = "savedAnchorRadiusMeters"
  @ObservationIgnored private let hudEditOpenCountKey = "sillage.prefs.hudEditOpenCount"
  @ObservationIgnored private let gpsAccuracyModeKey = "gpsAccuracyMode"

  @ObservationIgnored private let defaults = UserDefaults.standard

  var savedChartSource: String? {
    didSet { defaults.set(savedChartSource, forKey: chartSourceKey) }
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

  var savedTrackingMode: ChartTrackingMode = .northUp {
    didSet { defaults.set(savedTrackingMode.rawValue, forKey: savedTrackingModeKey) }
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

  var geoGarageUsername: String? {
    didSet {
      if let value = geoGarageUsername {
        defaults.set(value, forKey: geoGarageUsernameKey)
      } else {
        defaults.removeObject(forKey: geoGarageUsernameKey)
      }
    }
  }

  var geoGarageCustomerID: String? {
    didSet {
      if let value = geoGarageCustomerID {
        defaults.set(value, forKey: geoGarageCustomerIDKey)
      } else {
        defaults.removeObject(forKey: geoGarageCustomerIDKey)
      }
    }
  }

  var isCOGVectorEnabled: Bool {
    didSet { defaults.set(isCOGVectorEnabled, forKey: isCOGVectorEnabledKey) }
  }

  var isCOGVectorTicksEnabled: Bool {
    didSet { defaults.set(isCOGVectorTicksEnabled, forKey: isCOGVectorTicksEnabledKey) }
  }

  @ObservationIgnored
  var activeTrackSessionID: String? {
    didSet { defaults.set(activeTrackSessionID, forKey: activeTrackSessionIDKey) }
  }

  var goToWaypointID: String? {
    didSet { defaults.set(goToWaypointID, forKey: goToWaypointIDKey) }
  }

  var displayedTrackSessionID: String? {
    didSet { defaults.set(displayedTrackSessionID, forKey: displayedTrackSessionIDKey) }
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

  var isBaroAlarmEnabled: Bool {
    didSet { defaults.set(isBaroAlarmEnabled, forKey: isBaroAlarmEnabledKey) }
  }

  private var rawBaroAlarmSensitivity: String {
    didSet { defaults.set(rawBaroAlarmSensitivity, forKey: baroAlarmSensitivityKey) }
  }

  var baroAlarmSensitivity: BaroAlarmSensitivity {
    get { BaroAlarmSensitivity(rawValue: rawBaroAlarmSensitivity) ?? .medium }
    set { rawBaroAlarmSensitivity = newValue.rawValue }
  }

  private var rawBarometerOffsetHPa: Double {
    didSet { defaults.set(rawBarometerOffsetHPa, forKey: barometerOffsetHPaKey) }
  }

  var barometerOffset: Measurement<UnitPressure> {
    get { Measurement(value: rawBarometerOffsetHPa, unit: .hectopascals) }
    set { rawBarometerOffsetHPa = newValue.converted(to: .hectopascals).value }
  }

  private var rawAnchorRadiusMeters: Double {
    didSet { defaults.set(rawAnchorRadiusMeters, forKey: savedAnchorRadiusMetersKey) }
  }

  var savedAnchorRadius: Measurement<UnitLength> {
    get { Measurement(value: rawAnchorRadiusMeters, unit: .meters) }
    set { rawAnchorRadiusMeters = newValue.converted(to: .meters).value }
  }

  var hudEditOpenCount: Int {
    didSet { defaults.set(hudEditOpenCount, forKey: hudEditOpenCountKey) }
  }

  private var rawGPSAccuracyMode: String {
    didSet { defaults.set(rawGPSAccuracyMode, forKey: gpsAccuracyModeKey) }
  }

  var gpsAccuracyMode: GPSAccuracyMode {
    get { GPSAccuracyMode(rawValue: rawGPSAccuracyMode) ?? .best }
    set { rawGPSAccuracyMode = newValue.rawValue }
  }

  init() {
    self.savedChartSource = defaults.string(forKey: chartSourceKey)
    self.savedGeoGarageLayerID = defaults.string(forKey: savedGeoGarageLayerIDKey)
    self.savedLatitude = defaults.object(forKey: savedLatitudeKey) as? Double
    self.savedLongitude = defaults.object(forKey: savedLongitudeKey) as? Double
    self.savedZoom = defaults.object(forKey: savedZoomKey) as? Double
    self.savedDirection = defaults.object(forKey: savedDirectionKey) as? Double
    if let rawTrackingMode = defaults.string(forKey: savedTrackingModeKey), let mode = ChartTrackingMode(rawValue: rawTrackingMode) {
      self.savedTrackingMode = mode
    }
    self.gloveModeEnabled = defaults.bool(forKey: gloveModeEnabledKey)
    self.hasAcceptedDisclaimer = defaults.bool(forKey: hasAcceptedDisclaimerKey)
    self.isOpenSeaMapOverlayEnabled = defaults.bool(forKey: isOpenSeaMapOverlayEnabledKey)
    self.geoGarageUsername = defaults.string(forKey: geoGarageUsernameKey)
    self.geoGarageCustomerID = defaults.string(forKey: geoGarageCustomerIDKey)

    self.isCOGVectorEnabled = defaults.object(forKey: isCOGVectorEnabledKey) as? Bool ?? true
    self.isCOGVectorTicksEnabled = defaults.object(forKey: isCOGVectorTicksEnabledKey) as? Bool ?? true
    self.rawCogVectorTimeHorizonSeconds = defaults.object(forKey: cogVectorTimeHorizonSecondsKey) as? Double ?? 3600.0
    self.activeTrackSessionID = defaults.string(forKey: activeTrackSessionIDKey)
    self.goToWaypointID = defaults.string(forKey: goToWaypointIDKey)
    self.displayedTrackSessionID = defaults.string(forKey: displayedTrackSessionIDKey)

    self.isBaroAlarmEnabled = defaults.object(forKey: isBaroAlarmEnabledKey) as? Bool ?? false
    self.rawBaroAlarmSensitivity = defaults.string(forKey: baroAlarmSensitivityKey) ?? BaroAlarmSensitivity.medium.rawValue
    self.rawBarometerOffsetHPa = defaults.object(forKey: barometerOffsetHPaKey) as? Double ?? 0.0

    self.rawAnchorRadiusMeters = defaults.object(forKey: savedAnchorRadiusMetersKey) as? Double ?? 25.0
    self.hudEditOpenCount = defaults.integer(forKey: hudEditOpenCountKey)
    self.rawGPSAccuracyMode = defaults.string(forKey: gpsAccuracyModeKey) ?? GPSAccuracyMode.bestForNavigation.rawValue
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

  func saveActiveTrackSessionID(_ id: String) {
    self.activeTrackSessionID = id
  }

  func clearActiveTrackSessionID() {
    self.activeTrackSessionID = nil
  }
}

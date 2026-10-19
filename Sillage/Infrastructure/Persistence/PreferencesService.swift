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

// MARK: - Pending CAAS Download State Preservation

/// Persistent record of an in-flight CAAS download to survive iOS app termination or crashes.
nonisolated struct PendingCAASDownload: Codable, Equatable, Sendable, Identifiable {
  let id: UUID
  let packageID: UUID?
  let layerID: String
  let layerName: String
  let boundsWKT: String
  let zoomMax: Int
  let createdAt: Date
  let customName: String?
  let replacesChartID: UUID?

  init(
    id: UUID? = nil,
    packageID: UUID? = nil,
    layerID: String,
    layerName: String,
    boundsWKT: String,
    zoomMax: Int,
    createdAt: Date = Date(),
    customName: String? = nil,
    replacesChartID: UUID? = nil
  ) {
    self.id = id ?? packageID ?? UUID()
    self.packageID = packageID
    self.layerID = layerID
    self.layerName = layerName
    self.boundsWKT = boundsWKT
    self.zoomMax = zoomMax
    self.createdAt = createdAt
    self.customName = customName
    self.replacesChartID = replacesChartID
  }

  enum CodingKeys: String, CodingKey {
    case id, packageID, layerID, layerName, boundsWKT, zoomMax, createdAt, customName, replacesChartID
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? container.decodeIfPresent(UUID.self, forKey: .packageID) ?? UUID()
    self.packageID = try container.decodeIfPresent(UUID.self, forKey: .packageID)
    self.layerID = try container.decode(String.self, forKey: .layerID)
    self.layerName = try container.decode(String.self, forKey: .layerName)
    self.boundsWKT = try container.decode(String.self, forKey: .boundsWKT)
    self.zoomMax = try container.decode(Int.self, forKey: .zoomMax)
    self.createdAt = try container.decode(Date.self, forKey: .createdAt)
    self.customName = try container.decodeIfPresent(String.self, forKey: .customName)
    self.replacesChartID = try container.decodeIfPresent(UUID.self, forKey: .replacesChartID)
  }

  func updating(packageID: UUID?) -> PendingCAASDownload {
    PendingCAASDownload(
      id: self.id,
      packageID: packageID,
      layerID: self.layerID,
      layerName: self.layerName,
      boundsWKT: self.boundsWKT,
      zoomMax: self.zoomMax,
      createdAt: self.createdAt,
      customName: self.customName,
      replacesChartID: self.replacesChartID
    )
  }

  func updating(replacesChartID: UUID?) -> PendingCAASDownload {
    PendingCAASDownload(
      id: self.id,
      packageID: self.packageID,
      layerID: self.layerID,
      layerName: self.layerName,
      boundsWKT: self.boundsWKT,
      zoomMax: self.zoomMax,
      createdAt: self.createdAt,
      customName: self.customName,
      replacesChartID: replacesChartID
    )
  }
}


@MainActor
protocol PreferencesServiceProtocol: AnyObject {
  var savedChartSource: String? { get set }
  var savedGeoGarageLayerID: String? { get set }
  var savedLatitude: Double? { get set }
  var savedLongitude: Double? { get set }
  var savedZoom: Double? { get set }
  var savedDirection: Double? { get set }
  var savedTrackingMode: ChartTrackingMode? { get set }
  var lastMapTrackingMode: ChartTrackingMode? { get set }
  var gloveModeEnabled: Bool { get set }
  var hasAcceptedDisclaimer: Bool { get set }
  var isOpenSeaMapOverlayEnabled: Bool { get set }
  var geoGarageUsername: String? { get set }
  /// Unique GeoGarage customer account identifier.
  /// Reconstructs the SQLCipher decryption key dynamically at runtime (`customerID + sharedSecret`).
  /// Persisted in both UserDefaults and Keychain to survive app reinstallation.
  var geoGarageCustomerID: String? { get set }
  var pendingCAASDownloads: [PendingCAASDownload] { get set }

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

  // MARK: - Reset
  func clearAll()
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
  @ObservationIgnored private let lastMapTrackingModeKey = "lastMapTrackingMode"
  @ObservationIgnored private let gloveModeEnabledKey = "gloveModeEnabled"
  @ObservationIgnored private let hasAcceptedDisclaimerKey = "hasAcceptedDisclaimer"
  @ObservationIgnored private let isOpenSeaMapOverlayEnabledKey = "isOpenSeaMapOverlayEnabled"
  @ObservationIgnored private let geoGarageUsernameKey = "geogarage_username"
  @ObservationIgnored private let geoGarageCustomerIDKey = "geogarage_customer_id"
  @ObservationIgnored private let pendingCAASDownloadsKey = "pendingCAASDownloads"
  @ObservationIgnored private let keychainManager: (any KeychainManaging)?

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

  @ObservationIgnored private let defaults: UserDefaults

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

  var savedTrackingMode: ChartTrackingMode? {
    didSet {
      if let value = savedTrackingMode {
        defaults.set(value.rawValue, forKey: savedTrackingModeKey)
      } else {
        defaults.removeObject(forKey: savedTrackingModeKey)
      }
    }
  }

  var lastMapTrackingMode: ChartTrackingMode? {
    didSet {
      if let value = lastMapTrackingMode {
        defaults.set(value.rawValue, forKey: lastMapTrackingModeKey)
      } else {
        defaults.removeObject(forKey: lastMapTrackingModeKey)
      }
    }
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
        keychainManager?.saveSync(token: value, for: GeoGarageKeychainKeys.customerID)
      } else {
        defaults.removeObject(forKey: geoGarageCustomerIDKey)
        keychainManager?.deleteTokenSync(for: GeoGarageKeychainKeys.customerID)
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

  var pendingCAASDownloads: [PendingCAASDownload] {
    didSet {
      if let data = try? JSONEncoder().encode(pendingCAASDownloads) {
        defaults.set(data, forKey: pendingCAASDownloadsKey)
      } else {
        defaults.removeObject(forKey: pendingCAASDownloadsKey)
      }
    }
  }

  var gpsAccuracyMode: GPSAccuracyMode {
    get { GPSAccuracyMode(rawValue: rawGPSAccuracyMode) ?? .best }
    set { rawGPSAccuracyMode = newValue.rawValue }
  }

  init(
    defaults: UserDefaults = .standard,
    keychainManager: (any KeychainManaging)? = nil
  ) {
    self.defaults = defaults
    self.keychainManager = keychainManager
    self.savedChartSource = defaults.string(forKey: chartSourceKey)
    self.savedGeoGarageLayerID = defaults.string(forKey: savedGeoGarageLayerIDKey)
    self.savedLatitude = defaults.object(forKey: savedLatitudeKey) as? Double
    self.savedLongitude = defaults.object(forKey: savedLongitudeKey) as? Double
    self.savedZoom = defaults.object(forKey: savedZoomKey) as? Double
    self.savedDirection = defaults.object(forKey: savedDirectionKey) as? Double
    self.savedTrackingMode = defaults.string(forKey: savedTrackingModeKey).flatMap { ChartTrackingMode(rawValue: $0) }
    self.lastMapTrackingMode = defaults.string(forKey: lastMapTrackingModeKey).flatMap { ChartTrackingMode(rawValue: $0) }
    self.gloveModeEnabled = defaults.bool(forKey: gloveModeEnabledKey)
    self.hasAcceptedDisclaimer = defaults.bool(forKey: hasAcceptedDisclaimerKey)
    self.isOpenSeaMapOverlayEnabled = defaults.bool(forKey: isOpenSeaMapOverlayEnabledKey)
    self.geoGarageUsername = defaults.string(forKey: geoGarageUsernameKey)

    let customerIDFromDefaults = defaults.string(forKey: geoGarageCustomerIDKey)
    let customerIDFromKeychain = keychainManager?.retrieveValidTokenSync(for: GeoGarageKeychainKeys.customerID)
    let resolvedCustomerID = customerIDFromDefaults ?? customerIDFromKeychain
    self.geoGarageCustomerID = resolvedCustomerID
    if customerIDFromDefaults == nil, let customerIDFromKeychain {
      defaults.set(customerIDFromKeychain, forKey: geoGarageCustomerIDKey)
    }
    if customerIDFromKeychain == nil, let customerIDFromDefaults {
      keychainManager?.saveSync(token: customerIDFromDefaults, for: GeoGarageKeychainKeys.customerID)
    }

    if let data = defaults.data(forKey: pendingCAASDownloadsKey),
       let list = try? JSONDecoder().decode([PendingCAASDownload].self, from: data) {
      self.pendingCAASDownloads = list
    } else {
      self.pendingCAASDownloads = []
    }

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

  func clearAll() {
    savedChartSource = nil
    savedGeoGarageLayerID = nil
    savedLatitude = nil
    savedLongitude = nil
    savedZoom = nil
    savedDirection = nil
    savedTrackingMode = nil
    lastMapTrackingMode = nil
    gloveModeEnabled = false
    hasAcceptedDisclaimer = false
    isOpenSeaMapOverlayEnabled = false
    geoGarageUsername = nil
    geoGarageCustomerID = nil
    pendingCAASDownloads = []
    isCOGVectorEnabled = true
    isCOGVectorTicksEnabled = true
    cogVectorTimeHorizon = Measurement(value: 3600, unit: .seconds)
    activeTrackSessionID = nil
    goToWaypointID = nil
    displayedTrackSessionID = nil
    isBaroAlarmEnabled = false
    baroAlarmSensitivity = .medium
    barometerOffset = Measurement(value: 0, unit: .hectopascals)
    savedAnchorRadius = Measurement(value: 25.0, unit: .meters)
    hudEditOpenCount = 0
    gpsAccuracyMode = .bestForNavigation
  }
}

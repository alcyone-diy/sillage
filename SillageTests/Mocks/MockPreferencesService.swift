//
//  MockPreferencesService.swift
//  Alcyone SillageTests
//
//  Created by Alcyone on 2026-10-18.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation
import Observation
@testable import Sillage

@Observable
@MainActor
final class MockPreferencesService: PreferencesServiceProtocol {
  var savedChartSource: String?
  var savedGeoGarageLayerID: String?
  var geoGarageUsername: String?
  var geoGarageCustomerID: String?
  var savedLatitude: Double?
  var savedLongitude: Double?
  var savedZoom: Double?
  var savedDirection: Double?
  var savedTrackingMode: ChartTrackingMode? = nil
  var lastMapTrackingMode: ChartTrackingMode? = nil
  var gloveModeEnabled: Bool = false
  var hasAcceptedDisclaimer: Bool = false
  var isOpenSeaMapOverlayEnabled: Bool = false
  var isCOGVectorEnabled: Bool = false
  var cogVectorTimeHorizon: Measurement<UnitDuration> = Measurement(value: 3600, unit: .seconds)
  var isCOGVectorTicksEnabled: Bool = false

  var savedCameraCoordinate: CLLocationCoordinate2D?
  var savedCameraZoom: Double?
  var savedCameraDirection: Double?

  func saveCameraState(coordinate: CLLocationCoordinate2D, zoom: Double, direction: Double) {
    savedCameraCoordinate = coordinate
    savedCameraZoom = zoom
    savedCameraDirection = direction
  }

  func loadCameraState() -> (coordinate: CLLocationCoordinate2D, zoom: Double, direction: Double)? {
    guard let coord = savedCameraCoordinate,
          let zoom = savedCameraZoom,
          let dir = savedCameraDirection else {
      return nil
    }
    return (coordinate: coord, zoom: zoom, direction: dir)
  }

  var activeTrackSessionID: String?
  func saveActiveTrackSessionID(_ id: String) {
    activeTrackSessionID = id
  }
  func clearActiveTrackSessionID() {
    activeTrackSessionID = nil
  }

  var goToWaypointID: String?
  var displayedTrackSessionID: String?

  var isBaroAlarmEnabled: Bool = false
  var baroAlarmSensitivity: BaroAlarmSensitivity = .medium
  var barometerOffset: Measurement<UnitPressure> = Measurement(value: 0, unit: .hectopascals)

  var savedAnchorRadius: Measurement<UnitLength> = Measurement(value: 25.0, unit: .meters)
  var hudEditOpenCount: Int = 0
  var gpsAccuracyMode: GPSAccuracyMode = .bestForNavigation
  var pendingCAASDownloads: [PendingCAASDownload] = []

  func clearAll() {
    savedChartSource = nil
    savedGeoGarageLayerID = nil
    geoGarageUsername = nil
    geoGarageCustomerID = nil
    savedLatitude = nil
    savedLongitude = nil
    savedZoom = nil
    savedDirection = nil
    savedTrackingMode = nil
    lastMapTrackingMode = nil
    gloveModeEnabled = false
    hasAcceptedDisclaimer = false
    isOpenSeaMapOverlayEnabled = false
    isCOGVectorEnabled = true
    cogVectorTimeHorizon = Measurement(value: 3600, unit: .seconds)
    isCOGVectorTicksEnabled = true
    savedCameraCoordinate = nil
    savedCameraZoom = nil
    savedCameraDirection = nil
    activeTrackSessionID = nil
    goToWaypointID = nil
    displayedTrackSessionID = nil
    isBaroAlarmEnabled = false
    baroAlarmSensitivity = .medium
    barometerOffset = Measurement(value: 0, unit: .hectopascals)
    savedAnchorRadius = Measurement(value: 25.0, unit: .meters)
    hudEditOpenCount = 0
    gpsAccuracyMode = .bestForNavigation
    pendingCAASDownloads = []
  }
}

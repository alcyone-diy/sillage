//
//  MapViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Combine
import CoreLocation
import SwiftUI

class MapViewModel: ObservableObject {

  @Published var isTrackingUser: Bool = false
  @Published var currentMapSource: MapSource?
  @Published var mapBounds: MBTilesBounds?
  @Published var maxZoom: Double?
  @Published var minZoom: Double?
  @Published var availableGeoGarageLayers: [GeoGarageLayer] = []
  @Published var localOfflineMaps: [URL] = []
  @Published var mapImportError: String?
  @Published var showImportError: Bool = false

  // Current Map State
  @Published var centerCoordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)
  @Published var zoomLevel: Double = 10.0
  @Published var mapDirection: Double = 0.0

  // UI Properties
  @Published var formattedCoordinates: String = "--"
  @Published var formattedSOG: String = "-- kts"
  @Published var formattedCOG: String = "--°"

  private var mapLayer: MapLayer?
  private let locationService: LocationServiceProtocol
  private var cancellables = Set<AnyCancellable>()

  // Publisher to trigger a one-off camera animation to a specific location
  // We optionally pass a target zoom level if we want a specific viewport
  let cameraMovePublisher = PassthroughSubject<(CLLocationCoordinate2D, Double?), Never>()

  // Store the last received location to center on it when requested
  private var lastKnownLocation: CLLocation?

  private var preferencesService: PreferencesServiceProtocol
  private let authService: GeoGarageAuthServiceProtocol

  init(locationService: LocationServiceProtocol = LocationService.shared,
       preferencesService: PreferencesServiceProtocol = PreferencesService.shared,
       authService: GeoGarageAuthServiceProtocol = GeoGarageAuthService()) {
    self.locationService = locationService
    self.preferencesService = preferencesService
    self.authService = authService

    loadSavedMapSource()
    setupLocationService()
    silentlyFetchGeoGarageLayers()
    loadLocalOfflineMaps()
  }

  private func loadLocalOfflineMaps() {
    Task {
      let maps = await LocalMapManager.shared.fetchLocalMaps()
      await MainActor.run {
        self.localOfflineMaps = maps
      }
    }
  }

  func importOfflineMap(from url: URL) {
    Task {
      do {
        let importedURL = try await LocalMapManager.shared.importMap(from: url)
        await MainActor.run {
          self.localOfflineMaps.append(importedURL)
          self.switchMapSource(to: .localMBTiles(url: importedURL))
        }
      } catch {
        await MainActor.run {
          self.mapImportError = error.localizedDescription
          self.showImportError = true
        }
      }
    }
  }

  func updateGeoGarageLayers(_ layers: [GeoGarageLayer]) {
    self.availableGeoGarageLayers = layers
  }

  private func silentlyFetchGeoGarageLayers() {
    guard let accessToken = KeychainManager.shared.retrieveToken(for: "geogarage_access_token") else {
      return
    }

    Task.detached { [weak self] in
      guard let self = self else { return }
      do {
        let settings = try await self.authService.fetchAccountSettings(accessToken: accessToken)
        await MainActor.run {
          self.availableGeoGarageLayers = settings.layers
        }
      } catch {
        print("Silent fetch of GeoGarage layers failed: \(error)")
      }
    }
  }

  private func setupLocationService() {
    locationService.locationPublisher
      .throttle(for: .seconds(1), scheduler: DispatchQueue.main, latest: true)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] location in
        self?.handleNewLocation(location)
      }
      .store(in: &cancellables)

    locationService.requestAuthorization()
  }

  private func handleNewLocation(_ location: CLLocation) {
    if location.horizontalAccuracy < 0 || location.horizontalAccuracy > 50 {
      return
    }

    lastKnownLocation = location

    // Update formatted coordinates (Degrees, Minutes, Decimals)
    let lat = formatCoordinate(location.coordinate.latitude, isLatitude: true)
    let lon = formatCoordinate(location.coordinate.longitude, isLatitude: false)
    formattedCoordinates = "\(lat) / \(lon)"

    // Update SOG (m/s to knots) using Apple's Measurement
    let speed = location.speed
    if speed >= 0 {
      let speedMeasurement = Measurement(value: speed, unit: UnitSpeed.metersPerSecond)
      let speedInKnots = speedMeasurement.converted(to: .knots).value
      formattedSOG = String(format: "%.1f kts", speedInKnots)
    } else {
      formattedSOG = "-- kts"
    }

    // Update COG
    let course = location.course
    if course >= 0 {
      formattedCOG = String(format: "%.0f°", course)
    } else {
      formattedCOG = "--°"
    }

    // If tracking is active, recenter on the new location automatically
    if isTrackingUser {
      centerOnUserLocation()
    }
  }

  func switchMapSource(to source: MapSource) {
    self.currentMapSource = source

    switch source {
    case .localMBTiles(let url):
      // Extract the filename without extension, e.g., "7413_pal300"
      let fileName = url.deletingPathExtension().lastPathComponent
      preferencesService.savedMapSource = fileName

      self.mapLayer = MapLayer(name: LocalizedStringResource("Marine Raster Chart"), source: source)
      let metadata = MBTilesHelper.extractMetadata(from: url)
      if let bounds = metadata.bounds { self.mapBounds = bounds }
      if let minZ = metadata.minZoom { self.minZoom = minZ }
      if let maxZ = metadata.maxZoom { self.maxZoom = maxZ }

      // Only use map defaults if we do not already have a valid loaded state
      if preferencesService.savedLatitude == nil {
        if let center = metadata.center { self.centerCoordinate = center }
        if let zoom = metadata.defaultZoom { self.zoomLevel = zoom }
      }

    case .remoteGeoGarage(_, let layerID):
      preferencesService.savedMapSource = "remoteGeoGarage"
      preferencesService.savedGeoGarageLayerID = layerID

      self.mapLayer = MapLayer(name: LocalizedStringResource("GeoGarage Marine Chart"), source: source)
      self.mapBounds = nil
      self.minZoom = 0.0
      self.maxZoom = 20.0

      // Only use map defaults if we do not already have a valid loaded state
      if preferencesService.savedLatitude == nil {
        self.zoomLevel = 10.0
        if let location = lastKnownLocation {
          self.centerCoordinate = location.coordinate
        }
      }
    }
  }

  func mapInteractedByUser() {
    if isTrackingUser {
      isTrackingUser = false
    }
  }

  private func formatCoordinate(_ degrees: CLLocationDegrees, isLatitude: Bool) -> String {
    let direction = isLatitude ? (degrees >= 0 ? "N" : "S") : (degrees >= 0 ? "E" : "W")
    let absDegrees = abs(degrees)
    let intDegrees = Int(absDegrees)
    let minutes = (absDegrees - Double(intDegrees)) * 60.0

    return String(format: "%02d°%06.3f' %@", intDegrees, minutes, direction)
  }

  func activateTracking() {
    print("Recenter button tapped. Tracking activated.")
    isTrackingUser = true
    centerOnUserLocation()
  }

  func centerOnUserLocation() {
    guard let location = lastKnownLocation else {
      print("Cannot center: lastKnownLocation is nil. Waiting for a valid GPS fix from LocationService.")
      return
    }

    // Sending a high zoom level like 18.0, which roughly corresponds to ~50m visibility.
    // We clamp it to the map's maxZoom if available to avoid the "white screen" issue
    // caused by requesting a zoom level where no raster tiles exist.
    var targetZoom = 18.0
    if let maxZ = self.maxZoom, targetZoom > maxZ {
      targetZoom = maxZ
    }

    cameraMovePublisher.send((location.coordinate, targetZoom))
  }

  func saveCameraState() {
    preferencesService.saveCameraState(coordinate: centerCoordinate, zoom: zoomLevel, direction: mapDirection)
  }

  func loadSavedCameraState() {
    if let state = preferencesService.loadCameraState() {
      self.centerCoordinate = state.coordinate
      self.zoomLevel = state.zoom
      self.mapDirection = state.direction
    }
  }

  private func loadMBTilesData() {
    // Search for the file in the application Bundle
    guard let url = Bundle.main.url(forResource: "7413_pal300", withExtension: "mbtiles") else {
      print("Error: The file 7413_pal300.mbtiles was not found in the Bundle.")
      return
    }

    switchMapSource(to: .localMBTiles(url: url))
  }

  private func loadSavedMapSource() {
    let savedSource = preferencesService.savedMapSource

    if savedSource == "remoteGeoGarage", let savedLayerID = preferencesService.savedGeoGarageLayerID {
      switchMapSource(to: .remoteGeoGarage(clientID: AppConfiguration.shared.geoGarageClientID, layerID: savedLayerID))
    } else if let savedFileName = savedSource,
            let url = Bundle.main.url(forResource: savedFileName, withExtension: "mbtiles") {
      switchMapSource(to: .localMBTiles(url: url))
    } else {
      // Default to the predefined local MBTiles
      loadMBTilesData()
    }

    // Ensure camera state overrides any defaults populated by switchMapSource
    loadSavedCameraState()
  }
}

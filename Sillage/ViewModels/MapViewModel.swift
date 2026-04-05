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

  // Current Map State
  @Published var centerCoordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)
  @Published var zoomLevel: Double = 10.0
  @Published var mapDirection: Double = 0.0

  // UI Properties
  @Published var formattedCoordinates: String = "--"
  @Published var speedOverGround: Double = 0.0 // knots
  @Published var courseOverGround: Double = 0.0 // degrees

  private var mapLayer: MapLayer?
  private let locationService: LocationServiceProtocol
  private var cancellables = Set<AnyCancellable>()

  // Publisher to trigger a one-off camera animation to a specific location
  // We optionally pass a target zoom level if we want a specific viewport
  let cameraMovePublisher = PassthroughSubject<(CLLocationCoordinate2D, Double?), Never>()

  // Store the last received location to center on it when requested
  private var lastKnownLocation: CLLocation?

  private var preferencesService: PreferencesServiceProtocol

  init(locationService: LocationServiceProtocol = LocationService.shared,
     preferencesService: PreferencesServiceProtocol = PreferencesService.shared) {
    self.locationService = locationService
    self.preferencesService = preferencesService

    loadSavedMapSource()
    setupLocationService()
  }

  private func setupLocationService() {
    locationService.locationPublisher
      .receive(on: DispatchQueue.main)
      .sink { [weak self] location in
        self?.handleNewLocation(location)
      }
      .store(in: &cancellables)

    locationService.requestAuthorization()
  }

  private func handleNewLocation(_ location: CLLocation) {
    lastKnownLocation = location

    // Update formatted coordinates (Degrees, Minutes, Decimals)
    let lat = formatCoordinate(location.coordinate.latitude, isLatitude: true)
    let lon = formatCoordinate(location.coordinate.longitude, isLatitude: false)
    formattedCoordinates = "\(lat) / \(lon)"

    // Update SOG (m/s to knots)
    let speed = location.speed
    if speed >= 0 {
      speedOverGround = speed * 1.94384
    }

    // Update COG
    let course = location.course
    if course >= 0 {
      courseOverGround = course
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

      self.mapLayer = MapLayer(name: "Marine Raster Chart", source: source)
      let metadata = MBTilesHelper.extractMetadata(from: url)
      if let bounds = metadata.bounds { self.mapBounds = bounds }
      if let minZ = metadata.minZoom { self.minZoom = minZ }
      if let maxZ = metadata.maxZoom { self.maxZoom = maxZ }

      // Only use map defaults if we do not already have a valid loaded state
      if preferencesService.savedLatitude == nil {
        if let center = metadata.center { self.centerCoordinate = center }
        if let zoom = metadata.defaultZoom { self.zoomLevel = zoom }
      }

    case .remoteGeoGarage:
      preferencesService.savedMapSource = "remoteGeoGarage"

      self.mapLayer = MapLayer(name: "GeoGarage Marine Chart", source: source)
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

    if savedSource == "remoteGeoGarage" {
      switchMapSource(to: .remoteGeoGarage(clientID: Secrets.geoGarageClientID, layerID: Secrets.geoGarageLayerID))
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

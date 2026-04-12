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
import CoreLocation
import SwiftUI
import Observation
import MapLibre

struct CameraMoveEvent {
  let coordinate: CLLocationCoordinate2D
  let zoom: Double?
  let heading: Measurement<UnitAngle>?
}

enum MapTrackingMode {
  case free
  case northUp
  case courseUp
}


@Observable
@MainActor
class MapViewModel {

  var trackingMode: MapTrackingMode = .free
  var currentMapSource: MapSource?
  var mapBounds: MBTilesBounds?
  var maxZoom: Double?
  var minZoom: Double?
  var availableGeoGarageLayers: [GeoGarageLayer] = []
  var localOfflineMaps: [URL] = []
  var mapImportError: String?
  var showImportError: Bool = false
  var isOpenSeaMapOverlayEnabled: Bool = false {
    didSet {
      preferencesService.isOpenSeaMapOverlayEnabled = isOpenSeaMapOverlayEnabled
    }
  }

  // Current Map State
  var centerCoordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)
  var zoomLevel: Double = 10.0
  var mapDirection: Measurement<UnitAngle> = Measurement(value: 0.0, unit: UnitAngle.degrees)

  // UI Properties
  var formattedCoordinates: String = "--"
  var speedOverGround: Measurement<UnitSpeed>? = nil
  var courseOverGround: Measurement<UnitAngle>? = nil

  // Navigation Constants
  let infiniteCOGVectorDistance = Measurement<UnitLength>(value: 2000, unit: .nauticalMiles)

  // Vessel Tracking Features
  var vesselFeature: MLNPointFeature?
  var headingVectorFeature: MLNShapeCollectionFeature?
  var gpsAccuracyFeature: MLNPolygonFeature?
  var isDataStale: Bool = true

  private var mapLayer: MapLayer?
  private var staleDataTask: Task<Void, Never>?
  private var locationUpdatesTask: Task<Void, Never>?
  private let locationService: LocationServiceProtocol

  // Multicast Stream for Camera Move Events
  private var cameraMoveContinuations: [UUID: AsyncStream<CameraMoveEvent>.Continuation] = [:]
  var cameraMoveStream: AsyncStream<CameraMoveEvent> {
    let (stream, continuation) = AsyncStream.makeStream(of: CameraMoveEvent.self)
    let id = UUID()
    // We are on @MainActor, no lock needed
    cameraMoveContinuations[id] = continuation

    continuation.onTermination = { [weak self] _ in
      guard let self = self else { return }
      Task { @MainActor in
        self.cameraMoveContinuations.removeValue(forKey: id)
      }
    }
    return stream
  }

  // Store the last received location to center on it when requested
  private var lastKnownLocation: CLLocation?

  private var preferencesService: PreferencesServiceProtocol
  private let authService: GeoGarageAuthServiceProtocol

  @MainActor
  init(locationService: LocationServiceProtocol? = nil,
       preferencesService: PreferencesServiceProtocol? = nil,
       authService: GeoGarageAuthServiceProtocol? = nil) {
    self.locationService = locationService ?? LocationService.shared
    self.preferencesService = preferencesService ?? PreferencesService.shared
    self.authService = authService ?? GeoGarageAuthService()
    self.isOpenSeaMapOverlayEnabled = self.preferencesService.isOpenSeaMapOverlayEnabled

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
    let service = self.locationService
    locationUpdatesTask = Task { [weak self] in
      let clock = ContinuousClock()
      // Initialize to past to allow the first event to pass immediately
      var lastProcessedTime = clock.now.advanced(by: .seconds(-2))

      // locationService.locationUpdates creates a new stream on access
      for await location in service.locationUpdates {
        guard !Task.isCancelled else { break }

        let now = clock.now
        if now.duration(to: lastProcessedTime) > .seconds(-1) {
          continue
        }
        lastProcessedTime = now

        await MainActor.run {
          self?.handleNewLocation(location)
        }
      }
    }

    locationService.requestAuthorization()
  }

  private func handleNewLocation(_ location: CLLocation) {
    if location.horizontalAccuracy < 0 || location.horizontalAccuracy > 50 {
      speedOverGround = nil
      courseOverGround = nil
      return
    }

    lastKnownLocation = location

    // Reset stale data task
    self.isDataStale = false
    self.staleDataTask?.cancel()
    self.staleDataTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
      guard !Task.isCancelled else { return }
      self?.isDataStale = true
    }

    // Update formatted coordinates (Degrees, Minutes, Decimals)
    let lat = formatCoordinate(location.coordinate.latitude, isLatitude: true)
    let lon = formatCoordinate(location.coordinate.longitude, isLatitude: false)
    formattedCoordinates = "\(lat) / \(lon)"

    // Update SOG using Apple's Measurement
    let speed = location.speed
    if speed >= 0 {
      speedOverGround = Measurement(value: speed, unit: UnitSpeed.metersPerSecond)
    } else {
      speedOverGround = nil
    }

    // Update COG
    let course = location.course
    if course >= 0 {
      courseOverGround = Measurement(value: course, unit: UnitAngle.degrees)
    } else {
      courseOverGround = nil
    }

    // Update Vessel Feature
    let feature = MLNPointFeature()
    feature.coordinate = location.coordinate
    var attributes: [String: Any] = [:]
    if let cog = courseOverGround {
      attributes["course"] = cog.converted(to: .degrees).value
    }
    feature.attributes = attributes
    self.vesselFeature = feature

    // Update Heading Vector Feature
    self.headingVectorFeature = generateHeadingVector(location: location)

    // Update GPS Accuracy Polygon Feature
    if location.horizontalAccuracy > 0 {
      let accuracyMeasurement = Measurement(value: location.horizontalAccuracy, unit: UnitLength.meters)
      if var accuracyCoords = location.coordinate.accuracyPolygon(radius: accuracyMeasurement) {
        self.gpsAccuracyFeature = MLNPolygonFeature(coordinates: &accuracyCoords, count: UInt(accuracyCoords.count))
      } else {
        self.gpsAccuracyFeature = nil
      }
    } else {
      self.gpsAccuracyFeature = nil
    }

    // Push explicit camera updates if tracking
    if trackingMode != .free {
      let heading = (trackingMode == .courseUp && course >= 0) ? courseOverGround : Measurement(value: 0.0, unit: UnitAngle.degrees)
      let event = CameraMoveEvent(coordinate: location.coordinate, zoom: nil, heading: heading)
      for continuation in cameraMoveContinuations.values {
        continuation.yield(event)
      }
    }
  }

  private func generateHeadingVector(location: CLLocation) -> MLNShapeCollectionFeature? {
    guard let sogMeasurement = speedOverGround, let cog = courseOverGround, location.speed > 0 else {
      return nil
    }

    // Hide vector if speed is less than 0.5 knots
    let sogKnots = sogMeasurement.converted(to: .knots).value
    if sogKnots < 0.5 {
      return nil
    }

    let speedInMetersPerSecond = location.speed
    // 1 hour distance
    let segmentDistanceMeters = speedInMetersPerSecond * 3600.0
    let segmentDistance = Measurement<UnitLength>(value: segmentDistanceMeters, unit: .meters)

    var shapes: [MLNPolylineFeature] = []
    var currentStart = location.coordinate

    for i in 0..<10 {
      guard let currentEnd = currentStart.rhumbCoordinate(atDistance: segmentDistance, bearing: cog) else {
        break
      }
      var segmentCoordinates = [currentStart, currentEnd]

      let segmentFeature = MLNPolylineFeature(coordinates: &segmentCoordinates, count: UInt(segmentCoordinates.count))
      segmentFeature.attributes = ["colorIndex": i % 2]
      shapes.append(segmentFeature)

      currentStart = currentEnd
    }

    // Add 11th "infinite" planning segment
    if let infiniteEnd = currentStart.rhumbCoordinate(atDistance: infiniteCOGVectorDistance, bearing: cog) {
      var infiniteCoordinates = [currentStart, infiniteEnd]
      let infiniteFeature = MLNPolylineFeature(coordinates: &infiniteCoordinates, count: UInt(infiniteCoordinates.count))
      infiniteFeature.attributes = ["colorIndex": 2]
      shapes.append(infiniteFeature)
    }

    return MLNShapeCollectionFeature(shapes: shapes)
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

      resetToDefaultsIfNeeded(defaultZoom: metadata.defaultZoom ?? 10.0, defaultCenter: metadata.center)

    case .remoteGeoGarage(_, let layerID):
      preferencesService.savedMapSource = "remoteGeoGarage"
      preferencesService.savedGeoGarageLayerID = layerID

      self.mapLayer = MapLayer(name: LocalizedStringResource("GeoGarage Marine Chart"), source: source)
      self.mapBounds = nil
      self.minZoom = 0.0
      self.maxZoom = 20.0

      resetToDefaultsIfNeeded(defaultZoom: 10.0, defaultCenter: lastKnownLocation?.coordinate)

    case .openSeaMap:
      preferencesService.savedMapSource = "openSeaMap"
      self.mapLayer = MapLayer(name: LocalizedStringResource("OpenSeaMap"), source: source)
      self.mapBounds = nil
      self.minZoom = 0.0
      self.maxZoom = 18.0

      resetToDefaultsIfNeeded(defaultZoom: 10.0, defaultCenter: lastKnownLocation?.coordinate)
    }
  }

  private func resetToDefaultsIfNeeded(defaultZoom: Double, defaultCenter: CLLocationCoordinate2D?) {
    // Only use map defaults if we do not already have a valid loaded state
    if preferencesService.savedLatitude == nil {
      self.zoomLevel = defaultZoom
      if let center = defaultCenter {
        self.centerCoordinate = center
      }
    }
  }

  func mapInteractedByUser() {
    trackingMode = .free
  }

  private func formatCoordinate(_ degrees: CLLocationDegrees, isLatitude: Bool) -> String {
    let direction = isLatitude ? (degrees >= 0 ? "N" : "S") : (degrees >= 0 ? "E" : "W")
    let absDegrees = abs(degrees)
    let intDegrees = Int(absDegrees)
    let minutes = (absDegrees - Double(intDegrees)) * 60.0

    return String(format: "%02d°%06.3f' %@", intDegrees, minutes, direction)
  }

  func toggleTrackingMode() {
    switch trackingMode {
    case .free, .courseUp:
      trackingMode = .northUp
    case .northUp:
      trackingMode = .courseUp
    }

    if trackingMode != .free, let location = lastKnownLocation {
      let course = location.course
      let heading = (trackingMode == .courseUp && course >= 0) ? Measurement(value: course, unit: UnitAngle.degrees) : Measurement(value: 0.0, unit: UnitAngle.degrees)
      let event = CameraMoveEvent(coordinate: location.coordinate, zoom: nil, heading: heading)
      for continuation in cameraMoveContinuations.values {
        continuation.yield(event)
      }
    }
  }

  func centerOnUserLocation() {
    guard let location = lastKnownLocation else {
      print("Cannot center: lastKnownLocation is nil. Waiting for a valid GPS fix from LocationService.")
      return
    }

    // Pass `nil` for zoomLevel to allow MapLibreView to use `mapView.zoomLevel` and preserve it.
    let course = location.course
    let heading = (trackingMode == .courseUp && course >= 0) ? Measurement(value: course, unit: UnitAngle.degrees) : Measurement(value: 0.0, unit: UnitAngle.degrees)
    let event = CameraMoveEvent(coordinate: location.coordinate, zoom: nil, heading: heading)
    for continuation in cameraMoveContinuations.values {
      continuation.yield(event)
    }
  }

  func saveCameraState() {
    preferencesService.saveCameraState(coordinate: centerCoordinate, zoom: zoomLevel, direction: mapDirection.converted(to: .degrees).value)
  }

  func loadSavedCameraState() {
    if let state = preferencesService.loadCameraState() {
      self.centerCoordinate = state.coordinate
      self.zoomLevel = state.zoom
      self.mapDirection = Measurement(value: state.direction, unit: UnitAngle.degrees)
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
      // Default to OpenSeaMap.
      switchMapSource(to: .openSeaMap)
    }

    // Ensure camera state overrides any defaults populated by switchMapSource
    loadSavedCameraState()
  }
}

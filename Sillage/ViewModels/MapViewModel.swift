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

/// Represents a camera movement instruction to be consumed by the UI layer.
struct CameraMoveEvent {
  let coordinate: CLLocationCoordinate2D
  let zoom: Double?
  let heading: Measurement<UnitAngle>?
}

/// Defines how the map camera should behave relative to the user's location and orientation.
enum MapTrackingMode {
  case free
  case northUp
  case courseUp
}

/// The central state manager for the map interface.
/// It handles location updates, map source switching, and coordinates camera movements.
@Observable
@MainActor
class MapViewModel {

  // MARK: - Core State
  
  var trackingMode: MapTrackingMode = .free
  var currentMapSource: MapSource?
  var mapBounds: MBTilesBounds?
  var maxZoom: Double?
  var minZoom: Double?
  
  // MARK: - Map Sources Data
  
  var availableGeoGarageLayers: [GeoGarageLayer] = []
  
  /// Represents locally stored MBTiles files.
  /// This array is automatically kept in sync with the file system by the ChartStorageService.
  var localOfflineMaps: [MBTileFile] = []
  
  var mapImportError: String?
  var showImportError: Bool = false
  
  var isOpenSeaMapOverlayEnabled: Bool = false {
    didSet {
      preferencesService.isOpenSeaMapOverlayEnabled = isOpenSeaMapOverlayEnabled
    }
  }

  // MARK: - Map Camera State
  
  var centerCoordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)
  var zoomLevel: Double = 10.0
  var mapDirection: Measurement<UnitAngle> = Measurement(value: 0.0, unit: UnitAngle.degrees)

  // MARK: - Navigation & Telemetry
  
  var currentCoordinate: CLLocationCoordinate2D? = nil
  var speedOverGround: Measurement<UnitSpeed>? = nil
  var courseOverGround: Measurement<UnitAngle>? = nil

  /// The default length for the infinite course over ground (COG) projection.
  let infiniteCOGVectorDistance = Measurement<UnitLength>(value: 2000, unit: .nauticalMiles)

  // MARK: - Map Features (Annotations)
  
  var vesselFeature: MLNPointFeature?
  var headingVectorFeature: MLNShapeCollectionFeature?
  var gpsAccuracyFeature: MLNPolygonFeature?
  var isDataStale: Bool = true

  // MARK: - Private Services & Tasks
  
  private var mapLayer: MapLayer?
  private let locationService: LocationServiceProtocol
  private let chartStorageService = ChartStorageService()
  private var preferencesService: PreferencesServiceProtocol
  private let authService: GeoGarageAuthServiceProtocol

  /// TaskCancellable wrappers ensure that async tasks are automatically cancelled
  /// when the ViewModel is deallocated, adhering to Swift 6 strict concurrency rules
  /// without requiring a non-isolated `deinit`.
  private var staleDataTask: TaskCancellable?
  private var locationUpdatesTask: TaskCancellable?
  private var observationTask: TaskCancellable?

  // MARK: - Camera Multicast Stream
  
  private var cameraMoveContinuations: [UUID: AsyncStream<CameraMoveEvent>.Continuation] = [:]
  
  /// Exposes a multicast stream for camera events.
  /// Multiple UI components (like MapLibreView) can subscribe to this stream to react to pan/zoom commands.
  var cameraMoveStream: AsyncStream<CameraMoveEvent> {
    let (stream, continuation) = AsyncStream.makeStream(of: CameraMoveEvent.self)
    let id = UUID()
    cameraMoveContinuations[id] = continuation

    continuation.onTermination = { [weak self] _ in
      guard let self = self else { return }
      Task { @MainActor in
        self.cameraMoveContinuations.removeValue(forKey: id)
      }
    }
    return stream
  }

  /// Stores the last received GPS fix to allow instant recentering when requested.
  private var lastKnownLocation: CLLocation?

  // MARK: - Initialization

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
    startObservingLocalMaps()
  }

  // MARK: - Data Observation & Management

  /// Starts a background listener for local file system changes in the Charts directory.
  private func startObservingLocalMaps() {
    observationTask = TaskCancellable(Task { [weak self] in
      guard let self = self else { return }
      for await files in await self.chartStorageService.observeMBTilesDirectory() {
        await MainActor.run {
          self.localOfflineMaps = files
        }
      }
    })
  }

  /// Initiates the asynchronous import of an MBTiles file and switches the map to it upon success.
  func importOfflineMap(from url: URL) {
    Task {
      do {
        let importedURL = try await LocalMapManager.shared.importMap(from: url)
        await MainActor.run {
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

  /// Authenticates with GeoGarage in the background using stored credentials to populate available layers.
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

  // MARK: - Location Handling

  /// Subscribes to the location service stream, applying a 1-second throttle to UI updates to prevent overloading.
  private func setupLocationService() {
    let service = self.locationService
    
    locationUpdatesTask = TaskCancellable(Task { [weak self] in
      let clock = ContinuousClock()
      var lastProcessedTime = clock.now.advanced(by: .seconds(-2))

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
    })

    locationService.requestAuthorization()
  }

  /// Processes a new GPS fix, updating telemetry measurements, map features, and camera position if tracking is enabled.
  private func handleNewLocation(_ location: CLLocation) {
    // Discard highly inaccurate fixes
    if location.horizontalAccuracy < 0 || location.horizontalAccuracy > 50 {
      speedOverGround = nil
      courseOverGround = nil
      return
    }

    lastKnownLocation = location

    // Reset the stale data timer. If no new location is received within 5 seconds, UI will indicate stale data.
    self.isDataStale = false
    self.staleDataTask?.cancel()
    self.staleDataTask = TaskCancellable(Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 5_000_000_000)
      guard !Task.isCancelled else { return }
      self?.isDataStale = true
    })

    // Update current coordinate
    currentCoordinate = location.coordinate

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

    // Generate Map Annotations
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
    self.gpsAccuracyFeature = generateAccuracyFeature(for: location)

    // Broadcast camera move if actively tracking the user
    if trackingMode != .free {
      let heading = (trackingMode == .courseUp && course >= 0) ? courseOverGround : Measurement(value: 0.0, unit: UnitAngle.degrees)
      let event = CameraMoveEvent(coordinate: location.coordinate, zoom: nil, heading: heading)
      for continuation in cameraMoveContinuations.values {
        continuation.yield(event)
      }
    }
  }

  /// Generates a visual polyline representing the vessel's projected path based on current Speed and Course.
  /// The path is divided into 1-hour segments.
  private func generateHeadingVector(location: CLLocation) -> MLNShapeCollectionFeature? {
    guard let sogMeasurement = speedOverGround, let cog = courseOverGround, location.speed > 0 else {
      return nil
    }

    // Hide the vector at negligible speeds to avoid erratic UI behavior
    let sogKnots = sogMeasurement.converted(to: .knots).value
    if sogKnots < 0.5 {
      return nil
    }

    let speedInMetersPerSecond = location.speed
    let segmentDistanceMeters = speedInMetersPerSecond * 3600.0 // Distance covered in 1 hour
    let segmentDistance = Measurement<UnitLength>(value: segmentDistanceMeters, unit: .meters)

    var shapes: [MLNPolylineFeature] = []
    var currentStart = location.coordinate

    // Create 10 fixed-time segments
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

    // Append the final "infinite" line segment for long-distance projection
    if let infiniteEnd = currentStart.rhumbCoordinate(atDistance: infiniteCOGVectorDistance, bearing: cog) {
      var infiniteCoordinates = [currentStart, infiniteEnd]
      let infiniteFeature = MLNPolylineFeature(coordinates: &infiniteCoordinates, count: UInt(infiniteCoordinates.count))
      infiniteFeature.attributes = ["colorIndex": 2]
      shapes.append(infiniteFeature)
    }

    return MLNShapeCollectionFeature(shapes: shapes)
  }

  /// Generates a circle polygon around the user's location indicating GPS horizontal accuracy.
  private func generateAccuracyFeature(for location: CLLocation) -> MLNPolygonFeature? {
    guard location.horizontalAccuracy > 0 else {
      return nil
    }

    let accuracyMeasurement = Measurement(value: location.horizontalAccuracy, unit: UnitLength.meters)
    guard var accuracyCoords = location.coordinate.accuracyPolygon(radius: accuracyMeasurement) else {
      return nil
    }

    return MLNPolygonFeature(coordinates: &accuracyCoords, count: UInt(accuracyCoords.count))
  }

  // MARK: - Map State Management

  /// Changes the active map source and reconfigures map limits (bounds, zoom) accordingly.
  func switchMapSource(to source: MapSource) {
    self.currentMapSource = source

    switch source {
    case .localMBTiles(let url):
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

  /// Applies default map position settings only if the user hasn't previously saved a camera state.
  private func resetToDefaultsIfNeeded(defaultZoom: Double, defaultCenter: CLLocationCoordinate2D?) {
    if preferencesService.savedLatitude == nil {
      self.zoomLevel = defaultZoom
      if let center = defaultCenter {
        self.centerCoordinate = center
      }
    }
  }

  // MARK: - User Interactions

  /// Called when the user manually pans or zooms the map, breaking any active tracking lock.
  func mapInteractedByUser() {
    trackingMode = .free
  }

  /// Cycles through available camera tracking modes (Free -> North Up -> Course Up).
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

  /// Forces the map camera to jump to the user's last known location.
  func centerOnUserLocation() {
    guard let location = lastKnownLocation else {
      print("Cannot center: lastKnownLocation is nil. Waiting for a valid GPS fix from LocationService.")
      return
    }

    let course = location.course
    let heading = (trackingMode == .courseUp && course >= 0) ? Measurement(value: course, unit: UnitAngle.degrees) : Measurement(value: 0.0, unit: UnitAngle.degrees)
    let event = CameraMoveEvent(coordinate: location.coordinate, zoom: nil, heading: heading)
    for continuation in cameraMoveContinuations.values {
      continuation.yield(event)
    }
  }

  // MARK: - Persistence

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

  /// Restores the previously selected map source upon application launch.
  /// It verifies file existence in the Documents directory and falls back appropriately.
  private func loadSavedMapSource() {
    let savedSource = preferencesService.savedMapSource

    if savedSource == "remoteGeoGarage", let savedLayerID = preferencesService.savedGeoGarageLayerID {
      switchMapSource(to: .remoteGeoGarage(clientID: AppConfiguration.shared.geoGarageClientID, layerID: savedLayerID))
      
    } else if let savedFileName = savedSource {
      let fileManager = FileManager.default
      if let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
        let chartURL = documentsDirectory
          .appendingPathComponent("Charts")
          .appendingPathComponent(savedFileName)
          .appendingPathExtension("mbtiles")
        
        if fileManager.fileExists(atPath: chartURL.path) {
          switchMapSource(to: .localMBTiles(url: chartURL))
        } else if let bundleURL = Bundle.main.url(forResource: savedFileName, withExtension: "mbtiles") {
          // Fallback to internal app bundle if the map is a shipped default
          switchMapSource(to: .localMBTiles(url: bundleURL))
        } else {
          switchMapSource(to: .openSeaMap)
        }
      } else {
        switchMapSource(to: .openSeaMap)
      }
    } else {
      switchMapSource(to: .openSeaMap)
    }

    loadSavedCameraState()
  }
}

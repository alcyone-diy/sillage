//
//  MapViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation
import SwiftUI
import Observation
import MapLibre
import OSLog

/// Represents a camera movement instruction to be consumed by the UI layer.
enum CameraMoveEvent {
  case center(coordinate: CLLocationCoordinate2D, zoom: Double?, heading: Measurement<UnitAngle>?)
  case fitBounds(bounds: MLNCoordinateBounds, padding: UIEdgeInsets)
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
  var bearingToWaypoint: Measurement<UnitAngle>? = nil
  
  // MARK: - Map Features (Annotations)
  
  var vesselFeature: MLNPointFeature?
  var headingVectorFeature: MLNShapeCollectionFeature?
  var gpsAccuracyFeature: MLNPolygonFeature?
  var savedTrackFeature: MLNShape?
  var selectedWaypointFeature: MLNPointFeature?
  var visibleWaypointFeatures: MLNShapeCollectionFeature?
  var isDataStale: Bool = true
  
  // MARK: - Private Services & Tasks
  
  private var mapLayer: MapLayer?
  private let positioningService: PositioningService
  private let chartStorageService = ChartStorageService()
  private var preferencesService: PreferencesServiceProtocol
  private let authService: GeoGarageAuthServiceProtocol
  private let waypointService: WaypointService?
  
  /// TaskCancellable wrappers ensure that async tasks are automatically cancelled
  /// when the ViewModel is deallocated, adhering to Swift 6 strict concurrency rules
  /// without requiring a non-isolated `deinit`.
  private var staleDataTask: TaskCancellable?
  private var locationUpdatesTask: TaskCancellable?
  private var observationTask: TaskCancellable?
  private var waypointSelectionTask: TaskCancellable?
  private var waypointsObservationTask: TaskCancellable?
  
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
  private var lastKnownNavigationFix: NavigationFix?
  
  // MARK: - Initialization
  
  @MainActor
  init(
    positioningService: PositioningService,
    preferencesService: PreferencesServiceProtocol,
    authService: GeoGarageAuthServiceProtocol,
    waypointService: WaypointService? = nil
  ) {
    self.positioningService = positioningService
    self.preferencesService = preferencesService
    self.authService = authService
    self.waypointService = waypointService
    self.isOpenSeaMapOverlayEnabled = self.preferencesService.isOpenSeaMapOverlayEnabled
    
    loadSavedMapSource()
    setupPositioningService()
    setupWaypointService()
    silentlyFetchGeoGarageLayers()
    startObservingLocalMaps()
    observePreferences()
  }
  
  // MARK: - Data Observation & Management
  
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
  
  /// Observes the currently selected waypoint and updates the map feature.
  private func setupWaypointService() {
    guard let waypointService = waypointService else { return }
    waypointSelectionTask = TaskCancellable(Task { [weak self] in
      let stream = await waypointService.observeSelectedWaypoint()
      for await selectedId in stream {
        guard !Task.isCancelled else { break }
        if let id = selectedId, let waypoint = try? await waypointService.fetchWaypoint(id: id) {
          let coordinate = CLLocationCoordinate2D(
            latitude: waypoint.latitude.converted(to: .degrees).value,
            longitude: waypoint.longitude.converted(to: .degrees).value
          )
          
          let feature = MLNPointFeature()
          feature.coordinate = coordinate
          var attributes: [String: Any] = ["name": waypoint.name]
          if let colorHex = waypoint.colorHex, let color = Color(hex: colorHex) {
            attributes["colorHex"] = colorHex
            attributes["color"] = UIColor(color)
          } else {
            attributes["color"] = UIColor.systemOrange
          }
          feature.attributes = attributes
          
          await MainActor.run {
            guard let self = self else { return }
            self.selectedWaypointFeature = feature
            self.updateBearingToWaypoint()
            self.trackingMode = .free
            
            let event = CameraMoveEvent.center(coordinate: coordinate, zoom: nil, heading: nil)
            for continuation in self.cameraMoveContinuations.values {
              continuation.yield(event)
            }
          }
        } else {
          await MainActor.run {
            self?.selectedWaypointFeature = nil
            self?.updateBearingToWaypoint()
          }
        }
      }
    })
    
    waypointsObservationTask = TaskCancellable(Task { [weak self] in
      do {
        for try await waypoints in waypointService.observeWaypoints() {
          guard !Task.isCancelled else { break }
          
          let features: [MLNPointFeature] = waypoints.compactMap { waypoint in
            guard waypoint.isVisible else { return nil }
            let coordinate = CLLocationCoordinate2D(
              latitude: waypoint.latitude.converted(to: .degrees).value,
              longitude: waypoint.longitude.converted(to: .degrees).value
            )
            let feature = MLNPointFeature()
            feature.coordinate = coordinate
            var attributes: [String: Any] = ["name": waypoint.name]
            if let colorHex = waypoint.colorHex, let color = Color(hex: colorHex) {
              attributes["colorHex"] = colorHex
              attributes["color"] = UIColor(color)
            } else {
              attributes["color"] = UIColor.systemTeal
            }
            feature.attributes = attributes
            return feature
          }
          
          await MainActor.run {
            self?.visibleWaypointFeatures = features.isEmpty ? nil : MLNShapeCollectionFeature(shapes: features)
          }
        }
      } catch {
        Logger.map.error("Failed to observe waypoints: \(error, privacy: .public)")
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
        Logger.network.error("Silent fetch of GeoGarage layers failed: \(error, privacy: .public)")
      }
    }
  }
  
  // MARK: - Location Handling
  
  /// Subscribes to the positioning service stream, applying a 1-second throttle to UI updates to prevent overloading.
  private func setupPositioningService() {
    let service = self.positioningService
    
    locationUpdatesTask = TaskCancellable(Task { [weak self] in
      let clock = ContinuousClock()
      var lastProcessedTime = clock.now.advanced(by: .seconds(-2))
      
      for await navigationFix in service.locationUpdates {
        guard !Task.isCancelled else { break }
        
        let now = clock.now
        if now.duration(to: lastProcessedTime) > .seconds(-1) {
          continue
        }
        lastProcessedTime = now
        
        await MainActor.run {
          self?.handleNewNavigationFix(navigationFix)
        }
      }
    })
    
    positioningService.requestAuthorization()
  }
  
  /// Processes a new GPS fix, updating telemetry measurements, map features, and camera position if tracking is enabled.
  private func handleNewNavigationFix(_ navigationFix: NavigationFix) {
    // Discard highly inaccurate fixes
    if navigationFix.horizontalAccuracy.converted(to: .meters).value > 50 {
      speedOverGround = nil
      courseOverGround = nil
      return
    }
    
    lastKnownNavigationFix = navigationFix
    
    // Reset the stale data timer. If no new navigationFix is received within 5 seconds, UI will indicate stale data.
    self.isDataStale = false
    self.staleDataTask?.cancel()
    self.staleDataTask = TaskCancellable(Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 5_000_000_000)
      guard !Task.isCancelled else { return }
      self?.isDataStale = true
    })
    
    // Update current coordinate
    currentCoordinate = navigationFix.coordinate
    updateBearingToWaypoint()
    
    // Update SOG using Apple's Measurement
    speedOverGround = navigationFix.speedOverGround
    
    // Update COG
    courseOverGround = navigationFix.courseOverGround
    
    // Generate Map Annotations
    let feature = MLNPointFeature()
    feature.coordinate = navigationFix.coordinate
    var attributes: [String: Any] = [:]
    if let cog = courseOverGround {
      attributes["course"] = cog.converted(to: .degrees).value
    }
    feature.attributes = attributes
    self.vesselFeature = feature
    
    // Update Heading Vector Feature
    self.headingVectorFeature = generateHeadingVector(for: navigationFix)
    
    // Update GPS Accuracy Polygon Feature
    self.gpsAccuracyFeature = generateAccuracyFeature(for: navigationFix)
    
    // Broadcast camera move if actively tracking the user
    if trackingMode != .free {
      let heading = (trackingMode == .courseUp && courseOverGround != nil) ? courseOverGround : Measurement(value: 0.0, unit: UnitAngle.degrees)
      let event = CameraMoveEvent.center(coordinate: navigationFix.coordinate, zoom: nil, heading: heading)
      for continuation in cameraMoveContinuations.values {
        continuation.yield(event)
      }
    }
  }
  
  /// Generates a single, time-based predictive vector with optional point features serving as time ticks.
  private func generateHeadingVector(for navigationFix: NavigationFix) -> MLNShapeCollectionFeature? {
    guard preferencesService.isCOGVectorEnabled else {
      return nil
    }
    
    guard let sogMeasurement = speedOverGround, let cog = courseOverGround, navigationFix.speedOverGround != nil else {
      return nil
    }
    
    // Hide the vector at negligible speeds to avoid erratic UI behavior
    let sogKnots = sogMeasurement.converted(to: .knots).value
    if sogKnots < 0.5 {
      return nil
    }
    
    let speedInMetersPerSecond = sogMeasurement.converted(to: .metersPerSecond).value
    let timeHorizonSeconds = preferencesService.cogVectorTimeHorizon.converted(to: .seconds).value
    let totalDistanceMeters = speedInMetersPerSecond * timeHorizonSeconds
    let totalDistance = Measurement<UnitLength>(value: totalDistanceMeters, unit: .meters)
    
    let startCoordinate = navigationFix.coordinate
    guard let endCoordinate = startCoordinate.rhumbCoordinate(atDistance: totalDistance, bearing: cog) else {
      return nil
    }
    
    var shapes: [MLNShape] = []
    
    // 1. Calculate Main Vector
    var lineCoordinates = [startCoordinate, endCoordinate]
    let lineFeature = MLNPolylineFeature(coordinates: &lineCoordinates, count: UInt(lineCoordinates.count))
    lineFeature.attributes = ["featureType": "vectorLine"]
    shapes.append(lineFeature)
    
    // 2. Calculate Ticks
    if preferencesService.isCOGVectorTicksEnabled {
      let intervalSeconds: Double = timeHorizonSeconds <= 3600 ? 600 : 1800
      let majorIntervalSeconds: Double = timeHorizonSeconds <= 3600 ? 1800 : 3600
      var currentTickSeconds = intervalSeconds
      
      while currentTickSeconds < timeHorizonSeconds {
        let tickDistanceMeters = speedInMetersPerSecond * currentTickSeconds
        let tickDistance = Measurement<UnitLength>(value: tickDistanceMeters, unit: .meters)
        
        if let tickCoordinate = startCoordinate.rhumbCoordinate(atDistance: tickDistance, bearing: cog) {
          let tickFeature = MLNPointFeature()
          tickFeature.coordinate = tickCoordinate
          let isMajor = currentTickSeconds.truncatingRemainder(dividingBy: majorIntervalSeconds) == 0
          tickFeature.attributes = ["featureType": "vectorTick", "isMajorTick": isMajor]
          shapes.append(tickFeature)
        }
        
        currentTickSeconds += intervalSeconds
      }
      
      // Add a major tick point at the very end of the COG vector
      let endPointFeature = MLNPointFeature()
      endPointFeature.coordinate = endCoordinate
      endPointFeature.attributes = ["featureType": "vectorTick", "isMajorTick": true]
      shapes.append(endPointFeature)
    }
    
    return MLNShapeCollectionFeature(shapes: shapes)
  }
  
  /// Generates a circle polygon around the user's location indicating GPS horizontal accuracy.
  private func generateAccuracyFeature(for navigationFix: NavigationFix) -> MLNPolygonFeature? {
    let accuracyMeasurement = navigationFix.horizontalAccuracy
    guard var accuracyCoords = navigationFix.coordinate.accuracyPolygon(radius: accuracyMeasurement) else {
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
      
      resetToDefaultsIfNeeded(defaultZoom: 10.0, defaultCenter: lastKnownNavigationFix?.coordinate)
      
    case .openSeaMap:
      preferencesService.savedMapSource = "openSeaMap"
      self.mapLayer = MapLayer(name: LocalizedStringResource("OpenSeaMap"), source: source)
      self.mapBounds = nil
      self.minZoom = 0.0
      self.maxZoom = 18.0
      
      resetToDefaultsIfNeeded(defaultZoom: 10.0, defaultCenter: lastKnownNavigationFix?.coordinate)
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
    
    if trackingMode != .free, let navigationFix = lastKnownNavigationFix {
      let courseOverGround = navigationFix.courseOverGround
      let heading = (trackingMode == .courseUp && courseOverGround != nil) ? courseOverGround : Measurement(value: 0.0, unit: UnitAngle.degrees)
      let event = CameraMoveEvent.center(coordinate: navigationFix.coordinate, zoom: nil, heading: heading)
      for continuation in cameraMoveContinuations.values {
        continuation.yield(event)
      }
    }
  }
  
  /// Forces the map camera to jump to the user's last known location.
  func centerOnUserLocation() {
    guard let navigationFix = lastKnownNavigationFix else {
      Logger.map.warning("Cannot center: lastKnownNavigationFix is nil. Waiting for a valid GPS fix from PositioningService.")
      return
    }
    
    let courseOverGround = navigationFix.courseOverGround
    let heading = (trackingMode == .courseUp && courseOverGround != nil) ? courseOverGround : Measurement(value: 0.0, unit: UnitAngle.degrees)
    let event = CameraMoveEvent.center(coordinate: navigationFix.coordinate, zoom: nil, heading: heading)
    for continuation in cameraMoveContinuations.values {
      continuation.yield(event)
    }
  }
  
  // MARK: - Saved Tracks
  
  func loadAndDisplaySavedTrack(sessionId: String, trackService: TrackService, edgePadding: CGFloat) async throws {
    // Switch to free tracking mode when viewing a saved track
    trackingMode = .free
    
    let points = try await trackService.fetchTrackPoints(for: sessionId)
    guard !points.isEmpty else { return }
    
    let (feature, bounds) = await Task.detached(priority: .userInitiated) {
      return await Self.processTrackData(points)
    }.value
    
    guard let feature = feature else { return }
    
    self.savedTrackFeature = feature
    
    if let bounds = bounds {
      let event = CameraMoveEvent.fitBounds(bounds: bounds, padding: UIEdgeInsets(top: edgePadding, left: edgePadding, bottom: edgePadding, right: edgePadding))
      for continuation in self.cameraMoveContinuations.values {
        continuation.yield(event)
      }
    } else if let firstPoint = points.first {
      let center = CLLocationCoordinate2D(
        latitude: firstPoint.latitude.converted(to: .degrees).value,
        longitude: firstPoint.longitude.converted(to: .degrees).value
      )
      let event = CameraMoveEvent.center(coordinate: center, zoom: 10.0, heading: nil)
      for continuation in self.cameraMoveContinuations.values {
        continuation.yield(event)
      }
    }
  }
  
  func clearSavedTrack() {
    self.savedTrackFeature = nil
  }
  
  private static func processTrackData(_ points: [TrackPoint]) -> (MLNShape?, MLNCoordinateBounds?) {
    guard points.count >= 2 else { return (nil, nil) }
    
    // TODO: Implement Douglas-Peucker algorithm for accurate geographical simplification
    // Rudimentary simplification/downsampling to avoid OOM on massive tracks
    let strideCount = max(1, points.count / 10000)
    
    var minLat = 90.0, maxLat = -90.0
    var minLon = 180.0, maxLon = -180.0
    
    var segments: [[CLLocationCoordinate2D]] = []
    var currentSegment: [CLLocationCoordinate2D] = []
    var currentSegmentIndex: Int?
    var lastLon: Double?
    var crossesAntimeridian = false
    
    for (index, point) in points.enumerated() {
      // Keep first point, last point, and every Nth point
      if index % strideCount != 0 && index != 0 && index != points.count - 1 {
        continue
      }
      
      let lat = point.latitude.converted(to: .degrees).value
      let lon = point.longitude.converted(to: .degrees).value
      
      if lat < minLat { minLat = lat }
      if lat > maxLat { maxLat = lat }
      if lon < minLon { minLon = lon }
      if lon > maxLon { maxLon = lon }
      
      if let lLon = lastLon, abs(lon - lLon) > 180 {
        crossesAntimeridian = true
      }
      lastLon = lon
      
      if let currentIdx = currentSegmentIndex, currentIdx != point.segmentIndex {
        if currentSegment.count >= 2 {
          segments.append(currentSegment)
        }
        currentSegment = []
      }
      currentSegmentIndex = point.segmentIndex
      currentSegment.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
    }
    
    if currentSegment.count >= 2 {
      segments.append(currentSegment)
    }
    
    guard !segments.isEmpty else { return (nil, nil) }
    
    let shape: MLNShape?
    if segments.count == 1 {
      var coordinates = segments[0]
      shape = MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count))
    } else {
      let polylines = segments.map { coords -> MLNPolyline in
        var mutableCoords = coords
        return MLNPolyline(coordinates: &mutableCoords, count: UInt(mutableCoords.count))
      }
      shape = MLNMultiPolylineFeature(polylines: polylines)
    }
    
    let bounds: MLNCoordinateBounds?
    if crossesAntimeridian {
      // TODO: Handle antimeridian bounding box computation properly. 
      // For now, block bounds creation to prevent a global zoom out.
      bounds = nil
    } else {
      bounds = MLNCoordinateBounds(
        sw: CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
        ne: CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon)
      )
    }
    
    return (shape, bounds)
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
  
  // MARK: - Preferences Observation
  
  private func observePreferences() {
    withObservationTracking {
      _ = preferencesService.isCOGVectorEnabled
      _ = preferencesService.cogVectorTimeHorizon
      _ = preferencesService.isCOGVectorTicksEnabled
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self = self else { return }
        self.updateHeadingVector()
        self.observePreferences()
      }
    }
  }
  
  private func updateHeadingVector() {
    if let navigationFix = lastKnownNavigationFix {
      self.headingVectorFeature = generateHeadingVector(for: navigationFix)
    } else {
      self.headingVectorFeature = nil
    }
  }
  
  private func updateBearingToWaypoint() {
    guard let current = currentCoordinate, let waypoint = selectedWaypointFeature?.coordinate else {
      bearingToWaypoint = nil
      return
    }
    bearingToWaypoint = current.greatCircleBearing(to: waypoint)
  }
}

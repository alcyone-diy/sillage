//
//  ChartViewModel.swift
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

/// The central state manager for the chart interface.
/// It handles location updates, chart source switching, and coordinates camera movements.
@Observable
@MainActor
final class ChartViewModel {
  
  // MARK: - Core State
  
  var trackingMode: ChartTrackingMode = .free
  var currentChartSource: ChartSource?
  var chartBounds: MBTilesBounds?
  var maxZoom: Double?
  var minZoom: Double?
  
  // MARK: - Chart Sources Data
  
  var availableGeoGarageLayers: [GeoGarageLayer] = []
  
  /// Represents locally stored MBTiles files.
  /// This array is automatically kept in sync with the file system by the ChartStorageService.
  var localOfflineCharts: [MBTileFile] = []
  
  var chartImportError: String?
  var showImportError: Bool = false
  
  var isOpenSeaMapOverlayEnabled: Bool = false {
    didSet {
      preferencesService.isOpenSeaMapOverlayEnabled = isOpenSeaMapOverlayEnabled
    }
  }
  
  // MARK: - Chart Camera State
  
  var centerCoordinate: CLLocationCoordinate2D = AppConstants.defaultMapCenter
  var zoomLevel: Double = 10.0
  var chartDirection: Measurement<UnitAngle> = Measurement(value: 0.0, unit: UnitAngle.degrees)
  
  // MARK: - Navigation & Telemetry
  
  var courseState: CourseState? = nil
  var bearingToWaypoint: Measurement<UnitAngle>? = nil
  
  // MARK: - Chart Features (Annotations)
  
  var vesselFeature: MLNPointFeature?
  var headingVectorFeature: MLNShapeCollectionFeature?
  var gpsAccuracyFeature: MLNPolygonFeature?
  var savedTrackFeature: MLNShape?
  var goToWaypointFeature: MLNPointFeature?
  var visibleWaypointFeatures: MLNShapeCollectionFeature?
  var bearingLineFeature: MLNPolylineFeature?
  var goToWaypointID: String?
  var anchorPointFeature: MLNPointFeature?
  var anchorDroppedColor: UIColor?
  var anchorRadiusFeature: MLNPolygonFeature?
  var anchorRadiusColor: UIColor?
  var anchorRadiusOpacity: Double?
  var anchorRadiusDashPattern: [NSNumber]?
  var anchorRadiusLineWidth: Double?
  var displayedTrackSessionID: String? {
    didSet {
      preferencesService.displayedTrackSessionID = displayedTrackSessionID
    }
  }
  
  
  public enum CourseState: Sendable, Equatable {
    case active
    case stopped
    case invalid
  }
  
  // MARK: - Heading Stabilization State
  
  private enum MovementState {
    case moving
    case stopped
  }
  
  private var movementState: MovementState = .stopped
  private var courseOverGroundBuffer: [CLLocationDirection] = []
  private let maxBufferSize = 4
  private let cutOffSpeed: CLLocationSpeed = Measurement(value: 0.8, unit: UnitSpeed.knots).converted(to: .metersPerSecond).value
  private let resumeSpeed: CLLocationSpeed = Measurement(value: 1.5, unit: UnitSpeed.knots).converted(to: .metersPerSecond).value
  private var lastSmoothedCourseOverGround: Measurement<UnitAngle>?
  
  
  // MARK: - Private Services & Tasks
  
  private var chartLayer: ChartLayer?
  private let positioningService: PositioningService
  let instrumentDampingService: InstrumentDampingService<ContinuousClock>
  private let chartStorageService = ChartStorageService()
  private var preferencesService: PreferencesServiceProtocol
  private let authService: GeoGarageAuthServiceProtocol
  private let waypointService: WaypointService?
  private let anchorService: AnchorService
  private let anchorViewModel: AnchorViewModel
  private let messageService: MessageService?
  
  /// TaskCancellable wrappers ensure that async tasks are automatically cancelled
  /// when the ViewModel is deallocated, adhering to Swift 6 strict concurrency rules
  /// without requiring a non-isolated `deinit`.
    private var instrumentTask: TaskCancellable?
  private var observationTask: TaskCancellable?
  private var waypointSelectionTask: TaskCancellable?
  private var waypointsObservationTask: TaskCancellable?
  private var anchorObservationTask: TaskCancellable?
  
  var silentFetchTask: TaskCancellable?
  
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
  
  
  // MARK: - Initialization
  
  init(
    positioningService: PositioningService,
    instrumentDampingService: InstrumentDampingService<ContinuousClock>,
    preferencesService: PreferencesServiceProtocol,
    authService: GeoGarageAuthServiceProtocol,
    anchorService: AnchorService,
    anchorViewModel: AnchorViewModel,
    waypointService: WaypointService? = nil,
    messageService: MessageService? = nil
  ) {
    self.positioningService = positioningService
    self.instrumentDampingService = instrumentDampingService
    self.preferencesService = preferencesService
    self.authService = authService
    self.anchorService = anchorService
    self.anchorViewModel = anchorViewModel
    self.waypointService = waypointService
    self.messageService = messageService
    self.isOpenSeaMapOverlayEnabled = self.preferencesService.isOpenSeaMapOverlayEnabled
    
    loadSavedChartSource()
    setupInstrumentTask()
    setupWaypointService()
    setupAnchorService()
    silentlyFetchGeoGarageLayers()
    startObservingLocalCharts()
    observePreferences()
  }
  
  // MARK: - Data Observation & Management
  
  private func startObservingLocalCharts() {
    observationTask = TaskCancellable(Task { [weak self] in
      guard let storageService = self?.chartStorageService else { return }
      for await files in await storageService.observeMBTilesDirectory() {
        self?.localOfflineCharts = files
      }
    })
  }
  
  private func setupWaypointService() {
    guard let waypointService = waypointService else { return }
    
    func observeSelection() {
      withObservationTracking {
        _ = waypointService.goToWaypointID
      } onChange: { [weak self] in
        Task { @MainActor [weak self] in
          guard let self = self else { return }
          self.handleGoToWaypointChange(id: waypointService.goToWaypointID)
          observeSelection()
        }
      }
    }
    
    func observeWaypoints() {
      withObservationTracking {
        _ = waypointService.currentWaypoints
      } onChange: { [weak self] in
        Task { @MainActor [weak self] in
          guard let self = self else { return }
          self.handleWaypointsChange(waypoints: waypointService.currentWaypoints)
          observeWaypoints()
        }
      }
    }
    
    // Initial handling
    handleWaypointsChange(waypoints: waypointService.currentWaypoints)
    handleGoToWaypointChange(id: waypointService.goToWaypointID)
    
    observeSelection()
    observeWaypoints()
  }
  
  private func handleGoToWaypointChange(id: String?) {
    // 1. Validation stricte
    guard let id = id,
          let waypoint = waypointService?.currentWaypoints.first(where: { $0.id == id }) else {
      // 2. Safe fallback: Total reset if invalid or nil
      self.goToWaypointID = nil
      self.goToWaypointFeature = nil
      self.updateBearingToWaypoint(state: self.instrumentDampingService.state)
      self.updateBearingLine(state: self.instrumentDampingService.state)
      return
    }
    
    // 3. Application of the valid state
    let coordinate = waypoint.coordinate
    let feature = MLNPointFeature()
    feature.coordinate = coordinate
    
    var attributes: [String: Any] = ["name": waypoint.name, "id": waypoint.id]
    if let colorHex = waypoint.colorHex, let color = Color(hex: colorHex) {
      attributes["colorHex"] = colorHex
      attributes["color"] = UIColor(color)
    } else {
      attributes["color"] = UIColor(MarineTheme.Colors.primary)
    }
    feature.attributes = attributes
    
    self.goToWaypointID = id
    self.goToWaypointFeature = feature
    self.updateBearingToWaypoint(state: self.instrumentDampingService.state)
    self.updateBearingLine(state: self.instrumentDampingService.state)
    self.trackingMode = .free
    
    // 4. Emit the event
    let event: CameraMoveEvent
    if let boatCoordinate = instrumentDampingService.state?.coordinate {
      let minLat = min(coordinate.latitude, boatCoordinate.latitude)
      let maxLat = max(coordinate.latitude, boatCoordinate.latitude)
      let minLon = min(coordinate.longitude, boatCoordinate.longitude)
      let maxLon = max(coordinate.longitude, boatCoordinate.longitude)
      
      let bounds = MLNCoordinateBounds(
        sw: CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
        ne: CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon)
      )
      
      // Use padding to ensure points are not hidden behind UI panels
      event = CameraMoveEvent.fitBounds(bounds: bounds, padding: UIEdgeInsets(top: 100, left: 100, bottom: 100, right: 100))
    } else {
      event = CameraMoveEvent.center(coordinate: coordinate, zoom: nil, heading: nil)
    }
    
    for continuation in self.cameraMoveContinuations.values {
      continuation.yield(event)
    }
  }
  
  private func handleWaypointsChange(waypoints: [Waypoint]) {
    let features: [MLNPointFeature] = waypoints.compactMap { waypoint in
      guard waypoint.isVisible else { return nil }
      let coordinate = waypoint.coordinate
      let feature = MLNPointFeature()
      feature.coordinate = coordinate
      var attributes: [String: Any] = ["name": waypoint.name, "id": waypoint.id]
      if let colorHex = waypoint.colorHex, let color = Color(hex: colorHex) {
        attributes["colorHex"] = colorHex
        attributes["color"] = UIColor(color)
      } else {
        attributes["color"] = UIColor(MarineTheme.Colors.primary)
      }
      feature.attributes = attributes
      return feature
    }
    
    self.visibleWaypointFeatures = features.isEmpty ? nil : MLNShapeCollectionFeature(shapes: features)
    
    // Check the persistence of the current target waypoint
    // Note: We read the intent from waypointService instead of self.goToWaypointID
    // This allows correctly restoring navigation upon app startup,
    // as handleGoToWaypointChange might have temporarily purged the state if waypoints were not yet loaded.
    guard let targetID = waypointService?.goToWaypointID else {
      self.goToWaypointID = nil
      self.goToWaypointFeature = nil
      self.updateBearingToWaypoint(state: self.instrumentDampingService.state)
      self.updateBearingLine(state: self.instrumentDampingService.state)
      return
    }
    
    guard let waypoint = waypoints.first(where: { $0.id == targetID }) else {
      // The target waypoint no longer exists (deleted), cancel navigation
      self.goToWaypointID = nil
      self.goToWaypointFeature = nil
      self.updateBearingToWaypoint(state: self.instrumentDampingService.state)
      self.updateBearingLine(state: self.instrumentDampingService.state)
      return
    }
    
    // The waypoint still exists, update its data (color, name, position)
    let feature = MLNPointFeature()
    feature.coordinate = waypoint.coordinate
    var attributes: [String: Any] = ["name": waypoint.name, "id": waypoint.id]
    
    if let colorHex = waypoint.colorHex, let color = Color(hex: colorHex) {
      attributes["colorHex"] = colorHex
      attributes["color"] = UIColor(color)
    } else {
      attributes["color"] = UIColor(MarineTheme.Colors.primary)
    }
    feature.attributes = attributes
    
    self.goToWaypointID = targetID
    self.goToWaypointFeature = feature
    self.updateBearingToWaypoint(state: self.instrumentDampingService.state)
    self.updateBearingLine(state: self.instrumentDampingService.state)
  }
  
  /// Initiates the asynchronous import of an MBTiles file and switches the chart to it upon success.
  func importOfflineChart(from url: URL) {
    Task {
      do {
        let importedURL = try await LocalChartManager.shared.importChart(from: url)
        self.switchChartSource(to: .localMBTiles(url: importedURL))
      } catch {
        self.chartImportError = error.localizedDescription
        self.showImportError = true
      }
    }
  }
  
  func updateGeoGarageLayers(_ layers: [GeoGarageLayer]) {
    self.availableGeoGarageLayers = layers
    self.messageService?.clear(category: .geoGarage)
  }
  
  func logoutGeoGarage() {
    silentFetchTask?.cancel()
    authService.logout()
    self.availableGeoGarageLayers = []
    self.messageService?.clear(category: .geoGarage)
  }
  
  /// Authenticates with GeoGarage in the background using stored credentials to populate available layers.
  private func silentlyFetchGeoGarageLayers() {
    guard let accessToken = KeychainManager.shared.retrieveToken(for: "geogarage_access_token"), !accessToken.trimmingCharacters(in: .whitespaces).isEmpty else {
      Task { @MainActor [weak self] in
        self?.authService.authError = nil
      }
      return
    }
    
    silentFetchTask = TaskCancellable(Task { [weak self] in
      do {
        guard let authService = self?.authService else { return }
        let settings = try await authService.fetchAccountSettings(accessToken: accessToken)
        self?.updateGeoGarageLayers(settings.layers)
      } catch {
        self?.handleGeoGarageAuthError(error)
      }
    })
  }
  
  private func handleGeoGarageAuthError(_ error: Error) {
    Logger.network.error("Silent fetch of GeoGarage layers failed: \(error, privacy: .public)")
    
    if let authError = error as? AuthError, case .networkError = authError {
      return // Ignore offline / network issues silently
    }
    
    let appMessage = AppMessage(
      title: LocalizedStringResource("GeoGarage Auth Error"),
      detail: LocalizedStringResource("Failed to load layers. Please verify your connection or settings."),
      severity: .error,
      category: .geoGarage,
      intent: .openSettings(target: .geoGarage),
    )
    self.messageService?.post(appMessage)
  }
  
  // MARK: - Anchor Observation
  
  private func setupAnchorService() {
    anchorObservationTask = TaskCancellable(Task { [weak self] in
      // Process initial state safely without persistent strong capture
      self?.handleAnchorStateChange()
      
      guard let stateUpdates = self?.anchorService.stateUpdates else { return }
      
      for await _ in stateUpdates {
        guard !Task.isCancelled else { break }
        self?.handleAnchorStateChange()
      }
    })
    
    func observeSetupMode() {
      withObservationTracking {
        _ = anchorViewModel.isSetupModeActive
        _ = anchorViewModel.configuredRadius
        _ = anchorViewModel.anchorCoordinate
      } onChange: { [weak self] in
        Task { @MainActor [weak self] in
          guard let self = self else { return }
          self.handleAnchorStateChange()
          observeSetupMode()
        }
      }
    }
    observeSetupMode()
  }
  
  private func handleAnchorStateChange() {
    let status = anchorService.status
    
    if status == .inactive {
      if anchorViewModel.isSetupModeActive {
        if let coord = instrumentDampingService.state?.coordinate {
          // Setup Preview Point
          let pointFeature = MLNPointFeature()
          pointFeature.coordinate = coord
          self.anchorPointFeature = pointFeature
          self.anchorDroppedColor = UIColor(MarineTheme.Colors.anchorDropped).withAlphaComponent(0.5)
          self.anchorRadiusFeature = nil
        } else {
          anchorPointFeature = nil
          anchorRadiusFeature = nil
        }
      } else {
        anchorPointFeature = nil
        anchorRadiusFeature = nil
      }
      return
    }
    
    guard let watch = anchorService.activeWatch else { return }
    
    // Setup Point
    let pointFeature = MLNPointFeature()
    pointFeature.coordinate = watch.coordinate
    self.anchorPointFeature = pointFeature
    self.anchorDroppedColor = UIColor(MarineTheme.Colors.anchorDropped)
    
    // Setup Radius Polygon
    if let polygonCoords = watch.coordinate.circularPolygon(radius: watch.radius) {
      var coords = polygonCoords
      let polygonFeature = MLNPolygonFeature(coordinates: &coords, count: UInt(coords.count))
      self.anchorRadiusFeature = polygonFeature
      
      switch status {
      case .dropped:
        self.anchorRadiusColor = UIColor(MarineTheme.Colors.anchorDropped)
        self.anchorRadiusOpacity = 0.0
        self.anchorRadiusDashPattern = [4.0, 4.0]
        self.anchorRadiusLineWidth = 3.0
      case .armed:
        self.anchorRadiusColor = UIColor(MarineTheme.Colors.anchorArmed)
        self.anchorRadiusOpacity = 0.10
        self.anchorRadiusDashPattern = nil
        self.anchorRadiusLineWidth = 1.5
      case .dragging:
        self.anchorRadiusColor = UIColor(MarineTheme.Colors.anchorDragging)
        self.anchorRadiusOpacity = 0.25
        self.anchorRadiusDashPattern = nil
        self.anchorRadiusLineWidth = 1.5
      case .inactive:
        break
      }
    }
  }
  
  // MARK: - Location Handling
  
  // MARK: - Instrument & Positioning Services
  

  // ARCHITECTURE: Single Source of Truth & Memory Safety
  // The ViewModel subscribes strictly to the Domain Service (InstrumentDampingService)
  // rather than listening to the hardware sensors directly.
  // We use `[weak self]` in an unstructured Task loop to prevent retain cycles,
  // iterating safely over the `AsyncStream` instead of relying on Combine.
  private func setupInstrumentTask() {
    instrumentTask = TaskCancellable(Task { @MainActor [weak self] in
      guard let stream = self?.instrumentDampingService.observeState() else { return }
      
      for await state in stream {
        guard !Task.isCancelled, let self = self else { break }
        self.handleInstrumentState(state)
      }
    })
  }
  private func handleInstrumentState(_ state: InstrumentState) {
    if state.smoothedCOG != nil {
      self.courseState = state.movementState == .stopped ? .stopped : .active
    } else {
      self.courseState = .invalid
    }
    
    // Batched map refresh invoked after all data is safely assigned
    refreshMapFeatures(state: state)
  }
  private func refreshMapFeatures(state: InstrumentState? = nil) {
    let safeState = state ?? instrumentDampingService.state
    
    updateBearingToWaypoint(state: safeState)
    updateBearingLine(state: safeState)
    updateVesselFeature(state: safeState)
    updateHeadingVector(state: safeState)
    updateAccuracyFeature(state: safeState)
    
    if trackingMode != .free, let coordinate = safeState?.coordinate {
      let heading = (trackingMode == .courseUp) ? safeState?.smoothedCOG : nil
      let event = CameraMoveEvent.center(coordinate: coordinate, zoom: nil, heading: heading)
      for continuation in cameraMoveContinuations.values {
        continuation.yield(event)
      }
    }
  }

  private func updateVesselFeature(state: InstrumentState?) {
    guard let coordinate = state?.coordinate else {
      self.vesselFeature = nil
      return
    }
    let feature = MLNPointFeature()
    feature.coordinate = coordinate
    var attributes: [String: Any] = [:]
    
    if let cog = state?.smoothedCOG {
      attributes["course"] = cog.converted(to: .degrees).value
    }
    
    // The MapLibre style layer can bind to `isStale` to render the vessel in gray
    if state?.gpsState == .lost {
      attributes["isStale"] = true
    } else {
      attributes["isStale"] = false
    }
    
    feature.attributes = attributes
    self.vesselFeature = feature
  }

  private func updateHeadingVector(state: InstrumentState?) {
    guard preferencesService.isCOGVectorEnabled,
          let sog = state?.smoothedSOG,
          let cog = state?.smoothedCOG,
          let startCoordinate = state?.coordinate else {
      self.headingVectorFeature = nil
      return
    }
    
    let timeHorizonSeconds = preferencesService.cogVectorTimeHorizon.converted(to: .seconds).value
    let generateTicks = preferencesService.isCOGVectorTicksEnabled
    
    guard let prediction = HeadingVectorPredictor.predict(
      startCoordinate: startCoordinate,
      sog: sog,
      cog: cog,
      timeHorizonSeconds: timeHorizonSeconds,
      generateTicks: generateTicks
    ) else {
      self.headingVectorFeature = nil
      return
    }
    
    var shapes: [MLNShape] = []
    
    var lineCoords = prediction.lineCoordinates
    let lineFeature = MLNPolylineFeature(coordinates: &lineCoords, count: UInt(lineCoords.count))
    lineFeature.attributes = ["featureType": "vectorLine"]
    shapes.append(lineFeature)
    
    for tick in prediction.majorTickCoordinates {
      let tickFeature = MLNPointFeature()
      tickFeature.coordinate = tick
      tickFeature.attributes = ["featureType": "vectorTick", "isMajorTick": true]
      shapes.append(tickFeature)
    }
    
    for tick in prediction.minorTickCoordinates {
      let tickFeature = MLNPointFeature()
      tickFeature.coordinate = tick
      tickFeature.attributes = ["featureType": "vectorTick", "isMajorTick": false]
      shapes.append(tickFeature)
    }
    
    self.headingVectorFeature = MLNShapeCollectionFeature(shapes: shapes)
  }

  private func updateAccuracyFeature(state: InstrumentState?) {
    guard let accuracy = state?.horizontalAccuracy?.converted(to: .meters).value, let coordinate = state?.coordinate else {
      self.gpsAccuracyFeature = nil
      return
    }
    let accuracyMeasurement = Measurement(value: accuracy, unit: UnitLength.meters)
    guard var accuracyCoords = coordinate.circularPolygon(radius: accuracyMeasurement) else {
      self.gpsAccuracyFeature = nil
      return
    }
    self.gpsAccuracyFeature = MLNPolygonFeature(coordinates: &accuracyCoords, count: UInt(accuracyCoords.count))
  }
  
  // MARK: - Chart State Management
  
  /// Changes the active chart source and reconfigures chart limits (bounds, zoom) accordingly.
  func switchChartSource(to source: ChartSource) {
    self.currentChartSource = source
    
    switch source {
    case .localMBTiles(let url):
      let fileName = url.deletingPathExtension().lastPathComponent
      preferencesService.savedChartSource = fileName
      
      self.chartLayer = ChartLayer(name: LocalizedStringResource("Marine Raster Chart"), source: source)
      let metadata = MBTilesHelper.extractMetadata(from: url)
      if let bounds = metadata.bounds { self.chartBounds = bounds }
      if let minZ = metadata.minZoom { self.minZoom = minZ }
      if let maxZ = metadata.maxZoom { self.maxZoom = maxZ }
      
      resetToDefaultsIfNeeded(defaultZoom: metadata.defaultZoom ?? 10.0, defaultCenter: metadata.center)
      
    case .remoteGeoGarage(_, let layerID):
      preferencesService.savedChartSource = "remoteGeoGarage"
      preferencesService.savedGeoGarageLayerID = layerID
      
      self.chartLayer = ChartLayer(name: LocalizedStringResource("GeoGarage Marine Chart"), source: source)
      self.chartBounds = nil
      self.minZoom = 0.0
      self.maxZoom = 20.0
      
      resetToDefaultsIfNeeded(defaultZoom: 10.0, defaultCenter: instrumentDampingService.state?.coordinate)
      
    case .openSeaMap:
      preferencesService.savedChartSource = "openSeaMap"
      self.chartLayer = ChartLayer(name: LocalizedStringResource("OpenSeaMap"), source: source)
      self.chartBounds = nil
      self.minZoom = 0.0
      self.maxZoom = 18.0
      
      resetToDefaultsIfNeeded(defaultZoom: 10.0, defaultCenter: instrumentDampingService.state?.coordinate)
    }
  }
  
  /// Applies default chart position settings only if the user hasn't previously saved a camera state.
  private func resetToDefaultsIfNeeded(defaultZoom: Double, defaultCenter: CLLocationCoordinate2D?) {
    if preferencesService.savedLatitude == nil {
      self.zoomLevel = defaultZoom
      if let center = defaultCenter {
        self.centerCoordinate = center
      }
    }
  }
  
  // MARK: - User Interactions
  
  /// Called when the user manually pans or zooms the chart, breaking any active tracking lock.
  func chartInteractedByUser() {
    guard trackingMode != .free else { return }
    
    preferencesService.savedTrackingMode = trackingMode
    trackingMode = .free
  }
  
  /// Cycles through available camera tracking modes (Free -> North Up <-> Course Up).
  func toggleTrackingMode() {
    switch trackingMode {
    case .free:
      trackingMode = preferencesService.savedTrackingMode
    case .northUp:
      trackingMode = .courseUp
      preferencesService.savedTrackingMode = .courseUp
    case .courseUp:
      trackingMode = .northUp
      preferencesService.savedTrackingMode = .northUp
    }
    
    if trackingMode != .free, let coordinate = instrumentDampingService.state?.coordinate {
      let heading = (trackingMode == .courseUp) ? instrumentDampingService.state?.smoothedCOG : nil
      let event = CameraMoveEvent.center(coordinate: coordinate, zoom: nil, heading: heading)
      for continuation in cameraMoveContinuations.values {
        continuation.yield(event)
      }
    }
  }
  
  /// Forces the chart camera to jump to the user's last known location.
  func centerOnUserLocation() {
    guard let coordinate = instrumentDampingService.state?.coordinate else {
      Logger.chart.warning("Cannot center: coordinate is nil. Waiting for a valid GPS fix from PositioningService.")
      return
    }
    
    let heading = (trackingMode == .courseUp) ? instrumentDampingService.state?.smoothedCOG : nil
    let event = CameraMoveEvent.center(coordinate: coordinate, zoom: nil, heading: heading)
    for continuation in cameraMoveContinuations.values {
      continuation.yield(event)
    }
  }
  

  // MARK: - Saved Tracks
  
  func loadAndDisplaySavedTrack(sessionID: String, trackService: TrackService, edgePadding: CGFloat, centerOnTrack: Bool = true) async throws {
    // Switch to free tracking mode when viewing a saved track
    if centerOnTrack {
      trackingMode = .free
    }
    
    let points = try await trackService.fetchTrackPoints(for: sessionID)
    guard !points.isEmpty else { return }
    
    let (feature, bounds) = await Task.detached(priority: .userInitiated) {
      return await Self.processTrackData(points)
    }.value
    
    guard let feature = feature else { return }
    
    self.savedTrackFeature = feature
    self.displayedTrackSessionID = sessionID
    
    if centerOnTrack {
      if let bounds = bounds {
        let event = CameraMoveEvent.fitBounds(bounds: bounds, padding: UIEdgeInsets(top: edgePadding, left: edgePadding, bottom: edgePadding, right: edgePadding))
        for continuation in self.cameraMoveContinuations.values {
          continuation.yield(event)
        }
      } else if let firstPoint = points.first {
        let center = firstPoint.coordinate
        let event = CameraMoveEvent.center(coordinate: center, zoom: 10.0, heading: nil)
        for continuation in self.cameraMoveContinuations.values {
          continuation.yield(event)
        }
      }
    }
  }
  
  func clearSavedTrack() {
    self.savedTrackFeature = nil
    self.displayedTrackSessionID = nil
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
      
      let lat = point.coordinate.latitude
      let lon = point.coordinate.longitude
      
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
    preferencesService.saveCameraState(coordinate: centerCoordinate, zoom: zoomLevel, direction: chartDirection.converted(to: .degrees).value)
  }
  
  func loadSavedCameraState() {
    if let state = preferencesService.loadCameraState() {
      self.centerCoordinate = state.coordinate
      self.zoomLevel = state.zoom
      self.chartDirection = Measurement(value: state.direction, unit: UnitAngle.degrees)
    }
  }
  
  /// Restores the previously selected chart source upon application launch.
  /// It verifies file existence in the Documents directory and falls back appropriately.
  private func loadSavedChartSource() {
    let savedSource = preferencesService.savedChartSource
    
    if savedSource == "remoteGeoGarage", let savedLayerID = preferencesService.savedGeoGarageLayerID {
      switchChartSource(to: .remoteGeoGarage(clientID: AppConfiguration.shared.geoGarageClientID, layerID: savedLayerID))
      
    } else if let savedFileName = savedSource {
      let fileManager = FileManager.default
      if let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
        let chartURL = documentsDirectory
          .appendingPathComponent("Charts")
          .appendingPathComponent(savedFileName)
          .appendingPathExtension("mbtiles")
        
        if fileManager.fileExists(atPath: chartURL.path) {
          switchChartSource(to: .localMBTiles(url: chartURL))
        } else if let bundleURL = Bundle.main.url(forResource: savedFileName, withExtension: "mbtiles") {
          // Fallback to internal app bundle if the chart is a shipped default
          switchChartSource(to: .localMBTiles(url: bundleURL))
        } else {
          switchChartSource(to: .openSeaMap)
        }
      } else {
        switchChartSource(to: .openSeaMap)
      }
    } else {
      switchChartSource(to: .openSeaMap)
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
        self.updateHeadingVector(state: self.instrumentDampingService.state)
        self.observePreferences()
      }
    }
  }
  private func updateBearingToWaypoint(state: InstrumentState?) {
    guard let current = state?.coordinate, let waypoint = goToWaypointFeature?.coordinate else {
      bearingToWaypoint = nil
      return
    }
    bearingToWaypoint = current.greatCircleBearing(to: waypoint)
  }
  
  private func updateBearingLine(state: InstrumentState?) {
    guard let current = state?.coordinate, let waypoint = goToWaypointFeature?.coordinate else {
      bearingLineFeature = nil
      return
    }
    var coordinates = [current, waypoint]
    let feature = MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count))
    if let color = goToWaypointFeature?.attributes["color"] {
      feature.attributes = ["color": color]
    }
    bearingLineFeature = feature
  }
}
//
//  MapLibreView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import MapLibre
import CoreLocation
import OSLog

struct MapLibreView: UIViewRepresentable {
  
  @Environment(\.marineTheme) var marineTheme
  @Environment(TrackRecordingService.self) private var trackRecordingService
  var viewModel: MapViewModel
  
  
  private func ensureVesselLayersExist(in style: MLNStyle, with theme: MarineTheme) {
    let vesselSourceId = "vessel-source"
    let vesselLayerId = "vessel-layer"
    let headingSourceId = "heading-vector-source"
    let headingLayerId = "heading-vector-layer"
    let gpsAccuracySourceId = "gps-accuracy-source"
    let gpsAccuracyLayerId = "gps-accuracy-layer"
    let gpsAccuracyStrokeLayerId = "gps-accuracy-stroke-layer"
    let savedTrackSourceId = "saved-track-source"
    let savedTrackLayerId = "saved-track-layer"
    let activeTrackSourceId = "active-track-source"
    let activeTrackLayerId = "active-track-layer"
    let selectedWaypointSourceId = "selected-waypoint-source"
    let selectedWaypointLayerId = "selected-waypoint-layer"
    let visibleWaypointsSourceId = "visible-waypoints-source"
    let visibleWaypointsLayerId = "visible-waypoints-layer"
    
    if style.source(withIdentifier: vesselSourceId) == nil {
      // Create GPS Accuracy Source and Layers first so they are beneath the heading vector and vessel
      let gpsAccuracySource = MLNShapeSource(identifier: gpsAccuracySourceId, shape: nil, options: nil)
      style.addSource(gpsAccuracySource)
      
      let gpsAccuracyFillLayer = MLNFillStyleLayer(identifier: gpsAccuracyLayerId, source: gpsAccuracySource)
      gpsAccuracyFillLayer.fillColor = NSExpression(forConstantValue: UIColor(MarineTheme.Colors.accent))
      gpsAccuracyFillLayer.fillOpacity = NSExpression(forConstantValue: MarineTheme.MapMetrics.gpsAccuracyFillOpacity)
      style.addLayer(gpsAccuracyFillLayer)
      
      let gpsAccuracyStrokeLayer = MLNLineStyleLayer(identifier: gpsAccuracyStrokeLayerId, source: gpsAccuracySource)
      gpsAccuracyStrokeLayer.lineColor = NSExpression(forConstantValue: UIColor(MarineTheme.Colors.accent))
      gpsAccuracyStrokeLayer.lineOpacity = NSExpression(forConstantValue: MarineTheme.MapMetrics.gpsAccuracyStrokeOpacity)
      gpsAccuracyStrokeLayer.lineWidth = NSExpression(forConstantValue: MarineTheme.MapMetrics.gpsAccuracyLineWidth)
      style.insertLayer(gpsAccuracyStrokeLayer, above: gpsAccuracyFillLayer)
      
      let activeTrackSource = MLNShapeSource(identifier: activeTrackSourceId, shape: nil, options: nil)
      style.addSource(activeTrackSource)
      let activeTrackLayer = MLNLineStyleLayer(identifier: activeTrackLayerId, source: activeTrackSource)
      activeTrackLayer.lineWidth = NSExpression(forConstantValue: 4.0)
      activeTrackLayer.lineColor = NSExpression(forConstantValue: UIColor.systemRed)
      style.insertLayer(activeTrackLayer, above: gpsAccuracyStrokeLayer)
      
      let savedTrackSource = MLNShapeSource(identifier: savedTrackSourceId, shape: nil, options: nil)
      style.addSource(savedTrackSource)
      let savedTrackLayer = MLNLineStyleLayer(identifier: savedTrackLayerId, source: savedTrackSource)
      savedTrackLayer.lineWidth = NSExpression(forConstantValue: 4.0)
      savedTrackLayer.lineColor = NSExpression(forConstantValue: UIColor.systemBlue)
      style.insertLayer(savedTrackLayer, below: activeTrackLayer)
      
      let selectedWaypointSource = MLNShapeSource(identifier: selectedWaypointSourceId, shape: nil, options: nil)
      style.addSource(selectedWaypointSource)
      let selectedWaypointLayer = MLNCircleStyleLayer(identifier: selectedWaypointLayerId, source: selectedWaypointSource)
      selectedWaypointLayer.circleRadius = NSExpression(forConstantValue: 8.0)
      selectedWaypointLayer.circleColor = NSExpression(forConstantValue: UIColor.systemOrange)
      selectedWaypointLayer.circleStrokeWidth = NSExpression(forConstantValue: 2.0)
      selectedWaypointLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
      style.insertLayer(selectedWaypointLayer, below: activeTrackLayer)
      
      let visibleWaypointsSource = MLNShapeSource(identifier: visibleWaypointsSourceId, shape: nil, options: nil)
      style.addSource(visibleWaypointsSource)
      let visibleWaypointsLayer = MLNCircleStyleLayer(identifier: visibleWaypointsLayerId, source: visibleWaypointsSource)
      visibleWaypointsLayer.circleRadius = NSExpression(forConstantValue: 6.0)
      visibleWaypointsLayer.circleColor = NSExpression(forConstantValue: UIColor.systemTeal)
      visibleWaypointsLayer.circleStrokeWidth = NSExpression(forConstantValue: 1.5)
      visibleWaypointsLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
      style.insertLayer(visibleWaypointsLayer, below: selectedWaypointLayer)
      
      // Create Heading Source and Layer so it's above gps accuracy but beneath the vessel
      let headingSource = MLNShapeSource(identifier: headingSourceId, shape: nil, options: nil)
      style.addSource(headingSource)
      
      let headingLayer = MLNLineStyleLayer(identifier: headingLayerId, source: headingSource)
      headingLayer.predicate = NSPredicate(format: "featureType == 'vectorLine'")
      headingLayer.lineWidth = NSExpression(forConstantValue: MarineTheme.MapMetrics.headingLineWidth)
      headingLayer.lineColor = NSExpression(forConstantValue: UIColor(MarineTheme.Colors.vectorCOG))
      style.addLayer(headingLayer)
      
      let headingTickLayerId = "heading-vector-tick-layer"
      let headingTickLayer = MLNCircleStyleLayer(identifier: headingTickLayerId, source: headingSource)
      headingTickLayer.predicate = NSPredicate(format: "featureType == 'vectorTick'")
      headingTickLayer.circleRadius = NSExpression(format: "TERNARY(isMajorTick == YES, 4.0, 2.0)")
      headingTickLayer.circleColor = NSExpression(forConstantValue: UIColor(MarineTheme.Colors.vectorCOG))
      headingTickLayer.circleStrokeWidth = NSExpression(forConstantValue: 1.0)
      headingTickLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.systemBackground)
      style.insertLayer(headingTickLayer, above: headingLayer)
      
      // Create Vessel Source and Layer
      let vesselSource = MLNShapeSource(identifier: vesselSourceId, shape: nil, options: nil)
      style.addSource(vesselSource)
      
      let vesselLayer = MLNSymbolStyleLayer(identifier: vesselLayerId, source: vesselSource)
      vesselLayer.iconImageName = NSExpression(forConstantValue: "vessel-cursor")
      vesselLayer.iconRotationAlignment = NSExpression(forConstantValue: "map")
      vesselLayer.iconRotation = NSExpression(forKeyPath: "course")
      vesselLayer.iconAllowsOverlap = NSExpression(forConstantValue: true)
      vesselLayer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
      vesselLayer.iconOpacity = NSExpression(forConstantValue: 1.0)
      style.addLayer(vesselLayer)
    }
  }
  
  func makeUIView(context: Context) -> MLNMapView {
    // Initialization of the MapLibre view without a frame
    let mapView = MLNMapView(frame: .zero)
    
    // Explicitly disable automatic inset adjustments to avoid conflicts with SwiftUI Safe Areas
    mapView.automaticallyAdjustsContentInset = false
    // Note: MLNMapView legacy warning persists due to internal SDK check on UIHostingController. Layout is correctly managed by SwiftUI.
    
    mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    
    // Delegate configuration
    mapView.delegate = context.coordinator
    
    // Set maximum zoom level to allow overzooming
    mapView.maximumZoomLevel = 22.0
    
    // Disable pitch gesture to keep the map in 2D
    mapView.isPitchEnabled = false
    
    mapView.attributionButton.isHidden = true
    mapView.logoView.isHidden = true
    
    // Configure compass to remain permanently visible
    mapView.compassView.compassVisibility = .visible
    
    // Load a minimal blank style so MapLibre initializes and fires `mapView(_:didFinishLoading:)`
    if let blankStyleURL = createBlankStyleJSON() {
      mapView.styleURL = blankStyleURL
    }
    
    // Centering of the initial camera using ViewModel's state
    mapView.setCenter(viewModel.centerCoordinate, zoomLevel: viewModel.zoomLevel, direction: viewModel.mapDirection.converted(to: .degrees).value, animated: false)
    
    // Setup subscription for explicit user location centering via AsyncStream
    context.coordinator.setupSubscription(for: mapView)
    
    return mapView
  }
  
  func updateUIView(_ uiView: MLNMapView, context: Context) {
    // Updates the coordinator's parent to always point to the latest view (SwiftUI struct)
    context.coordinator.parent = self
    
    // Defensive Update for Vessel and Heading Features
    if let style = uiView.style {
      ensureVesselLayersExist(in: style, with: marineTheme)
      
      // Vessel feature update
      if let source = style.source(withIdentifier: "vessel-source") as? MLNShapeSource {
        source.shape = viewModel.vesselFeature
      }
      
      // Heading vector feature update
      if let source = style.source(withIdentifier: "heading-vector-source") as? MLNShapeSource {
        source.shape = viewModel.headingVectorFeature
      }
      
      // GPS accuracy feature update
      if let source = style.source(withIdentifier: "gps-accuracy-source") as? MLNShapeSource {
        source.shape = viewModel.gpsAccuracyFeature
      }
      
      // Active track feature update
      if let source = style.source(withIdentifier: "active-track-source") as? MLNShapeSource {
        source.shape = generateActiveTrackFeature(from: trackRecordingService.trackPoints)
      }
      
      // Saved track feature update
      if let source = style.source(withIdentifier: "saved-track-source") as? MLNShapeSource {
        source.shape = viewModel.savedTrackFeature
      }
      
      // Displayed waypoints feature update
      if let source = style.source(withIdentifier: "visible-waypoints-source") as? MLNShapeSource {
        source.shape = viewModel.visibleWaypointFeatures
      }
      
      // Selected waypoint feature update
      if let source = style.source(withIdentifier: "selected-waypoint-source") as? MLNShapeSource {
        source.shape = viewModel.selectedWaypointFeature
        if let layer = style.layer(withIdentifier: "selected-waypoint-layer") as? MLNCircleStyleLayer {
          if let hex = viewModel.selectedWaypointFeature?.attributes["colorHex"] as? String,
             let color = Color(hex: hex) {
            layer.circleColor = NSExpression(forConstantValue: UIColor(color))
          } else {
            layer.circleColor = NSExpression(forConstantValue: UIColor.systemOrange)
          }
        }
      }
      
      // Data Stale state update (Opacity)
      if let layer = style.layer(withIdentifier: "vessel-layer") as? MLNSymbolStyleLayer {
        layer.iconOpacity = NSExpression(forConstantValue: viewModel.isDataStale ? 0.4 : 1.0)
      }
    }
    
    
    // Force tracking mode to none if it deviated, since tracking is explicitly handled in the viewModel
    _ = viewModel.trackingMode
    if uiView.userTrackingMode != .none {
      uiView.userTrackingMode = .none
    }
    
    
    
    // If the map source has changed, update the map's style/source
    if let currentSource = viewModel.currentMapSource,
       context.coordinator.lastMapSource != currentSource,
       let style = uiView.style {
      context.coordinator.updateMapSource(currentSource, style: style, mapView: uiView)
    }
    
    // Handle OpenSeaMap overlay toggle
    if let style = uiView.style {
      context.coordinator.updateOpenSeaMapOverlay(isEnabled: viewModel.isOpenSeaMapOverlayEnabled, style: style, mapView: uiView)
    }
    
    // Handle Content Inset for Look-ahead in Course Up mode
    let newInset: UIEdgeInsets
    if viewModel.trackingMode == .courseUp {
      let lookAheadOffset = uiView.bounds.height / 3.0
      newInset = UIEdgeInsets(top: lookAheadOffset, left: 0, bottom: 0, right: 0)
    } else {
      newInset = .zero
    }
    
    if uiView.contentInset != newInset {
      uiView.setContentInset(newInset, animated: true, completionHandler: nil)
    }
    
    // Disable compass interaction when in an automated tracking mode to prevent state conflicts
    uiView.compassView.isUserInteractionEnabled = (viewModel.trackingMode != .courseUp)
  }
  
  private func generateActiveTrackFeature(from points: ArraySlice<TrackPoint>) -> MLNShape? {
    guard points.count >= 2 else { return nil }
    
    var segments: [[CLLocationCoordinate2D]] = []
    var currentSegment: [CLLocationCoordinate2D] = []
    currentSegment.reserveCapacity(points.count)
    var currentSegmentIndex: Int?
    
    for point in points {
      if let currentIdx = currentSegmentIndex, currentIdx != point.segmentIndex {
        if currentSegment.count >= 2 {
          segments.append(currentSegment)
        }
        currentSegment = []
        currentSegment.reserveCapacity(points.count)
      }
      currentSegmentIndex = point.segmentIndex
      currentSegment.append(
        CLLocationCoordinate2D(
          latitude: point.latitude.converted(to: .degrees).value,
          longitude: point.longitude.converted(to: .degrees).value
        )
      )
    }
    
    if currentSegment.count >= 2 {
      segments.append(currentSegment)
    }
    
    guard !segments.isEmpty else { return nil }
    
    if segments.count == 1 {
      var coordinates = segments[0]
      return MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count))
    } else {
      let polylines = segments.map { coords -> MLNPolyline in
        var mutableCoords = coords
        return MLNPolyline(coordinates: &mutableCoords, count: UInt(mutableCoords.count))
      }
      return MLNMultiPolylineFeature(polylines: polylines)
    }
  }
  
  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }
  
  /// Creates a minimal empty JSON style to force MapLibre to load its engine and fire the finish loading delegate method.
  private func createBlankStyleJSON() -> URL? {
    guard let styleURL = Bundle.main.url(forResource: "blank-style", withExtension: "json") else {
      Logger.map.warning("blank-style.json not found in App Bundle. MapLibre may not initialize correctly.")
      return nil
    }
    return styleURL
  }
  
  // MARK: - Coordinator
  
  class Coordinator: NSObject, MLNMapViewDelegate {
    var parent: MapLibreView
    private var streamTask: Task<Void, Never>?
    var lastMapSource: MapSource?
    
    init(_ parent: MapLibreView) {
      self.parent = parent
    }
    
    deinit {
      streamTask?.cancel()
    }
    
    func setupSubscription(for mapView: MLNMapView) {
      streamTask?.cancel()
      streamTask = Task { @MainActor in
        for await event in parent.viewModel.cameraMoveStream {
          switch event {
          case .fitBounds(let bounds, let padding):
            await mapView.setVisibleCoordinateBounds(bounds, edgePadding: padding, animated: true)
          case .center(let coordinate, let zoom, let heading):
            let targetZoom = zoom ?? mapView.zoomLevel
            
            // We pass the targetZoom explicitly. If the raster chart doesn't support this
            // zoom level (e.g., maxZoom is 14), MapLibre might show a white screen
            // depending on how over-zooming is handled by the raster source style.
            if let heading = heading {
              await mapView.setCenter(coordinate, zoomLevel: targetZoom, direction: heading.converted(to: .degrees).value, animated: true)
            } else {
              mapView.setCenter(coordinate, zoomLevel: targetZoom, animated: true)
            }
          }
        }
      }
    }
    
    var lastOpenSeaMapOverlayEnabled: Bool = false
    
    // Called when the map has finished loading its style
    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
      Logger.map.info("MapLibre successfully loaded the default style.")
      
      // Add vessel cursor image
      if let image = VesselGraphicsFactory.createVesselImage(size: MarineTheme.MapMetrics.vesselCursorBaseSize, color: UIColor(MarineTheme.Colors.accent)) {
        style.setImage(image, forName: "vessel-cursor")
      }
      
      if let currentSource = parent.viewModel.currentMapSource {
        updateMapSource(currentSource, style: style, mapView: mapView)
      }
      
      updateOpenSeaMapOverlay(isEnabled: parent.viewModel.isOpenSeaMapOverlayEnabled, style: style, mapView: mapView)
      
      // Ensure vessel layers are initialized after style finishes loading
      parent.ensureVesselLayersExist(in: style, with: parent.marineTheme)
      if let source = style.source(withIdentifier: "heading-vector-source") as? MLNShapeSource {
        source.shape = parent.viewModel.headingVectorFeature
      }
      if let source = style.source(withIdentifier: "gps-accuracy-source") as? MLNShapeSource {
        source.shape = parent.viewModel.gpsAccuracyFeature
      }
      if let source = style.source(withIdentifier: "vessel-source") as? MLNShapeSource {
        source.shape = parent.viewModel.vesselFeature
      }
      if let source = style.source(withIdentifier: "active-track-source") as? MLNShapeSource {
        source.shape = parent.generateActiveTrackFeature(from: parent.trackRecordingService.trackPoints)
      }
      if let source = style.source(withIdentifier: "saved-track-source") as? MLNShapeSource {
        source.shape = parent.viewModel.savedTrackFeature
      }
      if let source = style.source(withIdentifier: "visible-waypoints-source") as? MLNShapeSource {
        source.shape = parent.viewModel.visibleWaypointFeatures
      }
      if let source = style.source(withIdentifier: "selected-waypoint-source") as? MLNShapeSource {
        source.shape = parent.viewModel.selectedWaypointFeature
        if let layer = style.layer(withIdentifier: "selected-waypoint-layer") as? MLNCircleStyleLayer {
          if let hex = parent.viewModel.selectedWaypointFeature?.attributes["colorHex"] as? String,
             let color = Color(hex: hex) {
            layer.circleColor = NSExpression(forConstantValue: UIColor(color))
          } else {
            layer.circleColor = NSExpression(forConstantValue: UIColor.systemOrange)
          }
        }
      }
      if let layer = style.layer(withIdentifier: "vessel-layer") as? MLNSymbolStyleLayer {
        layer.iconOpacity = NSExpression(forConstantValue: parent.viewModel.isDataStale ? 0.4 : 1.0)
      }
      
      // NOTE: We do not call `mapView.setVisibleCoordinateBounds` here.
      // In SwiftUI, `didFinishLoading` can fire before the map view has a non-zero frame.
      // Calling coordinate bounds on a `.zero` frame corrupts the MapLibre camera (`NaN` zoom level).
      // Instead, we simply jump the camera back to the exact metadata `centerCoordinate` and `zoomLevel`.
      // This is required because loading the blank JSON style resets the map to (0,0), which leaves it looking at
      // the African coast where no French marine chart tiles exist, causing the map to appear blank.
      mapView.setCenter(parent.viewModel.centerCoordinate, zoomLevel: parent.viewModel.zoomLevel, direction: parent.viewModel.mapDirection.converted(to: .degrees).value, animated: false)
    }
    
    func updateMapSource(_ source: MapSource, style: MLNStyle, mapView: MLNMapView) {
      lastMapSource = source
      
      // Remove existing layer and source if they exist
      let layerId = "base-raster-layer"
      let sourceId = "base-raster-source"
      
      if let existingLayer = style.layer(withIdentifier: layerId) {
        style.removeLayer(existingLayer)
      }
      if let existingSource = style.source(withIdentifier: sourceId) {
        style.removeSource(existingSource)
      }
      
      switch source {
      case .localMBTiles(let activeMapPath):
        // Construct the mbtiles:// URL by prepending the scheme to the raw file path.
        // This guarantees the preservation of the three slashes (mbtiles:///Users/...)
        // which MapLibre's internal HTTP interceptor requires to resolve the TileJSON.
        var configurationURL: URL? = nil
        let mbtilesString = "mbtiles://" + activeMapPath.path
        // Safe encode to handle potential spaces in simulator paths
        if let encodedString = mbtilesString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
          configurationURL = URL(string: encodedString)
        } else {
          configurationURL = URL(string: mbtilesString)
        }
        
        if let configURL = configurationURL {
          // Add the raster source using configurationURL and tileSize
          let rasterSource = MLNRasterTileSource(identifier: sourceId, configurationURL: configURL, tileSize: 256)
          style.addSource(rasterSource)
          
          // Add the raster layer at the bottom so it doesn't cover vessel overlays
          let rasterLayer = MLNRasterStyleLayer(identifier: layerId, source: rasterSource)
          style.insertLayer(rasterLayer, at: 0)
          
          Logger.map.info("Programmatically injected MBTiles raster source and layer.")
        }
        
      case .remoteGeoGarage(_, let layerID):
        // Construct GeoGarage URL template using custom local scheme to bypass MapLibre direct request
        let template = "sillage-geo://geogarage-proxy/\(layerID)/{z}/{x}/{y}.png"
        
        let rasterSource = MLNRasterTileSource(identifier: sourceId, tileURLTemplates: [template], options: [
          .minimumZoomLevel: 0,
          .maximumZoomLevel: 16
        ])
        
        style.addSource(rasterSource)
        
        let rasterLayer = MLNRasterStyleLayer(identifier: layerId, source: rasterSource)
        style.insertLayer(rasterLayer, at: 0)
        
        Logger.map.info("Programmatically injected GeoGarage raster source and layer.")
        
      case .openSeaMap:
        let template = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
        let attribution = MLNAttributionInfo(title: NSAttributedString(string: "© OpenStreetMap contributors"), url: URL(string: "https://www.openstreetmap.org/copyright"))
        let rasterSource = MLNRasterTileSource(identifier: sourceId, tileURLTemplates: [template], options: [
          .minimumZoomLevel: 0,
          .maximumZoomLevel: 18,
          .attributionInfos: [attribution]
        ])
        
        style.addSource(rasterSource)
        
        let rasterLayer = MLNRasterStyleLayer(identifier: layerId, source: rasterSource)
        style.insertLayer(rasterLayer, at: 0)
        
        Logger.map.info("Programmatically injected OpenSeaMap raster source and layer.")
      }
      
      // Re-apply OpenSeaMap overlay if it was enabled, to ensure it stays on top of the new base map
      if lastOpenSeaMapOverlayEnabled {
        OpenSeaMapLayerService.shared.removeSeamarkLayer(from: style)
        OpenSeaMapLayerService.shared.addSeamarkLayer(to: style, above: layerId)
      }
      
      // Re-center on the new source's preferred coordinate and zoom if needed
      mapView.setCenter(parent.viewModel.centerCoordinate, zoomLevel: parent.viewModel.zoomLevel, direction: parent.viewModel.mapDirection.converted(to: .degrees).value, animated: false)
      

      if let gpsAccuracyFillLayer = style.layer(withIdentifier: "gps-accuracy-layer") {
        style.removeLayer(gpsAccuracyFillLayer)
        if let strokeLayer = style.layer(withIdentifier: "gps-accuracy-stroke-layer") {
          style.insertLayer(gpsAccuracyFillLayer, below: strokeLayer)
        } else if let headingLayer = style.layer(withIdentifier: "heading-vector-layer") {
          style.insertLayer(gpsAccuracyFillLayer, below: headingLayer)
        } else if let vesselLayer = style.layer(withIdentifier: "vessel-layer") {
          style.insertLayer(gpsAccuracyFillLayer, below: vesselLayer)
        } else {
          style.addLayer(gpsAccuracyFillLayer)
        }
      }
    }
    
    
    
    
    
    
    
    func updateOpenSeaMapOverlay(isEnabled: Bool, style: MLNStyle, mapView: MLNMapView) {
      if lastOpenSeaMapOverlayEnabled != isEnabled {
        lastOpenSeaMapOverlayEnabled = isEnabled
        if isEnabled {
          // Since we now use a consistent base layer ID, we can simply insert above it
          OpenSeaMapLayerService.shared.addSeamarkLayer(to: style, above: "base-raster-layer")
        } else {
          OpenSeaMapLayerService.shared.removeSeamarkLayer(from: style)
        }
      }
    }
    
    func mapView(_ mapView: MLNMapView, didChange mode: MLNUserTrackingMode, animated: Bool) {
      DispatchQueue.main.async {
        // Enforce userTrackingMode = .none
        if mode != .none {
          mapView.userTrackingMode = .none
        }
      }
    }
    
    // Hide the native MapLibre user location puck, as we draw our own custom vessel feature.
    func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
      if annotation is MLNUserLocation {
        let identifier = "hiddenUserLocation"
        var view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MLNUserLocationAnnotationView
        if view == nil {
          view = MLNUserLocationAnnotationView(annotation: annotation, reuseIdentifier: identifier)
        }
        view?.isHidden = true
        view?.alpha = 0
        return view
      }
      return nil
    }
    
    private func shouldBreakTracking(for reason: MLNCameraChangeReason) -> Bool {
      let isZooming = reason.contains(.gesturePinch) || reason.contains(.gestureZoomIn) || reason.contains(.gestureZoomOut) || reason.contains(.gestureOneFingerZoom)
      let isPanningOrRotating = reason.contains(.gesturePan) || reason.contains(.gestureRotate)
      
      // Break tracking ONLY if panning/rotating and NOT zooming
      return isPanningOrRotating && !isZooming
    }
    
    func mapView(_ mapView: MLNMapView, regionWillChangeWith reason: MLNCameraChangeReason, animated: Bool) {
      if shouldBreakTracking(for: reason) {
        DispatchQueue.main.async {
          self.parent.viewModel.mapInteractedByUser()
        }
      }
    }
    
    // Capture user's map movements to break tracking ONLY when the movement stops, as requested
    // Also sync the final camera state back to the ViewModel so it knows where the map is.
    func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason, animated: Bool) {
      DispatchQueue.main.async {
        // Keep ViewModel state in sync with the map
        self.parent.viewModel.centerCoordinate = mapView.centerCoordinate
        self.parent.viewModel.zoomLevel = mapView.zoomLevel
        self.parent.viewModel.mapDirection = Measurement(value: mapView.direction, unit: UnitAngle.degrees)
        
        // Save the camera state to UserDefaults
        self.parent.viewModel.saveCameraState()
        
        // If it was a manual interaction, break tracking
        if self.shouldBreakTracking(for: reason) {
          self.parent.viewModel.mapInteractedByUser()
        }
      }
    }
    
    // Potential loading errors
    func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
      Logger.map.error("Error loading MapLibre map: \(error.localizedDescription, privacy: .public)")
    }
  }
}

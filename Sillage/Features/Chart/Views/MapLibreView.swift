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

struct PopoverMenuAction: Identifiable {
  let id = UUID()
  let title: String
  let systemImage: String
  let isDestructive: Bool
  let action: () -> Void
  
  init(title: String, systemImage: String, isDestructive: Bool = false, action: @escaping () -> Void) {
    self.title = title
    self.systemImage = systemImage
    self.isDestructive = isDestructive
    self.action = action
  }
}

struct PopoverMenuView: View {
  let actions: [PopoverMenuAction]
  
  var body: some View {
    VStack(spacing: 0) {
      ForEach(actions) { action in
        Button(action: action.action) {
          HStack {
            Text(action.title)
              .foregroundColor(action.isDestructive ? .red : .primary)
            Spacer()
            Image(systemName: action.systemImage)
              .foregroundColor(action.isDestructive ? .red : .primary)
          }
          .padding()
          .frame(height: 50)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        
        if action.id != actions.last?.id {
          Divider()
        }
      }
    }
  }
}

extension UIView {
  var parentViewController: UIViewController? {
    var parentResponder: UIResponder? = self
    while parentResponder != nil {
      parentResponder = parentResponder?.next
      if let viewController = parentResponder as? UIViewController {
        return viewController
      }
    }
    return nil
  }
}

struct MapLibreView: UIViewRepresentable {
  
  @Environment(\.marineTheme) var marineTheme
  @Environment(TrackRecordingService.self) private var trackRecordingService
  @Environment(\.waypointService) private var waypointService
  @Environment(PanelManagerViewModel.self) private var panelManager
  @Environment(AppViewModel.self) private var appViewModel
  @Environment(OfflineSelectionViewModel.self) private var offlineSelectionViewModel: OfflineSelectionViewModel?
  var viewModel: ChartViewModel
  
  private enum MapLayer {
    static let activeTrackLayerID = "active-track-layer"
    static let activeTrackSourceID = "active-track-source"
    static let anchorPointLayerID = "anchor-point-layer"
    static let anchorPointSourceID = "anchor-point-source"
    static let anchorRadiusLayerID = "anchor-radius-layer"
    static let anchorRadiusSourceID = "anchor-radius-source"
    static let anchorRadiusStrokeLayerID = "anchor-radius-stroke-layer"
    static let baseRasterLayerID = "base-raster-layer"
    static let baseRasterSourceID = "base-raster-source"
    static let bearingLineLayerID = "bearing-line-layer"
    static let bearingLineSourceID = "bearing-line-source"
    static let goToWaypointLayerID = "goto-waypoint-layer"
    static let goToWaypointSourceID = "goto-waypoint-source"
    static let gpsAccuracyLayerID = "gps-accuracy-layer"
    static let gpsAccuracySourceID = "gps-accuracy-source"
    static let gpsAccuracyStrokeLayerID = "gps-accuracy-stroke-layer"
    static let headingLayerID = "heading-vector-layer"
    static let headingSourceID = "heading-vector-source"
    static let headingTickLayerID = "heading-vector-tick-layer"
    static let savedTrackLayerID = "saved-track-layer"
    static let savedTrackSourceID = "saved-track-source"
    static let vesselLayerID = "vessel-layer"
    static let vesselSourceID = "vessel-source"
    static let visibleWaypointsLayerID = "visible-waypoints-layer"
    static let visibleWaypointsSourceID = "visible-waypoints-source"
  }
  
  private func ensureVesselLayersExist(in style: MLNStyle, with theme: MarineTheme) {
    if style.source(withIdentifier: MapLayer.vesselSourceID) == nil {
      // Create GPS Accuracy Source and Layers first so they are beneath the heading vector and vessel
      let gpsAccuracySource = MLNShapeSource(identifier: MapLayer.gpsAccuracySourceID, shape: nil, options: nil)
      style.addSource(gpsAccuracySource)
      
      let gpsAccuracyFillLayer = MLNFillStyleLayer(identifier: MapLayer.gpsAccuracyLayerID, source: gpsAccuracySource)
      gpsAccuracyFillLayer.fillColor = NSExpression(forConstantValue: UIColor(theme.colors.accent))
      gpsAccuracyFillLayer.fillOpacity = NSExpression(forConstantValue: MarineTheme.ChartMetrics.gpsAccuracyFillOpacity)
      style.addLayer(gpsAccuracyFillLayer)
      
      let gpsAccuracyStrokeLayer = MLNLineStyleLayer(identifier: MapLayer.gpsAccuracyStrokeLayerID, source: gpsAccuracySource)
      gpsAccuracyStrokeLayer.lineColor = NSExpression(forConstantValue: UIColor(theme.colors.accent))
      gpsAccuracyStrokeLayer.lineOpacity = NSExpression(forConstantValue: MarineTheme.ChartMetrics.gpsAccuracyStrokeOpacity)
      gpsAccuracyStrokeLayer.lineWidth = NSExpression(forConstantValue: MarineTheme.ChartMetrics.gpsAccuracyLineWidth)
      style.insertLayer(gpsAccuracyStrokeLayer, above: gpsAccuracyFillLayer)
      
      let activeTrackSource = MLNShapeSource(identifier: MapLayer.activeTrackSourceID, shape: nil, options: nil)
      style.addSource(activeTrackSource)
      let activeTrackLayer = MLNLineStyleLayer(identifier: MapLayer.activeTrackLayerID, source: activeTrackSource)
      activeTrackLayer.lineWidth = NSExpression(forConstantValue: 4.0)
      activeTrackLayer.lineColor = NSExpression(forConstantValue: UIColor.systemRed)
      style.insertLayer(activeTrackLayer, above: gpsAccuracyStrokeLayer)
      
      let savedTrackSource = MLNShapeSource(identifier: MapLayer.savedTrackSourceID, shape: nil, options: nil)
      style.addSource(savedTrackSource)
      let savedTrackLayer = MLNLineStyleLayer(identifier: MapLayer.savedTrackLayerID, source: savedTrackSource)
      savedTrackLayer.lineWidth = NSExpression(forConstantValue: 4.0)
      savedTrackLayer.lineColor = NSExpression(forConstantValue: UIColor.systemBlue)
      style.insertLayer(savedTrackLayer, below: activeTrackLayer)
      
      let goToWaypointSource = MLNShapeSource(identifier: MapLayer.goToWaypointSourceID, shape: nil, options: nil)
      style.addSource(goToWaypointSource)
      let goToWaypointLayer = MLNCircleStyleLayer(identifier: MapLayer.goToWaypointLayerID, source: goToWaypointSource)
      goToWaypointLayer.circleRadius = NSExpression(forConstantValue: 8.0)
      goToWaypointLayer.circleColor = NSExpression(forKeyPath: "color")
      goToWaypointLayer.circleStrokeWidth = NSExpression(forConstantValue: 2.0)
      goToWaypointLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
      style.insertLayer(goToWaypointLayer, below: activeTrackLayer)
      
      let bearingLineSource = MLNShapeSource(identifier: MapLayer.bearingLineSourceID, shape: nil, options: nil)
      style.addSource(bearingLineSource)
      let bearingLineLayer = MLNLineStyleLayer(identifier: MapLayer.bearingLineLayerID, source: bearingLineSource)
      bearingLineLayer.lineWidth = NSExpression(forConstantValue: 1.5)
      bearingLineLayer.lineColor = NSExpression(forKeyPath: "color")
      bearingLineLayer.lineDashPattern = NSExpression(forConstantValue: [4.0, 4.0])
      style.insertLayer(bearingLineLayer, below: goToWaypointLayer)
      
      let visibleWaypointsSource = MLNShapeSource(identifier: MapLayer.visibleWaypointsSourceID, shape: nil, options: nil)
      style.addSource(visibleWaypointsSource)
      let visibleWaypointsLayer = MLNCircleStyleLayer(identifier: MapLayer.visibleWaypointsLayerID, source: visibleWaypointsSource)
      visibleWaypointsLayer.circleRadius = NSExpression(forConstantValue: 6.0)
      visibleWaypointsLayer.circleColor = NSExpression(forKeyPath: "color")
      visibleWaypointsLayer.circleStrokeWidth = NSExpression(forConstantValue: 1.5)
      visibleWaypointsLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
      style.insertLayer(visibleWaypointsLayer, below: goToWaypointLayer)
      
      // Create Heading Source and Layer so it's above gps accuracy but beneath the vessel
      let headingSource = MLNShapeSource(identifier: MapLayer.headingSourceID, shape: nil, options: nil)
      style.addSource(headingSource)
      
      let headingLayer = MLNLineStyleLayer(identifier: MapLayer.headingLayerID, source: headingSource)
      headingLayer.predicate = NSPredicate(format: "featureType == 'vectorLine'")
      headingLayer.lineWidth = NSExpression(forConstantValue: MarineTheme.ChartMetrics.headingLineWidth)
      headingLayer.lineColor = NSExpression(forConstantValue: UIColor(theme.colors.vectorCOG))
      style.addLayer(headingLayer)
      
      let headingTickLayer = MLNCircleStyleLayer(identifier: MapLayer.headingTickLayerID, source: headingSource)
      headingTickLayer.predicate = NSPredicate(format: "featureType == 'vectorTick'")
      headingTickLayer.circleRadius = NSExpression(format: "TERNARY(isMajorTick == YES, 4.0, 2.0)")
      headingTickLayer.circleColor = NSExpression(forConstantValue: UIColor(theme.colors.vectorTick))
      headingTickLayer.circleStrokeWidth = NSExpression(forConstantValue: 1.0)
      headingTickLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.systemBackground)
      style.insertLayer(headingTickLayer, above: headingLayer)
      
      // Create Vessel Source and Layer
      let vesselSource = MLNShapeSource(identifier: MapLayer.vesselSourceID, shape: nil, options: nil)
      style.addSource(vesselSource)
      
      let vesselLayer = MLNSymbolStyleLayer(identifier: MapLayer.vesselLayerID, source: vesselSource)
      vesselLayer.iconImageName = NSExpression(forConstantValue: "vessel-cursor")
      vesselLayer.iconRotationAlignment = NSExpression(forConstantValue: "map")
      vesselLayer.iconRotation = NSExpression(forKeyPath: "course")
      vesselLayer.iconAllowsOverlap = NSExpression(forConstantValue: true)
      vesselLayer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
      vesselLayer.iconOpacity = NSExpression(forConstantValue: 1.0)
      style.addLayer(vesselLayer)
      
      // Create Anchor Layers (below vessel but above GPS accuracy/tracks)
      let anchorRadiusSource = MLNShapeSource(identifier: MapLayer.anchorRadiusSourceID, shape: nil, options: nil)
      style.addSource(anchorRadiusSource)
      
      let anchorRadiusLayer = MLNFillStyleLayer(identifier: MapLayer.anchorRadiusLayerID, source: anchorRadiusSource)
      anchorRadiusLayer.fillColor = NSExpression(forConstantValue: UIColor(theme.colors.anchorDropped))
      anchorRadiusLayer.fillOpacity = NSExpression(forConstantValue: 0.15)
      style.insertLayer(anchorRadiusLayer, below: vesselLayer)
      
      let anchorRadiusStrokeLayer = MLNLineStyleLayer(identifier: MapLayer.anchorRadiusStrokeLayerID, source: anchorRadiusSource)
      anchorRadiusStrokeLayer.lineColor = NSExpression(forConstantValue: UIColor(theme.colors.anchorDropped))
      anchorRadiusStrokeLayer.lineWidth = NSExpression(forConstantValue: 1.5)
      anchorRadiusStrokeLayer.lineOpacity = NSExpression(forConstantValue: 0.8)
      style.insertLayer(anchorRadiusStrokeLayer, above: anchorRadiusLayer)
      
      let anchorPointSource = MLNShapeSource(identifier: MapLayer.anchorPointSourceID, shape: nil, options: nil)
      style.addSource(anchorPointSource)
      
      let anchorPointLayer = MLNSymbolStyleLayer(identifier: MapLayer.anchorPointLayerID, source: anchorPointSource)
      anchorPointLayer.iconImageName = NSExpression(forConstantValue: "anchor-icon")
      anchorPointLayer.iconColor = NSExpression(forConstantValue: UIColor(theme.colors.anchorDropped))
      anchorPointLayer.iconAllowsOverlap = NSExpression(forConstantValue: true)
      anchorPointLayer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
      anchorPointLayer.iconScale = NSExpression(forConstantValue: 1.0)
      style.insertLayer(anchorPointLayer, above: anchorRadiusStrokeLayer)
    }
  }
  
  func makeUIView(context: Context) -> MLNMapView {
    // Initialization of the MapLibre view without a frame
    let mapView = MLNMapView(frame: .zero)
    
    // Explicitly disable automatic inset adjustments to avoid conflicts with SwiftUI Safe Areas
    mapView.automaticallyAdjustsContentInset = false
    // Note: MLNMapView legacy warning persists due to internal SDK check on UIHostingController. Layout is correctly managed by SwiftUI.
    
    mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    
    context.coordinator.mapView = mapView
    
    // Delegate configuration
    mapView.delegate = context.coordinator
    
    // Set maximum zoom level to allow overzooming
    mapView.maximumZoomLevel = AppConstants.Cartography.Zoom.globalMaximum
    
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
    mapView.setCenter(viewModel.centerCoordinate, zoomLevel: viewModel.zoomLevel, direction: viewModel.chartDirection.converted(to: .degrees).value, animated: false)
    
    // Setup subscription for explicit user location centering via AsyncStream
    context.coordinator.setupSubscription(for: mapView)
    
    // Setup long press gesture for contextual menu / waypoint creation
    let longPressGesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
    longPressGesture.minimumPressDuration = 0.5
    mapView.addGestureRecognizer(longPressGesture)
    
    return mapView
  }
  
  func updateUIView(_ uiView: MLNMapView, context: Context) {
    // Updates the coordinator's parent to always point to the latest view (SwiftUI struct)
    context.coordinator.parent = self
    
    // Unconditional observation of state to ensure updateUIView is triggered 
    // even if the map style hasn't fully loaded yet.
    let vesselVisualState = viewModel.vesselVisualState
    let headingVectorData = viewModel.headingVectorData
    let gpsAccuracyVisualState = viewModel.gpsAccuracyVisualState
    let activeTrackPoints = trackRecordingService.trackPoints
    let savedTrackVisualState = viewModel.savedTrackVisualState
    let visibleWaypointVisualStates = viewModel.visibleWaypointVisualStates
    let goToWaypointVisualState = viewModel.goToWaypointVisualState
    let bearingLineVisualState = viewModel.bearingLineVisualState
    let isDataStale = viewModel.isDataStale
    let currentSource = viewModel.currentChartSource
    let isOpenSeaMapOverlayEnabled = viewModel.isOpenSeaMapOverlayEnabled
    let trackingMode = viewModel.trackingMode
    
    // Defensive Update for Vessel and Heading Features
    if let style = uiView.style {
      ensureVesselLayersExist(in: style, with: marineTheme)
      
      // Vessel feature update
      if vesselVisualState != context.coordinator.lastVesselVisualState {
        if let source = style.source(withIdentifier: MapLayer.vesselSourceID) as? MLNShapeSource {
          source.shape = MapLibreFeatureFactory.createVesselFeature(from: vesselVisualState)
          context.coordinator.lastVesselVisualState = vesselVisualState
        }
      }
      
      // Heading vector feature update
      if headingVectorData != context.coordinator.lastHeadingVectorData {
        if let source = style.source(withIdentifier: MapLayer.headingSourceID) as? MLNShapeSource {
          source.shape = MapLibreFeatureFactory.createHeadingVectorFeature(from: headingVectorData)
          context.coordinator.lastHeadingVectorData = headingVectorData
        }
      }
      
      // GPS accuracy feature update
      if gpsAccuracyVisualState != context.coordinator.lastGpsAccuracyVisualState {
        if let source = style.source(withIdentifier: MapLayer.gpsAccuracySourceID) as? MLNShapeSource {
          source.shape = MapLibreFeatureFactory.createAccuracyFeature(from: gpsAccuracyVisualState)
          context.coordinator.lastGpsAccuracyVisualState = gpsAccuracyVisualState
        }
      }
      
      // Active track feature update
      let currentActiveCount = activeTrackPoints.count
      let currentActiveTimestamp = activeTrackPoints.last?.timestamp
      if currentActiveCount != context.coordinator.lastActiveTrackCount || currentActiveTimestamp != context.coordinator.lastActiveTrackTimestamp {
        if let source = style.source(withIdentifier: MapLayer.activeTrackSourceID) as? MLNShapeSource {
          source.shape = generateActiveTrackFeature(from: activeTrackPoints)
          context.coordinator.lastActiveTrackCount = currentActiveCount
          context.coordinator.lastActiveTrackTimestamp = currentActiveTimestamp
        }
      }
      
      // Saved track feature update
      if savedTrackVisualState != context.coordinator.lastSavedTrackVisualState {
        if let source = style.source(withIdentifier: MapLayer.savedTrackSourceID) as? MLNShapeSource {
          source.shape = MapLibreFeatureFactory.createSavedTrackFeature(from: savedTrackVisualState)
          context.coordinator.lastSavedTrackVisualState = savedTrackVisualState
        }
      }
      
      // Displayed waypoints feature update
      if visibleWaypointVisualStates != context.coordinator.lastVisibleWaypointVisualStates {
        if let source = style.source(withIdentifier: MapLayer.visibleWaypointsSourceID) as? MLNShapeSource {
          source.shape = MapLibreFeatureFactory.createVisibleWaypointsFeature(from: visibleWaypointVisualStates)
          context.coordinator.lastVisibleWaypointVisualStates = visibleWaypointVisualStates
        }
      }
      
      // GoTo waypoint feature update
      if goToWaypointVisualState != context.coordinator.lastGoToWaypointVisualState {
        if let source = style.source(withIdentifier: MapLayer.goToWaypointSourceID) as? MLNShapeSource {
          source.shape = MapLibreFeatureFactory.createGoToWaypointFeature(from: goToWaypointVisualState)
          context.coordinator.lastGoToWaypointVisualState = goToWaypointVisualState
        }
      }
      
      // Bearing Line feature update
      if bearingLineVisualState != context.coordinator.lastBearingLineVisualState {
        if let source = style.source(withIdentifier: MapLayer.bearingLineSourceID) as? MLNShapeSource {
          source.shape = MapLibreFeatureFactory.createBearingLineFeature(from: bearingLineVisualState)
          context.coordinator.lastBearingLineVisualState = bearingLineVisualState
        }
      }
      
      // Anchor update
      let currentVisualState = viewModel.anchorVisualState
      if currentVisualState != context.coordinator.lastAnchorVisualState {
        context.coordinator.lastAnchorVisualState = currentVisualState
        let anchorFeatures = MapLibreFeatureFactory.createAnchorFeatures(from: currentVisualState)
        if let source = style.source(withIdentifier: MapLayer.anchorRadiusSourceID) as? MLNShapeSource {
          source.shape = anchorFeatures.radiusFeature
        }
        if let source = style.source(withIdentifier: MapLayer.anchorPointSourceID) as? MLNShapeSource {
          source.shape = anchorFeatures.pointFeature
        }
        if let status = currentVisualState?.status {
          updateAnchorLayerStyles(in: style, for: status, with: marineTheme)
        }
      }
      
      // Data Stale state update (Opacity)
      if isDataStale != context.coordinator.lastDataStale {
        if let layer = style.layer(withIdentifier: MapLayer.vesselLayerID) as? MLNSymbolStyleLayer {
          layer.iconOpacity = NSExpression(forConstantValue: isDataStale ? 0.4 : 1.0)
          context.coordinator.lastDataStale = isDataStale
        }
      }
    }
    
    if let offlineVM = offlineSelectionViewModel, offlineVM.isSelectionModeActive {
      if uiView.direction != 0 {
        uiView.setDirection(0, animated: true)
      }
      if uiView.camera.pitch != 0 {
        let camera = uiView.camera
        camera.pitch = 0
        uiView.setCamera(camera, animated: true)
      }
      uiView.isRotateEnabled = false
      
      context.coordinator.updateOfflineSelectionBounds(mapView: uiView)
    } else {
      uiView.isRotateEnabled = true
    }
    
    // Stop inertia cleanly when locking tracking mode without triggering delegate events
    if context.coordinator.lastTrackingMode != trackingMode {
      if context.coordinator.lastTrackingMode == .free && trackingMode != .free {
        uiView.delegate = nil
        uiView.setCamera(uiView.camera, animated: false)
        uiView.delegate = context.coordinator
      }
      context.coordinator.lastTrackingMode = trackingMode
    }
    
    // Force tracking mode to none if it deviated, since tracking is explicitly handled in the viewModel
    if uiView.userTrackingMode != .none {
      uiView.userTrackingMode = .none
    }
    
    // If the map source has changed, update the map's style/source
    if let currentSource = currentSource,
       context.coordinator.lastChartSource != currentSource,
       let style = uiView.style {
      context.coordinator.updateChartSource(currentSource, style: style, mapView: uiView)
    }
    
    // Handle OpenSeaMap overlay toggle
    if let style = uiView.style {
      context.coordinator.updateOpenSeaMapOverlay(isEnabled: isOpenSeaMapOverlayEnabled, style: style, mapView: uiView)
    }
    
    // Handle Content Inset for Look-ahead in Course Up mode
    let newInset: UIEdgeInsets
    if trackingMode == .courseUp {
      let lookAheadOffset = uiView.bounds.height / 3.0
      newInset = UIEdgeInsets(top: lookAheadOffset, left: 0, bottom: 0, right: 0)
    } else {
      newInset = .zero
    }
    
    if uiView.contentInset != newInset {
      uiView.setContentInset(newInset, animated: true, completionHandler: nil)
    }
    
    // Disable compass interaction when in an automated tracking mode to prevent state conflicts
    uiView.compassView.isUserInteractionEnabled = (trackingMode != .courseUp)
  }

  private func updateAnchorLayerStyles(in style: MLNStyle, for status: AnchorVisualStatus, with theme: MarineTheme) {
    if let pointLayer = style.layer(withIdentifier: MapLayer.anchorPointLayerID) as? MLNSymbolStyleLayer {
      let pointColor: UIColor = (status == .setup)
        ? UIColor(theme.colors.anchorDropped).withAlphaComponent(0.5)
        : UIColor(theme.colors.anchorDropped)
      
      pointLayer.iconColor = NSExpression(forConstantValue: pointColor)
    }
    
    // Configuration de la zone de rayon (Fill & Stroke)
    guard let fillLayer = style.layer(withIdentifier: MapLayer.anchorRadiusLayerID) as? MLNFillStyleLayer,
          let strokeLayer = style.layer(withIdentifier: MapLayer.anchorRadiusStrokeLayerID) as? MLNLineStyleLayer else {
      return
    }
    
    switch status {
    case .setup:
      fillLayer.fillOpacity = NSExpression(forConstantValue: 0.0)
      strokeLayer.lineOpacity = NSExpression(forConstantValue: 0.0)
      
    case .dropped:
      let color = UIColor(theme.colors.anchorDropped)
      fillLayer.fillColor = NSExpression(forConstantValue: color)
      fillLayer.fillOpacity = NSExpression(forConstantValue: 0.0)
      
      strokeLayer.lineColor = NSExpression(forConstantValue: color)
      strokeLayer.lineDashPattern = NSExpression(forConstantValue: [4.0, 4.0])
      strokeLayer.lineWidth = NSExpression(forConstantValue: 3.0)
      strokeLayer.lineOpacity = NSExpression(forConstantValue: 1.0)
      
    case .armed:
      let color = UIColor(theme.colors.anchorArmed)
      fillLayer.fillColor = NSExpression(forConstantValue: color)
      fillLayer.fillOpacity = NSExpression(forConstantValue: 0.10)
      
      strokeLayer.lineColor = NSExpression(forConstantValue: color)
      strokeLayer.lineDashPattern = nil
      strokeLayer.lineWidth = NSExpression(forConstantValue: 1.5)
      strokeLayer.lineOpacity = NSExpression(forConstantValue: 0.8)
      
    case .dragging:
      let color = UIColor(theme.colors.anchorDragging)
      fillLayer.fillColor = NSExpression(forConstantValue: color)
      fillLayer.fillOpacity = NSExpression(forConstantValue: 0.25)
      
      strokeLayer.lineColor = NSExpression(forConstantValue: color)
      strokeLayer.lineDashPattern = nil
      strokeLayer.lineWidth = NSExpression(forConstantValue: 1.5)
      strokeLayer.lineOpacity = NSExpression(forConstantValue: 1.0)
    }
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
      currentSegment.append(point.coordinate)
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
      Logger.chart.warning("blank-style.json not found in App Bundle. MapLibre may not initialize correctly.")
      return nil
    }
    return styleURL
  }
  
  // MARK: - Coordinator
  
  @MainActor
  class Coordinator: NSObject, MLNMapViewDelegate, UIPopoverPresentationControllerDelegate {
    var parent: MapLibreView
    private var streamTask: Task<Void, Never>?
    private var pendingBoundsUpdateTask: Task<Void, Never>?
    var lastChartSource: ChartSource?
    weak var mapView: MLNMapView?
    
    // Cache for diffing to avoid unnecessary MapLibre shape updates
    var lastVesselVisualState: VesselVisualState?
    var lastHeadingVectorData: HeadingVectorData?
    var lastGpsAccuracyVisualState: GpsAccuracyVisualState?
    var lastSavedTrackVisualState: SavedTrackVisualState?
    var lastVisibleWaypointVisualStates: [WaypointVisualState] = []
    var lastGoToWaypointVisualState: WaypointVisualState?
    var lastBearingLineVisualState: BearingLineVisualState?
    var lastAnchorVisualState: AnchorVisualState?
    
    var lastActiveTrackCount: Int?
    var lastActiveTrackTimestamp: Date?
    var lastDataStale: Bool?
    var lastTrackingMode: ChartTrackingMode = .free
    
    init(_ parent: MapLibreView) {
      self.parent = parent
      super.init()
      
      NotificationCenter.default.addObserver(forName: NSNotification.Name("NetworkDidReconnect"), object: nil, queue: .main) { [weak self] _ in
        Task { @MainActor [weak self] in
          guard let self = self, let mapView = self.mapView else { return }
          Logger.chart.info("Network reconnected, forcing MapLibre complete style reload")
          mapView.reloadStyle(nil)
        }
      }
    }
    
    deinit {
      streamTask?.cancel()
      pendingBoundsUpdateTask?.cancel()
      NotificationCenter.default.removeObserver(self)
    }
    
    @objc func handleLongPress(_ sender: UILongPressGestureRecognizer) {
      // Only trigger at the start of the gesture to prevent multiple openings
      guard sender.state == .began else { return }
      guard let mapView = sender.view as? MLNMapView else { return }
      let point = sender.location(in: mapView)
      
      let touchRect = CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
      let features = mapView.visibleFeatures(in: touchRect, styleLayerIdentifiers: [MapLayer.goToWaypointLayerID, MapLayer.visibleWaypointsLayerID])
      
      if let feature = features.first as? MLNPointFeature,
         let id = feature.attributes[MapFeatureKey.id.rawValue] as? String {
        let isSelected = self.parent.viewModel.goToWaypointID == id
        
        let actionTitle = isSelected ? String(localized: "Deselect") : String(localized: "Select")
        let actionImageName = isSelected ? MarineIcon.deselect.rawValue : MarineIcon.select.rawValue
        
        let selectAction = PopoverMenuAction(title: actionTitle, systemImage: actionImageName) { [weak self] in
          guard let self = self else { return }
          Task { @MainActor in
            if isSelected {
              self.parent.waypointService?.setDestination(waypointID: nil)
            } else {
              self.parent.waypointService?.setDestination(waypointID: id)
            }
          }
          mapView.parentViewController?.presentedViewController?.dismiss(animated: true)
        }
        
        let editAction = PopoverMenuAction(title: String(localized: "Show Details"), systemImage: MarineIcon.details.rawValue) { [weak self] in
          guard let self = self else { return }
          Task { @MainActor in
            self.parent.panelManager.commandPath = [.waypoints, .waypointDetail(id)]
            self.parent.panelManager.openPanel(.command)
          }
          mapView.parentViewController?.presentedViewController?.dismiss(animated: true)
        }
        
        showPopover(actions: [editAction, selectAction], at: point, in: mapView)
        
      } else {
        let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
        var actions: [PopoverMenuAction] = []
        
        let createAction = PopoverMenuAction(title: String(localized: "Create Waypoint…"), systemImage: MarineIcon.waypoint.rawValue) { [weak self] in
          guard let self = self else { return }
          Task { @MainActor in
            var defaultName: String? = nil
            if let service = self.parent.waypointService {
              defaultName = await service.generateDefaultName()
            }
            let draftCoord = CoordinateWrapper(coordinate: coordinate, defaultName: defaultName)
            self.parent.appViewModel.waypointDraft = draftCoord
          }
          mapView.parentViewController?.presentedViewController?.dismiss(animated: true)
        }
        actions.append(createAction)
        
        if self.parent.viewModel.goToWaypointID != nil {
          let deselectAction = PopoverMenuAction(title: String(localized: "Deselect Target"), systemImage: MarineIcon.deselect.rawValue) { [weak self] in
            Task { @MainActor in
              self?.parent.waypointService?.setDestination(waypointID: nil)
            }
            mapView.parentViewController?.presentedViewController?.dismiss(animated: true)
          }
          actions.append(deselectAction)
        }
        
        showPopover(actions: actions, at: point, in: mapView)
      }
    }
    
    private func showPopover(actions: [PopoverMenuAction], at point: CGPoint, in mapView: MLNMapView) {
      let popoverContent = PopoverMenuView(actions: actions)
      let hostingController = UIHostingController(rootView: popoverContent)
      hostingController.preferredContentSize = CGSize(width: 250, height: CGFloat(actions.count * 50))
      hostingController.modalPresentationStyle = .popover
      
      if let popover = hostingController.popoverPresentationController {
        popover.sourceView = mapView
        popover.sourceRect = CGRect(x: point.x, y: point.y, width: 1, height: 1)
        popover.delegate = self
        popover.permittedArrowDirections = .any
      }
      
      mapView.parentViewController?.present(hostingController, animated: true)
    }
    
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
      return .none
    }
    
    func setupSubscription(for mapView: MLNMapView) {
      streamTask?.cancel()
      streamTask = Task { @MainActor in
        for await event in parent.viewModel.cameraMoveStream {
          switch event {
          case .fitBounds(let bounds, let padding):
            let mlnBounds = MLNCoordinateBounds(sw: bounds.southWest, ne: bounds.northEast)
            await mapView.setVisibleCoordinateBounds(mlnBounds, edgePadding: padding, animated: true)
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
    
    func mapViewRegionIsChanging(_ mapView: MLNMapView) {
      let mpp = mapView.metersPerPoint(atLatitude: mapView.centerCoordinate.latitude)
      self.parent.viewModel.mapScale = Measurement(value: mpp, unit: UnitLength.meters)
      self.parent.viewModel.zoomLevel = mapView.zoomLevel
    }
    
    func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
      let mpp = mapView.metersPerPoint(atLatitude: mapView.centerCoordinate.latitude)
      self.parent.viewModel.mapScale = Measurement(value: mpp, unit: UnitLength.meters)
      self.parent.viewModel.zoomLevel = mapView.zoomLevel
    }
    
    // Called when the map has finished loading its style
    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
      Logger.chart.info("MapLibre successfully loaded the default style.")
      
      // Add vessel cursor image
      if let image = VesselGraphicsFactory.createVesselImage(size: MarineTheme.ChartMetrics.vesselCursorBaseSize, color: UIColor(parent.marineTheme.colors.accent)) {
        style.setImage(image, forName: "vessel-cursor")
      }
      
      // Add anchor icon
      let anchorConfig = UIImage.SymbolConfiguration(weight: .heavy)
      if let anchorImage = UIImage(systemName: "anchor", withConfiguration: anchorConfig)?.withRenderingMode(.alwaysTemplate) {
        style.setImage(anchorImage, forName: "anchor-icon")
      }
      
      if let currentSource = parent.viewModel.currentChartSource {
        updateChartSource(currentSource, style: style, mapView: mapView)
      }
      
      updateOpenSeaMapOverlay(isEnabled: parent.viewModel.isOpenSeaMapOverlayEnabled, style: style, mapView: mapView)
      
      // Ensure vessel layers are initialized after style finishes loading
      parent.ensureVesselLayersExist(in: style, with: parent.marineTheme)
      if let source = style.source(withIdentifier: MapLayer.headingSourceID) as? MLNShapeSource {
        let data = parent.viewModel.headingVectorData
        source.shape = MapLibreFeatureFactory.createHeadingVectorFeature(from: data)
        lastHeadingVectorData = data
      }
      if let source = style.source(withIdentifier: MapLayer.gpsAccuracySourceID) as? MLNShapeSource {
        let state = parent.viewModel.gpsAccuracyVisualState
        source.shape = MapLibreFeatureFactory.createAccuracyFeature(from: state)
        lastGpsAccuracyVisualState = state
      }
      if let source = style.source(withIdentifier: MapLayer.vesselSourceID) as? MLNShapeSource {
        let state = parent.viewModel.vesselVisualState
        source.shape = MapLibreFeatureFactory.createVesselFeature(from: state)
        lastVesselVisualState = state
      }
      if let source = style.source(withIdentifier: MapLayer.activeTrackSourceID) as? MLNShapeSource {
        source.shape = parent.generateActiveTrackFeature(from: parent.trackRecordingService.trackPoints)
        lastActiveTrackCount = parent.trackRecordingService.trackPoints.count
        lastActiveTrackTimestamp = parent.trackRecordingService.trackPoints.last?.timestamp
      }
      if let source = style.source(withIdentifier: MapLayer.savedTrackSourceID) as? MLNShapeSource {
        let state = parent.viewModel.savedTrackVisualState
        source.shape = MapLibreFeatureFactory.createSavedTrackFeature(from: state)
        lastSavedTrackVisualState = state
      }
      if let source = style.source(withIdentifier: MapLayer.visibleWaypointsSourceID) as? MLNShapeSource {
        let states = parent.viewModel.visibleWaypointVisualStates
        source.shape = MapLibreFeatureFactory.createVisibleWaypointsFeature(from: states)
        lastVisibleWaypointVisualStates = states
      }
      if let source = style.source(withIdentifier: MapLayer.goToWaypointSourceID) as? MLNShapeSource {
        let state = parent.viewModel.goToWaypointVisualState
        source.shape = MapLibreFeatureFactory.createGoToWaypointFeature(from: state)
        lastGoToWaypointVisualState = state
      }
      if let source = style.source(withIdentifier: MapLayer.bearingLineSourceID) as? MLNShapeSource {
        let state = parent.viewModel.bearingLineVisualState
        source.shape = MapLibreFeatureFactory.createBearingLineFeature(from: state)
        lastBearingLineVisualState = state
      }
      // Anchor features & styles initialization
      let anchorVisualState = parent.viewModel.anchorVisualState
      let anchorFeatures = MapLibreFeatureFactory.createAnchorFeatures(from: anchorVisualState)
      
      if let source = style.source(withIdentifier: MapLayer.anchorRadiusSourceID) as? MLNShapeSource {
        source.shape = anchorFeatures.radiusFeature
      }
      if let source = style.source(withIdentifier: MapLayer.anchorPointSourceID) as? MLNShapeSource {
        source.shape = anchorFeatures.pointFeature
      }
      if let status = anchorVisualState?.status {
        parent.updateAnchorLayerStyles(in: style, for: status, with: parent.marineTheme)
      }
      lastAnchorVisualState = anchorVisualState
      if let layer = style.layer(withIdentifier: MapLayer.vesselLayerID) as? MLNSymbolStyleLayer {
        let isStale = parent.viewModel.isDataStale
        layer.iconOpacity = NSExpression(forConstantValue: isStale ? 0.4 : 1.0)
        lastDataStale = isStale
      }
      
      // NOTE: We do not call `mapView.setVisibleCoordinateBounds` here.
      // In SwiftUI, `didFinishLoading` can fire before the map view has a non-zero frame.
      // Calling coordinate bounds on a `.zero` frame corrupts the MapLibre camera (`NaN` zoom level).
      // Instead, we simply jump the camera back to the exact metadata `centerCoordinate` and `zoomLevel`.
      // This is required because loading the blank JSON style resets the map to (0,0), which leaves it looking at
      // the African coast where no French marine chart tiles exist, causing the map to appear blank.
      mapView.setCenter(parent.viewModel.centerCoordinate, zoomLevel: parent.viewModel.zoomLevel, direction: parent.viewModel.chartDirection.converted(to: .degrees).value, animated: false)
    }
    
    func updateChartSource(_ source: ChartSource, style: MLNStyle, mapView: MLNMapView) {
      lastChartSource = source
      
      // 1. Clean up the layer FIRST
      if let existingLayer = style.layer(withIdentifier: MapLayer.baseRasterLayerID) {
        style.removeLayer(existingLayer)
        Logger.chart.debug("Removed existing layer: \(MapLayer.baseRasterLayerID, privacy: .public)")
      }
      
      // 2. Clean up the source SECOND
      if let existingSource = style.source(withIdentifier: MapLayer.baseRasterSourceID) {
        style.removeSource(existingSource)
        Logger.chart.debug("Removed existing source: \(MapLayer.baseRasterSourceID, privacy: .public)")
      }
      
      var newSource: MLNRasterTileSource?
      
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
          newSource = MLNRasterTileSource(identifier: MapLayer.baseRasterSourceID, configurationURL: configURL, tileSize: AppConstants.Cartography.Tile.rasterTileSize)
        }
        
      case .remoteGeoGarage(let clientID, let remoteLayerID):
        let template = "https://tiles.geogarage.com/\(clientID)/\(remoteLayerID)/{z}/{x}/{y}.png"
        newSource = MLNRasterTileSource(identifier: MapLayer.baseRasterSourceID, tileURLTemplates: [template], options: [
          .minimumZoomLevel: AppConstants.Cartography.Zoom.globalMinimum,
          .maximumZoomLevel: AppConstants.Cartography.Zoom.geoGarageMaximum,
          .tileSize: 256
        ])
        
      case .openSeaMap:
        let template = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
        let attribution = MLNAttributionInfo(title: NSAttributedString(string: "© OpenStreetMap contributors"), url: URL(string: "https://www.openstreetmap.org/copyright"))
        newSource = MLNRasterTileSource(identifier: MapLayer.baseRasterSourceID, tileURLTemplates: [template], options: [
          .minimumZoomLevel: AppConstants.Cartography.Zoom.globalMinimum,
          .maximumZoomLevel: AppConstants.Cartography.Zoom.openSeaMapMaximum,
          .attributionInfos: [attribution],
          .tileSize: AppConstants.Cartography.Tile.rasterTileSize
        ])
      }
      
      // 3. Defensively add the new source and layer
      if let rasterSource = newSource {
        if style.source(withIdentifier: MapLayer.baseRasterSourceID) == nil {
          style.addSource(rasterSource)
          Logger.chart.debug("Added source: \(MapLayer.baseRasterSourceID, privacy: .public)")
        } else {
          Logger.chart.error("Defensive check failed: Source \(MapLayer.baseRasterSourceID, privacy: .public) already exists despite cleanup.")
        }
        
        if style.layer(withIdentifier: MapLayer.baseRasterLayerID) == nil {
          let rasterLayer = MLNRasterStyleLayer(identifier: MapLayer.baseRasterLayerID, source: rasterSource)
          style.insertLayer(rasterLayer, at: 0)
          Logger.chart.debug("Added layer: \(MapLayer.baseRasterLayerID, privacy: .public)")
        } else {
          Logger.chart.error("Defensive check failed: Layer \(MapLayer.baseRasterLayerID, privacy: .public) already exists despite cleanup.")
        }
      }
      
      // Re-apply OpenSeaMap overlay if it was enabled, to ensure it stays on top of the new base map
      if lastOpenSeaMapOverlayEnabled {
        OpenSeaMapLayerService.shared.removeSeamarkLayer(from: style)
        OpenSeaMapLayerService.shared.addSeamarkLayer(to: style, above: MapLayer.baseRasterLayerID)
      }
      
      // Re-center on the new source's preferred coordinate and zoom if needed
      mapView.setCenter(parent.viewModel.centerCoordinate, zoomLevel: parent.viewModel.zoomLevel, direction: parent.viewModel.chartDirection.converted(to: .degrees).value, animated: false)
      

      if let gpsAccuracyFillLayer = style.layer(withIdentifier: MapLayer.gpsAccuracyLayerID) {
        style.removeLayer(gpsAccuracyFillLayer)
        if let strokeLayer = style.layer(withIdentifier: MapLayer.gpsAccuracyStrokeLayerID) {
          style.insertLayer(gpsAccuracyFillLayer, below: strokeLayer)
        } else if let headingLayer = style.layer(withIdentifier: MapLayer.headingLayerID) {
          style.insertLayer(gpsAccuracyFillLayer, below: headingLayer)
        } else if let vesselLayer = style.layer(withIdentifier: MapLayer.vesselLayerID) {
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
          OpenSeaMapLayerService.shared.addSeamarkLayer(to: style, above: MapLayer.baseRasterLayerID)
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
        Task { @MainActor [weak self] in
          guard let self else { return }
          self.parent.viewModel.chartInteractedByUser()
        }
      }
    }
    
    @MainActor
    func updateOfflineSelectionBounds(mapView: MLNMapView) {
      if let offlineVM = self.parent.offlineSelectionViewModel, offlineVM.isSelectionModeActive {
        let rect = offlineVM.cropRect ?? {
            let baseSize = min(mapView.bounds.width, mapView.bounds.height) * offlineVM.cropBoxWidthRatio
            let size = CGSize(width: baseSize, height: baseSize * offlineVM.cropBoxAspect)
            let x = (mapView.bounds.width - size.width) / 2.0
            let y = (mapView.bounds.height - size.height) / 2.0
            return CGRect(x: x, y: y, width: size.width, height: size.height)
        }()
        
        let mlnBounds = mapView.convert(rect, toCoordinateBoundsFrom: mapView)
        
        let bounds = GeographicBoundingBox(
          southWest: mlnBounds.sw,
          northEast: mlnBounds.ne
        )
        
        // Prevent redundant recalculations by only updating if bounds have changed significantly
        // This avoids infinite loops caused by MapLibre floating point conversion drift
        if let current = offlineVM.selectedBounds, current.isApproximatelyEqual(to: bounds) {
            return
        }
        
        // Cancel any pending bounds update to avoid saturating the MainActor with redundant tasks.
        pendingBoundsUpdateTask?.cancel()
        
        // Defer the mutation and debounce it by 50ms to avoid
        // "Modifying state during view update" runtime warnings in SwiftUI
        // and to prevent CPU saturation from rapid MapLibre layout passes.
        pendingBoundsUpdateTask = Task { @MainActor [weak offlineVM] in
            do {
                try await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                offlineVM?.updateBoundingBox(bounds)
            } catch is CancellationError {
                // Task was cancelled by a newer layout update, exit cleanly.
            } catch {
                // Ignore other potential sleep errors.
            }
        }
      }
    }
    
    // Capture user's chart movements to break tracking ONLY when the movement stops, as requested
    // Also sync the final camera state back to the ViewModel so it knows where the chart is.
    func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason, animated: Bool) {
      Task { @MainActor [weak self] in
        guard let self else { return }
        
        // Keep ViewModel state in sync with the chart.
        self.parent.viewModel.centerCoordinate = mapView.centerCoordinate
        self.parent.viewModel.zoomLevel = mapView.zoomLevel
        self.parent.viewModel.chartDirection = Measurement(value: mapView.direction, unit: UnitAngle.degrees)
        
        // Save the camera state to UserDefaults
        self.parent.viewModel.saveCameraState()
        
        // Compute geographic bounding box for offline selection locally and pass it down
        self.updateOfflineSelectionBounds(mapView: mapView)
        
        // If it was a manual interaction, break tracking
        if self.shouldBreakTracking(for: reason) {
          self.parent.viewModel.chartInteractedByUser()
        }
      }
    }
    
    // Potential loading errors
    func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
      Logger.chart.error("Error loading MapLibre map: \(error.localizedDescription, privacy: .public)")
    }
  }
}

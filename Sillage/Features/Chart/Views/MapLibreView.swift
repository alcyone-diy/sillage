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
  
  
  private func ensureVesselLayersExist(in style: MLNStyle, with theme: MarineTheme) {
    let vesselSourceID = "vessel-source"
    let vesselLayerID = "vessel-layer"
    let headingSourceID = "heading-vector-source"
    let headingLayerID = "heading-vector-layer"
    let gpsAccuracySourceID = "gps-accuracy-source"
    let gpsAccuracyLayerID = "gps-accuracy-layer"
    let gpsAccuracyStrokeLayerID = "gps-accuracy-stroke-layer"
    let savedTrackSourceID = "saved-track-source"
    let savedTrackLayerID = "saved-track-layer"
    let activeTrackSourceID = "active-track-source"
    let activeTrackLayerID = "active-track-layer"
    let goToWaypointSourceID = "goto-waypoint-source"
    let goToWaypointLayerID = "goto-waypoint-layer"
    let visibleWaypointsSourceID = "visible-waypoints-source"
    let visibleWaypointsLayerID = "visible-waypoints-layer"
    let bearingLineSourceID = "bearing-line-source"
    let bearingLineLayerID = "bearing-line-layer"
    let anchorRadiusSourceID = "anchor-radius-source"
    let anchorRadiusLayerID = "anchor-radius-layer"
    let anchorPointSourceID = "anchor-point-source"
    let anchorPointLayerID = "anchor-point-layer"
    
    if style.source(withIdentifier: vesselSourceID) == nil {
      // Create GPS Accuracy Source and Layers first so they are beneath the heading vector and vessel
      let gpsAccuracySource = MLNShapeSource(identifier: gpsAccuracySourceID, shape: nil, options: nil)
      style.addSource(gpsAccuracySource)
      
      let gpsAccuracyFillLayer = MLNFillStyleLayer(identifier: gpsAccuracyLayerID, source: gpsAccuracySource)
      gpsAccuracyFillLayer.fillColor = NSExpression(forConstantValue: UIColor(MarineTheme.Colors.accent))
      gpsAccuracyFillLayer.fillOpacity = NSExpression(forConstantValue: MarineTheme.ChartMetrics.gpsAccuracyFillOpacity)
      style.addLayer(gpsAccuracyFillLayer)
      
      let gpsAccuracyStrokeLayer = MLNLineStyleLayer(identifier: gpsAccuracyStrokeLayerID, source: gpsAccuracySource)
      gpsAccuracyStrokeLayer.lineColor = NSExpression(forConstantValue: UIColor(MarineTheme.Colors.accent))
      gpsAccuracyStrokeLayer.lineOpacity = NSExpression(forConstantValue: MarineTheme.ChartMetrics.gpsAccuracyStrokeOpacity)
      gpsAccuracyStrokeLayer.lineWidth = NSExpression(forConstantValue: MarineTheme.ChartMetrics.gpsAccuracyLineWidth)
      style.insertLayer(gpsAccuracyStrokeLayer, above: gpsAccuracyFillLayer)
      
      let activeTrackSource = MLNShapeSource(identifier: activeTrackSourceID, shape: nil, options: nil)
      style.addSource(activeTrackSource)
      let activeTrackLayer = MLNLineStyleLayer(identifier: activeTrackLayerID, source: activeTrackSource)
      activeTrackLayer.lineWidth = NSExpression(forConstantValue: 4.0)
      activeTrackLayer.lineColor = NSExpression(forConstantValue: UIColor.systemRed)
      style.insertLayer(activeTrackLayer, above: gpsAccuracyStrokeLayer)
      
      let savedTrackSource = MLNShapeSource(identifier: savedTrackSourceID, shape: nil, options: nil)
      style.addSource(savedTrackSource)
      let savedTrackLayer = MLNLineStyleLayer(identifier: savedTrackLayerID, source: savedTrackSource)
      savedTrackLayer.lineWidth = NSExpression(forConstantValue: 4.0)
      savedTrackLayer.lineColor = NSExpression(forConstantValue: UIColor.systemBlue)
      style.insertLayer(savedTrackLayer, below: activeTrackLayer)
      
      let goToWaypointSource = MLNShapeSource(identifier: goToWaypointSourceID, shape: nil, options: nil)
      style.addSource(goToWaypointSource)
      let goToWaypointLayer = MLNCircleStyleLayer(identifier: goToWaypointLayerID, source: goToWaypointSource)
      goToWaypointLayer.circleRadius = NSExpression(forConstantValue: 8.0)
      goToWaypointLayer.circleColor = NSExpression(forKeyPath: "color")
      goToWaypointLayer.circleStrokeWidth = NSExpression(forConstantValue: 2.0)
      goToWaypointLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
      style.insertLayer(goToWaypointLayer, below: activeTrackLayer)
      
      let bearingLineSource = MLNShapeSource(identifier: bearingLineSourceID, shape: nil, options: nil)
      style.addSource(bearingLineSource)
      let bearingLineLayer = MLNLineStyleLayer(identifier: bearingLineLayerID, source: bearingLineSource)
      bearingLineLayer.lineWidth = NSExpression(forConstantValue: 1.5)
      bearingLineLayer.lineColor = NSExpression(forKeyPath: "color")
      bearingLineLayer.lineDashPattern = NSExpression(forConstantValue: [4.0, 4.0])
      style.insertLayer(bearingLineLayer, below: goToWaypointLayer)
      
      let visibleWaypointsSource = MLNShapeSource(identifier: visibleWaypointsSourceID, shape: nil, options: nil)
      style.addSource(visibleWaypointsSource)
      let visibleWaypointsLayer = MLNCircleStyleLayer(identifier: visibleWaypointsLayerID, source: visibleWaypointsSource)
      visibleWaypointsLayer.circleRadius = NSExpression(forConstantValue: 6.0)
      visibleWaypointsLayer.circleColor = NSExpression(forKeyPath: "color")
      visibleWaypointsLayer.circleStrokeWidth = NSExpression(forConstantValue: 1.5)
      visibleWaypointsLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
      style.insertLayer(visibleWaypointsLayer, below: goToWaypointLayer)
      
      // Create Heading Source and Layer so it's above gps accuracy but beneath the vessel
      let headingSource = MLNShapeSource(identifier: headingSourceID, shape: nil, options: nil)
      style.addSource(headingSource)
      
      let headingLayer = MLNLineStyleLayer(identifier: headingLayerID, source: headingSource)
      headingLayer.predicate = NSPredicate(format: "featureType == 'vectorLine'")
      headingLayer.lineWidth = NSExpression(forConstantValue: MarineTheme.ChartMetrics.headingLineWidth)
      headingLayer.lineColor = NSExpression(forConstantValue: UIColor(MarineTheme.Colors.vectorCOG))
      style.addLayer(headingLayer)
      
      let headingTickLayerID = "heading-vector-tick-layer"
      let headingTickLayer = MLNCircleStyleLayer(identifier: headingTickLayerID, source: headingSource)
      headingTickLayer.predicate = NSPredicate(format: "featureType == 'vectorTick'")
      headingTickLayer.circleRadius = NSExpression(format: "TERNARY(isMajorTick == YES, 4.0, 2.0)")
      headingTickLayer.circleColor = NSExpression(forConstantValue: UIColor(MarineTheme.Colors.vectorTick))
      headingTickLayer.circleStrokeWidth = NSExpression(forConstantValue: 1.0)
      headingTickLayer.circleStrokeColor = NSExpression(forConstantValue: UIColor.systemBackground)
      style.insertLayer(headingTickLayer, above: headingLayer)
      
      // Create Vessel Source and Layer
      let vesselSource = MLNShapeSource(identifier: vesselSourceID, shape: nil, options: nil)
      style.addSource(vesselSource)
      
      let vesselLayer = MLNSymbolStyleLayer(identifier: vesselLayerID, source: vesselSource)
      vesselLayer.iconImageName = NSExpression(forConstantValue: "vessel-cursor")
      vesselLayer.iconRotationAlignment = NSExpression(forConstantValue: "map")
      vesselLayer.iconRotation = NSExpression(forKeyPath: "course")
      vesselLayer.iconAllowsOverlap = NSExpression(forConstantValue: true)
      vesselLayer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
      vesselLayer.iconOpacity = NSExpression(forConstantValue: 1.0)
      style.addLayer(vesselLayer)
      
      // Create Anchor Layers (below vessel but above GPS accuracy/tracks)
      let anchorRadiusSource = MLNShapeSource(identifier: anchorRadiusSourceID, shape: nil, options: nil)
      style.addSource(anchorRadiusSource)
      
      let anchorRadiusLayer = MLNFillStyleLayer(identifier: anchorRadiusLayerID, source: anchorRadiusSource)
      anchorRadiusLayer.fillColor = NSExpression(forConstantValue: UIColor(MarineTheme.Colors.anchorDropped))
      anchorRadiusLayer.fillOpacity = NSExpression(forConstantValue: 0.15)
      style.insertLayer(anchorRadiusLayer, below: vesselLayer)
      
      let anchorRadiusStrokeLayer = MLNLineStyleLayer(identifier: "anchor-radius-stroke-layer", source: anchorRadiusSource)
      anchorRadiusStrokeLayer.lineColor = NSExpression(forConstantValue: UIColor(MarineTheme.Colors.anchorDropped))
      anchorRadiusStrokeLayer.lineWidth = NSExpression(forConstantValue: 1.5)
      anchorRadiusStrokeLayer.lineOpacity = NSExpression(forConstantValue: 0.8)
      style.insertLayer(anchorRadiusStrokeLayer, above: anchorRadiusLayer)
      
      let anchorPointSource = MLNShapeSource(identifier: anchorPointSourceID, shape: nil, options: nil)
      style.addSource(anchorPointSource)
      
      let anchorPointLayer = MLNSymbolStyleLayer(identifier: anchorPointLayerID, source: anchorPointSource)
      anchorPointLayer.iconImageName = NSExpression(forConstantValue: "anchor-icon")
      anchorPointLayer.iconColor = NSExpression(forConstantValue: UIColor(MarineTheme.Colors.anchorDropped))
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
    let vesselFeature = viewModel.vesselFeature
    let headingVectorFeature = viewModel.headingVectorFeature
    let gpsAccuracyFeature = viewModel.gpsAccuracyFeature
    let activeTrackPoints = trackRecordingService.trackPoints
    let savedTrackFeature = viewModel.savedTrackFeature
    let visibleWaypointFeatures = viewModel.visibleWaypointFeatures
    let goToWaypointFeature = viewModel.goToWaypointFeature
    let bearingLineFeature = viewModel.bearingLineFeature
    let anchorPointFeature = viewModel.anchorPointFeature
    let anchorRadiusFeature = viewModel.anchorRadiusFeature
    let isDataStale: Bool
    switch viewModel.gpsState {
    case .stale, .lost:
      isDataStale = true
    case .waiting, .active:
      isDataStale = false
    }
    let currentSource = viewModel.currentChartSource
    let isOpenSeaMapOverlayEnabled = viewModel.isOpenSeaMapOverlayEnabled
    let trackingMode = viewModel.trackingMode
    
    // Defensive Update for Vessel and Heading Features
    if let style = uiView.style {
      ensureVesselLayersExist(in: style, with: marineTheme)
      
      // Vessel feature update
      if vesselFeature !== context.coordinator.lastVesselFeature {
        if let source = style.source(withIdentifier: "vessel-source") as? MLNShapeSource {
          source.shape = vesselFeature
          context.coordinator.lastVesselFeature = vesselFeature
        }
      }
      
      // Heading vector feature update
      if headingVectorFeature !== context.coordinator.lastHeadingVectorFeature {
        if let source = style.source(withIdentifier: "heading-vector-source") as? MLNShapeSource {
          source.shape = headingVectorFeature
          context.coordinator.lastHeadingVectorFeature = headingVectorFeature
        }
      }
      
      // GPS accuracy feature update
      if gpsAccuracyFeature !== context.coordinator.lastGpsAccuracyFeature {
        if let source = style.source(withIdentifier: "gps-accuracy-source") as? MLNShapeSource {
          source.shape = gpsAccuracyFeature
          context.coordinator.lastGpsAccuracyFeature = gpsAccuracyFeature
        }
      }
      
      // Active track feature update
      let currentActiveCount = activeTrackPoints.count
      let currentActiveTimestamp = activeTrackPoints.last?.timestamp
      if currentActiveCount != context.coordinator.lastActiveTrackCount || currentActiveTimestamp != context.coordinator.lastActiveTrackTimestamp {
        if let source = style.source(withIdentifier: "active-track-source") as? MLNShapeSource {
          source.shape = generateActiveTrackFeature(from: activeTrackPoints)
          context.coordinator.lastActiveTrackCount = currentActiveCount
          context.coordinator.lastActiveTrackTimestamp = currentActiveTimestamp
        }
      }
      
      // Saved track feature update
      if savedTrackFeature !== context.coordinator.lastSavedTrackFeature {
        if let source = style.source(withIdentifier: "saved-track-source") as? MLNShapeSource {
          source.shape = savedTrackFeature
          context.coordinator.lastSavedTrackFeature = savedTrackFeature
        }
      }
      
      // Displayed waypoints feature update
      if visibleWaypointFeatures !== context.coordinator.lastVisibleWaypointFeatures {
        if let source = style.source(withIdentifier: "visible-waypoints-source") as? MLNShapeSource {
          source.shape = visibleWaypointFeatures
          context.coordinator.lastVisibleWaypointFeatures = visibleWaypointFeatures
        }
      }
      
      // GoTo waypoint feature update
      if goToWaypointFeature !== context.coordinator.lastGoToWaypointFeature {
        if let source = style.source(withIdentifier: "goto-waypoint-source") as? MLNShapeSource {
          source.shape = goToWaypointFeature
          context.coordinator.lastGoToWaypointFeature = goToWaypointFeature
        }
      }
      
      // Bearing Line feature update
      if bearingLineFeature !== context.coordinator.lastBearingLineFeature {
        if let source = style.source(withIdentifier: "bearing-line-source") as? MLNShapeSource {
          source.shape = bearingLineFeature
          context.coordinator.lastBearingLineFeature = bearingLineFeature
        }
      }
      
      // Anchor Radius update
      if anchorRadiusFeature !== context.coordinator.lastAnchorRadiusFeature {
        if let source = style.source(withIdentifier: "anchor-radius-source") as? MLNShapeSource {
          source.shape = anchorRadiusFeature
          context.coordinator.lastAnchorRadiusFeature = anchorRadiusFeature
        }
      }
      
      if let anchorRadiusColor = viewModel.anchorRadiusColor, let anchorRadiusOpacity = viewModel.anchorRadiusOpacity {
        if let layer = style.layer(withIdentifier: "anchor-radius-layer") as? MLNFillStyleLayer {
          layer.fillColor = NSExpression(forConstantValue: anchorRadiusColor)
          layer.fillOpacity = NSExpression(forConstantValue: anchorRadiusOpacity)
        }
        if let strokeLayer = style.layer(withIdentifier: "anchor-radius-stroke-layer") as? MLNLineStyleLayer {
          strokeLayer.lineColor = NSExpression(forConstantValue: anchorRadiusColor)
          if let dashPattern = viewModel.anchorRadiusDashPattern {
            strokeLayer.lineDashPattern = NSExpression(forConstantValue: dashPattern)
          } else {
            strokeLayer.lineDashPattern = nil
          }
          if let width = viewModel.anchorRadiusLineWidth {
            strokeLayer.lineWidth = NSExpression(forConstantValue: width)
          }
        }
      }
      
      // Anchor Point update
      if anchorPointFeature !== context.coordinator.lastAnchorPointFeature {
        if let source = style.source(withIdentifier: "anchor-point-source") as? MLNShapeSource {
          source.shape = anchorPointFeature
          context.coordinator.lastAnchorPointFeature = anchorPointFeature
        }
      }
      
      if let anchorDroppedColor = viewModel.anchorDroppedColor {
        if let layer = style.layer(withIdentifier: "anchor-point-layer") as? MLNSymbolStyleLayer {
          layer.iconColor = NSExpression(forConstantValue: anchorDroppedColor)
        }
      }
      
      // Data Stale state update (Opacity)
      if isDataStale != context.coordinator.lastDataStale {
        if let layer = style.layer(withIdentifier: "vessel-layer") as? MLNSymbolStyleLayer {
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
      
      if offlineVM.selectedBounds == nil {
        context.coordinator.updateOfflineSelectionBounds(mapView: uiView)
      }
    } else {
      uiView.isRotateEnabled = true
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
  
  class Coordinator: NSObject, MLNMapViewDelegate, UIPopoverPresentationControllerDelegate {
    var parent: MapLibreView
    private var streamTask: Task<Void, Never>?
    var lastChartSource: ChartSource?
    weak var mapView: MLNMapView?
    
    // Cache for diffing to avoid unnecessary MapLibre shape updates
    var lastVesselFeature: MLNShape?
    var lastHeadingVectorFeature: MLNShape?
    var lastGpsAccuracyFeature: MLNShape?
    var lastSavedTrackFeature: MLNShape?
    var lastVisibleWaypointFeatures: MLNShape?
    var lastGoToWaypointFeature: MLNShape?
    var lastBearingLineFeature: MLNShape?
    var lastAnchorPointFeature: MLNShape?
    var lastAnchorRadiusFeature: MLNShape?
    
    var lastActiveTrackCount: Int?
    var lastActiveTrackTimestamp: Date?
    var lastDataStale: Bool?
    
    init(_ parent: MapLibreView) {
      self.parent = parent
      super.init()
      
      NotificationCenter.default.addObserver(forName: NSNotification.Name("NetworkDidReconnect"), object: nil, queue: .main) { [weak self] _ in
        guard let self = self, let mapView = self.mapView else { return }
        Logger.chart.info("Network reconnected, forcing MapLibre complete style reload")
        mapView.reloadStyle(nil)
      }
    }
    
    deinit {
      streamTask?.cancel()
      NotificationCenter.default.removeObserver(self)
    }
    
    @objc func handleLongPress(_ sender: UILongPressGestureRecognizer) {
      // Ne déclencher qu'au début du geste pour éviter les ouvertures multiples
      guard sender.state == .began else { return }
      guard let mapView = sender.view as? MLNMapView else { return }
      let point = sender.location(in: mapView)
      
      let touchRect = CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
      let features = mapView.visibleFeatures(in: touchRect, styleLayerIdentifiers: ["goto-waypoint-layer", "visible-waypoints-layer"])
      
      if let feature = features.first as? MLNPointFeature, let id = feature.attributes["id"] as? String {
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
      Logger.chart.info("MapLibre successfully loaded the default style.")
      
      // Add vessel cursor image
      if let image = VesselGraphicsFactory.createVesselImage(size: MarineTheme.ChartMetrics.vesselCursorBaseSize, color: UIColor(MarineTheme.Colors.accent)) {
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
      if let source = style.source(withIdentifier: "heading-vector-source") as? MLNShapeSource {
        source.shape = parent.viewModel.headingVectorFeature
        lastHeadingVectorFeature = parent.viewModel.headingVectorFeature
      }
      if let source = style.source(withIdentifier: "gps-accuracy-source") as? MLNShapeSource {
        source.shape = parent.viewModel.gpsAccuracyFeature
        lastGpsAccuracyFeature = parent.viewModel.gpsAccuracyFeature
      }
      if let source = style.source(withIdentifier: "vessel-source") as? MLNShapeSource {
        source.shape = parent.viewModel.vesselFeature
        lastVesselFeature = parent.viewModel.vesselFeature
      }
      if let source = style.source(withIdentifier: "active-track-source") as? MLNShapeSource {
        source.shape = parent.generateActiveTrackFeature(from: parent.trackRecordingService.trackPoints)
        lastActiveTrackCount = parent.trackRecordingService.trackPoints.count
        lastActiveTrackTimestamp = parent.trackRecordingService.trackPoints.last?.timestamp
      }
      if let source = style.source(withIdentifier: "saved-track-source") as? MLNShapeSource {
        source.shape = parent.viewModel.savedTrackFeature
        lastSavedTrackFeature = parent.viewModel.savedTrackFeature
      }
      if let source = style.source(withIdentifier: "visible-waypoints-source") as? MLNShapeSource {
        source.shape = parent.viewModel.visibleWaypointFeatures
        lastVisibleWaypointFeatures = parent.viewModel.visibleWaypointFeatures
      }
      if let source = style.source(withIdentifier: "goto-waypoint-source") as? MLNShapeSource {
        source.shape = parent.viewModel.goToWaypointFeature
        lastGoToWaypointFeature = parent.viewModel.goToWaypointFeature
      }
      if let source = style.source(withIdentifier: "bearing-line-source") as? MLNShapeSource {
        source.shape = parent.viewModel.bearingLineFeature
        lastBearingLineFeature = parent.viewModel.bearingLineFeature
      }
      if let source = style.source(withIdentifier: "anchor-radius-source") as? MLNShapeSource {
        source.shape = parent.viewModel.anchorRadiusFeature
        lastAnchorRadiusFeature = parent.viewModel.anchorRadiusFeature
      }
      if let source = style.source(withIdentifier: "anchor-point-source") as? MLNShapeSource {
        source.shape = parent.viewModel.anchorPointFeature
        lastAnchorPointFeature = parent.viewModel.anchorPointFeature
      }
      if let layer = style.layer(withIdentifier: "vessel-layer") as? MLNSymbolStyleLayer {
        let isStale: Bool
        switch parent.viewModel.gpsState {
        case .stale, .lost:
          isStale = true
        case .waiting, .active:
          isStale = false
        }
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
      
      let layerID = "base-raster-layer"
      let sourceID = "base-raster-source"
      
      // 1. Clean up the layer FIRST
      if let existingLayer = style.layer(withIdentifier: layerID) {
        style.removeLayer(existingLayer)
        Logger.chart.debug("Removed existing layer: \(layerID, privacy: .public)")
      }
      
      // 2. Clean up the source SECOND
      if let existingSource = style.source(withIdentifier: sourceID) {
        style.removeSource(existingSource)
        Logger.chart.debug("Removed existing source: \(sourceID, privacy: .public)")
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
          newSource = MLNRasterTileSource(identifier: sourceID, configurationURL: configURL, tileSize: 256)
        }
        
      case .remoteGeoGarage(let clientID, let remoteLayerID):
        let template = "https://tiles.geogarage.com/\(clientID)/\(remoteLayerID)/{z}/{x}/{y}.png"
        newSource = MLNRasterTileSource(identifier: sourceID, tileURLTemplates: [template], options: [
          .minimumZoomLevel: AppConstants.Cartography.Zoom.globalMinimum,
          .maximumZoomLevel: AppConstants.Cartography.Zoom.geoGarageMaximum,
          .tileSize: 256
        ])
        
      case .openSeaMap:
        let template = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
        let attribution = MLNAttributionInfo(title: NSAttributedString(string: "© OpenStreetMap contributors"), url: URL(string: "https://www.openstreetmap.org/copyright"))
        newSource = MLNRasterTileSource(identifier: sourceID, tileURLTemplates: [template], options: [
          .minimumZoomLevel: AppConstants.Cartography.Zoom.globalMinimum,
          .maximumZoomLevel: AppConstants.Cartography.Zoom.openSeaMapMaximum,
          .attributionInfos: [attribution],
          .tileSize: 256
        ])
      }
      
      // 3. Defensively add the new source and layer
      if let rasterSource = newSource {
        if style.source(withIdentifier: sourceID) == nil {
          style.addSource(rasterSource)
          Logger.chart.debug("Added source: \(sourceID, privacy: .public)")
        } else {
          Logger.chart.error("Defensive check failed: Source \(sourceID, privacy: .public) already exists despite cleanup.")
        }
        
        if style.layer(withIdentifier: layerID) == nil {
          let rasterLayer = MLNRasterStyleLayer(identifier: layerID, source: rasterSource)
          style.insertLayer(rasterLayer, at: 0)
          Logger.chart.debug("Added layer: \(layerID, privacy: .public)")
        } else {
          Logger.chart.error("Defensive check failed: Layer \(layerID, privacy: .public) already exists despite cleanup.")
        }
      }
      
      // Re-apply OpenSeaMap overlay if it was enabled, to ensure it stays on top of the new base map
      if lastOpenSeaMapOverlayEnabled {
        OpenSeaMapLayerService.shared.removeSeamarkLayer(from: style)
        OpenSeaMapLayerService.shared.addSeamarkLayer(to: style, above: layerID)
      }
      
      // Re-center on the new source's preferred coordinate and zoom if needed
      mapView.setCenter(parent.viewModel.centerCoordinate, zoomLevel: parent.viewModel.zoomLevel, direction: parent.viewModel.chartDirection.converted(to: .degrees).value, animated: false)
      

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
          self.parent.viewModel.chartInteractedByUser()
        }
      }
    }
    
    func updateOfflineSelectionBounds(mapView: MLNMapView) {
      if let offlineVM = self.parent.offlineSelectionViewModel, offlineVM.isSelectionModeActive {
        let baseSize = min(mapView.bounds.width, mapView.bounds.height) * offlineVM.cropBoxWidthRatio
        let cropWidth = baseSize
        let cropHeight = baseSize * offlineVM.cropBoxAspect
        let x = (mapView.bounds.width - cropWidth) / 2.0
        let y = (mapView.bounds.height - cropHeight) / 2.0
        let rect = CGRect(x: x, y: y, width: cropWidth, height: cropHeight)
        
        let mlnBounds = mapView.convert(rect, toCoordinateBoundsFrom: mapView)
        
        let bounds = GeographicBoundingBox(
          southWest: mlnBounds.sw,
          northEast: mlnBounds.ne
        )
        offlineVM.updateBoundingBox(bounds)
      }
    }
    
    // Capture user's chart movements to break tracking ONLY when the movement stops, as requested
    // Also sync the final camera state back to the ViewModel so it knows where the chart is.
    func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason, animated: Bool) {
      DispatchQueue.main.async {
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

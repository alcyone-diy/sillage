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
    
    // Configure compass to remain permanently visible at top-right below top HUD overlay
    mapView.compassView.compassVisibility = .visible
    mapView.compassViewPosition = .topRight
    mapView.compassViewMargins = CGPoint(x: MarineTheme.Spacing.medium, y: MarineTheme.Spacing.compassTopMargin)
    
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
    
    // Setup single tap gesture for implicit context callout dismissal
    let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
    tapGesture.cancelsTouchesInView = false
    
    // Prevent single-tap callout dismiss from interfering with MapLibre's native double-tap zoom gestures
    if let gestureRecognizers = mapView.gestureRecognizers {
      for recognizer in gestureRecognizers {
        if let tapRecognizer = recognizer as? UITapGestureRecognizer, tapRecognizer.numberOfTapsRequired == 2 {
          tapGesture.require(toFail: tapRecognizer)
        }
      }
    }
    
    mapView.addGestureRecognizer(tapGesture)
    
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
    let savedTrackVisualS tate = viewModel.savedTrackVisualState
    let visibleWaypointVisualStates = viewModel.visibleWaypointVisualStates
    let goToWaypointVisualState = viewModel.goToWaypointVisualState
    let bearingLineVisualState = viewModel.bearingLineVisualState
    let offlineMaskVisualState = viewModel.offlineMaskVisualState
    let isDataStale = viewModel.isDataStale
    let currentSource = viewModel.currentChartSource
    let isOpenSeaMapOverlayEnabled = viewModel.isOpenSeaMapOverlayEnabled
    let trackingMode = viewModel.trackingMode
    
    // Defensive Update for Vessel and Heading Features
    if let style = uiView.style {
      MapStyleController.ensureTelemetryLayersExist(in: style, theme: marineTheme)
      
      // Vessel feature update
      if vesselVisualState != context.coordinator.lastVesselVisualState {
        MapStyleController.updateVessel(state: vesselVisualState, in: style, theme: marineTheme)
        context.coordinator.lastVesselVisualState = vesselVisualState
      }
      
      // Heading vector feature update
      if headingVectorData != context.coordinator.lastHeadingVectorData {
        MapStyleController.updateHeadingVector(data: headingVectorData, in: style, theme: marineTheme)
        context.coordinator.lastHeadingVectorData = headingVectorData
      }
      
      // GPS accuracy feature update
      if gpsAccuracyVisualState != context.coordinator.lastGpsAccuracyVisualState {
        MapStyleController.updateGpsAccuracy(state: gpsAccuracyVisualState, in: style, theme: marineTheme)
        context.coordinator.lastGpsAccuracyVisualState = gpsAccuracyVisualState
      }
      
      // Active track feature update
      let currentActiveCount = activeTrackPoints.count
      let currentActiveTimestamp = activeTrackPoints.last?.timestamp
      if currentActiveCount != context.coordinator.lastActiveTrackCount || currentActiveTimestamp != context.coordinator.lastActiveTrackTimestamp {
        MapStyleController.updateActiveTrack(points: activeTrackPoints, in: style, theme: marineTheme)
        context.coordinator.lastActiveTrackCount = currentActiveCount
        context.coordinator.lastActiveTrackTimestamp = currentActiveTimestamp
      }
      
      // Saved track feature update
      if savedTrackVisualState != context.coordinator.lastSavedTrackVisualState {
        MapStyleController.updateSavedTrack(state: savedTrackVisualState, in: style, theme: marineTheme)
        context.coordinator.lastSavedTrackVisualState = savedTrackVisualState
      }
      
      // Displayed waypoints feature update
      let targetWaypointID = viewModel.calloutViewModel.targetWaypointID
      if visibleWaypointVisualStates != context.coordinator.lastVisibleWaypointVisualStates || targetWaypointID != context.coordinator.lastCalloutTargetWaypointID {
        MapStyleController.updateVisibleWaypoints(states: visibleWaypointVisualStates, targetWaypointID: targetWaypointID, in: style, theme: marineTheme)
        context.coordinator.lastVisibleWaypointVisualStates = visibleWaypointVisualStates
      }
      
      // GoTo waypoint feature update
      if goToWaypointVisualState != context.coordinator.lastGoToWaypointVisualState || targetWaypointID != context.coordinator.lastCalloutTargetWaypointID {
        MapStyleController.updateGoToWaypoint(state: goToWaypointVisualState, targetWaypointID: targetWaypointID, in: style, theme: marineTheme)
        context.coordinator.lastGoToWaypointVisualState = goToWaypointVisualState
      }

      context.coordinator.lastCalloutTargetWaypointID = targetWaypointID
      
      // Bearing Line feature update
      if bearingLineVisualState != context.coordinator.lastBearingLineVisualState {
        MapStyleController.updateBearingLine(state: bearingLineVisualState, in: style, theme: marineTheme)
        context.coordinator.lastBearingLineVisualState = bearingLineVisualState
      }
      
      // Anchor update
      let currentVisualState = viewModel.anchorVisualState
      if currentVisualState != context.coordinator.lastAnchorVisualState {
        context.coordinator.lastAnchorVisualState = currentVisualState
        MapStyleController.updateAnchor(state: currentVisualState, in: style, theme: marineTheme)
      }

      // Offline mask update
      if offlineMaskVisualState != context.coordinator.lastOfflineMaskVisualState {
        MapStyleController.updateOfflineMask(state: offlineMaskVisualState, in: style, theme: marineTheme)
        context.coordinator.lastOfflineMaskVisualState = offlineMaskVisualState
      }

      // Data Stale state update (Opacity)
      if isDataStale != context.coordinator.lastDataStale {
        MapStyleController.updateDataStaleState(isStale: isDataStale, in: style)
        context.coordinator.lastDataStale = isDataStale
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
      MapStyleController.updateChartSource(currentSource, in: style, isOverlayEnabled: isOpenSeaMapOverlayEnabled)
      context.coordinator.lastChartSource = currentSource
      context.coordinator.lastOpenSeaMapOverlayEnabled = isOpenSeaMapOverlayEnabled
      uiView.setCenter(viewModel.centerCoordinate, zoomLevel: viewModel.zoomLevel, direction: viewModel.chartDirection.converted(to: .degrees).value, animated: false)
    }
    
    // Handle OpenSeaMap overlay toggle
    if let style = uiView.style, context.coordinator.lastOpenSeaMapOverlayEnabled != isOpenSeaMapOverlayEnabled {
      context.coordinator.lastOpenSeaMapOverlayEnabled = isOpenSeaMapOverlayEnabled
      MapStyleController.updateOpenSeaMapOverlay(isEnabled: isOpenSeaMapOverlayEnabled, in: style)
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
  class Coordinator: NSObject, MLNMapViewDelegate {
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
    var lastOfflineMaskVisualState: OfflineMaskVisualState?
    
    var lastActiveTrackCount: Int?
    var lastActiveTrackTimestamp: Date?
    var lastDataStale: Bool?
    var lastTrackingMode: ChartTrackingMode = .free
    var lastCalloutTargetWaypointID: String?
    
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
    
    @objc func handleTap(_ sender: UITapGestureRecognizer) {
      guard sender.state == .ended else { return }
      if parent.viewModel.calloutViewModel.isCalloutVisible {
        parent.viewModel.calloutViewModel.dismiss()
      }
    }
    
    @objc func handleLongPress(_ sender: UILongPressGestureRecognizer) {
      // Only trigger at the start of the gesture to prevent multiple openings
      guard sender.state == .began else { return }
      
      /// Technical Design Choice: Disable contextual gesture during active action confirmation cards
      /// Prevents long-press waypoint popover creation whenever a MarineActionConfirmationCard is active
      /// (e.g. anchor repositioning or offline area selection).
      guard !parent.viewModel.isActionConfirmationCardActive else { return }
      
      guard let mapView = sender.view as? MLNMapView else { return }

      let point = sender.location(in: mapView)
      let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
      
      let touchRect = CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
      let features = mapView.visibleFeatures(in: touchRect, styleLayerIdentifiers: [MapLayerIdentifier.goToWaypoint.rawValue, MapLayerIdentifier.visibleWaypoints.rawValue])

      if let feature = features.first as? MLNPointFeature,
         let id = feature.attributes[MapFeatureKey.id.rawValue] as? String {
        let exactCoordinate = feature.coordinate
        let exactPoint = mapView.convert(exactCoordinate, toPointTo: mapView)
        self.parent.viewModel.calloutViewModel.presentCallout(at: exactPoint, coordinate: exactCoordinate, waypointID: id)
      } else {
        self.parent.viewModel.calloutViewModel.presentCallout(at: point, coordinate: coordinate, waypointID: nil)
      }
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
      self.parent.viewModel.throttledUpdateMapScaleAndZoom(metersPerPoint: mpp, zoomLevel: mapView.zoomLevel)
      self.parent.viewModel.calloutViewModel.throttledUpdateScreenPosition(from: mapView)
      self.parent.viewModel.throttledUpdateCenterCoordinate(mapView.centerCoordinate)
    }
    
    func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
      let mpp = mapView.metersPerPoint(atLatitude: mapView.centerCoordinate.latitude)
      self.parent.viewModel.updateMapScaleAndZoomImmediately(metersPerPoint: mpp, zoomLevel: mapView.zoomLevel)
      self.parent.viewModel.calloutViewModel.updateScreenPositionImmediately(from: mapView)
      self.parent.viewModel.updateCenterCoordinateImmediately(mapView.centerCoordinate)
    }
    
    // Called when the map has finished loading its style
    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
      Logger.chart.info("MapLibre successfully loaded the default style.")
      
      // Add vessel cursor image
      if let image = VesselGraphicsFactory.createVesselImage(size: MarineTheme.ChartMetrics.vesselCursorBaseSize, color: UIColor(parent.marineTheme.colors.accent)) {
        style.setImage(image, forName: "vessel-cursor")
      }
      
      // Register all 4 anchor status icons once in MapLibre style
      MapStyleController.ensureAnchorImagesExist(in: style, theme: parent.marineTheme)
      
      if let currentSource = parent.viewModel.currentChartSource {
        MapStyleController.updateChartSource(currentSource, in: style, isOverlayEnabled: parent.viewModel.isOpenSeaMapOverlayEnabled)
        lastChartSource = currentSource
      }
      
      lastOpenSeaMapOverlayEnabled = parent.viewModel.isOpenSeaMapOverlayEnabled
      MapStyleController.updateOpenSeaMapOverlay(isEnabled: parent.viewModel.isOpenSeaMapOverlayEnabled, in: style)

      
      // Ensure vessel & telemetry layers are initialized after style finishes loading
      MapStyleController.ensureTelemetryLayersExist(in: style, theme: parent.marineTheme)
      let headingData = parent.viewModel.headingVectorData
      MapStyleController.updateHeadingVector(data: headingData, in: style, theme: parent.marineTheme)
      lastHeadingVectorData = headingData

      let gpsState = parent.viewModel.gpsAccuracyVisualState
      MapStyleController.updateGpsAccuracy(state: gpsState, in: style, theme: parent.marineTheme)
      lastGpsAccuracyVisualState = gpsState

      let vesselState = parent.viewModel.vesselVisualState
      MapStyleController.updateVessel(state: vesselState, in: style, theme: parent.marineTheme)
      lastVesselVisualState = vesselState

      MapStyleController.ensureNavigationLayersExist(in: style, theme: parent.marineTheme)

      MapStyleController.updateActiveTrack(points: parent.trackRecordingService.trackPoints, in: style, theme: parent.marineTheme)
      lastActiveTrackCount = parent.trackRecordingService.trackPoints.count
      lastActiveTrackTimestamp = parent.trackRecordingService.trackPoints.last?.timestamp

      let savedState = parent.viewModel.savedTrackVisualState
      MapStyleController.updateSavedTrack(state: savedState, in: style, theme: parent.marineTheme)
      lastSavedTrackVisualState = savedState

      let visibleStates = parent.viewModel.visibleWaypointVisualStates
      let targetID = parent.viewModel.calloutViewModel.targetWaypointID
      MapStyleController.updateVisibleWaypoints(states: visibleStates, targetWaypointID: targetID, in: style, theme: parent.marineTheme)
      lastVisibleWaypointVisualStates = visibleStates

      let goToState = parent.viewModel.goToWaypointVisualState
      MapStyleController.updateGoToWaypoint(state: goToState, targetWaypointID: targetID, in: style, theme: parent.marineTheme)
      lastGoToWaypointVisualState = goToState
      lastCalloutTargetWaypointID = targetID

      let bearingState = parent.viewModel.bearingLineVisualState
      MapStyleController.updateBearingLine(state: bearingState, in: style, theme: parent.marineTheme)
      lastBearingLineVisualState = bearingState

      let anchorVisualState = parent.viewModel.anchorVisualState
      MapStyleController.updateAnchor(state: anchorVisualState, in: style, theme: parent.marineTheme)
      lastAnchorVisualState = anchorVisualState

      // Offline Mask layer initialization
      MapStyleController.ensureOfflineMaskLayersExist(in: style, theme: parent.marineTheme)
      let maskState = parent.viewModel.offlineMaskVisualState
      MapStyleController.updateOfflineMask(state: maskState, in: style, theme: parent.marineTheme)
      lastOfflineMaskVisualState = maskState

      let isStale = parent.viewModel.isDataStale
      MapStyleController.updateDataStaleState(isStale: isStale, in: style)
      lastDataStale = isStale


      
      // NOTE: We do not call `mapView.setVisibleCoordinateBounds` here.
      // In SwiftUI, `didFinishLoading` can fire before the map view has a non-zero frame.
      // Calling coordinate bounds on a `.zero` frame corrupts the MapLibre camera (`NaN` zoom level).
      // Instead, we simply jump the camera back to the exact metadata `centerCoordinate` and `zoomLevel`.
      // This is required because loading the blank JSON style resets the map to (0,0), which leaves it looking at
      // the African coast where no French marine chart tiles exist, causing the map to appear blank.
      mapView.setCenter(parent.viewModel.centerCoordinate, zoomLevel: parent.viewModel.zoomLevel, direction: parent.viewModel.chartDirection.converted(to: .degrees).value, animated: false)
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
        let mpp = mapView.metersPerPoint(atLatitude: mapView.centerCoordinate.latitude)
        self.parent.viewModel.updateMapScaleAndZoomImmediately(metersPerPoint: mpp, zoomLevel: mapView.zoomLevel)
        self.parent.viewModel.updateCenterCoordinateImmediately(mapView.centerCoordinate)
        self.parent.viewModel.chartDirection = Measurement(value: mapView.direction, unit: UnitAngle.degrees)
        
        // Save the camera state to UserDefaults
        self.parent.viewModel.saveCameraState()
        
        let visibleBounds = mapView.visibleCoordinateBounds
        self.parent.viewModel.currentVisibleBounds = GeographicBoundingBox(
          southWest: visibleBounds.sw,
          northEast: visibleBounds.ne
        )
        
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

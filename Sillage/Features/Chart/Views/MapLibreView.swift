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
import QuartzCore
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
    let mapView = MarineMapView(frame: .zero)
    
    // Anchor one-finger quick zoom to the nautical aiming crosshair when displayed
    mapView.customGestureAnchorProvider = { [weak coordinator = context.coordinator, weak mapView] gesture in
      guard let coordinator, let mapView else { return nil }
      let calloutVM = coordinator.parent.viewModel.calloutViewModel
      let measureVM = coordinator.parent.viewModel.measureToolViewModel
      
      let isCrosshairDisplayed = calloutVM.isCalloutVisible &&
        calloutVM.targetWaypointID == nil &&
        !measureVM.isActive
      
      guard isCrosshairDisplayed, mapView.bounds.width > 0, mapView.bounds.height > 0 else {
        return nil
      }
      
      // Center quick zoom, double-tap zoom-in, and two-finger tap zoom-out on the aiming crosshair
      if gesture is UILongPressGestureRecognizer {
        return CGPoint(
          x: mapView.bounds.midX,
          y: mapView.bounds.height * AppConstants.Map.aimingCrosshairYFraction
        )
      }
      if let tapGesture = gesture as? UITapGestureRecognizer {
        let isDoubleTapZoomIn = tapGesture.numberOfTapsRequired == 2 && tapGesture.numberOfTouchesRequired == 1
        let isTwoFingerTapZoomOut = tapGesture.numberOfTapsRequired == 1 && tapGesture.numberOfTouchesRequired == 2
        if isDoubleTapZoomIn || isTwoFingerTapZoomOut {
          return CGPoint(
            x: mapView.bounds.midX,
            y: mapView.bounds.height * AppConstants.Map.aimingCrosshairYFraction
          )
        }
      }
      
      return nil
    }
    
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
    
    // Setup single tap gesture for measure tool interactions (pin selection, placing Pin B)
    let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
    tapGesture.cancelsTouchesInView = false
    
    // Prevent single-tap from interfering with MapLibre's native double-tap zoom gestures
    if let gestureRecognizers = mapView.gestureRecognizers {
      for recognizer in gestureRecognizers {
        if let tapRecognizer = recognizer as? UITapGestureRecognizer, tapRecognizer.numberOfTapsRequired == 2 {
          tapGesture.require(toFail: tapRecognizer)
        }
      }
    }
    
    mapView.addGestureRecognizer(tapGesture)
    
    // Setup dedicated pan gesture for interactive measure pin drag-and-drop
    let pinPanGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinPan(_:)))
    pinPanGesture.delegate = context.coordinator
    pinPanGesture.cancelsTouchesInView = true
    mapView.addGestureRecognizer(pinPanGesture)
    context.coordinator.pinPanGesture = pinPanGesture
    
    viewModel.isCoordinateVisible = { [weak mapView] coord in
      guard let mapView = mapView else { return false }
      let pt = mapView.convert(coord, toPointTo: mapView)
      let sheetClearance: CGFloat = 240.0
      let topInset = mapView.safeAreaInsets.top
      let visibleRect = CGRect(
        x: 0,
        y: topInset,
        width: mapView.bounds.width,
        height: max(50.0, mapView.bounds.height - sheetClearance - topInset)
      )
      return visibleRect.contains(pt)
    }
    
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
    let offlineMaskVisualState = viewModel.offlineMaskVisualState
    let anchorVisualState = viewModel.anchorVisualState
    let highlightedOfflineRegion = viewModel.highlightedOfflineRegion
    let isDataStale = viewModel.isDataStale
    let currentSource = viewModel.currentChartSource
    let isOpenSeaMapOverlayEnabled = viewModel.isOpenSeaMapOverlayEnabled
    let trackingMode = viewModel.trackingMode
    let _ = viewModel.measureToolViewModel.state
    let _ = viewModel.measureToolViewModel.activePin
    
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

      // Ensure pin and anchor images match the current MarineTheme when the theme changes
      var themeHasher = Hasher()
      themeHasher.combine(marineTheme.isGloveMode)
      themeHasher.combine(marineTheme.colors.primary)
      themeHasher.combine(marineTheme.colors.accent)
      themeHasher.combine(marineTheme.colors.surfaceBackground)
      themeHasher.combine(marineTheme.colors.textPrimary)
      themeHasher.combine(marineTheme.colors.panelBackground)
      themeHasher.combine(marineTheme.colors.anchorDropped)
      themeHasher.combine(marineTheme.colors.anchorArmed)
      themeHasher.combine(marineTheme.colors.anchorDragging)
      let currentThemeHash = themeHasher.finalize()

      if context.coordinator.lastThemeHash != currentThemeHash {
        context.coordinator.lastThemeHash = currentThemeHash
        MapStyleController.ensureAnchorImagesExist(in: style, theme: marineTheme)
        MapStyleController.ensureMeasurePinImagesExist(in: style, theme: marineTheme)
        MapStyleController.refreshTargetAimingCrosshairImage(in: style, theme: marineTheme)
      }

      // Target Aiming Crosshair GPU layer update during centering flight
      let aimingCoord = viewModel.calloutViewModel.aimingCoordinate
      if aimingCoord != context.coordinator.lastAimingCoordinate {
        context.coordinator.lastAimingCoordinate = aimingCoord
        MapStyleController.updateTargetAimingCrosshair(coordinate: aimingCoord, in: style, theme: marineTheme)
      }

      // Measure feature update (polyline and pins)
      let measureState = viewModel.measureToolViewModel.state
      let measureActivePin = viewModel.measureToolViewModel.activePin
      if measureState != context.coordinator.lastMeasureState || measureActivePin != context.coordinator.lastMeasureActivePin {
        MapStyleController.updateMeasureLine(state: measureState, in: style, theme: marineTheme)
        MapStyleController.updateMeasurePins(state: measureState, activePin: measureActivePin, in: style, theme: marineTheme)
        context.coordinator.lastMeasureState = measureState
        context.coordinator.lastMeasureActivePin = measureActivePin
      }
      
      // Anchor update
      if anchorVisualState != context.coordinator.lastAnchorVisualState {
        context.coordinator.lastAnchorVisualState = anchorVisualState
        MapStyleController.updateAnchor(state: anchorVisualState, in: style, theme: marineTheme)
      }

      // Offline mask update
      if offlineMaskVisualState != context.coordinator.lastOfflineMaskVisualState {
        MapStyleController.updateOfflineMask(state: offlineMaskVisualState, in: style, theme: marineTheme)
        context.coordinator.lastOfflineMaskVisualState = offlineMaskVisualState
        viewModel.updateOfflineRegionScreenPositions(
          projection: { uiView.convert($0, toPointTo: uiView) },
          bounds: uiView.bounds
        )
      }

      // Highlighted offline region update
      if highlightedOfflineRegion != context.coordinator.lastHighlightedOfflineRegion {
        context.coordinator.lastHighlightedOfflineRegion = highlightedOfflineRegion
        MapStyleController.updateOfflineHighlight(region: highlightedOfflineRegion, in: style, theme: marineTheme)
      }

      // Active offline selection zone update
      let activeSelectionBounds = (offlineSelectionViewModel?.isSelectionModeActive == true) ? offlineSelectionViewModel?.selectedBounds : nil
      if activeSelectionBounds != context.coordinator.lastOfflineSelectionBounds {
        context.coordinator.lastOfflineSelectionBounds = activeSelectionBounds
        MapStyleController.updateOfflineSelection(bounds: activeSelectionBounds, in: style, theme: marineTheme)
      }

      // Data Stale state update (Opacity)
      if isDataStale != context.coordinator.lastDataStale {
        MapStyleController.updateDataStaleState(isStale: isDataStale, in: style)
        context.coordinator.lastDataStale = isDataStale
      }
    }

    // Viewport bounds resize / rotation handling
    if context.coordinator.lastBounds.size != uiView.bounds.size {
      context.coordinator.lastBounds = uiView.bounds
      if viewModel.calloutViewModel.isCentering,
         let target = viewModel.calloutViewModel.targetCoordinate,
         let style = uiView.style {
        let targetScreenPoint = CGPoint(
          x: uiView.bounds.midX,
          y: uiView.bounds.height * AppConstants.Map.aimingCrosshairYFraction
        )
        let newCenterCoordinate = context.coordinator.centerCoordinateToPosition(target, at: targetScreenPoint, in: uiView)
        uiView.setCenter(newCenterCoordinate, animated: false)
        let targetCoord = uiView.convert(targetScreenPoint, toCoordinateFrom: uiView)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
          viewModel.calloutViewModel.interruptCentering(at: targetCoord)
        }
        context.coordinator.lastAimingCoordinate = nil
        MapStyleController.updateTargetAimingCrosshair(coordinate: nil, in: style, theme: marineTheme)
      }
    }

    // Offline selection mode: force chart rotation to 0 (North-Up) and reset pitch to 0.
    if let offlineVM = offlineSelectionViewModel, offlineVM.isSelectionModeActive {
      uiView.isRotateEnabled = false

      // Restore North-Up orientation and level pitch immediately without animation.
      // Mathematical integrity: animated transitions cause uiView.convert() to project against
      // a transient tilted/rotated perspective, producing corrupted coordinates.
      if uiView.direction != 0 {
        uiView.setDirection(0, animated: false)
      }
      if uiView.camera.pitch != 0 {
        let camera = uiView.camera
        camera.pitch = 0
        uiView.setCamera(camera, animated: false)
      }

      // If selection mode just started without explicit bounds, initialize them once from map center
      if offlineVM.selectedBounds == nil, uiView.bounds.width > 0, uiView.bounds.height > 0 {
        let baseSize = min(uiView.bounds.width, uiView.bounds.height) * offlineVM.cropBoxWidthRatio
        let size = CGSize(width: baseSize, height: baseSize * offlineVM.cropBoxAspect)
        let x = (uiView.bounds.width - size.width) / 2.0
        let y = (uiView.bounds.height - size.height) / 2.0
        let rect = CGRect(x: x, y: y, width: size.width, height: size.height)
        let mlnBounds = uiView.convert(rect, toCoordinateBoundsFrom: uiView)
        let initialBounds = GeographicBoundingBox(southWest: mlnBounds.sw, northEast: mlnBounds.ne)

        Task { @MainActor [weak offlineVM] in
          offlineVM?.updateBoundingBox(initialBounds)
        }
      }
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
  class Coordinator: NSObject, MLNMapViewDelegate, UIGestureRecognizerDelegate {
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
    var lastMeasureState: MeasureState = .inactive
    var lastMeasureActivePin: ActiveMeasurePin?
    weak var pinPanGesture: UIPanGestureRecognizer?
    private var activeDraggedPin: ActiveMeasurePin?
    private var isLongPressActive: Bool = false
    private var measurePinDragOffset: CGPoint = .zero
    private var isUserActivelyInteractingWithPins: Bool {
      isLongPressActive || activeDraggedPin != nil || parent.viewModel.measureToolViewModel.isDraggingPin || activeDraggedSelectionCorner != nil
    }
    private var lastPanUpdateTime: CFTimeInterval = 0
    private var lastCalloutTargetUpdateTime: CFTimeInterval = 0
    private static let pinPanThrottleInterval: CFTimeInterval = 0.016
    var lastThemeHash: Int?
    var lastAnchorVisualState: AnchorVisualState?
    var lastOfflineMaskVisualState: OfflineMaskVisualState?
    var lastHighlightedOfflineRegion: HighlightedOfflineRegion?
    var lastOfflineSelectionBounds: GeographicBoundingBox?

    enum ActiveSelectionCorner {
      case topLeft      // NW
      case topRight     // NE
      case bottomLeft   // SW
      case bottomRight  // SE
    }
    private var activeDraggedSelectionCorner: ActiveSelectionCorner?
    private var activeSelectionDragInitialBounds: GeographicBoundingBox?
    private var activeSelectionDragCurrentBounds: GeographicBoundingBox?
    
    var lastActiveTrackCount: Int?
    var lastActiveTrackTimestamp: Date?
    var lastDataStale: Bool?
    var lastTrackingMode: ChartTrackingMode = .free
    var lastCalloutTargetWaypointID: String?
    
    /// Technical Design Choice: Vessel Centering Gesture Tolerance Margin
    /// Tracks the initial anchor coordinate and screen point at the start of a manual drag gesture,
    /// allowing accidental touches, slips, and small vibrations to be tolerated without immediately breaking tracking mode.
    var initialPanCenterCoordinate: CLLocationCoordinate2D?
    var initialPanScreenPoint: CGPoint?
    var hasExceededTrackingMargin: Bool = false
    var lastBounds: CGRect = .zero
    var lastAimingCoordinate: CLLocationCoordinate2D?
    
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
    
    /// Computes the minimal distance between a touch point and an inverted nautical map pin (checking both circular head and needle tip).
    private func distanceToPin(touchPoint: CGPoint, tipPoint: CGPoint) -> CGFloat {
      let headOffset = MarineMapPinShape.needleToHeadCenterOffset
      let headCenter = CGPoint(x: tipPoint.x, y: tipPoint.y + headOffset)
      let distHead = hypot(touchPoint.x - headCenter.x, touchPoint.y - headCenter.y)
      let distTip = hypot(touchPoint.x - tipPoint.x, touchPoint.y - tipPoint.y)
      return min(distHead, distTip)
    }

    /// Tests whether a screen touch point is within the touch hit target of Pin A or Pin B.
    func hitTestMeasurePin(at point: CGPoint, in mapView: MLNMapView) -> ActiveMeasurePin? {
      guard parent.viewModel.measureToolViewModel.isActive else { return nil }
      let measureVM = parent.viewModel.measureToolViewModel
      guard let startCoord = measureVM.startCoordinate,
            let endCoord = measureVM.endCoordinate else { return nil }

      let ptA = mapView.convert(startCoord, toPointTo: mapView)
      let ptB = mapView.convert(endCoord, toPointTo: mapView)

      let hitRadius: CGFloat = parent.marineTheme.isGloveMode ? 48.0 : 36.0
      let minA = distanceToPin(touchPoint: point, tipPoint: ptA)
      let minB = distanceToPin(touchPoint: point, tipPoint: ptB)

      if minA <= hitRadius && minB <= hitRadius {
        if measureVM.activePin == .start {
          return .start
        } else if measureVM.activePin == .end {
          return .end
        }
        return minA <= minB ? .start : .end
      } else if minA <= hitRadius {
        return .start
      } else if minB <= hitRadius {
        return .end
      }
      return nil
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      if gestureRecognizer === pinPanGesture {
        guard !isLongPressActive else { return false }
        guard let mapView = self.mapView else { return false }
        let touchPoint = gestureRecognizer.location(in: mapView)
        if parent.viewModel.measureToolViewModel.isActive {
          return hitTestMeasurePin(at: touchPoint, in: mapView) != nil
        }
        if let offlineVM = parent.offlineSelectionViewModel, offlineVM.isSelectionModeActive {
          return hitTestSelectionCorner(at: touchPoint, in: mapView) != nil
        }
        return false
      }
      return true
    }
    
    @objc func handleTap(_ sender: UITapGestureRecognizer) {
      guard sender.state == .ended else { return }
      if parent.viewModel.measureToolViewModel.isActive {
        guard let mapView = sender.view as? MLNMapView else { return }
        parent.viewModel.chartInteractedByUser()
        let point = sender.location(in: mapView)
        // Check if user tapped directly on Pin A or Pin B to select it
        if let hitPin = hitTestMeasurePin(at: point, in: mapView) {
          parent.viewModel.measureToolViewModel.activePin = hitPin
          return
        }
        let coord = mapView.convert(point, toCoordinateFrom: mapView)
        parent.viewModel.measureToolViewModel.handleMapTap(at: coord)
        return
      }
    }
    
    @objc func handlePinPan(_ sender: UIPanGestureRecognizer) {
      guard let mapView = sender.view as? MLNMapView else { return }

      // Route according to active measure tool pin drag
      if activeDraggedPin != nil || parent.viewModel.measureToolViewModel.isActive {
        handleMeasurePinPan(sender, in: mapView)
        return
      }

      if activeDraggedSelectionCorner != nil || (parent.offlineSelectionViewModel?.isSelectionModeActive == true && hitTestSelectionCorner(at: sender.location(in: mapView), in: mapView) != nil) {
        handleSelectionCornerPan(sender, in: mapView)
        return
      }
    }

    private func handleMeasurePinPan(_ sender: UIPanGestureRecognizer, in mapView: MLNMapView) {
      let touchPoint = sender.location(in: mapView)

      switch sender.state {
      case .began:
        guard let pin = hitTestMeasurePin(at: touchPoint, in: mapView) else { return }
        activeDraggedPin = pin
        parent.viewModel.measureToolViewModel.activePin = pin
        parent.viewModel.measureToolViewModel.isDraggingPin = true
        parent.viewModel.chartInteractedByUser()

        let currentCoord = (pin == .start)
          ? parent.viewModel.measureToolViewModel.startCoordinate
          : parent.viewModel.measureToolViewModel.endCoordinate
        if let currentCoord = currentCoord {
          let tipPoint = mapView.convert(currentCoord, toPointTo: mapView)
          measurePinDragOffset = CGPoint(
            x: touchPoint.x - tipPoint.x,
            y: touchPoint.y - tipPoint.y
          )
        } else {
          measurePinDragOffset = .zero
        }
        lastPanUpdateTime = CACurrentMediaTime()

      case .changed:
        guard let pin = activeDraggedPin else { return }
        guard parent.viewModel.measureToolViewModel.isActive else {
          activeDraggedPin = nil
          measurePinDragOffset = .zero
          parent.viewModel.measureToolViewModel.isDraggingPin = false
          return
        }

        let now = CACurrentMediaTime()
        guard now - lastPanUpdateTime >= Self.pinPanThrottleInterval else { return }
        lastPanUpdateTime = now

        let rawTip = CGPoint(
          x: touchPoint.x - measurePinDragOffset.x,
          y: touchPoint.y - measurePinDragOffset.y
        )
        let clampedTip = clampPointToMapBounds(rawTip, in: mapView)
        let coord = mapView.convert(clampedTip, toCoordinateFrom: mapView)
        switch pin {
        case .start:
          parent.viewModel.measureToolViewModel.updateStart(to: coord)
        case .end:
          parent.viewModel.measureToolViewModel.updateEnd(to: coord)
        }

      case .ended:
        if let pin = activeDraggedPin {
          let rawTip = CGPoint(
            x: touchPoint.x - measurePinDragOffset.x,
            y: touchPoint.y - measurePinDragOffset.y
          )
          let clampedTip = clampPointToMapBounds(rawTip, in: mapView)
          let coord = mapView.convert(clampedTip, toCoordinateFrom: mapView)
          switch pin {
          case .start:
            parent.viewModel.measureToolViewModel.updateStart(to: coord)
          case .end:
            parent.viewModel.measureToolViewModel.updateEnd(to: coord)
          }
        }
        activeDraggedPin = nil
        measurePinDragOffset = .zero
        parent.viewModel.measureToolViewModel.isDraggingPin = false
        ensureMeasurePinsVisible(in: mapView, sheetHeight: parent.viewModel.measureToolViewModel.lastSheetHeight)

      case .cancelled, .failed:
        activeDraggedPin = nil
        measurePinDragOffset = .zero
        parent.viewModel.measureToolViewModel.isDraggingPin = false
        ensureMeasurePinsVisible(in: mapView, sheetHeight: parent.viewModel.measureToolViewModel.lastSheetHeight)

      default:
        break
      }
    }

    private func clampPointToMapBounds(_ point: CGPoint, in mapView: MLNMapView) -> CGPoint {
      CGPoint(
        x: min(max(point.x, 0), mapView.bounds.width),
        y: min(max(point.y, 0), mapView.bounds.height)
      )
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
      if gestureRecognizer == pinPanGesture || otherGestureRecognizer == pinPanGesture {
        return false
      }
      if gestureRecognizer is UILongPressGestureRecognizer || otherGestureRecognizer is UILongPressGestureRecognizer {
        return false
      }
      if isUserActivelyInteractingWithPins {
        return false
      }
      return true
    }
    
    @objc func handleLongPress(_ sender: UILongPressGestureRecognizer) {
      if sender.state == .ended || sender.state == .cancelled || sender.state == .failed {
        // Guarantee isLongPressActive and measure pin drag session are reset, even if guards return early
        if parent.viewModel.measureToolViewModel.isDraggingPin && !parent.viewModel.measureToolViewModel.isActive {
          parent.viewModel.measureToolViewModel.isDraggingPin = false
        }
        isLongPressActive = false
      }

      if parent.viewModel.measureToolViewModel.isActive {
        guard let mapView = sender.view as? MLNMapView else { return }
        let touchPoint = sender.location(in: mapView)
        // Technical Design Choice: Offset so the circular round head arrives directly under the user's finger,
        // leaving the needle tip pointing above the finger for full chart feature visibility.
        let tipPoint = CGPoint(
          x: touchPoint.x,
          y: touchPoint.y - MarineMapPinShape.needleToHeadCenterOffset
        )
        let clampedTip = clampPointToMapBounds(tipPoint, in: mapView)
        let coord = mapView.convert(clampedTip, toCoordinateFrom: mapView)

        switch sender.state {
        case .began:
          parent.viewModel.measureToolViewModel.isDraggingPin = true
          isLongPressActive = true
          parent.viewModel.chartInteractedByUser()
          parent.viewModel.measureToolViewModel.handleMapLongPress(at: coord)
          lastPanUpdateTime = CACurrentMediaTime()

        case .changed:
          let now = CACurrentMediaTime()
          guard now - lastPanUpdateTime >= Self.pinPanThrottleInterval else { return }
          lastPanUpdateTime = now

          parent.viewModel.chartInteractedByUser()
          parent.viewModel.measureToolViewModel.handleMapLongPress(at: coord)

        case .ended:
          parent.viewModel.chartInteractedByUser()
          parent.viewModel.measureToolViewModel.handleMapLongPress(at: coord)
          parent.viewModel.measureToolViewModel.isDraggingPin = false
          isLongPressActive = false
          ensureMeasurePinsVisible(in: mapView, sheetHeight: parent.viewModel.measureToolViewModel.lastSheetHeight)

        case .cancelled, .failed:
          parent.viewModel.measureToolViewModel.isDraggingPin = false
          isLongPressActive = false
          ensureMeasurePinsVisible(in: mapView, sheetHeight: parent.viewModel.measureToolViewModel.lastSheetHeight)

        default:
          break
        }
        return
      }

      /// Technical Design Choice: Disable contextual gesture during active action confirmation cards
      /// Prevents long-press waypoint popover creation whenever a MarineActionConfirmationCard is active
      /// (e.g. anchor repositioning or offline area selection).
      guard !parent.viewModel.isActionConfirmationCardActive else { return }
      
      guard let mapView = sender.view as? MLNMapView else { return }
      let touchPoint = sender.location(in: mapView)

      switch sender.state {
      case .began:
        isLongPressActive = true
        lastPanUpdateTime = CACurrentMediaTime()
        // Disable active tracking mode during target inspection
        parent.viewModel.chartInteractedByUser()

        // 1. Trigger haptic feedback as soon as the long press is detected
        let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        feedbackGenerator.impactOccurred()

        let touchRect = CGRect(x: touchPoint.x - 22, y: touchPoint.y - 22, width: 44, height: 44)
        let features = mapView.visibleFeatures(in: touchRect, styleLayerIdentifiers: [MapLayerIdentifier.goToWaypoint.rawValue, MapLayerIdentifier.visibleWaypoints.rawValue])

        if let feature = features.first as? MLNPointFeature,
           let id = feature.attributes[MapFeatureKey.id.rawValue] as? String {
          if id == parent.viewModel.draftWaypointID {
            // Interacting with the draft waypoint currently being created: ignore map callout presentation
            break
          }
          // Tapped on an existing waypoint: present callout immediately, defer camera adjustment until release (.ended)
          if let style = mapView.style {
            lastAimingCoordinate = nil
            MapStyleController.updateTargetAimingCrosshair(coordinate: nil, in: style, theme: parent.marineTheme)
          }
          parent.viewModel.calloutViewModel.presentWaypointCallout(coordinate: feature.coordinate, waypointID: id)
        } else {
          // Long press on empty chart area:
          // 2. Display callout dialog immediately
          // 3. Display crosshair in MapLibre under the finger immediately
          let targetCoordinate = mapView.convert(touchPoint, toCoordinateFrom: mapView)

          if let style = mapView.style {
            lastAimingCoordinate = targetCoordinate
            MapStyleController.updateTargetAimingCrosshair(
              coordinate: targetCoordinate,
              in: style,
              theme: parent.marineTheme
            )
          }

          parent.viewModel.calloutViewModel.startAimingPreview(at: targetCoordinate)
        }

      case .changed:
        // Update crosshair under finger as the user drags before releasing
        guard parent.viewModel.calloutViewModel.targetWaypointID == nil,
              parent.viewModel.calloutViewModel.aimingCoordinate != nil else { break }
        let now = CACurrentMediaTime()
        guard now - lastPanUpdateTime >= Self.pinPanThrottleInterval else { break }
        lastPanUpdateTime = now

        let currentTouchPoint = sender.location(in: mapView)
        let updatedCoordinate = mapView.convert(currentTouchPoint, toCoordinateFrom: mapView)
        if let style = mapView.style {
          lastAimingCoordinate = updatedCoordinate
          MapStyleController.updateTargetAimingCrosshair(
            coordinate: updatedCoordinate,
            in: style,
            theme: parent.marineTheme
          )
        }
        parent.viewModel.calloutViewModel.updateAimingPreview(at: updatedCoordinate)

      case .ended:
        isLongPressActive = false
        if parent.viewModel.calloutViewModel.isCalloutVisible,
           parent.viewModel.calloutViewModel.targetWaypointID != nil,
           let targetCoord = parent.viewModel.calloutViewModel.targetCoordinate {
          let currentPoint = mapView.convert(targetCoord, toPointTo: mapView)
          ensureTargetVisible(at: currentPoint, in: mapView, sheetHeight: parent.viewModel.calloutViewModel.lastSheetHeight)
        } else if parent.viewModel.calloutViewModel.aimingCoordinate != nil {
          let targetCoordinate = mapView.convert(touchPoint, toCoordinateFrom: mapView)
          if let style = mapView.style {
            lastAimingCoordinate = targetCoordinate
            MapStyleController.updateTargetAimingCrosshair(
              coordinate: targetCoordinate,
              in: style,
              theme: parent.marineTheme
            )
          }
          let targetScreenPoint = CGPoint(
            x: mapView.bounds.midX,
            y: mapView.bounds.height * AppConstants.Map.aimingCrosshairYFraction
          )
          let rawOffset = CGSize(
            width: touchPoint.x - targetScreenPoint.x,
            height: touchPoint.y - targetScreenPoint.y
          )
          let isNearCenter = hypot(rawOffset.width, rawOffset.height) < 1.0

          if !isNearCenter {
            // 1. Center the map with the MapLibre crosshair so targetCoordinate lands at targetScreenPoint
            parent.viewModel.calloutViewModel.beginAiming(at: targetCoordinate, needsCentering: true)
            let newCenterCoordinate = centerCoordinateToPosition(targetCoordinate, at: targetScreenPoint, in: mapView)
            mapView.setCenter(newCenterCoordinate, animated: true)
          } else {
            // Already at target screen point:
            // Trigger SwiftUI crosshair opacity = 1.0; MapLibreView.updateUIView will hide the MapLibre
            // crosshair layer in the exact same SwiftUI render transaction.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
              parent.viewModel.calloutViewModel.beginAiming(at: targetCoordinate, needsCentering: false)
            }
          }
        }

      case .cancelled, .failed:
        isLongPressActive = false
        if parent.viewModel.calloutViewModel.aimingCoordinate != nil {
          if let style = mapView.style {
            lastAimingCoordinate = nil
            MapStyleController.updateTargetAimingCrosshair(
              coordinate: nil,
              in: style,
              theme: parent.marineTheme
            )
          }
          parent.viewModel.calloutViewModel.cancelAimingPreview()
        }

      default:
        break
      }
    }
    
    /// Technical Design Choice: Automatic Map Camera Framing for Sheet Obscuration Prevention
    /// Shifts the map camera vertically so that the vertical segment [minY, maxY] fits comfortably
    /// between topClearance and the top of the bottom sheet dialog (with safety margin).
    private func shiftCameraToFitVerticalRange(
      minY: CGFloat,
      maxY: CGFloat,
      fallbackPoint: CGPoint?,
      fallbackBottomOffset: CGFloat? = nil,
      in mapView: MLNMapView,
      sheetHeight: CGFloat
    ) {
      let safeBottom = mapView.safeAreaInsets.bottom
      // The required clearance margin between the bottom of the target visual element and the top of the dialog
      let marginAboveSheet: CGFloat = 24.0
      let topClearance: CGFloat = max(mapView.safeAreaInsets.top + 80.0, MarineTheme.Metrics.topToolbarClearance)

      let effectiveSheetHeight = sheetHeight > 0 ? sheetHeight : (parent.marineTheme.isGloveMode ? 260.0 : 220.0)
      let dialogTopY = mapView.bounds.height - effectiveSheetHeight - safeBottom
      let targetPinBottomY = dialogTopY - marginAboveSheet
      let effectiveFallbackOffset = fallbackBottomOffset ?? MarinePinGraphicsFactory.pinHeight

      var deltaY: CGFloat = 0.0

      if maxY > targetPinBottomY {
        let neededShiftUp = maxY - targetPinBottomY
        if minY - neededShiftUp >= topClearance {
          deltaY = neededShiftUp
        } else if let fallback = fallbackPoint {
          let fallbackBottom = fallback.y + effectiveFallbackOffset
          if fallbackBottom > targetPinBottomY {
            deltaY = fallbackBottom - targetPinBottomY
          } else if fallback.y < topClearance {
            deltaY = fallback.y - topClearance
          }
        }
      } else if minY < topClearance {
        let neededShiftDown = minY - topClearance
        if maxY - neededShiftDown <= targetPinBottomY {
          deltaY = neededShiftDown
        } else if let fallback = fallbackPoint {
          let fallbackBottom = fallback.y + effectiveFallbackOffset
          if fallback.y < topClearance {
            deltaY = fallback.y - topClearance
          } else if fallbackBottom > targetPinBottomY {
            deltaY = fallbackBottom - targetPinBottomY
          }
        }
      }

      if abs(deltaY) > 1.0 {
        let currentCenterPoint = mapView.convert(mapView.centerCoordinate, toPointTo: mapView)
        let newCenterPoint = CGPoint(x: currentCenterPoint.x, y: currentCenterPoint.y + deltaY)
        let newCenterCoordinate = mapView.convert(newCenterPoint, toCoordinateFrom: mapView)
        mapView.setCenter(newCenterCoordinate, animated: true)
      }
    }

    private func ensureTargetVisible(at point: CGPoint, in mapView: MLNMapView, sheetHeight: CGFloat = 220) {
      let isWaypointTarget = parent.viewModel.calloutViewModel.targetWaypointID != nil
      let targetBottomOffset: CGFloat = isWaypointTarget
        ? (parent.marineTheme.isGloveMode ? 20.0 : 16.0)
        : MarinePinGraphicsFactory.pinHeight
      shiftCameraToFitVerticalRange(
        minY: point.y,
        maxY: point.y + targetBottomOffset,
        fallbackPoint: point,
        fallbackBottomOffset: targetBottomOffset,
        in: mapView,
        sheetHeight: sheetHeight
      )
    }

    private func ensureMeasurePinsVisible(in mapView: MLNMapView, sheetHeight: CGFloat = 220) {
      guard parent.viewModel.measureToolViewModel.isActive else { return }
      guard let startCoord = parent.viewModel.measureToolViewModel.startCoordinate,
            let endCoord = parent.viewModel.measureToolViewModel.endCoordinate else { return }

      let pinHeight: CGFloat = MarinePinGraphicsFactory.pinHeight
      let ptA = mapView.convert(startCoord, toPointTo: mapView)
      let ptB = mapView.convert(endCoord, toPointTo: mapView)
      let activePt = parent.viewModel.measureToolViewModel.activePin == .start ? ptA : ptB

      shiftCameraToFitVerticalRange(
        minY: min(ptA.y, ptB.y),
        maxY: max(ptA.y + pinHeight, ptB.y + pinHeight),
        fallbackPoint: activePt,
        fallbackBottomOffset: pinHeight,
        in: mapView,
        sheetHeight: sheetHeight
      )
    }

    /// Computes the new center coordinate such that `coordinate` will appear at `targetPoint` on screen.
    func centerCoordinateToPosition(
      _ coordinate: CLLocationCoordinate2D,
      at targetPoint: CGPoint,
      in mapView: MLNMapView
    ) -> CLLocationCoordinate2D {
      if mapView.contentInset != .zero {
        mapView.contentInset = .zero
      }
      let currentCoordPoint = mapView.convert(coordinate, toPointTo: mapView)
      let deltaX = currentCoordPoint.x - targetPoint.x
      let deltaY = currentCoordPoint.y - targetPoint.y
      let viewCenter = CGPoint(x: mapView.bounds.midX, y: mapView.bounds.midY)
      let newCenterPoint = CGPoint(x: viewCenter.x + deltaX, y: viewCenter.y + deltaY)
      return mapView.convert(newCenterPoint, toCoordinateFrom: mapView)
    }

    func setupSubscription(for mapView: MLNMapView) {
      // Connect ensureVisible callback from MapCalloutViewModel
      parent.viewModel.calloutViewModel.onEnsureVisibleRequested = { [weak self, weak mapView] sheetHeight in
        guard let self = self, let mapView = mapView else { return }
        // Never move the camera while the user is actively touching or dragging on the map!
        guard !self.isUserActivelyInteractingWithPins else { return }
        // EnsureVisible is only applied to waypoints; crosshairs remain positioned at aimingCrosshairYFraction (40% from top)
        guard self.parent.viewModel.calloutViewModel.isCalloutVisible,
              self.parent.viewModel.calloutViewModel.targetWaypointID != nil,
              let targetCoord = self.parent.viewModel.calloutViewModel.targetCoordinate else { return }
        let currentPoint = mapView.convert(targetCoord, toPointTo: mapView)
        self.ensureTargetVisible(at: currentPoint, in: mapView, sheetHeight: sheetHeight)
      }

      // Connect ensureVisible callback from MeasureToolViewModel
      parent.viewModel.measureToolViewModel.onEnsureVisibleRequested = { [weak self, weak mapView] sheetHeight in
        guard let self = self, let mapView = mapView else { return }
        // Never move the camera while the user is actively touching or dragging on the map!
        guard !self.isUserActivelyInteractingWithPins else { return }
        self.ensureMeasurePinsVisible(in: mapView, sheetHeight: sheetHeight)
      }

      streamTask?.cancel()
      streamTask = Task { @MainActor in
        for await event in parent.viewModel.cameraMoveStream {
          switch event {
          case .fitBounds(let bounds, let padding, let animated):
            let mlnBounds = MLNCoordinateBounds(sw: bounds.southWest, ne: bounds.northEast)
            await mapView.setVisibleCoordinateBounds(mlnBounds, edgePadding: padding, animated: animated)
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
          case .positionAtScreenFraction(let coordinate, let yFraction, let xFraction):
            guard mapView.bounds.height > 0, mapView.bounds.width > 0 else {
              mapView.setCenter(coordinate, animated: true)
              break
            }
            let targetPoint = CGPoint(x: mapView.bounds.width * xFraction, y: mapView.bounds.height * yFraction)
            let newCenterCoordinate = centerCoordinateToPosition(coordinate, at: targetPoint, in: mapView)
            mapView.setCenter(newCenterCoordinate, animated: true)
          }
        }
      }
    }
    
    var lastOpenSeaMapOverlayEnabled: Bool = false
    
    func mapViewRegionIsChanging(_ mapView: MLNMapView) {
      let mpp = mapView.metersPerPoint(atLatitude: mapView.centerCoordinate.latitude)
      self.parent.viewModel.throttledUpdateMapScaleAndZoom(metersPerPoint: mpp, zoomLevel: mapView.zoomLevel)
      self.parent.viewModel.throttledUpdateCenterCoordinate(mapView.centerCoordinate)
      self.parent.viewModel.updateOfflineRegionScreenPositions(
        projection: { mapView.convert($0, toPointTo: mapView) },
        bounds: mapView.bounds
      )

      // Live update target coordinate under crosshair when user moves the map (throttled to ~30Hz)
      if parent.viewModel.calloutViewModel.isCalloutVisible &&
         parent.viewModel.calloutViewModel.targetWaypointID == nil &&
         !parent.viewModel.measureToolViewModel.isActive &&
         !parent.viewModel.calloutViewModel.isCentering &&
         parent.viewModel.calloutViewModel.aimingCoordinate == nil {
        let now = CACurrentMediaTime()
        if now - lastCalloutTargetUpdateTime >= 0.032 {
          lastCalloutTargetUpdateTime = now
          let aimingPoint = CGPoint(
            x: mapView.bounds.midX,
            y: mapView.bounds.height * AppConstants.Map.aimingCrosshairYFraction
          )
          let targetCoord = mapView.convert(aimingPoint, toCoordinateFrom: mapView)
          parent.viewModel.calloutViewModel.updateTarget(coordinate: targetCoord)
        }
      }
      
      // Technical Design Choice: Dynamic Tracking Break Evaluation
      // During active manual panning in tracking mode (.northUp or .courseUp), measure the physical screen displacement
      // of the initial anchor coordinate. As soon as displacement exceeds the threshold (scaled for Glove Mode),
      // transition immediately to .free mode so the user experiences smooth, uninterrupted chart panning.
      if parent.viewModel.trackingMode != .free,
         !parent.viewModel.anchorViewModel.isAdjustingAnchor,
         parent.viewModel.waypointAdjustmentSession == nil,
         !hasExceededTrackingMargin,
         let initialCoord = initialPanCenterCoordinate,
         let initialPoint = initialPanScreenPoint {
        let currentPoint = mapView.convert(initialCoord, toPointTo: mapView)
        let displacement = hypot(currentPoint.x - initialPoint.x, currentPoint.y - initialPoint.y)
        let threshold = parent.marineTheme.isGloveMode ? AppConstants.Map.trackingBreakGloveThreshold : AppConstants.Map.trackingBreakThreshold
        if displacement >= threshold {
          hasExceededTrackingMargin = true
          parent.viewModel.chartInteractedByUser()
        }
      }
    }
    
    func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
      let mpp = mapView.metersPerPoint(atLatitude: mapView.centerCoordinate.latitude)
      self.parent.viewModel.updateMapScaleAndZoomImmediately(metersPerPoint: mpp, zoomLevel: mapView.zoomLevel)
      self.parent.viewModel.updateCenterCoordinateImmediately(mapView.centerCoordinate)
      self.parent.viewModel.updateOfflineRegionScreenPositions(
        projection: { mapView.convert($0, toPointTo: mapView) },
        bounds: mapView.bounds
      )
    }
    
    // Called when the map has finished loading its style
    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
      Logger.chart.info("MapLibre successfully loaded the default style.")
      
      // Add vessel cursor image
      if let image = VesselGraphicsFactory.createVesselImage(size: MarineTheme.ChartMetrics.vesselCursorBaseSize, color: UIColor(parent.marineTheme.colors.accent)) {
        style.setImage(image, forName: "vessel-cursor")
      }
      
      // Register all pin and anchor status icons once in MapLibre style
      MapStyleController.ensureAnchorImagesExist(in: style, theme: parent.marineTheme)
      MapStyleController.ensureMeasurePinImagesExist(in: style, theme: parent.marineTheme)
      lastThemeHash = nil
      
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

      let measureState = parent.viewModel.measureToolViewModel.state
      let measureActivePin = parent.viewModel.measureToolViewModel.activePin
      MapStyleController.updateMeasureLine(state: measureState, in: style, theme: parent.marineTheme)
      MapStyleController.updateMeasurePins(state: measureState, activePin: measureActivePin, in: style, theme: parent.marineTheme)
      lastMeasureState = measureState
      lastMeasureActivePin = measureActivePin

      let anchorVisualState = parent.viewModel.anchorVisualState
      MapStyleController.updateAnchor(state: anchorVisualState, in: style, theme: parent.marineTheme)
      lastAnchorVisualState = anchorVisualState

      // Offline Mask layer initialization
      let maskState = parent.viewModel.offlineMaskVisualState
      MapStyleController.updateOfflineMask(state: maskState, in: style, theme: parent.marineTheme)
      lastOfflineMaskVisualState = maskState

      // Highlighted offline region preview initialization
      let highlightRegion = parent.viewModel.highlightedOfflineRegion
      MapStyleController.updateOfflineHighlight(region: highlightRegion, in: style, theme: parent.marineTheme)
      lastHighlightedOfflineRegion = highlightRegion

      // Active offline selection zone initialization
      let activeSelection = (parent.offlineSelectionViewModel?.isSelectionModeActive == true) ? parent.offlineSelectionViewModel?.selectedBounds : nil
      MapStyleController.updateOfflineSelection(bounds: activeSelection, in: style, theme: parent.marineTheme)
      lastOfflineSelectionBounds = activeSelection

      let isStale = parent.viewModel.isDataStale
      MapStyleController.updateDataStaleState(isStale: isStale, in: style)
      lastDataStale = isStale

      MapStyleController.ensureTargetAimingCrosshairLayersExist(in: style, theme: parent.marineTheme)
      lastAimingCoordinate = nil


      
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
      if !reason.contains(.programmatic) {
        self.parent.viewModel.isMapMoving = true
        if self.parent.viewModel.calloutViewModel.isCalloutVisible &&
           self.parent.viewModel.calloutViewModel.targetWaypointID == nil &&
           !self.parent.viewModel.measureToolViewModel.isActive {
          if self.parent.viewModel.calloutViewModel.isCentering {
            // Trigger SwiftUI crosshair opacity = 1.0; MapLibreView.updateUIView will hide the MapLibre
            // crosshair layer in the exact same SwiftUI render transaction.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
              self.parent.viewModel.calloutViewModel.interruptCentering(at: mapView.centerCoordinate)
            }
          }
        }
        
        if self.parent.viewModel.trackingMode != .free && !self.parent.viewModel.anchorViewModel.isAdjustingAnchor && self.parent.viewModel.waypointAdjustmentSession == nil {
          if shouldBreakTracking(for: reason) {
            // Technical Design Choice: Delayed Tracking Break on Pan Gesture
            // Instead of instantly dropping tracking mode at the first sub-pixel camera movement,
            // we snapshot the current anchor coordinate and screen projection. The tracking mode will only
            // break if the user drags further than the tolerance threshold (AppConstants.Map.trackingBreakThreshold).
            self.initialPanCenterCoordinate = mapView.centerCoordinate
            self.initialPanScreenPoint = mapView.convert(mapView.centerCoordinate, toPointTo: mapView)
            self.hasExceededTrackingMargin = false
          } else {
            // Pinch-to-zoom or non-breaking gestures explicitly preserve automated vessel tracking.
            self.initialPanCenterCoordinate = nil
            self.initialPanScreenPoint = nil
            self.hasExceededTrackingMargin = false
          }
        }
      }
    }
    
    // MARK: - Offline Selection Corner Drag Gestures

    /// Tests whether a screen touch point is within the touch hit target of one of the 4 selection corners.
    func hitTestSelectionCorner(at point: CGPoint, in mapView: MLNMapView) -> ActiveSelectionCorner? {
      guard let offlineVM = parent.offlineSelectionViewModel,
            offlineVM.isSelectionModeActive,
            let bounds = offlineVM.selectedBounds else {
        return nil
      }

      let nw = CLLocationCoordinate2D(latitude: bounds.northEast.latitude, longitude: bounds.southWest.longitude)
      let ne = CLLocationCoordinate2D(latitude: bounds.northEast.latitude, longitude: bounds.northEast.longitude)
      let se = CLLocationCoordinate2D(latitude: bounds.southWest.latitude, longitude: bounds.northEast.longitude)
      let sw = CLLocationCoordinate2D(latitude: bounds.southWest.latitude, longitude: bounds.southWest.longitude)

      let ptNW = mapView.convert(nw, toPointTo: mapView)
      let ptNE = mapView.convert(ne, toPointTo: mapView)
      let ptSE = mapView.convert(se, toPointTo: mapView)
      let ptSW = mapView.convert(sw, toPointTo: mapView)

      let hitRadius: CGFloat = parent.marineTheme.isGloveMode ? 48.0 : 36.0

      let distNW = hypot(point.x - ptNW.x, point.y - ptNW.y)
      let distNE = hypot(point.x - ptNE.x, point.y - ptNE.y)
      let distSE = hypot(point.x - ptSE.x, point.y - ptSE.y)
      let distSW = hypot(point.x - ptSW.x, point.y - ptSW.y)

      let corners: [(ActiveSelectionCorner, CGFloat)] = [
        (.topLeft, distNW),
        (.topRight, distNE),
        (.bottomRight, distSE),
        (.bottomLeft, distSW)
      ]

      if let closest = corners.min(by: { $0.1 < $1.1 }), closest.1 <= hitRadius {
        return closest.0
      }
      return nil
    }

    private func computeUpdatedBounds(
      from current: GeographicBoundingBox,
      dragging corner: ActiveSelectionCorner,
      to coord: CLLocationCoordinate2D
    ) -> GeographicBoundingBox {
      let minSpan: Double = 0.005 // ~500m to prevent inversion
      var sw = current.southWest
      var ne = current.northEast

      switch corner {
      case .topLeft: // NW: updates latitude of North, longitude of West
        ne.latitude = max(coord.latitude, sw.latitude + minSpan)
        sw.longitude = min(coord.longitude, ne.longitude - minSpan)
      case .topRight: // NE: updates latitude of North, longitude of East
        ne.latitude = max(coord.latitude, sw.latitude + minSpan)
        ne.longitude = max(coord.longitude, sw.longitude + minSpan)
      case .bottomLeft: // SW: updates latitude of South, longitude of West
        sw.latitude = min(coord.latitude, ne.latitude - minSpan)
        sw.longitude = min(coord.longitude, ne.longitude - minSpan)
      case .bottomRight: // SE: updates latitude of South, longitude of East
        sw.latitude = min(coord.latitude, ne.latitude - minSpan)
        ne.longitude = max(coord.longitude, sw.longitude + minSpan)
      }

      return GeographicBoundingBox(southWest: sw, northEast: ne)
    }

    private func handleSelectionCornerPan(_ sender: UIPanGestureRecognizer, in mapView: MLNMapView) {
      guard let offlineVM = parent.offlineSelectionViewModel,
            offlineVM.isSelectionModeActive else {
        activeDraggedSelectionCorner = nil
        activeSelectionDragInitialBounds = nil
        activeSelectionDragCurrentBounds = nil
        return
      }

      let touchPoint = sender.location(in: mapView)

      switch sender.state {
      case .began:
        guard let corner = hitTestSelectionCorner(at: touchPoint, in: mapView),
              let initialBounds = offlineVM.selectedBounds else { return }
        activeDraggedSelectionCorner = corner
        activeSelectionDragInitialBounds = initialBounds
        activeSelectionDragCurrentBounds = initialBounds
        lastPanUpdateTime = CACurrentMediaTime()
        parent.viewModel.chartInteractedByUser()

      case .changed:
        guard let corner = activeDraggedSelectionCorner,
              let initialBounds = activeSelectionDragInitialBounds else { return }
        let now = CACurrentMediaTime()
        guard now - lastPanUpdateTime >= Self.pinPanThrottleInterval else { return }
        lastPanUpdateTime = now

        let coord = mapView.convert(touchPoint, toCoordinateFrom: mapView)
        let updatedBounds = computeUpdatedBounds(from: initialBounds, dragging: corner, to: coord)
        activeSelectionDragCurrentBounds = updatedBounds

        // Isolated visual update: directly mutate MapLibre vector layers to prevent SwiftUI render storm
        if let style = mapView.style {
          MapStyleController.updateOfflineSelection(
            bounds: updatedBounds,
            in: style,
            theme: parent.marineTheme
          )
        }

      case .ended:
        if let corner = activeDraggedSelectionCorner,
           let initialBounds = activeSelectionDragInitialBounds {
          let coord = mapView.convert(touchPoint, toCoordinateFrom: mapView)
          let finalBounds = computeUpdatedBounds(from: initialBounds, dragging: corner, to: coord)
          offlineVM.updateBoundingBox(finalBounds)
        } else if let finalBounds = activeSelectionDragCurrentBounds {
          offlineVM.updateBoundingBox(finalBounds)
        }
        activeDraggedSelectionCorner = nil
        activeSelectionDragInitialBounds = nil
        activeSelectionDragCurrentBounds = nil

      case .cancelled, .failed:
        // Restore MapLibre visual layers to the uncommitted model bounds
        if let style = mapView.style {
          MapStyleController.updateOfflineSelection(
            bounds: offlineVM.selectedBounds,
            in: style,
            theme: parent.marineTheme
          )
        }
        activeDraggedSelectionCorner = nil
        activeSelectionDragInitialBounds = nil
        activeSelectionDragCurrentBounds = nil

      default:
        break
      }
    }
    
    // Capture user's chart movements to sync the final camera state and evaluate tracking mode persistence.
    func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason, animated: Bool) {
      self.parent.viewModel.isMapMoving = false

      // Synchronously hand off from MapLibre crosshair to SwiftUI crosshair on the exact frame camera movement stops.
      // MapLibreView.updateUIView will hide the MapLibre crosshair layer in the exact same SwiftUI render pass.
      if !self.isLongPressActive &&
         self.parent.viewModel.calloutViewModel.isCalloutVisible &&
         self.parent.viewModel.calloutViewModel.targetWaypointID == nil &&
         !self.parent.viewModel.measureToolViewModel.isActive {
        let aimingPoint = CGPoint(
          x: mapView.bounds.midX,
          y: mapView.bounds.height * AppConstants.Map.aimingCrosshairYFraction
        )
        let aimingCoord = mapView.convert(aimingPoint, toCoordinateFrom: mapView)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
          self.parent.viewModel.calloutViewModel.completeCentering(at: aimingCoord)
        }
      }

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
        
        self.parent.viewModel.updateOfflineRegionScreenPositions(
          projection: { mapView.convert($0, toPointTo: mapView) },
          bounds: mapView.bounds
        )
        
        // Technical Design Choice: Centering Restoration vs Tracking Break
        // If the user was in an automated tracking mode:
        // - If movement exceeded the threshold: tracking mode was broken during the gesture (or broken now).
        // - If movement remained within the tolerance margin: restore camera lock on vessel smoothly,
        //   EXCEPT when manual anchor position adjustment or callout targeting is active,
        //   preventing the crosshair aiming position from being pulled away (rubber-band bug) during micro-drags.
        if self.parent.viewModel.trackingMode != .free {
          if self.hasExceededTrackingMargin {
            self.parent.viewModel.chartInteractedByUser()
          } else if self.shouldBreakTracking(for: reason) {
            if !self.parent.viewModel.anchorViewModel.isAdjustingAnchor &&
               self.parent.viewModel.waypointAdjustmentSession == nil &&
               !self.parent.viewModel.calloutViewModel.isCalloutVisible {
              Logger.chart.info("Manual drag remained within tolerance margin; recentering on vessel.")
              self.parent.viewModel.centerOnUserLocation()
            }
          }
        }
        
        self.initialPanCenterCoordinate = nil
        self.initialPanScreenPoint = nil
        self.hasExceededTrackingMargin = false
      }
    }
    
    // Potential loading errors
    func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
      Logger.chart.error("Error loading MapLibre map: \(error.localizedDescription, privacy: .public)")
    }
  }
}

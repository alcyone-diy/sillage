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
  @Environment(WaypointService.self) private var waypointService
  @Environment(PanelManagerViewModel.self) private var panelManager
  @Environment(AppViewModel.self) private var appViewModel
  @Environment(OfflineSelectionViewModel.self) private var offlineSelectionViewModel
  var viewModel: ChartViewModel
  
  func makeUIView(context: Context) -> MLNMapView {

    // Initialization of the MapLibre view without a frame
    let mapView = MarineMapView(frame: .zero)
    
    // Anchor all zoom gestures (pinch, one-finger quick zoom, double-tap, two-finger tap)
    // to the active nautical crosshair so zooming never drifts the aimed point off the reticle.
    mapView.customGestureAnchorProvider = { [weak coordinator = context.coordinator, weak mapView] gesture in
      guard let coordinator, let mapView else { return nil }
      let viewModel = coordinator.parent.viewModel
      let calloutVM = viewModel.calloutViewModel
      let measureVM = viewModel.measureToolViewModel

      let isPositionPickerCrosshairDisplayed =
        viewModel.anchorViewModel.isAdjustingAnchor ||
        viewModel.anchorViewModel.isPreparingDropAnchor ||
        viewModel.waypointAdjustmentSession != nil

      let isCalloutCrosshairDisplayed =
        calloutVM.isCalloutVisible &&
        !measureVM.isActive

      let crosshairYFraction: CGFloat?
      if isPositionPickerCrosshairDisplayed {
        crosshairYFraction = AppConstants.Map.positionPickerCrosshairYFraction
      } else if isCalloutCrosshairDisplayed {
        crosshairYFraction = AppConstants.Map.aimingCrosshairYFraction
      } else {
        crosshairYFraction = nil
      }

      return MarineMapView.zoomAnchorPoint(
        for: gesture,
        in: mapView.bounds,
        crosshairYFraction: crosshairYFraction
      )
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
      if context.coordinator.lastMarineTheme != marineTheme {
        context.coordinator.lastMarineTheme = marineTheme
        MapStyleController.applyTheme(marineTheme, in: style)
      }
      
      // Vessel feature update
      if vesselVisualState != context.coordinator.lastVesselVisualState {
        MapStyleController.updateVessel(state: vesselVisualState, in: style)
        context.coordinator.lastVesselVisualState = vesselVisualState
      }
      
      // Heading vector feature update
      if headingVectorData != context.coordinator.lastHeadingVectorData {
        MapStyleController.updateHeadingVector(data: headingVectorData, in: style)
        context.coordinator.lastHeadingVectorData = headingVectorData
      }
      
      // GPS accuracy feature update
      if gpsAccuracyVisualState != context.coordinator.lastGpsAccuracyVisualState {
        MapStyleController.updateGpsAccuracy(state: gpsAccuracyVisualState, in: style)
        context.coordinator.lastGpsAccuracyVisualState = gpsAccuracyVisualState
      }
      
      // Active track feature update
      let currentActiveCount = activeTrackPoints.count
      let currentActiveTimestamp = activeTrackPoints.last?.timestamp
      if currentActiveCount != context.coordinator.lastActiveTrackCount || currentActiveTimestamp != context.coordinator.lastActiveTrackTimestamp {
        MapStyleController.updateActiveTrack(points: activeTrackPoints, in: style)
        context.coordinator.lastActiveTrackCount = currentActiveCount
        context.coordinator.lastActiveTrackTimestamp = currentActiveTimestamp
      }
      
      // Saved track feature update
      if savedTrackVisualState != context.coordinator.lastSavedTrackVisualState {
        MapStyleController.updateSavedTrack(state: savedTrackVisualState, in: style)
        context.coordinator.lastSavedTrackVisualState = savedTrackVisualState
      }
      
      // Displayed waypoints feature update
      if visibleWaypointVisualStates != context.coordinator.lastVisibleWaypointVisualStates {
        MapStyleController.updateVisibleWaypoints(states: visibleWaypointVisualStates, in: style)
        context.coordinator.lastVisibleWaypointVisualStates = visibleWaypointVisualStates
      }
      
      // GoTo waypoint feature update
      if goToWaypointVisualState != context.coordinator.lastGoToWaypointVisualState {
        MapStyleController.updateGoToWaypoint(state: goToWaypointVisualState, in: style)
        context.coordinator.lastGoToWaypointVisualState = goToWaypointVisualState
      }
      
      // Bearing Line feature update
      if bearingLineVisualState != context.coordinator.lastBearingLineVisualState {
        MapStyleController.updateBearingLine(state: bearingLineVisualState, in: style)
        context.coordinator.lastBearingLineVisualState = bearingLineVisualState
      }

      // Target Aiming Crosshair GPU layer update during centering flight
      let aimingCoord = viewModel.calloutViewModel.aimingCoordinate
      if aimingCoord != context.coordinator.lastAimingCoordinate {
        context.coordinator.lastAimingCoordinate = aimingCoord
        MapStyleController.updateTargetAimingCrosshair(coordinate: aimingCoord, in: style)
      }

      // Measure feature update (polyline and pins)
      let measureState = viewModel.measureToolViewModel.state
      let measureActivePin = viewModel.measureToolViewModel.activePin
      if measureState != context.coordinator.lastMeasureState || measureActivePin != context.coordinator.lastMeasureActivePin {
        MapStyleController.updateMeasureLine(state: measureState, in: style)
        MapStyleController.updateMeasurePins(state: measureState, activePin: measureActivePin, in: style)
        context.coordinator.lastMeasureState = measureState
        context.coordinator.lastMeasureActivePin = measureActivePin
      }
      
      // Anchor update
      if anchorVisualState != context.coordinator.lastAnchorVisualState {
        context.coordinator.lastAnchorVisualState = anchorVisualState
        MapStyleController.updateAnchor(state: anchorVisualState, in: style)
      }

      // Offline mask update
      if offlineMaskVisualState != context.coordinator.lastOfflineMaskVisualState {
        MapStyleController.updateOfflineMask(state: offlineMaskVisualState, in: style)
        context.coordinator.lastOfflineMaskVisualState = offlineMaskVisualState
        viewModel.updateOfflineRegionScreenPositions(
          projection: { uiView.convert($0, toPointTo: uiView) },
          bounds: uiView.bounds
        )
      }

      // Highlighted offline region update
      if highlightedOfflineRegion != context.coordinator.lastHighlightedOfflineRegion {
        context.coordinator.lastHighlightedOfflineRegion = highlightedOfflineRegion
        MapStyleController.updateOfflineHighlight(region: highlightedOfflineRegion, in: style)
      }

      // Active offline selection zone update
      let activeSelectionBounds = offlineSelectionViewModel.isSelectionModeActive ? offlineSelectionViewModel.selectedBounds : nil
      if activeSelectionBounds != context.coordinator.lastOfflineSelectionBounds {
        context.coordinator.lastOfflineSelectionBounds = activeSelectionBounds
        MapStyleController.updateOfflineSelection(bounds: activeSelectionBounds, in: style)
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
        let targetWaypointID = viewModel.calloutViewModel.targetWaypointID
        let resolvedCoord = targetWaypointID != nil ? target : uiView.convert(targetScreenPoint, toCoordinateFrom: uiView)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
          viewModel.calloutViewModel.interruptCentering(at: resolvedCoord, waypointID: targetWaypointID)
        }
        context.coordinator.lastAimingCoordinate = nil
        MapStyleController.updateTargetAimingCrosshair(coordinate: nil, in: style)
      }
    }

    // Offline selection mode: force chart rotation to 0 (North-Up) and reset pitch to 0.
    if offlineSelectionViewModel.isSelectionModeActive {
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
      if offlineSelectionViewModel.selectedBounds == nil, uiView.bounds.width > 0, uiView.bounds.height > 0 {
        let baseSize = min(uiView.bounds.width, uiView.bounds.height) * offlineSelectionViewModel.cropBoxWidthRatio
        let size = CGSize(width: baseSize, height: baseSize * offlineSelectionViewModel.cropBoxAspect)
        let x = (uiView.bounds.width - size.width) / 2.0
        let y = (uiView.bounds.height - size.height) / 2.0
        let rect = CGRect(x: x, y: y, width: size.width, height: size.height)
        let mlnBounds = uiView.convert(rect, toCoordinateBoundsFrom: uiView)
        let initialBounds = GeographicBoundingBox(southWest: mlnBounds.sw, northEast: mlnBounds.ne)

        Task { @MainActor [weak offlineVM = offlineSelectionViewModel] in
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

  static func dismantleUIView(_ uiView: MLNMapView, coordinator: Coordinator) {
    coordinator.cancelTasks()
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
    nonisolated(unsafe) private var streamTask: Task<Void, Never>?
    nonisolated(unsafe) private var pendingBoundsUpdateTask: Task<Void, Never>?
    nonisolated(unsafe) private var networkObservationTask: Task<Void, Never>?
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
    private var snappedMeasurePinWaypointID: String?
    private var isLongPressActive: Bool = false
    private var hasDraggedDuringLongPress: Bool = false
    private var longPressBeganPoint: CGPoint?
    private static let longPressDragThreshold: CGFloat = 6.0
    private var isMagneticRecentering: Bool = false
    private var isStartingMagneticRecenter: Bool = false
    private var isUserPanMoveActive: Bool = false
    private var isZoomMoveActive: Bool = false
    private var panStartWaypointID: String?
    private let snapFeedbackGenerator = UISelectionFeedbackGenerator()
    private var measurePinDragOffset: CGPoint = .zero
    private var isUserActivelyInteractingWithPins: Bool {
      isLongPressActive || activeDraggedPin != nil || parent.viewModel.measureToolViewModel.isDraggingPin || activeDraggedSelectionCorner != nil
    }
    private var lastPanUpdateTime: CFTimeInterval = 0
    private var lastCalloutTargetUpdateTime: CFTimeInterval = 0
    private static let pinPanThrottleInterval: CFTimeInterval = 0.016
    var lastMarineTheme: MarineTheme?
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
    
    /// Technical Design Choice: Vessel Centering Gesture Tolerance Margin
    /// Tracks the initial anchor coordinate and screen point at the start of a manual drag gesture,
    /// allowing accidental touches, slips, and small vibrations to be tolerated without immediately breaking tracking mode.
    var initialPanCenterCoordinate: CLLocationCoordinate2D?
    var initialPanScreenPoint: CGPoint?
    var hasExceededTrackingMargin: Bool = false
    var lastBounds: CGRect = .zero
    var lastAimingCoordinate: CLLocationCoordinate2D?
    var hasAppliedInitialCamera: Bool = false
    var pendingReloadCamera: (center: CLLocationCoordinate2D, zoomLevel: Double, direction: CLLocationDirection)?
    
    init(_ parent: MapLibreView) {
      self.parent = parent
      super.init()
      
      networkObservationTask = Task { @MainActor [weak self] in
        for await _ in NotificationCenter.default.notifications(named: NSNotification.Name("NetworkDidReconnect")) {
          guard !Task.isCancelled, let self else { break }
          guard let mapView = self.mapView else { continue }
          Logger.chart.info("Network reconnected, forcing MapLibre complete style reload")
          if self.hasAppliedInitialCamera {
            self.pendingReloadCamera = (
              center: mapView.centerCoordinate,
              zoomLevel: mapView.zoomLevel,
              direction: mapView.direction
            )
          }
          mapView.reloadStyle(nil)
        }
      }
    }
    
    func cancelTasks() {
      streamTask?.cancel()
      streamTask = nil
      pendingBoundsUpdateTask?.cancel()
      pendingBoundsUpdateTask = nil
      networkObservationTask?.cancel()
      networkObservationTask = nil
    }
    
    deinit {
      streamTask?.cancel()
      pendingBoundsUpdateTask?.cancel()
      networkObservationTask?.cancel()
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
        if parent.offlineSelectionViewModel.isSelectionModeActive {
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

      if activeDraggedSelectionCorner != nil || (parent.offlineSelectionViewModel.isSelectionModeActive && hitTestSelectionCorner(at: sender.location(in: mapView), in: mapView) != nil) {
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
        snapFeedbackGenerator.prepare()

        let currentCoord = (pin == .start)
          ? parent.viewModel.measureToolViewModel.startCoordinate
          : parent.viewModel.measureToolViewModel.endCoordinate
        if let currentCoord = currentCoord {
          let tipPoint = mapView.convert(currentCoord, toPointTo: mapView)
          measurePinDragOffset = CGPoint(
            x: touchPoint.x - tipPoint.x,
            y: touchPoint.y - tipPoint.y
          )
          // Seed hysteresis only if the pin is actually resting on a waypoint (<= 1pt),
          // so zooming out near an open-water pin never causes a false lock on grab.
          snappedMeasurePinWaypointID = WaypointMagneticSnap.evaluate(
            reticlePoint: tipPoint,
            candidates: waypointSnapCandidates(in: mapView),
            currentlySnappedID: nil,
            attachRadius: 1.0,
            detachHysteresis: 0
          )?.waypointID
        } else {
          measurePinDragOffset = .zero
          snappedMeasurePinWaypointID = nil
        }
        lastPanUpdateTime = CACurrentMediaTime()

      case .changed:
        guard let pin = activeDraggedPin else { return }
        guard parent.viewModel.measureToolViewModel.isActive else {
          activeDraggedPin = nil
          snappedMeasurePinWaypointID = nil
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
        let coord = resolveMeasurePinCoordinate(for: clampedTip, in: mapView)
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
          let coord = resolveMeasurePinCoordinate(for: clampedTip, in: mapView)
          switch pin {
          case .start:
            parent.viewModel.measureToolViewModel.updateStart(to: coord)
          case .end:
            parent.viewModel.measureToolViewModel.updateEnd(to: coord)
          }
        }
        activeDraggedPin = nil
        snappedMeasurePinWaypointID = nil
        measurePinDragOffset = .zero
        parent.viewModel.measureToolViewModel.isDraggingPin = false
        ensureMeasurePinsVisible(in: mapView, sheetHeight: parent.viewModel.measureToolViewModel.lastSheetHeight)

      case .cancelled, .failed:
        activeDraggedPin = nil
        snappedMeasurePinWaypointID = nil
        measurePinDragOffset = .zero
        parent.viewModel.measureToolViewModel.isDraggingPin = false
        ensureMeasurePinsVisible(in: mapView, sheetHeight: parent.viewModel.measureToolViewModel.lastSheetHeight)

      default:
        break
      }
    }

    /// Resolves a measure pin tip screen position with the same waypoint magnetism and hysteresis
    /// used by the chart aiming reticle, firing selection haptic feedback upon attaching to a waypoint.
    private func resolveMeasurePinCoordinate(
      for tipPoint: CGPoint,
      in mapView: MLNMapView
    ) -> CLLocationCoordinate2D {
      if let snap = evaluateWaypointSnap(
        at: tipPoint,
        in: mapView,
        currentlySnappedID: snappedMeasurePinWaypointID
      ) {
        if snap.waypointID != snappedMeasurePinWaypointID {
          snapFeedbackGenerator.selectionChanged()
        }
        snappedMeasurePinWaypointID = snap.waypointID
        return snap.coordinate
      } else {
        snappedMeasurePinWaypointID = nil
        return mapView.convert(tipPoint, toCoordinateFrom: mapView)
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

        switch sender.state {
        case .began:
          parent.viewModel.measureToolViewModel.isDraggingPin = true
          isLongPressActive = true
          snappedMeasurePinWaypointID = nil
          snapFeedbackGenerator.prepare()
          parent.viewModel.chartInteractedByUser()
          let coord = resolveMeasurePinCoordinate(for: clampedTip, in: mapView)
          parent.viewModel.measureToolViewModel.handleMapLongPress(at: coord)
          lastPanUpdateTime = CACurrentMediaTime()

        case .changed:
          let now = CACurrentMediaTime()
          guard now - lastPanUpdateTime >= Self.pinPanThrottleInterval else { return }
          lastPanUpdateTime = now

          parent.viewModel.chartInteractedByUser()
          let coord = resolveMeasurePinCoordinate(for: clampedTip, in: mapView)
          parent.viewModel.measureToolViewModel.handleMapLongPress(at: coord)

        case .ended:
          parent.viewModel.chartInteractedByUser()
          let coord = resolveMeasurePinCoordinate(for: clampedTip, in: mapView)
          parent.viewModel.measureToolViewModel.handleMapLongPress(at: coord)
          snappedMeasurePinWaypointID = nil
          parent.viewModel.measureToolViewModel.isDraggingPin = false
          isLongPressActive = false
          ensureMeasurePinsVisible(in: mapView, sheetHeight: parent.viewModel.measureToolViewModel.lastSheetHeight)

        case .cancelled, .failed:
          snappedMeasurePinWaypointID = nil
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
        hasDraggedDuringLongPress = false
        longPressBeganPoint = touchPoint
        isMagneticRecentering = false
        lastPanUpdateTime = CACurrentMediaTime()
        snapFeedbackGenerator.prepare()
        // Disable active tracking mode during target inspection
        parent.viewModel.chartInteractedByUser()

        // 1. Trigger haptic feedback as soon as the long press is detected
        let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        feedbackGenerator.impactOccurred()

        // Respect Glove Mode touch target sizing (44pt standard, 66pt glove mode) for initial waypoint hit-testing
        let hitSize = parent.marineTheme.minTouchTarget
        let halfHitSize = hitSize / 2.0
        let touchRect = CGRect(x: touchPoint.x - halfHitSize, y: touchPoint.y - halfHitSize, width: hitSize, height: hitSize)
        let features = mapView.visibleFeatures(in: touchRect, styleLayerIdentifiers: [MapLayerIdentifier.goToWaypoint.rawValue, MapLayerIdentifier.visibleWaypoints.rawValue])

        let draftID = parent.viewModel.draftWaypointID
        var containsDraftFeature = false
        var closestWaypoint: (feature: MLNPointFeature, id: String, distance: CGFloat)? = nil

        for case let feature as MLNPointFeature in features {
          guard let id = feature.attributes[MapFeatureKey.id.rawValue] as? String else { continue }
          if id == draftID {
            containsDraftFeature = true
            continue
          }
          let pt = mapView.convert(feature.coordinate, toPointTo: mapView)
          let dist = hypot(pt.x - touchPoint.x, pt.y - touchPoint.y)
          if let existing = closestWaypoint {
            if dist < existing.distance {
              closestWaypoint = (feature, id, dist)
            }
          } else {
            closestWaypoint = (feature, id, dist)
          }
        }

        if let hit = closestWaypoint {
          // Unified reticle targeting: place the GPU crosshair directly on the waypoint coordinate
          // so the user can drag off it or release to center it under the reticle.
          if let style = mapView.style {
            lastAimingCoordinate = hit.feature.coordinate
            MapStyleController.updateTargetAimingCrosshair(
              coordinate: hit.feature.coordinate,
              in: style
            )
          }
          parent.viewModel.calloutViewModel.startAimingPreview(at: hit.feature.coordinate, waypointID: hit.id)
        } else if containsDraftFeature {
          // Interacting exclusively with the draft waypoint currently being created: ignore map callout presentation
          break
        } else {
          // Long press on empty chart area:
          // 2. Display callout dialog immediately
          // 3. Display crosshair in MapLibre under the finger immediately
          let targetCoordinate = mapView.convert(touchPoint, toCoordinateFrom: mapView)

          if let style = mapView.style {
            lastAimingCoordinate = targetCoordinate
            MapStyleController.updateTargetAimingCrosshair(
              coordinate: targetCoordinate,
              in: style
            )
          }

          parent.viewModel.calloutViewModel.startAimingPreview(at: targetCoordinate, waypointID: nil)
        }

      case .changed:
        // Update crosshair under finger as the user drags before releasing (with light waypoint magnetism)
        guard parent.viewModel.calloutViewModel.aimingCoordinate != nil else { break }
        let now = CACurrentMediaTime()
        guard now - lastPanUpdateTime >= Self.pinPanThrottleInterval else { break }
        lastPanUpdateTime = now

        let currentTouchPoint = sender.location(in: mapView)
        if !hasDraggedDuringLongPress {
          if let beganPoint = longPressBeganPoint,
             hypot(currentTouchPoint.x - beganPoint.x, currentTouchPoint.y - beganPoint.y) < Self.longPressDragThreshold {
            // Ignore sub-threshold finger micro-tremors so Glove Mode waypoint locks (30–33pt) do not detach prematurely.
            break
          }
          hasDraggedDuringLongPress = true
        }

        let previousWaypointID = parent.viewModel.calloutViewModel.targetWaypointID
        let snap = evaluateWaypointSnap(
          at: currentTouchPoint,
          in: mapView,
          currentlySnappedID: previousWaypointID
        )

        let updatedCoordinate: CLLocationCoordinate2D
        let updatedWaypointID: String?
        if let snap {
          updatedCoordinate = snap.coordinate
          updatedWaypointID = snap.waypointID
          if snap.waypointID != previousWaypointID {
            snapFeedbackGenerator.selectionChanged()
          }
        } else {
          updatedCoordinate = mapView.convert(currentTouchPoint, toCoordinateFrom: mapView)
          updatedWaypointID = nil
        }

        if let style = mapView.style {
          lastAimingCoordinate = updatedCoordinate
          MapStyleController.updateTargetAimingCrosshair(
            coordinate: updatedCoordinate,
            in: style
          )
        }
        parent.viewModel.calloutViewModel.updateAimingPreview(at: updatedCoordinate, waypointID: updatedWaypointID)

      case .ended:
        isLongPressActive = false
        longPressBeganPoint = nil
        if let currentAimingCoordinate = parent.viewModel.calloutViewModel.aimingCoordinate {
          let resolvedCoordinate: CLLocationCoordinate2D
          let resolvedWaypointID: String?

          // Preserve initial Glove Mode touch-target lock if the user released without dragging,
          // since minTouchTarget/2 (33pt) intentionally exceeds the magnetic detach radius (30pt).
          if !hasDraggedDuringLongPress, let lockedID = parent.viewModel.calloutViewModel.targetWaypointID {
            resolvedCoordinate = currentAimingCoordinate
            resolvedWaypointID = lockedID
          } else if let snap = evaluateWaypointSnap(
            at: touchPoint,
            in: mapView,
            currentlySnappedID: parent.viewModel.calloutViewModel.targetWaypointID
          ) {
            resolvedCoordinate = snap.coordinate
            resolvedWaypointID = snap.waypointID
          } else {
            resolvedCoordinate = mapView.convert(touchPoint, toCoordinateFrom: mapView)
            resolvedWaypointID = nil
          }

          if let style = mapView.style {
            lastAimingCoordinate = resolvedCoordinate
            MapStyleController.updateTargetAimingCrosshair(
              coordinate: resolvedCoordinate,
              in: style
            )
          }

          let targetScreenPoint = CGPoint(
            x: mapView.bounds.midX,
            y: mapView.bounds.height * AppConstants.Map.aimingCrosshairYFraction
          )
          let resolvedScreenPoint = mapView.convert(resolvedCoordinate, toPointTo: mapView)
          let isNearCenter = hypot(
            resolvedScreenPoint.x - targetScreenPoint.x,
            resolvedScreenPoint.y - targetScreenPoint.y
          ) < 1.0

          if !isNearCenter {
            // 1. Center the map with the MapLibre crosshair so resolvedCoordinate lands at targetScreenPoint
            parent.viewModel.calloutViewModel.beginAiming(
              at: resolvedCoordinate,
              waypointID: resolvedWaypointID,
              needsCentering: true
            )
            let newCenterCoordinate = centerCoordinateToPosition(resolvedCoordinate, at: targetScreenPoint, in: mapView)
            mapView.setCenter(newCenterCoordinate, animated: true)
          } else {
            // Already at target screen point:
            // Trigger SwiftUI crosshair opacity = 1.0; MapLibreView.updateUIView will hide the MapLibre
            // crosshair layer in the exact same SwiftUI render transaction.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
              parent.viewModel.calloutViewModel.beginAiming(
                at: resolvedCoordinate,
                waypointID: resolvedWaypointID,
                needsCentering: false
              )
            }
          }
        }

      case .cancelled, .failed:
        isLongPressActive = false
        hasDraggedDuringLongPress = false
        longPressBeganPoint = nil
        if parent.viewModel.calloutViewModel.aimingCoordinate != nil {
          if let style = mapView.style {
            lastAimingCoordinate = nil
            MapStyleController.updateTargetAimingCrosshair(
              coordinate: nil,
              in: style
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

    /// Returns the nominal screen position of the aiming crosshair (40% from top),
    /// or `nil` if the map view has not yet been laid out with non-zero bounds.
    func reticleScreenPoint(in mapView: MLNMapView) -> CGPoint? {
      guard mapView.bounds.width > 0, mapView.bounds.height > 0 else {
        return nil
      }
      return CGPoint(
        x: mapView.bounds.midX,
        y: mapView.bounds.height * AppConstants.Map.aimingCrosshairYFraction
      )
    }

    /// Returns the geographic coordinate currently under the aiming crosshair (40% from top),
    /// or `nil` if the map view has not yet been laid out with non-zero bounds.
    func reticleCoordinate(in mapView: MLNMapView) -> CLLocationCoordinate2D? {
      guard let aimingPoint = reticleScreenPoint(in: mapView) else {
        return nil
      }
      return mapView.convert(aimingPoint, toCoordinateFrom: mapView)
    }

    private func isCoordinateNearVisibleBounds(
      _ coordinate: CLLocationCoordinate2D,
      bounds: MLNCoordinateBounds
    ) -> Bool {
      let latSpan = max(bounds.ne.latitude - bounds.sw.latitude, 0.0)
      let latMargin = latSpan * 0.1
      guard coordinate.latitude >= bounds.sw.latitude - latMargin &&
            coordinate.latitude <= bounds.ne.latitude + latMargin else {
        return false
      }

      if bounds.sw.longitude <= bounds.ne.longitude {
        let lonSpan = bounds.ne.longitude - bounds.sw.longitude
        let lonMargin = lonSpan * 0.1
        return coordinate.longitude >= bounds.sw.longitude - lonMargin &&
               coordinate.longitude <= bounds.ne.longitude + lonMargin
      } else {
        // Viewport crosses the antimeridian: accept either side
        return coordinate.longitude >= bounds.sw.longitude ||
               coordinate.longitude <= bounds.ne.longitude
      }
    }

    private func waypointSnapCandidates(in mapView: MLNMapView) -> [WaypointSnapCandidate] {
      let draftID = parent.viewModel.draftWaypointID
      let visibleBounds = mapView.visibleCoordinateBounds
      var candidates: [WaypointSnapCandidate] = []

      for wp in parent.viewModel.visibleWaypointVisualStates where !wp.isDraft && wp.id != draftID {
        guard isCoordinateNearVisibleBounds(wp.coordinate, bounds: visibleBounds) else { continue }
        candidates.append(
          WaypointSnapCandidate(
            id: wp.id,
            coordinate: wp.coordinate,
            screenPoint: mapView.convert(wp.coordinate, toPointTo: mapView)
          )
        )
      }

      if let goTo = parent.viewModel.goToWaypointVisualState,
         !goTo.isDraft,
         goTo.id != draftID,
         isCoordinateNearVisibleBounds(goTo.coordinate, bounds: visibleBounds),
         !candidates.contains(where: { $0.id == goTo.id }) {
        candidates.append(
          WaypointSnapCandidate(
            id: goTo.id,
            coordinate: goTo.coordinate,
            screenPoint: mapView.convert(goTo.coordinate, toPointTo: mapView)
          )
        )
      }

      return candidates
    }

    /// Returns true while the user still has a finger actively driving a MapLibre camera gesture.
    /// When false during a user pan (`isUserPanMoveActive`), the map is coasting on deceleration inertia.
    private func hasActiveMapTouchGesture(in mapView: MLNMapView) -> Bool {
      guard let recognizers = mapView.gestureRecognizers else { return false }
      return recognizers.contains { recognizer in
        guard recognizer != pinPanGesture else { return false }
        return recognizer.state == .began || recognizer.state == .changed
      }
    }

    private var magneticDetachRadius: CGFloat {
      let attachRadius = parent.marineTheme.isGloveMode
        ? AppConstants.Map.waypointMagneticSnapGloveRadius
        : AppConstants.Map.waypointMagneticSnapRadius
      return attachRadius + AppConstants.Map.waypointMagneticDetachHysteresis
    }

    /// Evaluates whether an already-locked waypoint remains within its detach radius during a zoom
    /// gesture without ever acquiring a new neighboring waypoint.
    private func evaluateLockedWaypointRetention(
      at reticlePoint: CGPoint,
      in mapView: MLNMapView,
      waypointID: String,
      coordinate: CLLocationCoordinate2D
    ) -> WaypointSnapResult? {
      let wpPoint = mapView.convert(coordinate, toPointTo: mapView)
      let offset = CGSize(width: wpPoint.x - reticlePoint.x, height: wpPoint.y - reticlePoint.y)
      guard hypot(offset.width, offset.height) <= magneticDetachRadius else { return nil }
      return WaypointSnapResult(waypointID: waypointID, coordinate: coordinate, visualOffset: offset)
    }

    private func evaluateWaypointSnap(
      at point: CGPoint,
      in mapView: MLNMapView,
      currentlySnappedID: String?
    ) -> WaypointSnapResult? {
      let attachRadius = parent.marineTheme.isGloveMode
        ? AppConstants.Map.waypointMagneticSnapGloveRadius
        : AppConstants.Map.waypointMagneticSnapRadius
      return WaypointMagneticSnap.evaluate(
        reticlePoint: point,
        candidates: waypointSnapCandidates(in: mapView),
        currentlySnappedID: currentlySnappedID,
        attachRadius: attachRadius,
        detachHysteresis: AppConstants.Map.waypointMagneticDetachHysteresis
      )
    }

    func setupSubscription(for mapView: MLNMapView) {
      // Connect ensureVisible callback from MeasureToolViewModel
      parent.viewModel.measureToolViewModel.onEnsureVisibleRequested = { [weak self, weak mapView] sheetHeight in
        guard let self = self, let mapView = mapView else { return }
        // Never move the camera while the user is actively touching or dragging on the map!
        guard !self.isUserActivelyInteractingWithPins else { return }
        self.ensureMeasurePinsVisible(in: mapView, sheetHeight: sheetHeight)
      }

      streamTask?.cancel()
      streamTask = Task { @MainActor [weak self, weak mapView] in
        guard let stream = self?.parent.viewModel.cameraMoveStream else { return }
        for await event in stream {
          guard !Task.isCancelled, let self, let mapView else { break }
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

      // Live update reticle magnetic pull (120fps) and target coordinate (throttled ~30Hz on empty water)
      if parent.viewModel.calloutViewModel.isCalloutVisible &&
         !parent.viewModel.measureToolViewModel.isActive &&
         !parent.viewModel.calloutViewModel.isCentering &&
         parent.viewModel.calloutViewModel.aimingCoordinate == nil,
         let reticlePoint = reticleScreenPoint(in: mapView) {
        let calloutVM = parent.viewModel.calloutViewModel

        // During programmatic magnetic recentering, track only the locked waypoint's shrinking visual offset
        // so intermediate frames cannot jump to a neighboring waypoint or retrigger haptics.
        if isMagneticRecentering,
           calloutVM.targetWaypointID != nil,
           let lockedCoord = calloutVM.targetCoordinate {
          let lockedPoint = mapView.convert(lockedCoord, toPointTo: mapView)
          let shrinkingOffset = CGSize(
            width: lockedPoint.x - reticlePoint.x,
            height: lockedPoint.y - reticlePoint.y
          )
          calloutVM.updateReticleVisualOffset(shrinkingOffset)
        } else if isZoomMoveActive {
          // Never acquire a new waypoint during zoom (e.g. zooming out shrinking screen distance to a neighbor),
          // while keeping open-water coordinates or an already-locked waypoint synchronized if the pinch pans/rotates.
          let now = CACurrentMediaTime()
          if let lockedID = calloutVM.targetWaypointID, let lockedCoord = calloutVM.targetCoordinate {
            if let retained = evaluateLockedWaypointRetention(
              at: reticlePoint,
              in: mapView,
              waypointID: lockedID,
              coordinate: lockedCoord
            ) {
              calloutVM.updateReticleVisualOffset(retained.visualOffset)
            } else {
              lastCalloutTargetUpdateTime = now
              let targetCoord = mapView.convert(reticlePoint, toCoordinateFrom: mapView)
              calloutVM.updateTarget(coordinate: targetCoord, waypointID: nil, visualOffset: .zero)
            }
          } else if now - lastCalloutTargetUpdateTime >= 0.032 {
            lastCalloutTargetUpdateTime = now
            let targetCoord = mapView.convert(reticlePoint, toCoordinateFrom: mapView)
            calloutVM.updateTarget(coordinate: targetCoord, waypointID: nil, visualOffset: .zero)
          }
        } else {
          let previousWaypointID = calloutVM.targetWaypointID
          let snap = evaluateWaypointSnap(
            at: reticlePoint,
            in: mapView,
            currentlySnappedID: previousWaypointID
          )

          let now = CACurrentMediaTime()
          if let snap {
            if snap.waypointID != previousWaypointID {
              snapFeedbackGenerator.selectionChanged()
              lastCalloutTargetUpdateTime = now
              calloutVM.updateTarget(
                coordinate: snap.coordinate,
                waypointID: snap.waypointID,
                visualOffset: snap.visualOffset
              )
            } else {
              calloutVM.updateReticleVisualOffset(snap.visualOffset)
            }

            // Stop pan deceleration inertia once the finger is off screen so the reticle catches
            // a waypoint instead of coasting past it, while never blocking an active finger drag
            // or a short flick meant to leave the waypoint already targeted when the pan began.
            if isUserPanMoveActive &&
               !hasActiveMapTouchGesture(in: mapView) &&
               snap.waypointID != panStartWaypointID {
              let offsetDistance = hypot(snap.visualOffset.width, snap.visualOffset.height)
              if offsetDistance > 1.0 {
                isMagneticRecentering = true
                isUserPanMoveActive = false
                panStartWaypointID = nil
                isStartingMagneticRecenter = true
                defer { isStartingMagneticRecenter = false }
                let newCenterCoordinate = centerCoordinateToPosition(snap.coordinate, at: reticlePoint, in: mapView)
                mapView.setCenter(newCenterCoordinate, animated: true)
              }
            }
          } else if previousWaypointID != nil {
            // Immediately transition sheet from waypoint back to empty water upon detaching
            panStartWaypointID = nil
            lastCalloutTargetUpdateTime = now
            let targetCoord = mapView.convert(reticlePoint, toCoordinateFrom: mapView)
            calloutVM.updateTarget(coordinate: targetCoord, waypointID: nil, visualOffset: .zero)
          } else if now - lastCalloutTargetUpdateTime >= 0.032 {
            lastCalloutTargetUpdateTime = now
            let targetCoord = mapView.convert(reticlePoint, toCoordinateFrom: mapView)
            calloutVM.updateTarget(coordinate: targetCoord, waypointID: nil, visualOffset: .zero)
          }
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

      if let currentSource = parent.viewModel.currentChartSource {
        MapStyleController.updateChartSource(currentSource, in: style, isOverlayEnabled: parent.viewModel.isOpenSeaMapOverlayEnabled)
        lastChartSource = currentSource
      }

      lastOpenSeaMapOverlayEnabled = parent.viewModel.isOpenSeaMapOverlayEnabled
      MapStyleController.updateOpenSeaMapOverlay(isEnabled: parent.viewModel.isOpenSeaMapOverlayEnabled, in: style)

      // Single initialization path: create all vector layers in Z-Index order, then apply theme colors & sprites
      MapStyleController.ensureAllLayers(in: style)
      MapStyleController.applyTheme(parent.marineTheme, in: style)
      lastMarineTheme = parent.marineTheme

      let headingData = parent.viewModel.headingVectorData
      MapStyleController.updateHeadingVector(data: headingData, in: style)
      lastHeadingVectorData = headingData

      let gpsState = parent.viewModel.gpsAccuracyVisualState
      MapStyleController.updateGpsAccuracy(state: gpsState, in: style)
      lastGpsAccuracyVisualState = gpsState

      let vesselState = parent.viewModel.vesselVisualState
      MapStyleController.updateVessel(state: vesselState, in: style)
      lastVesselVisualState = vesselState

      MapStyleController.updateActiveTrack(points: parent.trackRecordingService.trackPoints, in: style)
      lastActiveTrackCount = parent.trackRecordingService.trackPoints.count
      lastActiveTrackTimestamp = parent.trackRecordingService.trackPoints.last?.timestamp

      let savedState = parent.viewModel.savedTrackVisualState
      MapStyleController.updateSavedTrack(state: savedState, in: style)
      lastSavedTrackVisualState = savedState

      let visibleStates = parent.viewModel.visibleWaypointVisualStates
      MapStyleController.updateVisibleWaypoints(states: visibleStates, in: style)
      lastVisibleWaypointVisualStates = visibleStates

      let goToState = parent.viewModel.goToWaypointVisualState
      MapStyleController.updateGoToWaypoint(state: goToState, in: style)
      lastGoToWaypointVisualState = goToState

      let bearingState = parent.viewModel.bearingLineVisualState
      MapStyleController.updateBearingLine(state: bearingState, in: style)
      lastBearingLineVisualState = bearingState

      let measureState = parent.viewModel.measureToolViewModel.state
      let measureActivePin = parent.viewModel.measureToolViewModel.activePin
      MapStyleController.updateMeasureLine(state: measureState, in: style)
      MapStyleController.updateMeasurePins(state: measureState, activePin: measureActivePin, in: style)
      lastMeasureState = measureState
      lastMeasureActivePin = measureActivePin

      let anchorVisualState = parent.viewModel.anchorVisualState
      MapStyleController.updateAnchor(state: anchorVisualState, in: style)
      lastAnchorVisualState = anchorVisualState

      // Offline Mask layer initialization
      let maskState = parent.viewModel.offlineMaskVisualState
      MapStyleController.updateOfflineMask(state: maskState, in: style)
      lastOfflineMaskVisualState = maskState

      // Highlighted offline region preview initialization
      let highlightRegion = parent.viewModel.highlightedOfflineRegion
      MapStyleController.updateOfflineHighlight(region: highlightRegion, in: style)
      lastHighlightedOfflineRegion = highlightRegion

      // Active offline selection zone initialization
      let activeSelection = parent.offlineSelectionViewModel.isSelectionModeActive ? parent.offlineSelectionViewModel.selectedBounds : nil
      MapStyleController.updateOfflineSelection(bounds: activeSelection, in: style)
      lastOfflineSelectionBounds = activeSelection

      let isStale = parent.viewModel.isDataStale
      MapStyleController.updateDataStaleState(isStale: isStale, in: style)
      lastDataStale = isStale

      lastAimingCoordinate = nil


      
      // NOTE: We do not call `mapView.setVisibleCoordinateBounds` here.
      // In SwiftUI, `didFinishLoading` can fire before the map view has a non-zero frame.
      // Calling coordinate bounds on a `.zero` frame corrupts the MapLibre camera (`NaN` zoom level).
      // Loading `blank-style.json` (which has no center/zoom) resets the MapLibre camera to (0,0),
      // so we must restore the camera whenever a style finishes loading:
      // - On a style reload (e.g., `NetworkDidReconnect`), restore the exact pre-reload camera.
      // - On initial boot, apply the ViewModel's starting camera once.
      if let savedCamera = pendingReloadCamera {
        pendingReloadCamera = nil
        mapView.setCenter(savedCamera.center, zoomLevel: savedCamera.zoomLevel, direction: savedCamera.direction, animated: false)
      } else if !hasAppliedInitialCamera {
        hasAppliedInitialCamera = true
        mapView.setCenter(parent.viewModel.centerCoordinate, zoomLevel: parent.viewModel.zoomLevel, direction: parent.viewModel.chartDirection.converted(to: .degrees).value, animated: false)
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
    
    private func isZoomReason(_ reason: MLNCameraChangeReason) -> Bool {
      reason.contains(.gesturePinch) ||
      reason.contains(.gestureZoomIn) ||
      reason.contains(.gestureZoomOut) ||
      reason.contains(.gestureOneFingerZoom)
    }

    private func shouldBreakTracking(for reason: MLNCameraChangeReason) -> Bool {
      let isZooming = isZoomReason(reason)
      let isPanningOrRotating = reason.contains(.gesturePan) || reason.contains(.gestureRotate)
      
      // Break tracking ONLY if panning/rotating and NOT zooming
      return isPanningOrRotating && !isZooming
    }
    
    func mapView(_ mapView: MLNMapView, regionWillChangeWith reason: MLNCameraChangeReason, animated: Bool) {
      if !reason.contains(.programmatic) {
        self.parent.viewModel.isMapMoving = true
        self.isMagneticRecentering = false
        let isZoom = isZoomReason(reason)
        let isUserPan = reason.contains(.gesturePan) && !isZoom
        self.isZoomMoveActive = isZoom
        self.isUserPanMoveActive = isUserPan
        self.panStartWaypointID = isUserPan ? self.parent.viewModel.calloutViewModel.targetWaypointID : nil
        self.snapFeedbackGenerator.prepare()
        if self.parent.viewModel.calloutViewModel.isCalloutVisible &&
           !self.parent.viewModel.measureToolViewModel.isActive {
          if self.parent.viewModel.calloutViewModel.isCentering,
             let reticlePoint = reticleScreenPoint(in: mapView) {
            let snap = evaluateWaypointSnap(
              at: reticlePoint,
              in: mapView,
              currentlySnappedID: self.parent.viewModel.calloutViewModel.targetWaypointID
            )
            let resolvedCoord = snap?.coordinate ?? mapView.convert(reticlePoint, toCoordinateFrom: mapView)
            // Trigger SwiftUI crosshair opacity = 1.0; MapLibreView.updateUIView will hide the MapLibre
            // crosshair layer in the exact same SwiftUI render transaction.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
              self.parent.viewModel.calloutViewModel.interruptCentering(
                at: resolvedCoord,
                waypointID: snap?.waypointID,
                visualOffset: snap?.visualOffset ?? .zero
              )
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
      } else {
        self.isZoomMoveActive = false
        self.isUserPanMoveActive = false
        self.panStartWaypointID = nil
      }
    }
    
    // MARK: - Offline Selection Corner Drag Gestures

    /// Tests whether a screen touch point is within the touch hit target of one of the 4 selection corners.
    func hitTestSelectionCorner(at point: CGPoint, in mapView: MLNMapView) -> ActiveSelectionCorner? {
      guard parent.offlineSelectionViewModel.isSelectionModeActive,
            let bounds = parent.offlineSelectionViewModel.selectedBounds else {
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
      guard parent.offlineSelectionViewModel.isSelectionModeActive else {
        activeDraggedSelectionCorner = nil
        activeSelectionDragInitialBounds = nil
        activeSelectionDragCurrentBounds = nil
        return
      }

      let touchPoint = sender.location(in: mapView)

      switch sender.state {
      case .began:
        guard let corner = hitTestSelectionCorner(at: touchPoint, in: mapView),
              let initialBounds = parent.offlineSelectionViewModel.selectedBounds else { return }
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
            in: style
          )
        }

      case .ended:
        if let corner = activeDraggedSelectionCorner,
           let initialBounds = activeSelectionDragInitialBounds {
          let coord = mapView.convert(touchPoint, toCoordinateFrom: mapView)
          let finalBounds = computeUpdatedBounds(from: initialBounds, dragging: corner, to: coord)
          parent.offlineSelectionViewModel.updateBoundingBox(finalBounds)
        } else if let finalBounds = activeSelectionDragCurrentBounds {
          parent.offlineSelectionViewModel.updateBoundingBox(finalBounds)
        }
        activeDraggedSelectionCorner = nil
        activeSelectionDragInitialBounds = nil
        activeSelectionDragCurrentBounds = nil

      case .cancelled, .failed:
        // Restore MapLibre visual layers to the uncommitted model bounds
        if let style = mapView.style {
          MapStyleController.updateOfflineSelection(
            bounds: parent.offlineSelectionViewModel.selectedBounds,
            in: style
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
      let wasZoomMove = self.isZoomMoveActive || isZoomReason(reason)
      self.parent.viewModel.isMapMoving = false
      self.isZoomMoveActive = false
      self.isUserPanMoveActive = false
      self.panStartWaypointID = nil

      // Synchronously hand off from MapLibre crosshair to SwiftUI crosshair on the exact frame camera movement stops,
      // or gently recenter onto a magnetically snapped waypoint once manual panning settles.
      // Skip only when this callback is a synchronous re-entrant cancellation from starting a magnetic recenter.
      if !self.isStartingMagneticRecenter &&
         !self.isLongPressActive &&
         self.parent.viewModel.calloutViewModel.isCalloutVisible &&
         !self.parent.viewModel.measureToolViewModel.isActive,
         let reticlePoint = reticleScreenPoint(in: mapView) {
        let calloutVM = self.parent.viewModel.calloutViewModel

        if calloutVM.isCentering {
          let resolvedCoord: CLLocationCoordinate2D
          let resolvedWaypointID: String?
          if let lockedID = calloutVM.targetWaypointID, let lockedCoord = calloutVM.targetCoordinate {
            resolvedCoord = lockedCoord
            resolvedWaypointID = lockedID
          } else if let snap = evaluateWaypointSnap(
            at: reticlePoint,
            in: mapView,
            currentlySnappedID: calloutVM.targetWaypointID
          ) {
            resolvedCoord = snap.coordinate
            resolvedWaypointID = snap.waypointID
          } else {
            resolvedCoord = mapView.convert(reticlePoint, toCoordinateFrom: mapView)
            resolvedWaypointID = nil
          }

          var transaction = Transaction()
          transaction.disablesAnimations = true
          withTransaction(transaction) {
            calloutVM.completeCentering(at: resolvedCoord, waypointID: resolvedWaypointID)
          }
        } else {
          let snap: WaypointSnapResult?
          if wasZoomMove {
            // During zoom, never acquire a new waypoint; only retain an already-locked one if still within detach radius.
            if let lockedID = calloutVM.targetWaypointID, let lockedCoord = calloutVM.targetCoordinate {
              snap = evaluateLockedWaypointRetention(
                at: reticlePoint,
                in: mapView,
                waypointID: lockedID,
                coordinate: lockedCoord
              )
            } else {
              snap = nil
            }
          } else {
            snap = evaluateWaypointSnap(
              at: reticlePoint,
              in: mapView,
              currentlySnappedID: calloutVM.targetWaypointID
            )
          }

          if let snap {
            let offsetDistance = hypot(snap.visualOffset.width, snap.visualOffset.height)
            if offsetDistance > 1.0 && !self.isMagneticRecentering {
              self.isMagneticRecentering = true
              calloutVM.updateTarget(
                coordinate: snap.coordinate,
                waypointID: snap.waypointID,
                visualOffset: snap.visualOffset
              )
              let newCenterCoordinate = centerCoordinateToPosition(snap.coordinate, at: reticlePoint, in: mapView)
              mapView.setCenter(newCenterCoordinate, animated: true)
            } else {
              self.isMagneticRecentering = false
              calloutVM.updateTarget(
                coordinate: snap.coordinate,
                waypointID: snap.waypointID,
                visualOffset: .zero
              )
            }
          } else {
            self.isMagneticRecentering = false
            let aimingCoord = mapView.convert(reticlePoint, toCoordinateFrom: mapView)
            calloutVM.updateTarget(coordinate: aimingCoord, waypointID: nil, visualOffset: .zero)
          }
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

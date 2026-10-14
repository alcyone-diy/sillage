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
        MapStyleController.ensureTargetPinImagesExist(in: style, theme: marineTheme)
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

      // Target pin feature update (contextual map target selection)
      let targetPinCoord = viewModel.calloutViewModel.targetCoordinate
      let isTargetPinVisible = viewModel.calloutViewModel.isCalloutVisible && viewModel.calloutViewModel.targetWaypointID == nil && !viewModel.measureToolViewModel.isActive
      let isTargetPinDragging = viewModel.calloutViewModel.isDraggingPin
      if targetPinCoord != context.coordinator.lastTargetPinCoordinate ||
         isTargetPinVisible != context.coordinator.lastTargetPinVisible ||
         isTargetPinDragging != context.coordinator.lastTargetPinDragging {
        MapStyleController.updateTargetPin(
          coordinate: targetPinCoord,
          isDragging: isTargetPinDragging,
          isVisible: isTargetPinVisible,
          in: style,
          theme: marineTheme
        )
        context.coordinator.lastTargetPinCoordinate = targetPinCoord
        context.coordinator.lastTargetPinVisible = isTargetPinVisible
        context.coordinator.lastTargetPinDragging = isTargetPinDragging
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
    private var isDraggingCalloutPin: Bool = false
    private var isLongPressActive: Bool = false
    private var hasMovedCalloutPin: Bool = false
    private var calloutPinDragOffset: CGPoint = .zero
    private var lastPanUpdateTime: CFTimeInterval = 0
    private static let pinPanThrottleInterval: CFTimeInterval = 0.016
    var lastTargetPinCoordinate: CLLocationCoordinate2D?
    var lastTargetPinVisible: Bool = false
    var lastTargetPinDragging: Bool = false
    var lastThemeHash: Int?
    var lastAnchorVisualState: AnchorVisualState?
    var lastOfflineMaskVisualState: OfflineMaskVisualState?
    var lastHighlightedOfflineRegion: HighlightedOfflineRegion?
    
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

    /// Tests whether a screen touch point is within the touch hit target of the contextual callout target pin.
    func hitTestCalloutPin(at point: CGPoint, in mapView: MLNMapView) -> Bool {
      guard parent.viewModel.calloutViewModel.isCalloutVisible,
            parent.viewModel.calloutViewModel.targetWaypointID == nil,
            !parent.viewModel.measureToolViewModel.isActive,
            let targetCoord = parent.viewModel.calloutViewModel.targetCoordinate else { return false }

      let tipPoint = mapView.convert(targetCoord, toPointTo: mapView)
      let hitRadius: CGFloat = parent.marineTheme.isGloveMode ? 48.0 : 36.0
      return distanceToPin(touchPoint: point, tipPoint: tipPoint) <= hitRadius
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      if gestureRecognizer == pinPanGesture {
        guard !isLongPressActive else { return false }
        guard let mapView = self.mapView else { return false }
        let touchPoint = gestureRecognizer.location(in: mapView)
        if parent.viewModel.measureToolViewModel.isActive {
          return hitTestMeasurePin(at: touchPoint, in: mapView) != nil
        }
        if parent.viewModel.calloutViewModel.isCalloutVisible && parent.viewModel.calloutViewModel.targetWaypointID == nil {
          return hitTestCalloutPin(at: touchPoint, in: mapView)
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

      // Route first according to any already engaged drag session before testing tool modes
      if activeDraggedPin != nil {
        handleMeasurePinPan(sender, in: mapView)
      } else if isDraggingCalloutPin {
        handleCalloutPinPan(sender, in: mapView)
      } else if parent.viewModel.measureToolViewModel.isActive {
        handleMeasurePinPan(sender, in: mapView)
      } else if parent.viewModel.calloutViewModel.isCalloutVisible && parent.viewModel.calloutViewModel.targetWaypointID == nil {
        handleCalloutPinPan(sender, in: mapView)
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

        let tipPoint = CGPoint(
          x: touchPoint.x,
          y: touchPoint.y - MarineMapPinShape.needleToHeadCenterOffset
        )
        let coord = mapView.convert(tipPoint, toCoordinateFrom: mapView)
        switch pin {
        case .start:
          parent.viewModel.measureToolViewModel.updateStart(to: coord)
        case .end:
          parent.viewModel.measureToolViewModel.updateEnd(to: coord)
        }
        lastPanUpdateTime = CACurrentMediaTime()

      case .changed:
        guard let pin = activeDraggedPin else { return }
        guard parent.viewModel.measureToolViewModel.isActive else {
          activeDraggedPin = nil
          parent.viewModel.measureToolViewModel.isDraggingPin = false
          return
        }

        let now = CACurrentMediaTime()
        guard now - lastPanUpdateTime >= Self.pinPanThrottleInterval else { return }
        lastPanUpdateTime = now

        let tipPoint = CGPoint(
          x: touchPoint.x,
          y: touchPoint.y - MarineMapPinShape.needleToHeadCenterOffset
        )
        let coord = mapView.convert(tipPoint, toCoordinateFrom: mapView)
        switch pin {
        case .start:
          parent.viewModel.measureToolViewModel.updateStart(to: coord)
        case .end:
          parent.viewModel.measureToolViewModel.updateEnd(to: coord)
        }

      case .ended:
        if let pin = activeDraggedPin {
          let tipPoint = CGPoint(
            x: touchPoint.x,
            y: touchPoint.y - MarineMapPinShape.needleToHeadCenterOffset
          )
          let coord = mapView.convert(tipPoint, toCoordinateFrom: mapView)
          switch pin {
          case .start:
            parent.viewModel.measureToolViewModel.updateStart(to: coord)
          case .end:
            parent.viewModel.measureToolViewModel.updateEnd(to: coord)
          }
        }
        activeDraggedPin = nil
        parent.viewModel.measureToolViewModel.isDraggingPin = false

      case .cancelled, .failed:
        activeDraggedPin = nil
        parent.viewModel.measureToolViewModel.isDraggingPin = false

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

    private func handleCalloutPinPan(_ sender: UIPanGestureRecognizer, in mapView: MLNMapView) {
      let touchPoint = sender.location(in: mapView)

      switch sender.state {
      case .began:
        guard hitTestCalloutPin(at: touchPoint, in: mapView),
              let targetCoord = parent.viewModel.calloutViewModel.targetCoordinate else { return }
        isDraggingCalloutPin = true
        hasMovedCalloutPin = false
        parent.viewModel.calloutViewModel.beginDragging()
        parent.viewModel.chartInteractedByUser()

        let tipPoint = mapView.convert(targetCoord, toPointTo: mapView)
        calloutPinDragOffset = CGPoint(
          x: touchPoint.x - tipPoint.x,
          y: touchPoint.y - tipPoint.y
        )
        lastPanUpdateTime = CACurrentMediaTime()

        // Immediate visual feedback on MapLibre style
        if let style = mapView.style {
          MapStyleController.updateTargetPin(
            coordinate: targetCoord,
            isDragging: true,
            isVisible: true,
            in: style,
            theme: parent.marineTheme
          )
          lastTargetPinDragging = true
        }

      case .changed:
        updateCalloutPinDrag(at: touchPoint, in: mapView)

      case .ended:
        endCalloutPinDrag(at: touchPoint, in: mapView)

      case .cancelled, .failed:
        cancelCalloutPinDrag(in: mapView)

      default:
        break
      }
    }

    private func updateCalloutPinDrag(at touchPoint: CGPoint, in mapView: MLNMapView) {
      guard isDraggingCalloutPin else { return }
      // Ensure callout target mode is still valid; otherwise abort and clean up drag state
      guard parent.viewModel.calloutViewModel.isCalloutVisible,
            parent.viewModel.calloutViewModel.targetWaypointID == nil else {
        cancelCalloutPinDrag(in: mapView)
        return
      }

      hasMovedCalloutPin = true

      let now = CACurrentMediaTime()
      guard now - lastPanUpdateTime >= Self.pinPanThrottleInterval else { return }
      lastPanUpdateTime = now

      let rawTip = CGPoint(
        x: touchPoint.x - calloutPinDragOffset.x,
        y: touchPoint.y - calloutPinDragOffset.y
      )
      let clampedTip = clampPointToMapBounds(rawTip, in: mapView)
      let coord = mapView.convert(clampedTip, toCoordinateFrom: mapView)

      // Atomic update of both GPU layer and ViewModel at 60Hz lockstep
      if let style = mapView.style {
        MapStyleController.updateTargetPin(
          coordinate: coord,
          isDragging: true,
          isVisible: true,
          in: style,
          theme: parent.marineTheme
        )
        lastTargetPinCoordinate = coord
        lastTargetPinDragging = true
      }

      parent.viewModel.calloutViewModel.updateTarget(coordinate: coord)
    }

    private func endCalloutPinDrag(at touchPoint: CGPoint, in mapView: MLNMapView) {
      guard isDraggingCalloutPin else { return }
      let moved = hasMovedCalloutPin
      let dragOffset = calloutPinDragOffset
      isDraggingCalloutPin = false
      isLongPressActive = false
      hasMovedCalloutPin = false
      calloutPinDragOffset = .zero
      parent.viewModel.calloutViewModel.endDragging()

      if parent.viewModel.calloutViewModel.isCalloutVisible && parent.viewModel.calloutViewModel.targetWaypointID == nil {
        let finalCoord: CLLocationCoordinate2D
        if moved {
          let rawTip = CGPoint(
            x: touchPoint.x - dragOffset.x,
            y: touchPoint.y - dragOffset.y
          )
          let clampedTip = clampPointToMapBounds(rawTip, in: mapView)
          finalCoord = mapView.convert(clampedTip, toCoordinateFrom: mapView)
          parent.viewModel.calloutViewModel.updateTarget(coordinate: finalCoord)
        } else if let existingCoord = parent.viewModel.calloutViewModel.targetCoordinate {
          finalCoord = existingCoord
        } else {
          cancelCalloutPinDrag(in: mapView)
          return
        }

        if let style = mapView.style {
          MapStyleController.updateTargetPin(
            coordinate: finalCoord,
            isDragging: false,
            isVisible: true,
            in: style,
            theme: parent.marineTheme
          )
          lastTargetPinCoordinate = finalCoord
          lastTargetPinDragging = false
        }

        let currentPoint = mapView.convert(finalCoord, toPointTo: mapView)
        ensureTargetVisible(at: currentPoint, in: mapView, sheetHeight: parent.viewModel.calloutViewModel.lastSheetHeight)
        return
      }

      cancelCalloutPinDrag(in: mapView)
    }

    private func cancelCalloutPinDrag(in mapView: MLNMapView) {
      guard isDraggingCalloutPin else { return }
      isDraggingCalloutPin = false
      isLongPressActive = false
      hasMovedCalloutPin = false
      calloutPinDragOffset = .zero
      parent.viewModel.calloutViewModel.endDragging()
      if let style = mapView.style {
        MapStyleController.updateTargetPin(
          coordinate: parent.viewModel.calloutViewModel.targetCoordinate,
          isDragging: false,
          isVisible: parent.viewModel.calloutViewModel.isCalloutVisible && parent.viewModel.calloutViewModel.targetWaypointID == nil,
          in: style,
          theme: parent.marineTheme
        )
        lastTargetPinVisible = parent.viewModel.calloutViewModel.isCalloutVisible && parent.viewModel.calloutViewModel.targetWaypointID == nil
        lastTargetPinDragging = false
      }

      if parent.viewModel.calloutViewModel.isCalloutVisible,
         let targetCoord = parent.viewModel.calloutViewModel.targetCoordinate {
        let currentPoint = mapView.convert(targetCoord, toPointTo: mapView)
        ensureTargetVisible(at: currentPoint, in: mapView, sheetHeight: parent.viewModel.calloutViewModel.lastSheetHeight)
      }
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
      if gestureRecognizer == pinPanGesture || otherGestureRecognizer == pinPanGesture {
        return false
      }
      if gestureRecognizer is UILongPressGestureRecognizer || otherGestureRecognizer is UILongPressGestureRecognizer {
        return false
      }
      if isLongPressActive || isDraggingCalloutPin {
        return false
      }
      return true
    }
    
    @objc func handleLongPress(_ sender: UILongPressGestureRecognizer) {
      if sender.state == .ended || sender.state == .cancelled || sender.state == .failed {
        // Guarantee isLongPressActive and any abandoned drag session are reset, even if guards return early
        if isDraggingCalloutPin && (parent.viewModel.measureToolViewModel.isActive || parent.viewModel.isActionConfirmationCardActive) {
          if let mapView = sender.view as? MLNMapView {
            cancelCalloutPinDrag(in: mapView)
          } else {
            isDraggingCalloutPin = false
            hasMovedCalloutPin = false
            calloutPinDragOffset = .zero
            parent.viewModel.calloutViewModel.endDragging()
          }
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
        let coord = mapView.convert(tipPoint, toCoordinateFrom: mapView)

        switch sender.state {
        case .began:
          parent.viewModel.measureToolViewModel.isDraggingPin = true
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

        case .cancelled, .failed:
          parent.viewModel.measureToolViewModel.isDraggingPin = false

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
        // Disable active tracking mode during target inspection
        parent.viewModel.chartInteractedByUser()

        let touchRect = CGRect(x: touchPoint.x - 22, y: touchPoint.y - 22, width: 44, height: 44)
        let features = mapView.visibleFeatures(in: touchRect, styleLayerIdentifiers: [MapLayerIdentifier.goToWaypoint.rawValue, MapLayerIdentifier.visibleWaypoints.rawValue])

        if let feature = features.first as? MLNPointFeature,
           let id = feature.attributes[MapFeatureKey.id.rawValue] as? String {
          // Tapped on an existing waypoint: present callout for the waypoint
          // Note: Camera adjustment is deferred until finger release (.ended)
          let targetCoordinate = feature.coordinate
          parent.viewModel.calloutViewModel.presentCallout(coordinate: targetCoordinate, waypointID: id)

          // Immediately hide any previously placed TargetPin from the MapLibre style
          if let style = mapView.style {
            MapStyleController.updateTargetPin(
              coordinate: nil,
              isDragging: false,
              isVisible: false,
              in: style,
              theme: parent.marineTheme
            )
            lastTargetPinCoordinate = nil
            lastTargetPinVisible = false
            lastTargetPinDragging = false
          }
        } else {
          // Long press on map to create/drag target pin:
          // The bottom circular badge must appear directly under the user's finger.
          // Therefore, the needle tip is positioned offset upwards by needleToHeadCenterOffset.
          let rawTip = CGPoint(
            x: touchPoint.x,
            y: touchPoint.y - MarineMapPinShape.needleToHeadCenterOffset
          )
          let clampedTip = clampPointToMapBounds(rawTip, in: mapView)
          let targetCoordinate = mapView.convert(clampedTip, toCoordinateFrom: mapView)

          calloutPinDragOffset = CGPoint(
            x: touchPoint.x - clampedTip.x,
            y: touchPoint.y - clampedTip.y
          )
          isDraggingCalloutPin = true
          hasMovedCalloutPin = false
          lastPanUpdateTime = CACurrentMediaTime()

          parent.viewModel.calloutViewModel.presentCallout(coordinate: targetCoordinate, waypointID: nil)
          parent.viewModel.calloutViewModel.beginDragging()

          if let style = mapView.style {
            MapStyleController.updateTargetPin(
              coordinate: targetCoordinate,
              isDragging: true,
              isVisible: true,
              in: style,
              theme: parent.marineTheme
            )
            lastTargetPinCoordinate = targetCoordinate
            lastTargetPinVisible = true
            lastTargetPinDragging = true
          }
        }

      case .changed:
        updateCalloutPinDrag(at: touchPoint, in: mapView)

      case .ended:
        if isDraggingCalloutPin {
          endCalloutPinDrag(at: touchPoint, in: mapView)
        } else if parent.viewModel.calloutViewModel.isCalloutVisible,
                  let targetCoord = parent.viewModel.calloutViewModel.targetCoordinate {
          let currentPoint = mapView.convert(targetCoord, toPointTo: mapView)
          ensureTargetVisible(at: currentPoint, in: mapView, sheetHeight: parent.viewModel.calloutViewModel.lastSheetHeight)
        }
        isLongPressActive = false

      case .cancelled, .failed:
        if isDraggingCalloutPin {
          cancelCalloutPinDrag(in: mapView)
        } else if parent.viewModel.calloutViewModel.isCalloutVisible,
                  let targetCoord = parent.viewModel.calloutViewModel.targetCoordinate {
          let currentPoint = mapView.convert(targetCoord, toPointTo: mapView)
          ensureTargetVisible(at: currentPoint, in: mapView, sheetHeight: parent.viewModel.calloutViewModel.lastSheetHeight)
        }
        isLongPressActive = false

      default:
        break
      }
    }
    
    /// Technical Design Choice: Automatic Map Camera Framing for Contextual Callout Target Pin
    /// Ensures the selected target point is never obscured by the bottom sheet or the top telemetry HUD.
    /// If the point is too close to the bottom (under the sheet) or too close to the top (under the HUD),
    /// the map camera smoothly animates to bring the target into comfortable, unobstructed view with full pin clearance.
    private func ensureTargetVisible(at point: CGPoint, in mapView: MLNMapView, sheetHeight: CGFloat = 220) {
      let isWaypointTarget = parent.viewModel.calloutViewModel.targetWaypointID != nil
      let targetBottomOffset: CGFloat = isWaypointTarget
        ? (parent.marineTheme.isGloveMode ? 20.0 : 16.0)
        : MarinePinGraphicsFactory.pinHeight
      let safeBottom = mapView.safeAreaInsets.bottom
      // The required clearance margin between the bottom of the target (pin or waypoint) and the top of the callout dialog
      let marginAboveSheet: CGFloat = 24.0
      let topClearance: CGFloat = max(mapView.safeAreaInsets.top + 80.0, MarineTheme.Metrics.topToolbarClearance)
      
      // The callout dialog occupies the bottom of the screen. Its actual visual height includes content and safe area.
      let effectiveSheetHeight = sheetHeight > 0 ? sheetHeight : (parent.marineTheme.isGloveMode ? 260.0 : 220.0)
      let dialogTopY = mapView.bounds.height - effectiveSheetHeight - safeBottom

      // Screen Y coordinate of the bottom of the target visual element
      let targetBottomY = point.y + targetBottomOffset

      var deltaY: CGFloat = 0.0

      // If the bottom of the target is less than marginAboveSheet pixels above the dialog top
      // (or under the dialog), shift the map upwards so the target sits exactly marginAboveSheet pixels above the dialog.
      let targetPinBottomY = dialogTopY - marginAboveSheet
      if targetBottomY > targetPinBottomY {
        deltaY = targetBottomY - targetPinBottomY
      } else if point.y < topClearance {
        deltaY = point.y - topClearance
      }
      
      if abs(deltaY) > 1.0 {
        let currentCenterPoint = mapView.convert(mapView.centerCoordinate, toPointTo: mapView)
        let newCenterPoint = CGPoint(x: currentCenterPoint.x, y: currentCenterPoint.y + deltaY)
        let newCenterCoordinate = mapView.convert(newCenterPoint, toCoordinateFrom: mapView)
        
        mapView.setCenter(newCenterCoordinate, animated: true)
      }
    }
    
    func setupSubscription(for mapView: MLNMapView) {
      // Connect ensureVisible callback from MapCalloutViewModel
      parent.viewModel.calloutViewModel.onEnsureVisibleRequested = { [weak self, weak mapView] sheetHeight in
        guard let self = self, let mapView = mapView else { return }
        // Never move the camera while the user is actively touching or dragging on the map!
        guard !self.isDraggingCalloutPin && !self.isLongPressActive else { return }
        guard self.parent.viewModel.calloutViewModel.isCalloutVisible,
              let targetCoord = self.parent.viewModel.calloutViewModel.targetCoordinate else { return }
        let currentPoint = mapView.convert(targetCoord, toPointTo: mapView)
        self.ensureTargetVisible(at: currentPoint, in: mapView, sheetHeight: sheetHeight)
      }

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
      self.parent.viewModel.throttledUpdateCenterCoordinate(mapView.centerCoordinate)
      self.parent.viewModel.updateOfflineRegionScreenPositions(
        projection: { mapView.convert($0, toPointTo: mapView) },
        bounds: mapView.bounds
      )
      
      // Technical Design Choice: Dynamic Tracking Break Evaluation
      // During active manual panning in tracking mode (.northUp or .courseUp), measure the physical screen displacement
      // of the initial anchor coordinate. As soon as displacement exceeds the threshold (scaled for Glove Mode),
      // transition immediately to .free mode so the user experiences smooth, uninterrupted chart panning.
      if parent.viewModel.trackingMode != .free,
         !parent.viewModel.anchorViewModel.isAdjustingAnchor,
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
      MapStyleController.ensureTargetPinImagesExist(in: style, theme: parent.marineTheme)
      lastTargetPinCoordinate = nil
      lastTargetPinVisible = false
      lastTargetPinDragging = false
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
      if !reason.contains(.programmatic) {
        self.parent.viewModel.isMapMoving = true
        
        if self.parent.viewModel.trackingMode != .free && !self.parent.viewModel.anchorViewModel.isAdjustingAnchor {
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
    
    // Capture user's chart movements to sync the final camera state and evaluate tracking mode persistence.
    func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason, animated: Bool) {
      self.parent.viewModel.isMapMoving = false
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
        self.parent.viewModel.updateOfflineRegionScreenPositions(
          projection: { mapView.convert($0, toPointTo: mapView) },
          bounds: mapView.bounds
        )
        
        // Technical Design Choice: Centering Restoration vs Tracking Break
        // If the user was in an automated tracking mode:
        // - If movement exceeded the threshold: tracking mode was broken during the gesture (or broken now).
        // - If movement remained within the tolerance margin: restore camera lock on vessel smoothly,
        //   EXCEPT when manual anchor position adjustment is active (`anchorViewModel.isAdjustingAnchor == false`),
        //   preventing the crosshair aiming position from being pulled away (rubber-band bug) during micro-drags.
        if self.parent.viewModel.trackingMode != .free {
          if self.hasExceededTrackingMargin {
            self.parent.viewModel.chartInteractedByUser()
          } else if self.shouldBreakTracking(for: reason) {
            if !self.parent.viewModel.anchorViewModel.isAdjustingAnchor {
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

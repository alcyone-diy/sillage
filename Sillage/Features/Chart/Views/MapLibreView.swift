//
//  MapLibreView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import CoreLocation
import MapLibre
import OSLog
import SwiftUI

struct MapLibreView: UIViewRepresentable {

  @Environment(\.marineTheme) var marineTheme
  @Environment(TrackRecordingService.self) private var trackRecordingService
  @Environment(OfflineSelectionViewModel.self) private var offlineSelectionViewModel
  var viewModel: ChartViewModel

  func makeUIView(context: Context) -> MLNMapView {
    let mapView = MarineMapView(frame: .zero)
    let coordinator = context.coordinator

    // Anchor all zoom gestures (pinch, one-finger quick zoom, double-tap, two-finger tap)
    // to the active nautical crosshair so zooming never drifts the aimed point off the reticle.
    mapView.customGestureAnchorProvider = { [weak coordinator, weak mapView] gesture in
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
    mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    mapView.maximumZoomLevel = AppConstants.Cartography.Zoom.globalMaximum
    mapView.isPitchEnabled = false
    mapView.attributionButton.isHidden = true
    mapView.logoView.isHidden = true

    // Configure compass to remain permanently visible at top-right below top HUD overlay
    mapView.compassView.compassVisibility = .visible
    mapView.compassViewPosition = .topRight
    mapView.compassViewMargins = CGPoint(
      x: MarineTheme.Spacing.medium,
      y: MarineTheme.Spacing.compassTopMargin
    )

    coordinator.mapView = mapView
    mapView.delegate = coordinator

    if let blankStyleURL = createBlankStyleJSON() {
      mapView.styleURL = blankStyleURL
    }

    coordinator.cameraController.applyInitialViewportCamera(from: viewModel, in: mapView)
    coordinator.setupSubscriptions(for: mapView)
    installGestureRecognizers(on: mapView, coordinator: coordinator)

    viewModel.isCoordinateVisible = { [weak coordinator, weak mapView] coord in
      guard let coordinator, let mapView else { return false }
      return coordinator.cameraController.isCoordinateVisible(coord, in: mapView)
    }

    offlineSelectionViewModel.defaultSelectionBoundsProvider = { [weak coordinator, weak mapView, weak offlineVM = offlineSelectionViewModel] in
      guard let coordinator, let mapView, let offlineVM else { return nil }
      coordinator.cameraController.resetToNorthUpLevelIfNeeded(in: mapView)
      return coordinator.offlineSelectionController.makeDefaultBounds(
        in: mapView,
        cropBoxWidthRatio: offlineVM.cropBoxWidthRatio,
        cropBoxAspect: offlineVM.cropBoxAspect
      )
    }

    return mapView
  }

  func makeStyleSnapshot(
    using coordinator: Coordinator,
    activeTrackPoints: ArraySlice<TrackPoint>
  ) -> MapStyleSnapshot {
    let activeSelectionBounds = coordinator.offlineSelectionController.resolvedBounds(
      isSelectionModeActive: offlineSelectionViewModel.isSelectionModeActive,
      committedBounds: offlineSelectionViewModel.selectedBounds
    )
    return MapStyleSnapshot(
      chartSource: viewModel.currentChartSource,
      isOpenSeaMapOverlayEnabled: viewModel.isOpenSeaMapOverlayEnabled,
      marineTheme: marineTheme,
      offlineMask: viewModel.offlineMaskVisualState,
      offlineHighlight: viewModel.highlightedOfflineRegion,
      offlineSelectionBounds: activeSelectionBounds,
      gpsAccuracy: viewModel.gpsAccuracyVisualState,
      savedTrack: viewModel.savedTrackVisualState,
      activeTrack: ActiveTrackFingerprint(points: activeTrackPoints),
      bearingLine: viewModel.bearingLineVisualState,
      measureState: viewModel.measureToolViewModel.state,
      measureActivePin: viewModel.measureToolViewModel.activePin,
      visibleWaypoints: viewModel.visibleWaypointVisualStates,
      goToWaypoint: viewModel.goToWaypointVisualState,
      anchor: viewModel.anchorVisualState,
      headingVector: viewModel.headingVectorData,
      vessel: viewModel.vesselVisualState,
      isDataStale: viewModel.isDataStale,
      aimingCoordinate: viewModel.calloutViewModel.aimingCoordinate
    )
  }

  func updateUIView(_ uiView: MLNMapView, context: Context) {
    let coordinator = context.coordinator
    coordinator.parent = self

    // Unconditionally construct snapshot so SwiftUI tracks all `@Observable` dependencies
    // even if the MapLibre style hasn't finished loading yet.
    // `activeTrackPoints` is scoped locally and never stored inside `lastSnapshot` to preserve CoW refcount == 1.
    let activeTrackPoints = trackRecordingService.trackPoints
    let snapshot = makeStyleSnapshot(using: coordinator, activeTrackPoints: activeTrackPoints)
    let trackingMode = viewModel.trackingMode

    if let style = uiView.style {
      let hadPreviousSnapshot = coordinator.styleSynchronizer.lastSnapshot != nil
      let dirty = coordinator.styleSynchronizer.apply(
        snapshot,
        activeTrackPoints: activeTrackPoints,
        forceAll: false,
        to: style
      )

      if dirty.contains(.offlineMask) {
        viewModel.updateOfflineRegionScreenPositions(
          projection: { uiView.convert($0, toPointTo: uiView) },
          bounds: uiView.bounds
        )
      }

      if hadPreviousSnapshot && dirty.contains(.baseChart) && snapshot.chartSource != nil {
        coordinator.cameraController.syncCameraAfterChartSourceSwitch(from: viewModel, in: uiView)
      }
    }

    if coordinator.cameraController.consumeBoundsSizeChange(uiView.bounds) {
      coordinator.calloutController.handleViewportResize(
        in: uiView,
        calloutViewModel: viewModel.calloutViewModel
      )
    }

    coordinator.cameraController.syncOfflineSelectionRotationLock(
      isSelectionModeActive: offlineSelectionViewModel.isSelectionModeActive,
      in: uiView
    )
    coordinator.cameraController.syncTrackingModeAndContentInset(
      trackingMode: trackingMode,
      in: uiView,
      delegate: coordinator
    )
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  static func dismantleUIView(_ uiView: MLNMapView, coordinator: Coordinator) {
    coordinator.parent.offlineSelectionViewModel.defaultSelectionBoundsProvider = nil
    coordinator.cancelTasks()
  }

  private func installGestureRecognizers(on mapView: MLNMapView, coordinator: Coordinator) {
    let longPressGesture = UILongPressGestureRecognizer(
      target: coordinator,
      action: #selector(Coordinator.handleLongPress(_:))
    )
    longPressGesture.minimumPressDuration = 0.5
    mapView.addGestureRecognizer(longPressGesture)

    let tapGesture = UITapGestureRecognizer(
      target: coordinator,
      action: #selector(Coordinator.handleTap(_:))
    )
    tapGesture.cancelsTouchesInView = false
    if let gestureRecognizers = mapView.gestureRecognizers {
      for recognizer in gestureRecognizers {
        if let tapRecognizer = recognizer as? UITapGestureRecognizer,
           tapRecognizer.numberOfTapsRequired == 2 {
          tapGesture.require(toFail: tapRecognizer)
        }
      }
    }
    mapView.addGestureRecognizer(tapGesture)

    let pinPanGesture = UIPanGestureRecognizer(
      target: coordinator,
      action: #selector(Coordinator.handlePinPan(_:))
    )
    pinPanGesture.delegate = coordinator
    pinPanGesture.cancelsTouchesInView = true
    mapView.addGestureRecognizer(pinPanGesture)
    coordinator.pinPanGesture = pinPanGesture
  }

  /// Loads a minimal blank JSON style so MapLibre initializes its engine and fires `mapView(_:didFinishLoading:)`.
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
    let styleSynchronizer = MapStyleStateSynchronizer()
    let cameraController = MapCameraController()
    let offlineSelectionController: OfflineSelectionInteractionController
    let measureController = MeasureMapInteractionController()
    let calloutController: CalloutAimingController

    private var networkObservationTask: TaskCancellable?
    weak var mapView: MLNMapView?
    weak var pinPanGesture: UIPanGestureRecognizer?

    private var isUserActivelyInteractingWithTools: Bool {
      calloutController.isInteracting ||
      measureController.isInteracting(measureViewModel: parent.viewModel.measureToolViewModel) ||
      offlineSelectionController.isInteracting
    }

    init(_ parent: MapLibreView) {
      self.parent = parent
      self.offlineSelectionController = OfflineSelectionInteractionController(styleSynchronizer: styleSynchronizer)
      self.calloutController = CalloutAimingController(
        styleSynchronizer: styleSynchronizer,
        cameraController: cameraController
      )
      super.init()
    }

    func cancelTasks() {
      cameraController.cancelTasks()
      networkObservationTask?.cancel()
      networkObservationTask = nil
    }

    func setupSubscriptions(for mapView: MLNMapView) {
      parent.viewModel.measureToolViewModel.onEnsureVisibleRequested = { [weak self, weak mapView] sheetHeight in
        guard let self, let mapView, !self.isUserActivelyInteractingWithTools else { return }
        self.measureController.requestEnsureVisibleIfNeeded(
          in: mapView,
          measureViewModel: self.parent.viewModel.measureToolViewModel,
          sheetHeight: sheetHeight,
          onRequestVerticalFraming: { [weak self, weak mapView] request, resolvedSheetHeight in
            guard let self, let mapView else { return }
            self.cameraController.shiftToFitVerticalRange(
              minY: request.minY,
              maxY: request.maxY,
              fallbackPoint: request.fallbackPoint,
              fallbackBottomOffset: request.fallbackBottomOffset,
              in: mapView,
              sheetHeight: resolvedSheetHeight,
              isGloveMode: self.parent.marineTheme.isGloveMode
            )
          }
        )
      }

      networkObservationTask?.cancel()
      networkObservationTask = TaskCancellable(Task { @MainActor [weak self, weak mapView] in
        for await _ in NotificationCenter.default.notifications(named: .networkDidReconnect) {
          guard !Task.isCancelled, let self, let mapView else { break }
          Logger.chart.info("Network reconnected, forcing MapLibre complete style reload")
          self.cameraController.captureReloadCameraIfNeeded(from: mapView)
          mapView.reloadStyle(nil)
        }
      })

      cameraController.startCameraStreamSubscription(for: mapView, viewModel: parent.viewModel)
    }

    private func waypointSnapCandidates(in mapView: MLNMapView) -> [WaypointSnapCandidate] {
      let visibleBounds = mapView.visibleCoordinateBounds
      return WaypointMagneticSnap.makeCandidates(
        visibleWaypoints: parent.viewModel.visibleWaypointVisualStates,
        goToWaypoint: parent.viewModel.goToWaypointVisualState,
        draftWaypointID: parent.viewModel.draftWaypointID,
        southWest: visibleBounds.sw,
        northEast: visibleBounds.ne,
        project: { mapView.convert($0, toPointTo: mapView) }
      )
    }

    // MARK: - Explicit Gesture Routing

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      if gestureRecognizer === pinPanGesture {
        guard !calloutController.isLongPressActive, !measureController.isLongPressingPin else {
          return false
        }
        guard let mapView else { return false }
        let touchPoint = gestureRecognizer.location(in: mapView)
        let hitRadius = parent.marineTheme.metrics.mapHandleHitRadius
        if parent.viewModel.measureToolViewModel.isActive {
          return measureController.shouldBeginPan(
            at: touchPoint,
            in: mapView,
            measureViewModel: parent.viewModel.measureToolViewModel,
            hitRadius: hitRadius
          )
        }
        if parent.offlineSelectionViewModel.isSelectionModeActive {
          return offlineSelectionController.shouldBeginPan(
            at: touchPoint,
            in: mapView,
            offlineViewModel: parent.offlineSelectionViewModel,
            hitRadius: hitRadius
          )
        }
        return false
      }
      return true
    }

    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
      if gestureRecognizer == pinPanGesture || otherGestureRecognizer == pinPanGesture {
        return false
      }
      if gestureRecognizer is UILongPressGestureRecognizer || otherGestureRecognizer is UILongPressGestureRecognizer {
        return false
      }
      if isUserActivelyInteractingWithTools {
        return false
      }
      return true
    }

    @objc func handleTap(_ sender: UITapGestureRecognizer) {
      guard sender.state == .ended,
            parent.viewModel.measureToolViewModel.isActive,
            let mapView = sender.view as? MLNMapView else {
        return
      }
      measureController.handleTap(
        sender,
        in: mapView,
        measureViewModel: parent.viewModel.measureToolViewModel,
        hitRadius: parent.marineTheme.metrics.mapHandleHitRadius,
        onUserInteraction: { [weak self] in
          self?.parent.viewModel.chartInteractedByUser()
        }
      )
    }

    @objc func handlePinPan(_ sender: UIPanGestureRecognizer) {
      guard let mapView = sender.view as? MLNMapView else { return }

      // 1. Active drag session takes strict precedence so `.changed` / `.ended` / `.cancelled`
      // always complete inside their originating controller even if tool mode flips mid-gesture.
      if measureController.isDraggingPin {
        routePanToMeasure(sender, in: mapView)
        return
      }
      if offlineSelectionController.isDraggingCorner {
        routePanToOfflineSelection(sender, in: mapView)
        return
      }

      // 2. New drag session: route according to active modal tool
      if parent.viewModel.measureToolViewModel.isActive {
        routePanToMeasure(sender, in: mapView)
        return
      }
      if parent.offlineSelectionViewModel.isSelectionModeActive {
        routePanToOfflineSelection(sender, in: mapView)
      }
    }

    @objc func handleLongPress(_ sender: UILongPressGestureRecognizer) {
      // 1. Active long-press session takes strict precedence so `.changed` / `.ended` / `.cancelled`
      // never jump across controllers if tool state changes mid-gesture.
      if measureController.isLongPressingPin {
        guard let mapView = sender.view as? MLNMapView else {
          measureController.cancelActiveInteraction(measureViewModel: parent.viewModel.measureToolViewModel)
          return
        }
        routeLongPressToMeasure(sender, in: mapView)
        return
      }
      if calloutController.isLongPressActive {
        guard let mapView = sender.view as? MLNMapView else {
          calloutController.cancelLongPressSession(
            calloutViewModel: parent.viewModel.calloutViewModel,
            style: self.mapView?.style
          )
          return
        }
        routeLongPressToCallout(sender, in: mapView)
        return
      }

      // 2. New long-press session: route according to active tool state
      if parent.viewModel.measureToolViewModel.isActive {
        guard let mapView = sender.view as? MLNMapView else { return }
        routeLongPressToMeasure(sender, in: mapView)
        return
      }

      /// Technical Design Choice: Disable contextual gesture during active action confirmation cards
      /// Prevents long-press waypoint popover creation whenever a MarineActionConfirmationCard is active
      /// (e.g. anchor repositioning or offline area selection).
      guard !parent.viewModel.isActionConfirmationCardActive,
            let mapView = sender.view as? MLNMapView else {
        return
      }
      routeLongPressToCallout(sender, in: mapView)
    }

    private func routePanToMeasure(_ sender: UIPanGestureRecognizer, in mapView: MLNMapView) {
      let attachRadius = parent.marineTheme.isGloveMode
        ? AppConstants.Map.waypointMagneticSnapGloveRadius
        : AppConstants.Map.waypointMagneticSnapRadius
      measureController.handlePan(
        sender,
        in: mapView,
        measureViewModel: parent.viewModel.measureToolViewModel,
        hitRadius: parent.marineTheme.metrics.mapHandleHitRadius,
        attachRadius: attachRadius,
        snapCandidatesProvider: { [weak self] map in
          self?.waypointSnapCandidates(in: map) ?? []
        },
        onUserInteraction: { [weak self] in
          self?.parent.viewModel.chartInteractedByUser()
        },
        onRequestVerticalFraming: { [weak self, weak mapView] request, sheetHeight in
          guard let self, let mapView else { return }
          self.cameraController.shiftToFitVerticalRange(
            minY: request.minY,
            maxY: request.maxY,
            fallbackPoint: request.fallbackPoint,
            fallbackBottomOffset: request.fallbackBottomOffset,
            in: mapView,
            sheetHeight: sheetHeight,
            isGloveMode: self.parent.marineTheme.isGloveMode
          )
        }
      )
    }

    private func routePanToOfflineSelection(_ sender: UIPanGestureRecognizer, in mapView: MLNMapView) {
      offlineSelectionController.handlePan(
        sender,
        in: mapView,
        offlineViewModel: parent.offlineSelectionViewModel,
        hitRadius: parent.marineTheme.metrics.mapHandleHitRadius,
        onUserInteraction: { [weak self] in
          self?.parent.viewModel.chartInteractedByUser()
        }
      )
    }

    private func routeLongPressToMeasure(_ sender: UILongPressGestureRecognizer, in mapView: MLNMapView) {
      let attachRadius = parent.marineTheme.isGloveMode
        ? AppConstants.Map.waypointMagneticSnapGloveRadius
        : AppConstants.Map.waypointMagneticSnapRadius
      measureController.handleLongPress(
        sender,
        in: mapView,
        measureViewModel: parent.viewModel.measureToolViewModel,
        attachRadius: attachRadius,
        snapCandidatesProvider: { [weak self] map in
          self?.waypointSnapCandidates(in: map) ?? []
        },
        onUserInteraction: { [weak self] in
          self?.parent.viewModel.chartInteractedByUser()
        },
        onRequestVerticalFraming: { [weak self, weak mapView] request, sheetHeight in
          guard let self, let mapView else { return }
          self.cameraController.shiftToFitVerticalRange(
            minY: request.minY,
            maxY: request.maxY,
            fallbackPoint: request.fallbackPoint,
            fallbackBottomOffset: request.fallbackBottomOffset,
            in: mapView,
            sheetHeight: sheetHeight,
            isGloveMode: self.parent.marineTheme.isGloveMode
          )
        }
      )
    }

    private func routeLongPressToCallout(_ sender: UILongPressGestureRecognizer, in mapView: MLNMapView) {
      calloutController.handleLongPress(
        sender,
        in: mapView,
        viewModel: parent.viewModel,
        theme: parent.marineTheme,
        snapCandidatesProvider: { [weak self] map in
          self?.waypointSnapCandidates(in: map) ?? []
        }
      )
    }

    // MARK: - MLNMapViewDelegate

    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
      Logger.chart.info("MapLibre successfully loaded the default style.")

      let activeTrackPoints = parent.trackRecordingService.trackPoints
      let snapshot = parent.makeStyleSnapshot(using: self, activeTrackPoints: activeTrackPoints)
      styleSynchronizer.apply(snapshot, activeTrackPoints: activeTrackPoints, forceAll: true, to: style)

      cameraController.restoreCameraAfterStyleLoad(from: parent.viewModel, in: mapView)

      if snapshot.offlineMask != nil, mapView.bounds.width > 0, mapView.bounds.height > 0 {
        parent.viewModel.updateOfflineRegionScreenPositions(
          projection: { mapView.convert($0, toPointTo: mapView) },
          bounds: mapView.bounds
        )
      }
    }

    func mapView(_ mapView: MLNMapView, regionWillChangeWith reason: MLNCameraChangeReason, animated: Bool) {
      calloutController.regionWillChange(
        in: mapView,
        reason: reason,
        viewModel: parent.viewModel,
        theme: parent.marineTheme,
        snapCandidatesProvider: { [weak self] map in
          self?.waypointSnapCandidates(in: map) ?? []
        }
      )
      cameraController.regionWillChange(in: mapView, reason: reason, viewModel: parent.viewModel)
    }

    func mapViewRegionIsChanging(_ mapView: MLNMapView) {
      cameraController.regionIsChanging(
        in: mapView,
        viewModel: parent.viewModel,
        isGloveMode: parent.marineTheme.isGloveMode
      )
      calloutController.regionIsChanging(
        in: mapView,
        viewModel: parent.viewModel,
        theme: parent.marineTheme,
        excludedGestureRecognizer: pinPanGesture,
        snapCandidatesProvider: { [weak self] map in
          self?.waypointSnapCandidates(in: map) ?? []
        }
      )
    }

    func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason, animated: Bool) {
      calloutController.regionDidChange(
        in: mapView,
        reason: reason,
        viewModel: parent.viewModel,
        theme: parent.marineTheme,
        snapCandidatesProvider: { [weak self] map in
          self?.waypointSnapCandidates(in: map) ?? []
        }
      )
      cameraController.regionDidChange(in: mapView, reason: reason, viewModel: parent.viewModel)
    }

    func mapView(_ mapView: MLNMapView, didChange mode: MLNUserTrackingMode, animated: Bool) {
      cameraController.enforceDisabledNativeUserTracking(on: mapView, mode: mode)
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

    func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
      Logger.chart.error("Error loading MapLibre map: \(error.localizedDescription, privacy: .public)")
    }
  }
}

//
//  MapLibreView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI
import MapLibre
import CoreLocation
import Combine

struct MapLibreView: UIViewRepresentable {

  @ObservedObject var viewModel: MapViewModel

  func makeUIView(context: Context) -> MLNMapView {
    // Initialization of the MapLibre view without a frame
    let mapView = MLNMapView(frame: .zero)
    mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

    // Delegate configuration
    mapView.delegate = context.coordinator

    // Set maximum zoom level to allow overzooming
    mapView.maximumZoomLevel = 22.0

    // Disable pitch gesture to keep the map in 2D
    mapView.isPitchEnabled = false

    // Disable compass interaction to prevent tapping from resetting the map's heading to 0
    mapView.compassView.isUserInteractionEnabled = false

    // Load a minimal blank style so MapLibre initializes and fires `mapView(_:didFinishLoading:)`
    if let blankStyleURL = createBlankStyleJSON() {
      mapView.styleURL = blankStyleURL
    }

    // Centering of the initial camera using ViewModel's state
    mapView.setCenter(viewModel.centerCoordinate, zoomLevel: viewModel.zoomLevel, direction: viewModel.mapDirection, animated: false)

    // Setup subscription for explicit user location centering via Publisher
    context.coordinator.setupSubscription(for: mapView)

    return mapView
  }

  func updateUIView(_ uiView: MLNMapView, context: Context) {
    // Updates the coordinator's parent to always point to the latest view (SwiftUI struct)
    context.coordinator.parent = self

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
      uiView.setContentInset(newInset, animated: true)
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  /// Creates a minimal empty JSON style to force MapLibre to load its engine and fire the finish loading delegate method.
  private func createBlankStyleJSON() -> URL? {
    guard let styleURL = Bundle.main.url(forResource: "blank-style", withExtension: "json") else {
      print("WARNING: blank-style.json not found in App Bundle. MapLibre may not initialize correctly.")
      return nil
    }
    return styleURL
  }

  // MARK: - Coordinator

  class Coordinator: NSObject, MLNMapViewDelegate {
    var parent: MapLibreView
    private var cancellables = Set<AnyCancellable>()
    var lastMapSource: MapSource?

    init(_ parent: MapLibreView) {
      self.parent = parent
    }

    func setupSubscription(for mapView: MLNMapView) {
      parent.viewModel.cameraMovePublisher
        .receive(on: DispatchQueue.main)
        .sink { (coordinate, requestedZoom, heading) in
          let targetZoom = requestedZoom ?? mapView.zoomLevel

          // We pass the targetZoom explicitly. If the raster chart doesn't support this
          // zoom level (e.g., maxZoom is 14), MapLibre might show a white screen
          // depending on how over-zooming is handled by the raster source style.
          if let heading = heading {
            mapView.setCenter(coordinate, zoomLevel: targetZoom, direction: heading, animated: true, completionHandler: nil)
          } else {
            mapView.setCenter(coordinate, zoomLevel: targetZoom, animated: true)
          }
        }
        .store(in: &cancellables)

      parent.viewModel.$vesselFeature
        .receive(on: DispatchQueue.main)
        .sink { [weak self] feature in
          self?.updateVesselFeature(feature, in: mapView)
        }
        .store(in: &cancellables)

      parent.viewModel.$headingVectorFeature
        .receive(on: DispatchQueue.main)
        .sink { [weak self] feature in
          self?.updateHeadingVectorFeature(feature, in: mapView)
        }
        .store(in: &cancellables)

      parent.viewModel.$isDataStale
        .receive(on: DispatchQueue.main)
        .sink { [weak self] isStale in
          self?.updateStaleState(isStale, in: mapView)
        }
        .store(in: &cancellables)

      parent.viewModel.$trackingMode
        .receive(on: DispatchQueue.main)
        .sink { [weak mapView] mode in
          guard let mapView = mapView else { return }
          // Force tracking mode to none, as we handle tracking explicitly
          if mapView.userTrackingMode != .none {
            mapView.userTrackingMode = .none
          }
        }
        .store(in: &cancellables)
    }

    var lastOpenSeaMapOverlayEnabled: Bool = false

    // Called when the map has finished loading its style
    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
      print("MapLibre successfully loaded the default style.")

      // Add vessel cursor image
      if let image = VesselGraphicsFactory.createVesselImage(size: MarineTheme.MapMetrics.vesselCursorBaseSize, color: UIColor(MarineTheme.Colors.accent)) {
        style.setImage(image, forName: "vessel-cursor")
      }

      if let currentSource = parent.viewModel.currentMapSource {
        updateMapSource(currentSource, style: style, mapView: mapView)
      }

      updateOpenSeaMapOverlay(isEnabled: parent.viewModel.isOpenSeaMapOverlayEnabled, style: style, mapView: mapView)

      // Ensure vessel layers are initialized after style finishes loading
      updateHeadingVectorFeature(parent.viewModel.headingVectorFeature, in: mapView)
      updateVesselFeature(parent.viewModel.vesselFeature, in: mapView)
      updateStaleState(parent.viewModel.isDataStale, in: mapView)

      // NOTE: We do not call `mapView.setVisibleCoordinateBounds` here.
      // In SwiftUI, `didFinishLoading` can fire before the map view has a non-zero frame.
      // Calling coordinate bounds on a `.zero` frame corrupts the MapLibre camera (`NaN` zoom level).
      // Instead, we simply jump the camera back to the exact metadata `centerCoordinate` and `zoomLevel`.
      // This is required because loading the blank JSON style resets the map to (0,0), which leaves it looking at
      // the African coast where no French marine chart tiles exist, causing the map to appear blank.
      mapView.setCenter(parent.viewModel.centerCoordinate, zoomLevel: parent.viewModel.zoomLevel, direction: parent.viewModel.mapDirection, animated: false)
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

          // Add the raster layer
          let rasterLayer = MLNRasterStyleLayer(identifier: layerId, source: rasterSource)
          style.addLayer(rasterLayer)

          print("Programmatically injected MBTiles raster source and layer.")
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
        style.addLayer(rasterLayer)

        print("Programmatically injected GeoGarage raster source and layer.")

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
        style.addLayer(rasterLayer)

        print("Programmatically injected OpenSeaMap raster source and layer.")
      }

      // Re-apply OpenSeaMap overlay if it was enabled, to ensure it stays on top of the new base map
      if lastOpenSeaMapOverlayEnabled {
        OpenSeaMapLayerService.shared.removeSeamarkLayer(from: style)
        OpenSeaMapLayerService.shared.addSeamarkLayer(to: style, above: layerId)
      }

      // Re-center on the new source's preferred coordinate and zoom if needed
      mapView.setCenter(parent.viewModel.centerCoordinate, zoomLevel: parent.viewModel.zoomLevel, direction: parent.viewModel.mapDirection, animated: false)

      // After updating the map source, we need to ensure the vessel layers are still at the top.
      // But we shouldn't do it by constantly removing/adding in the feature updates.
      // Doing it once here when the base map changes is acceptable.
      if let vesselLayer = style.layer(withIdentifier: "vessel-layer") {
        style.removeLayer(vesselLayer)
        style.addLayer(vesselLayer)
      }
      if let headingLayer = style.layer(withIdentifier: "heading-vector-layer") {
        style.removeLayer(headingLayer)
        if let vesselLayer = style.layer(withIdentifier: "vessel-layer") {
          style.insertLayer(headingLayer, below: vesselLayer)
        } else {
          style.addLayer(headingLayer)
        }
      }
    }

    private func updateVesselFeature(_ feature: MLNPointFeature?, in mapView: MLNMapView) {
      guard let style = mapView.style else { return }

      let sourceId = "vessel-source"
      let layerId = "vessel-layer"

      if let source = style.source(withIdentifier: sourceId) as? MLNShapeSource {
        if let feature = feature {
          source.shape = feature
        } else {
          source.shape = nil
        }
      } else {
        guard let feature = feature else { return }

        let source = MLNShapeSource(identifier: sourceId, shape: feature, options: nil)
        style.addSource(source)

        let layer = MLNSymbolStyleLayer(identifier: layerId, source: source)
        layer.iconImageName = NSExpression(forConstantValue: "vessel-cursor")
        layer.iconRotationAlignment = NSExpression(forConstantValue: "map")
        layer.iconRotation = NSExpression(forKeyPath: "course")
        layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
        layer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
        layer.iconOpacity = NSExpression(forConstantValue: parent.viewModel.isDataStale ? 0.4 : 1.0)

        style.addLayer(layer) // Add at top
      }
    }

    private func updateHeadingVectorFeature(_ feature: MLNShapeCollectionFeature?, in mapView: MLNMapView) {
      guard let style = mapView.style else { return }

      let sourceId = "heading-vector-source"
      let layerId = "heading-vector-layer"

      if let source = style.source(withIdentifier: sourceId) as? MLNShapeSource {
        if let feature = feature {
          source.shape = feature
        } else {
          source.shape = nil
        }
      } else {
        guard let feature = feature else { return }

        let source = MLNShapeSource(identifier: sourceId, shape: feature, options: nil)
        style.addSource(source)

        let layer = MLNLineStyleLayer(identifier: layerId, source: source)

        let lineWidthValue = MarineTheme.MapMetrics.headingLineWidth
        let planningLineWidthValue = MarineTheme.MapMetrics.planningLineWidth
        layer.lineWidth = NSExpression(format: "TERNARY(colorIndex == 2, %@, %@)", NSNumber(value: planningLineWidthValue), NSNumber(value: lineWidthValue))

        let color0 = UIColor(MarineTheme.Colors.primary)
        let color1 = UIColor(MarineTheme.Colors.primaryFaded)
        let color2 = UIColor(MarineTheme.Colors.planningLine)
        layer.lineColor = NSExpression(format: "TERNARY(colorIndex == 0, %@, TERNARY(colorIndex == 1, %@, %@))", color0, color1, color2)

        // Ensure heading vector is under the vessel layer
        if let vesselLayer = style.layer(withIdentifier: "vessel-layer") {
          style.insertLayer(layer, below: vesselLayer)
        } else {
          style.addLayer(layer)
        }
      }
    }

    private func updateStaleState(_ isStale: Bool, in mapView: MLNMapView) {
      guard let style = mapView.style, let layer = style.layer(withIdentifier: "vessel-layer") as? MLNSymbolStyleLayer else { return }
      layer.iconOpacity = NSExpression(forConstantValue: isStale ? 0.4 : 1.0)
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
        self.parent.viewModel.mapDirection = mapView.direction

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
      print("Error loading MapLibre map: \(error.localizedDescription)")
    }
  }
}

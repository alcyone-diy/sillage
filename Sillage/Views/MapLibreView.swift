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

        // Load a minimal blank style so MapLibre initializes and fires `mapView(_:didFinishLoading:)`
        if let blankStyleURL = createBlankStyleJSON() {
            mapView.styleURL = blankStyleURL
        }

        // Centering of the initial camera
        if let initialCenter = viewModel.initialCenterCoordinate, let initialZoom = viewModel.initialZoomLevel {
            mapView.setCenter(initialCenter, zoomLevel: initialZoom, animated: false)
        } else {
            // Default center if none available
            mapView.setCenter(CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522), zoomLevel: 10.0, animated: false)
        }

        // Setup subscription for explicit user location centering via Publisher
        context.coordinator.setupSubscription(for: mapView)

        return mapView
    }

    func updateUIView(_ uiView: MLNMapView, context: Context) {
        // Updates the coordinator's parent to always point to the latest view (SwiftUI struct)
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    /// Creates a minimal empty JSON style to force MapLibre to load its engine and fire the finish loading delegate method.
    private func createBlankStyleJSON() -> URL? {
        let styleDictionary: [String: Any] = [
            "version": 8,
            "name": "EmptyStyle",
            "sources": [:],
            "layers": []
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: styleDictionary)
            let tempDirectory = FileManager.default.temporaryDirectory
            let styleFileURL = tempDirectory.appendingPathComponent("blank-style.json")
            try jsonData.write(to: styleFileURL)
            return styleFileURL
        } catch {
            print("Failed to create blank style JSON: \(error)")
            return nil
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: MapLibreView
        private var cancellables = Set<AnyCancellable>()

        init(_ parent: MapLibreView) {
            self.parent = parent
        }

        func setupSubscription(for mapView: MLNMapView) {
            parent.viewModel.cameraMovePublisher
                .receive(on: DispatchQueue.main)
                .sink { (coordinate, requestedZoom) in
                    let targetZoom = requestedZoom ?? mapView.zoomLevel

                    // We pass the targetZoom explicitly. If the raster chart doesn't support this
                    // zoom level (e.g., maxZoom is 14), MapLibre might show a white screen
                    // depending on how over-zooming is handled by the raster source style.
                    mapView.setCenter(coordinate, zoomLevel: targetZoom, animated: true)
                }
                .store(in: &cancellables)
        }

        // Called when the map has finished loading its style
        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            print("MapLibre successfully loaded the default style.")

            // Programmatically inject MBTiles source and layer
            if let activeMapPath = parent.viewModel.activeMapPath {
                let mbtilesProtocolURL = "mbtiles://\(activeMapPath.path)"
                let sourceId = "local-raster-source"

                // Add the raster source
                let rasterSource = MLNRasterTileSource(identifier: sourceId, tileURLTemplates: [mbtilesProtocolURL], options: [
                    .tileSize: 256
                ])
                style.addSource(rasterSource)

                // Add the raster layer
                let rasterLayer = MLNRasterStyleLayer(identifier: "local-raster-layer", source: rasterSource)
                style.addLayer(rasterLayer)

                print("Programmatically injected MBTiles raster source and layer.")
            }

            // If bounds are available, perfectly fit the camera to the bounds
            if let bounds = parent.viewModel.mapBounds {
                let sw = CLLocationCoordinate2D(latitude: bounds.minLat, longitude: bounds.minLon)
                let ne = CLLocationCoordinate2D(latitude: bounds.maxLat, longitude: bounds.maxLon)
                let coordinateBounds = MLNCoordinateBounds(sw: sw, ne: ne)

                // Add a small delay to ensure the view's layout is complete before fitting bounds
                DispatchQueue.main.async {
                    mapView.setVisibleCoordinateBounds(coordinateBounds, edgePadding: UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20), animated: false)
                }
            }
        }

        // Capture user's map movements to break tracking ONLY when the movement stops, as requested
        func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            // Break tracking only if the change was caused by user interaction (like panning or zooming).
            // Using `reason` is the most precise way in MapLibre.
            let isUserInteraction = reason.contains(.gesturePan) ||
                                    reason.contains(.gesturePinch) ||
                                    reason.contains(.gestureZoomIn) ||
                                    reason.contains(.gestureZoomOut) ||
                                    reason.contains(.gestureOneFingerZoom)

            if isUserInteraction {
                DispatchQueue.main.async {
                    self.parent.viewModel.mapInteractedByUser()
                }
            }
        }

        // Fallback for older MapLibre versions or if reason is not fully reliable:
        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            // Check if user is panning or zooming manually
            let isUserInteraction = mapView.panGestureRecognizer.state == .ended ||
                                    mapView.pinchGestureRecognizer.state == .ended

            if isUserInteraction {
                DispatchQueue.main.async {
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

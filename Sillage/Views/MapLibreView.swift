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

        // Centering of the initial camera using ViewModel's state
        mapView.setCenter(viewModel.centerCoordinate, zoomLevel: viewModel.zoomLevel, animated: false)

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
        let jsonString = """
        { "version": 8, "name": "EmptyStyle", "sources": {}, "layers": [] }
        """

        do {
            let jsonData = Data(jsonString.utf8)
            let tempDirectory = FileManager.default.temporaryDirectory
            let uniqueFilename = "blank-style-\(UUID().uuidString).json"
            let styleFileURL = tempDirectory.appendingPathComponent(uniqueFilename)
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
            if let activeMapPath = parent.viewModel.activeMapPath,
               let encodedPath = activeMapPath.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
               let configurationURL = URL(string: "mbtiles://\(encodedPath)") {
                let sourceId = "local-raster-source"

                // Ensure the source isn't already added
                if style.source(withIdentifier: sourceId) == nil {
                    // Add the raster source using configurationURL and tileSize
                    let rasterSource = MLNRasterTileSource(identifier: sourceId, configurationURL: configurationURL, tileSize: 256)
                    style.addSource(rasterSource)

                    // Add the raster layer
                    let rasterLayer = MLNRasterStyleLayer(identifier: "local-raster-layer", source: rasterSource)
                    style.addLayer(rasterLayer)

                    print("Programmatically injected MBTiles raster source and layer.")
                }
            }

            // If bounds are available, perfectly fit the camera to the bounds
            if let bounds = parent.viewModel.mapBounds {
                let sw = CLLocationCoordinate2D(latitude: bounds.minLat, longitude: bounds.minLon)
                let ne = CLLocationCoordinate2D(latitude: bounds.maxLat, longitude: bounds.maxLon)
                let coordinateBounds = MLNCoordinateBounds(sw: sw, ne: ne)

                // Add a small delay to ensure the view's layout is complete before fitting bounds
                DispatchQueue.main.async {
                    mapView.setVisibleCoordinateBounds(coordinateBounds, edgePadding: UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20), animated: false, completionHandler: nil)
                }
            }
        }

        // Capture user's map movements to break tracking ONLY when the movement stops, as requested
        // Also sync the final camera state back to the ViewModel so it knows where the map is.
        func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            // Break tracking only if the change was caused by user interaction (like panning or zooming).
            // Using `reason` is the most precise way in MapLibre.
            let isUserInteraction = !reason.contains(.programmatic)

            DispatchQueue.main.async {
                // Keep ViewModel state in sync with the map
                self.parent.viewModel.centerCoordinate = mapView.centerCoordinate
                self.parent.viewModel.zoomLevel = mapView.zoomLevel

                // If it was a manual interaction, break tracking
                if isUserInteraction {
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

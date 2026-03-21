import SwiftUI
import MapLibre
import CoreLocation
import Combine

struct MapLibreView: UIViewRepresentable {

    @Binding var centerCoordinate: CLLocationCoordinate2D
    @Binding var zoomLevel: Double
    @Binding var styleURL: URL?
    @Binding var mapBounds: MBTilesBounds?
    let moveToLocationPublisher: PassthroughSubject<CLLocationCoordinate2D, Never>

    func makeUIView(context: Context) -> MLNMapView {
        // Initialization of the MapLibre view without a frame
        let mapView = MLNMapView(frame: .zero)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // Delegate configuration
        mapView.delegate = context.coordinator

        // Application of the local style (if available)
        if let styleURL = styleURL {
            mapView.styleURL = styleURL
        }

        // Centering of the initial camera
        mapView.setCenter(centerCoordinate, zoomLevel: zoomLevel, animated: false)

        // Setup subscription for explicit user location centering
        context.coordinator.setupSubscription(for: mapView)

        return mapView
    }

    func updateUIView(_ uiView: MLNMapView, context: Context) {
        // Updates the coordinator's parent to always point to the latest view (SwiftUI struct)
        context.coordinator.parent = self

        // Updates the map according to the ViewModel's modifications

        // Center
        if uiView.centerCoordinate.latitude != centerCoordinate.latitude ||
           uiView.centerCoordinate.longitude != centerCoordinate.longitude {
            uiView.setCenter(centerCoordinate, animated: true)
        }

        // Zoom
        if uiView.zoomLevel != zoomLevel {
            uiView.setZoomLevel(zoomLevel, animated: true)
        }

        // Style
        if uiView.styleURL != styleURL {
            uiView.styleURL = styleURL
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: MapLibreView
        private var cancellables = Set<AnyCancellable>()

        init(_ parent: MapLibreView) {
            self.parent = parent
        }

        func setupSubscription(for mapView: MLNMapView) {
            parent.moveToLocationPublisher
                .receive(on: DispatchQueue.main)
                .sink { coordinate in
                    mapView.setCenter(coordinate, animated: true)
                }
                .store(in: &cancellables)
        }

        // Called when the map has finished loading its style
        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            print("MapLibre successfully loaded the style: \(style.name ?? "Unknown")")

            // If bounds are available, perfectly fit the camera to the bounds
            if let bounds = parent.mapBounds {
                let sw = CLLocationCoordinate2D(latitude: bounds.minLat, longitude: bounds.minLon)
                let ne = CLLocationCoordinate2D(latitude: bounds.maxLat, longitude: bounds.maxLon)
                let coordinateBounds = MLNCoordinateBounds(sw: sw, ne: ne)

                // Add a small delay to ensure the view's layout is complete before fitting bounds
                DispatchQueue.main.async {
                    mapView.setVisibleCoordinateBounds(coordinateBounds, edgePadding: UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20), animated: false)

                    // Update the state with the exact calculated camera after fitting bounds
                    self.parent.centerCoordinate = mapView.centerCoordinate
                    self.parent.zoomLevel = mapView.zoomLevel
                }
            }
        }

        // Methods to capture user's map movements
        func mapViewRegionIsChanging(_ mapView: MLNMapView) {
            parent.centerCoordinate = mapView.centerCoordinate
            parent.zoomLevel = mapView.zoomLevel
        }

        // Potential loading errors
        func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
            print("Error loading MapLibre map: \(error.localizedDescription)")
        }
    }
}

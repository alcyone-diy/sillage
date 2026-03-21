import SwiftUI
import MapLibre
import CoreLocation

struct MapLibreView: UIViewRepresentable {

    @Binding var centerCoordinate: CLLocationCoordinate2D
    @Binding var zoomLevel: Double
    @Binding var styleURL: URL?

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

        init(_ parent: MapLibreView) {
            self.parent = parent
        }

        // Called when the map has finished loading its style
        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            print("MapLibre successfully loaded the style: \(style.name ?? "Unknown")")
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

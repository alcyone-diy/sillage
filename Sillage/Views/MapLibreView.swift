import SwiftUI
import MapLibre
import CoreLocation

struct MapLibreView: UIViewRepresentable {

    @Binding var centerCoordinate: CLLocationCoordinate2D
    @Binding var zoomLevel: Double
    @Binding var styleURL: URL?

    func makeUIView(context: Context) -> MLNMapView {
        // Initialisation de la vue MapLibre sans frame
        let mapView = MLNMapView(frame: .zero)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // Configuration du delegate
        mapView.delegate = context.coordinator

        // Application du style local (si disponible)
        if let styleURL = styleURL {
            mapView.styleURL = styleURL
        }

        // Centrage de la caméra initiale
        mapView.setCenter(centerCoordinate, zoomLevel: zoomLevel, animated: false)

        return mapView
    }

    func updateUIView(_ uiView: MLNMapView, context: Context) {
        // Met à jour le parent du coordinator pour toujours pointer vers la dernière vue (struct SwiftUI)
        context.coordinator.parent = self

        // Met à jour la carte en fonction des modifications du ViewModel

        // Centre
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

        // Appelé lorsque la carte a fini de charger son style
        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            print("MapLibre a chargé avec succès le style : \(style.name ?? "Inconnu")")
        }

        // Méthodes pour capturer les déplacements de la carte par l'utilisateur
        func mapViewRegionIsChanging(_ mapView: MLNMapView) {
            parent.centerCoordinate = mapView.centerCoordinate
            parent.zoomLevel = mapView.zoomLevel
        }

        // Erreurs éventuelles lors du chargement
        func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
            print("Erreur de chargement de la carte MapLibre : \(error.localizedDescription)")
        }
    }
}

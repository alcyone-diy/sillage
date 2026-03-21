import Foundation
import Combine
import CoreLocation
import SwiftUI

class MapViewModel: ObservableObject {

    @Published var centerCoordinate: CLLocationCoordinate2D
    @Published var zoomLevel: Double
    @Published var styleURL: URL?

    private var mapLayer: MapLayer?

    init() {
        // Initialisation avec des valeurs par défaut (ex: Paris)
        self.centerCoordinate = CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)
        self.zoomLevel = 10.0

        loadMBTilesData()
    }

    private func loadMBTilesData() {
        // Recherche du fichier dans le Bundle de l'application
        guard let url = Bundle.main.url(forResource: "7413_pal300", withExtension: "mbtiles") else {
            print("Erreur : Le fichier 7413_pal300.mbtiles n'a pas été trouvé dans le Bundle.")
            return
        }

        self.mapLayer = MapLayer(name: "Carte Marine Raster", localURL: url)

        // Extraction du centre et du zoom par défaut depuis le fichier SQLite (mbtiles)
        let metadata = MBTilesHelper.extractMetadata(from: url)

        if let center = metadata.center {
            self.centerCoordinate = center
        }
        if let zoom = metadata.defaultZoom {
            self.zoomLevel = zoom
        }

        // Construction dynamique du Style JSON pour MapLibre
        self.styleURL = buildStyleJSON(for: url)
    }

    /// Construit le dictionnaire de style JSON et le sauvegarde dans un fichier temporaire
    /// - Parameter url: L'URL pointant vers le fichier MBTiles local
    /// - Returns: L'URL du fichier JSON de style généré (file://...)
    private func buildStyleJSON(for url: URL) -> URL? {
        // L'URL du protocole interne MapLibre pour pointer sur le système de fichiers
        let mbtilesProtocolURL = "mbtiles://\(url.path)"

        // --- Structure du style JSON pour la carte ---
        let styleDictionary: [String: Any] = [
            "version": 8,
            "name": "LocalRasterStyle",
            // Définition des sources de données de la carte
            "sources": [
                "local-raster-source": [
                    "type": "raster",
                    "url": mbtilesProtocolURL,
                    "tileSize": 256

                    // NOTE POUR LE FUTUR (Vector Tiles - MVT) :
                    // Si vous passez à des tuiles vectorielles, changez le type en "vector" :
                    // "type": "vector",
                    // "url": "mbtiles://\(url.path)"
                ]
            ],
            // Définition des couches d'affichage (Layers)
            "layers": [
                [
                    "id": "local-raster-layer",
                    "type": "raster",
                    "source": "local-raster-source",
                    "paint": [
                        "raster-opacity": 1.0,
                        "raster-fade-duration": 0
                    ]

                    // NOTE POUR LE FUTUR (Vector Tiles - MVT) :
                    // Pour les cartes vectorielles, vous aurez plusieurs couches. Par exemple :
                    // "type": "line", "type": "fill", "type": "symbol", etc.
                    // Chacune référençant un "source-layer" spécifique du fichier MVT :
                    // "source-layer": "water",
                    // "paint": { "fill-color": "#a0cfdf" }
                ]
            ]
        ]

        // Conversion du dictionnaire en données JSON
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: styleDictionary, options: .prettyPrinted)

            // Sauvegarde dans le répertoire temporaire de l'application
            let tempDirectory = FileManager.default.temporaryDirectory
            let styleFileURL = tempDirectory.appendingPathComponent("mapstyle.json")

            try jsonData.write(to: styleFileURL)

            // On retourne l'URL locale file:// du fichier JSON généré
            return styleFileURL
        } catch {
            print("Erreur lors de la génération du style JSON : \(error.localizedDescription)")
            return nil
        }
    }
}

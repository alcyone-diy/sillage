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
        // Initialization with default values (e.g., Paris)
        self.centerCoordinate = CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)
        self.zoomLevel = 10.0

        loadMBTilesData()
    }

    private func loadMBTilesData() {
        // Search for the file in the application Bundle
        guard let url = Bundle.main.url(forResource: "7413_pal300", withExtension: "mbtiles") else {
            print("Error: The file 7413_pal300.mbtiles was not found in the Bundle.")
            return
        }

        self.mapLayer = MapLayer(name: "Marine Raster Chart", localURL: url)

        // Extraction of default center and zoom from the SQLite file (mbtiles)
        let metadata = MBTilesHelper.extractMetadata(from: url)

        if let center = metadata.center {
            self.centerCoordinate = center
        }
        if let zoom = metadata.defaultZoom {
            self.zoomLevel = zoom
        }

        // Dynamic construction of the JSON Style for MapLibre
        self.styleURL = buildStyleJSON(for: url)
    }

    /// Builds the JSON style dictionary and saves it in a temporary file
    /// - Parameter url: The URL pointing to the local MBTiles file
    /// - Returns: The URL of the generated JSON style file (file://...)
    private func buildStyleJSON(for url: URL) -> URL? {
        // The URL of the internal MapLibre protocol to point to the file system
        let mbtilesProtocolURL = "mbtiles://\(url.path)"

        // --- Structure of the map's JSON style ---
        let styleDictionary: [String: Any] = [
            "version": 8,
            "name": "LocalRasterStyle",
            // Definition of the map data sources
            "sources": [
                "local-raster-source": [
                    "type": "raster",
                    "url": mbtilesProtocolURL,
                    "tileSize": 256

                    // NOTE FOR THE FUTURE (Vector Tiles - MVT):
                    // If you switch to vector tiles, change the type to "vector":
                    // "type": "vector",
                    // "url": "mbtiles://\(url.path)"
                ]
            ],
            // Definition of display layers
            "layers": [
                [
                    "id": "local-raster-layer",
                    "type": "raster",
                    "source": "local-raster-source",
                    "paint": [
                        "raster-opacity": 1.0,
                        "raster-fade-duration": 0
                    ]

                    // NOTE FOR THE FUTURE (Vector Tiles - MVT):
                    // For vector charts, you will have several layers. For example:
                    // "type": "line", "type": "fill", "type": "symbol", etc.
                    // Each referencing a specific "source-layer" of the MVT file:
                    // "source-layer": "water",
                    // "paint": { "fill-color": "#a0cfdf" }
                ]
            ]
        ]

        // Conversion of the dictionary into JSON data
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: styleDictionary, options: .prettyPrinted)

            // Saving in the application's temporary directory
            let tempDirectory = FileManager.default.temporaryDirectory
            let styleFileURL = tempDirectory.appendingPathComponent("mapstyle.json")

            try jsonData.write(to: styleFileURL)

            // Return the local file:// URL of the generated JSON file
            return styleFileURL
        } catch {
            print("Error generating JSON style: \(error.localizedDescription)")
            return nil
        }
    }
}

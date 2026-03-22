import Foundation
import Combine
import CoreLocation
import SwiftUI

class MapViewModel: ObservableObject {

    @Published var centerCoordinate: CLLocationCoordinate2D
    @Published var zoomLevel: Double
    @Published var styleURL: URL?
    @Published var mapBounds: MBTilesBounds?
    @Published var maxZoom: Double?
    @Published var minZoom: Double?

    // UI Properties
    @Published var formattedCoordinates: String = "--"
    @Published var speedOverGround: Double = 0.0 // knots
    @Published var courseOverGround: Double = 0.0 // degrees

    private var mapLayer: MapLayer?
    private let locationService: LocationServiceProtocol
    private var cancellables = Set<AnyCancellable>()

    // Publisher to trigger a one-off camera animation to a specific location
    // We optionally pass a target zoom level if we want a specific viewport
    let moveToLocationPublisher = PassthroughSubject<(CLLocationCoordinate2D, Double?), Never>()

    // Store the last received location to center on it when requested
    private var lastKnownLocation: CLLocation?

    init(locationService: LocationServiceProtocol = LocationService()) {
        self.locationService = locationService
        // Initialization with default values (e.g., Paris)
        self.centerCoordinate = CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)
        self.zoomLevel = 10.0

        loadMBTilesData()
        setupLocationService()
    }

    private func setupLocationService() {
        locationService.locationPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                self?.handleNewLocation(location)
            }
            .store(in: &cancellables)

        locationService.requestAuthorization()
    }

    private func handleNewLocation(_ location: CLLocation) {
        lastKnownLocation = location

        // Update formatted coordinates (Degrees, Minutes, Decimals)
        let lat = formatCoordinate(location.coordinate.latitude, isLatitude: true)
        let lon = formatCoordinate(location.coordinate.longitude, isLatitude: false)
        formattedCoordinates = "\(lat) / \(lon)"

        // Update SOG (m/s to knots)
        let speed = location.speed
        if speed >= 0 {
            speedOverGround = speed * 1.94384
        }

        // Update COG
        let course = location.course
        if course >= 0 {
            courseOverGround = course
        }
    }

    private func formatCoordinate(_ degrees: CLLocationDegrees, isLatitude: Bool) -> String {
        let direction = isLatitude ? (degrees >= 0 ? "N" : "S") : (degrees >= 0 ? "E" : "W")
        let absDegrees = abs(degrees)
        let intDegrees = Int(absDegrees)
        let minutes = (absDegrees - Double(intDegrees)) * 60.0

        return String(format: "%02d°%06.3f' %@", intDegrees, minutes, direction)
    }

    func centerOnUserLocation() {
        guard let location = lastKnownLocation else { return }

        // Sending a high zoom level like 18.0, which roughly corresponds to ~50m visibility.
        // We clamp it to the map's maxZoom if available to avoid the "white screen" issue
        // caused by requesting a zoom level where no raster tiles exist.
        var targetZoom = 18.0
        if let maxZ = self.maxZoom, targetZoom > maxZ {
            targetZoom = maxZ
        }

        moveToLocationPublisher.send((location.coordinate, targetZoom))
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
        if let bounds = metadata.bounds {
            self.mapBounds = bounds
        }
        if let minZ = metadata.minZoom {
            self.minZoom = minZ
        }
        if let maxZ = metadata.maxZoom {
            self.maxZoom = maxZ
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

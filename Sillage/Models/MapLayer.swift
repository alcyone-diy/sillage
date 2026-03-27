import Foundation

enum MapSource: Equatable {
    case localMBTiles(url: URL)
    case remoteGeoGarage(clientID: String, layerID: String)
}

struct MapLayer {
    /// The displayed name or identifier of the map layer
    let name: String

    /// The map source defining where the tiles come from
    let source: MapSource
}

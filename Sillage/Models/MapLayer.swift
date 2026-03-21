import Foundation

struct MapLayer {
    /// Le nom affiché ou l'identifiant de la couche cartographique
    let name: String

    /// L'URL locale pointant vers le fichier .mbtiles
    let localURL: URL
}

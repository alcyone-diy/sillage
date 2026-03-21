import Foundation
import SQLite3
import CoreLocation

struct MBTilesMetadata {
    let center: CLLocationCoordinate2D?
    let defaultZoom: Double?
}

class MBTilesHelper {

    /// Extrait les métadonnées de la table 'metadata' d'un fichier MBTiles.
    ///
    /// - Parameter url: L'URL locale pointant vers le fichier `.mbtiles`
    /// - Returns: Une structure `MBTilesMetadata` contenant le centre et le zoom (si disponibles).
    static func extractMetadata(from url: URL) -> MBTilesMetadata {
        var db: OpaquePointer?

        // Connexion à la base de données SQLite (Read-Only)
        if sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            print("Erreur : Impossible d'ouvrir la base de données MBTiles à \(url.path)")
            return MBTilesMetadata(center: nil, defaultZoom: nil)
        }

        defer {
            if db != nil {
                sqlite3_close(db)
            }
        }

        let query = "SELECT value FROM metadata WHERE name = 'center';"
        var statement: OpaquePointer?

        var centerCoordinate: CLLocationCoordinate2D? = nil
        var defaultZoom: Double? = nil

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                if let cString = sqlite3_column_text(statement, 0) {
                    let centerString = String(cString: cString)
                    // Le format de 'center' est typiquement : "longitude,latitude,zoom"
                    let components = centerString.split(separator: ",")
                    if components.count >= 2,
                       let lon = Double(components[0]),
                       let lat = Double(components[1]) {
                        centerCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)

                        if components.count >= 3, let zoom = Double(components[2]) {
                            defaultZoom = zoom
                        }
                    }
                }
            }
        } else {
            print("Erreur : La table metadata ne contient pas la clé 'center' ou la requête a échoué.")
        }

        sqlite3_finalize(statement)

        return MBTilesMetadata(center: centerCoordinate, defaultZoom: defaultZoom)
    }
}

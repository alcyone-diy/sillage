import Foundation
import SQLite3
import CoreLocation

struct MBTilesMetadata {
    let center: CLLocationCoordinate2D?
    let defaultZoom: Double?
}

class MBTilesHelper {

    /// Extracts metadata from the 'metadata' table of an MBTiles file.
    ///
    /// - Parameter url: The local URL pointing to the `.mbtiles` file
    /// - Returns: An `MBTilesMetadata` structure containing the center and default zoom (if available).
    static func extractMetadata(from url: URL) -> MBTilesMetadata {
        var db: OpaquePointer?

        defer {
            if db != nil {
                sqlite3_close(db)
            }
        }

        // Connect to the SQLite database (Read-Only)
        if sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            print("Error: Cannot open the MBTiles database at \(url.path)")
            return MBTilesMetadata(center: nil, defaultZoom: nil)
        }

        let query = "SELECT value FROM metadata WHERE name = 'center';"
        var statement: OpaquePointer?

        var centerCoordinate: CLLocationCoordinate2D? = nil
        var defaultZoom: Double? = nil

        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                if let cString = sqlite3_column_text(statement, 0) {
                    let centerString = String(cString: cString)
                    // The 'center' format is typically: "longitude,latitude,zoom"
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
            print("Error: The metadata table does not contain the 'center' key or the query failed.")
        }

        sqlite3_finalize(statement)

        return MBTilesMetadata(center: centerCoordinate, defaultZoom: defaultZoom)
    }
}

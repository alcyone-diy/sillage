import Foundation

public enum GPXExportError: Error {
  case emptyTrack
}

public actor GPXExportService {
  private let dateFormatter: ISO8601DateFormatter

  public init() {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    self.dateFormatter = formatter
  }

  public func export(track: [TrackPoint]) throws -> String {
    guard !track.isEmpty else {
      throw GPXExportError.emptyTrack
    }

    var xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="Alcyone Sillage" xmlns="http://www.topografix.com/GPX/1/1" xmlns:sillage="http://alcyone.com/sillage/gpx">
      <trk>
        <trkseg>
    """

    for point in track {
      // Force en_US locale to use '.' instead of ',' for decimals
      let latString = String(format: "%.6f", locale: Locale(identifier: "en_US"), point.latitude)
      let lonString = String(format: "%.6f", locale: Locale(identifier: "en_US"), point.longitude)
      let timeString = dateFormatter.string(from: point.timestamp)

      xml += "\n      <trkpt lat=\"\(latString)\" lon=\"\(lonString)\">"
      xml += "\n        <time>\(timeString)</time>"

      if point.sog != nil || point.cog != nil {
        xml += "\n        <extensions>"

        if let sog = point.sog {
          let sogString = String(format: "%.2f", locale: Locale(identifier: "en_US"), sog.converted(to: .knots).value)
          xml += "\n          <sillage:sog>\(sogString)</sillage:sog>"
        }

        if let cog = point.cog {
          let cogString = String(format: "%.1f", locale: Locale(identifier: "en_US"), cog.converted(to: .degrees).value)
          xml += "\n          <sillage:cog>\(cogString)</sillage:cog>"
        }

        xml += "\n        </extensions>"
      }

      xml += "\n      </trkpt>"
    }

    xml += """

        </trkseg>
      </trk>
    </gpx>
    """

    return xml
  }
}

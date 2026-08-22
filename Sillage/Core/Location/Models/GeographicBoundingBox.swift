//
//  GeographicBoundingBox.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-25.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation

public struct GeographicBoundingBox: Sendable, Equatable, Codable {
  
  // MARK: - Properties
  
  /// (Minimums)
  public private(set) var southWest: CLLocationCoordinate2D
  /// (Maximums)
  public private(set) var northEast: CLLocationCoordinate2D

  /// The center coordinate of the geographic bounding box.
  public nonisolated var center: CLLocationCoordinate2D {
    let centerLat = (southWest.latitude + northEast.latitude) / 2.0
    let centerLon: CLLocationDegrees
    if southWest.longitude <= northEast.longitude {
      centerLon = (southWest.longitude + northEast.longitude) / 2.0
    } else {
      let rawLon = (southWest.longitude + northEast.longitude + 360.0) / 2.0
      centerLon = rawLon > 180.0 ? rawLon - 360.0 : rawLon
    }
    return CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
  }
  
  // MARK: - Initialization
  
  public nonisolated init(southWest: CLLocationCoordinate2D, northEast: CLLocationCoordinate2D) {
    self.southWest = southWest
    self.northEast = northEast
  }
  
  public nonisolated init(coordinate: CLLocationCoordinate2D) {
    self.southWest = coordinate
    self.northEast = coordinate
  }

  /// Parses a standard WKT (Well-Known Text) POLYGON string into a `GeographicBoundingBox`.
  /// Uses strict `en_US_POSIX` scanning to avoid locale-specific decimal separator bugs (e.g. French comma).
  public nonisolated init?(wkt: String) {
    guard let box = Self.fromWKT(wkt) else { return nil }
    self = box
  }
  
  // MARK: - Public
  
  public nonisolated mutating func expand(toInclude coordinate: CLLocationCoordinate2D) {
    if coordinate.latitude < southWest.latitude { southWest.latitude = coordinate.latitude }
    if coordinate.latitude > northEast.latitude { northEast.latitude = coordinate.latitude }
    
    let isInside: Bool
    if southWest.longitude <= northEast.longitude {
      isInside = (coordinate.longitude >= southWest.longitude) && (coordinate.longitude <= northEast.longitude)
    } else {
      isInside = (coordinate.longitude >= southWest.longitude) || (coordinate.longitude <= northEast.longitude)
    }
    
    if !isInside {
      let expandEast = degreesDistance(from: northEast.longitude, to: coordinate.longitude)
      let expandWest = degreesDistance(from: coordinate.longitude, to: southWest.longitude)
      
      if expandEast < expandWest {
        northEast.longitude = coordinate.longitude
      } else {
        southWest.longitude = coordinate.longitude
      }
    }
  }
  
  // MARK: - Geometry & Topology

  /// Indicates whether the bounding box crosses the international anti-meridian (-180° / +180° longitude).
  public nonisolated var crossesAntiMeridian: Bool {
    southWest.longitude > northEast.longitude
  }

  /// Returns the 5 closed polygon vertices (SW, SE, NE, NW, SW) for rendering or clipping.
  public nonisolated var polygonCoordinates: [CLLocationCoordinate2D] {
    [
      CLLocationCoordinate2D(latitude: southWest.latitude, longitude: southWest.longitude),
      CLLocationCoordinate2D(latitude: southWest.latitude, longitude: northEast.longitude),
      CLLocationCoordinate2D(latitude: northEast.latitude, longitude: northEast.longitude),
      CLLocationCoordinate2D(latitude: northEast.latitude, longitude: southWest.longitude),
      CLLocationCoordinate2D(latitude: southWest.latitude, longitude: southWest.longitude)
    ]
  }

  /// Splits an anti-meridian-crossing bounding box into two standard rectangular bounding boxes
  /// (one west of the anti-meridian extending to +180°, and one east extending from -180°).
  /// If the bounding box does not cross the anti-meridian, returns an array containing only `self`.
  public nonisolated func splitAtAntiMeridian() -> [GeographicBoundingBox] {
    guard crossesAntiMeridian else { return [self] }

    let westSegment = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: southWest.latitude, longitude: southWest.longitude),
      northEast: CLLocationCoordinate2D(latitude: northEast.latitude, longitude: 180.0)
    )

    let eastSegment = GeographicBoundingBox(
      southWest: CLLocationCoordinate2D(latitude: southWest.latitude, longitude: -180.0),
      northEast: CLLocationCoordinate2D(latitude: northEast.latitude, longitude: northEast.longitude)
    )

    return [westSegment, eastSegment]
  }

  /// Determines whether this bounding box intersects with another bounding box.
  /// Correctly evaluates multi-part boxes when crossing the anti-meridian.
  public nonisolated func intersects(_ other: GeographicBoundingBox) -> Bool {
    let selfParts = self.splitAtAntiMeridian()
    let otherParts = other.splitAtAntiMeridian()

    for s in selfParts {
      for o in otherParts {
        if s.intersectsStandard(o) {
          return true
        }
      }
    }
    return false
  }

  private nonisolated func intersectsStandard(_ other: GeographicBoundingBox) -> Bool {
    let latOverlap = max(self.southWest.latitude, other.southWest.latitude) <= min(self.northEast.latitude, other.northEast.latitude)
    let lonOverlap = max(self.southWest.longitude, other.southWest.longitude) <= min(self.northEast.longitude, other.northEast.longitude)
    return latOverlap && lonOverlap
  }

  /// Merges a collection of bounding boxes into exact, non-intersecting closed polygon contours.
  /// Overlapping and adjacent rectangles are merged into exact orthogonal boundary polygons (e.g. L-shapes)
  /// using cell decomposition rather than encompassing bounding boxes. This prevents un-downloaded regions
  /// from being falsely unmasked on marine charts.
  /// Anti-meridian crossing bounding boxes are split before merging.
  ///
  /// - Parameter boxes: The input bounding boxes to merge.
  /// - Returns: An array of closed coordinate rings (where the first coordinate equals the last coordinate),
  ///            ready to be passed directly as MapLibre / GeoJSON interior rings (holes).
  public nonisolated static func mergeIntoNonIntersectingPolygons(_ boxes: [GeographicBoundingBox]) -> [[CLLocationCoordinate2D]] {
    guard !boxes.isEmpty else { return [] }

    // 1. Normalize by splitting any anti-meridian crossing boxes into standard rectangular boxes
    let normalized = boxes.flatMap { $0.splitAtAntiMeridian() }
    guard !normalized.isEmpty else { return [] }

    if normalized.count == 1 {
      return [normalized[0].polygonCoordinates]
    }

    // 2. Extract unique sorted grid lines for X (longitude) and Y (latitude)
    var xSet = Set<CLLocationDegrees>()
    var ySet = Set<CLLocationDegrees>()

    for box in normalized {
      xSet.insert(box.southWest.longitude)
      xSet.insert(box.northEast.longitude)
      ySet.insert(box.southWest.latitude)
      ySet.insert(box.northEast.latitude)
    }

    let xCoords = xSet.sorted()
    let yCoords = ySet.sorted()

    guard xCoords.count >= 2, yCoords.count >= 2 else { return [] }

    let cols = xCoords.count - 1
    let rows = yCoords.count - 1

    // 3. Mark grid cells as occupied if their center is inside any bounding box
    var grid = Array(repeating: Array(repeating: false, count: cols), count: rows)

    for r in 0..<rows {
      let midY = (yCoords[r] + yCoords[r + 1]) / 2.0
      for c in 0..<cols {
        let midX = (xCoords[c] + xCoords[c + 1]) / 2.0
        let isOccupied = normalized.contains { box in
          midX >= box.southWest.longitude && midX <= box.northEast.longitude &&
          midY >= box.southWest.latitude && midY <= box.northEast.latitude
        }
        grid[r][c] = isOccupied
      }
    }

    // 4. Identify directed boundary segments
    struct GridPoint: Hashable {
      let c: Int
      let r: Int
    }

    var adjacency: [GridPoint: [GridPoint]] = [:]

    // Horizontal edges:
    for r in 0...rows {
      for c in 0..<cols {
        let occupiedBelow = (r > 0) ? grid[r - 1][c] : false
        let occupiedAbove = (r < rows) ? grid[r][c] : false

        if occupiedAbove != occupiedBelow {
          if occupiedAbove && !occupiedBelow {
            // Interior is North (above): direction is West to East (c -> c + 1)
            let p1 = GridPoint(c: c, r: r)
            let p2 = GridPoint(c: c + 1, r: r)
            adjacency[p1, default: []].append(p2)
          } else {
            // Interior is South (below): direction is East to West (c + 1 -> c)
            let p1 = GridPoint(c: c + 1, r: r)
            let p2 = GridPoint(c: c, r: r)
            adjacency[p1, default: []].append(p2)
          }
        }
      }
    }

    // Vertical edges:
    for c in 0...cols {
      for r in 0..<rows {
        let occupiedLeft = (c > 0) ? grid[r][c - 1] : false
        let occupiedRight = (c < cols) ? grid[r][c] : false

        if occupiedLeft != occupiedRight {
          if occupiedLeft && !occupiedRight {
            // Interior is West (left): walking South to North (r -> r + 1) keeps interior on the left
            let p1 = GridPoint(c: c, r: r)
            let p2 = GridPoint(c: c, r: r + 1)
            adjacency[p1, default: []].append(p2)
          } else {
            // Interior is East (right): walking North to South (r + 1 -> r) keeps interior on the left
            let p1 = GridPoint(c: c, r: r + 1)
            let p2 = GridPoint(c: c, r: r)
            adjacency[p1, default: []].append(p2)
          }
        }
      }
    }

    // 5. Trace closed loops from adjacency graph
    var unvisitedEdges = adjacency
    var polygons: [[CLLocationCoordinate2D]] = []

    while let startPoint = unvisitedEdges.keys.first(where: { !(unvisitedEdges[$0]?.isEmpty ?? true) }) {
      var currentLoop: [GridPoint] = [startPoint]
      var current = startPoint

      while true {
        guard var destinations = unvisitedEdges[current], !destinations.isEmpty else {
          break
        }
        let next = destinations.removeFirst()
        if destinations.isEmpty {
          unvisitedEdges.removeValue(forKey: current)
        } else {
          unvisitedEdges[current] = destinations
        }

        currentLoop.append(next)
        if next == startPoint {
          break // Loop closed
        }
        current = next
      }

      guard currentLoop.count >= 4 else { continue }

      // 6. Simplify collinear vertices: retain only orthogonal turning points (corners)
      let rawLoop = Array(currentLoop.dropLast())
      guard rawLoop.count >= 3 else { continue }

      var corners: [GridPoint] = []
      let count = rawLoop.count

      for i in 0..<count {
        let prev = rawLoop[(i - 1 + count) % count]
        let curr = rawLoop[i]
        let next = rawLoop[(i + 1) % count]

        let isHorizontalIncoming = (prev.r == curr.r)
        let isHorizontalOutgoing = (curr.r == next.r)

        if isHorizontalIncoming != isHorizontalOutgoing {
          corners.append(curr)
        }
      }

      guard corners.count >= 3 else { continue }

      // 7. Convert GridPoints to CLLocationCoordinate2D and close polygon ring
      var coordRing = corners.map { pt in
        CLLocationCoordinate2D(latitude: yCoords[pt.r], longitude: xCoords[pt.c])
      }
      coordRing.append(coordRing[0]) // Close polygon ring

      polygons.append(coordRing)
    }

    return polygons
  }
  
  /// Estimated area (approximation via Haversine for the bounding box)
  public nonisolated var estimatedArea: Measurement<UnitArea> {
    let heightPoint = CLLocation(latitude: northEast.latitude, longitude: 0)
    let swPoint = CLLocation(latitude: southWest.latitude, longitude: 0)
    let heightMeters = heightPoint.distance(from: swPoint)
    
    let centerLat = (southWest.latitude + northEast.latitude) / 2.0
    let angularWidth = (northEast.longitude - southWest.longitude + 360.0).truncatingRemainder(dividingBy: 360.0)
    let leftPoint = CLLocation(latitude: centerLat, longitude: 0)
    let rightPoint = CLLocation(latitude: centerLat, longitude: angularWidth)
    let widthMeters = leftPoint.distance(from: rightPoint)
    
    return Measurement(value: widthMeters * heightMeters, unit: UnitArea.squareMeters)
  }
  
  /// Compares two bounding boxes with a geographic epsilon tolerance to prevent infinite render loops
  /// caused by floating point precision limits when converting screen rects to map bounds.
  /// 
  /// - Parameters:
  ///   - other: The other `GeographicBoundingBox` to compare against.
  ///   - tolerance: The maximum allowed coordinate deviation (epsilon) in degrees. Defaults to `1e-6`.
  /// - Returns: `true` if all corner coordinates are within the specified tolerance; otherwise `false`.
  public nonisolated func isApproximatelyEqual(to other: GeographicBoundingBox, tolerance: CLLocationDegrees = 1e-6) -> Bool {
    return abs(southWest.latitude - other.southWest.latitude) < tolerance &&
           shortestLongitudeDelta(from: southWest.longitude, to: other.southWest.longitude) < tolerance &&
           abs(northEast.latitude - other.northEast.latitude) < tolerance &&
           shortestLongitudeDelta(from: northEast.longitude, to: other.northEast.longitude) < tolerance
  }

  /// Generates a standard WKT (Well-Known Text) POLYGON representation of the bounding box
  /// in the format `POLYGON((minLon minLat, maxLon minLat, maxLon maxLat, minLon maxLat, minLon minLat))`.
  public nonisolated func toWKT() -> String {
    let minLon = southWest.longitude
    let minLat = southWest.latitude
    let maxLon = northEast.longitude
    let maxLat = northEast.latitude
    return "POLYGON((\(minLon) \(minLat), \(maxLon) \(minLat), \(maxLon) \(maxLat), \(minLon) \(maxLat), \(minLon) \(minLat)))"
  }

  /// Parses a WKT POLYGON string into a `GeographicBoundingBox`.
  /// Uses POSIX locale to parse double values accurately regardless of user device language.
  /// Preserves native anti-meridian crossing direction from rectangular BBOX coordinate order (SW, SE, NE, NW, SW).
  public nonisolated static func fromWKT(_ wkt: String) -> GeographicBoundingBox? {
    let trimmed = wkt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.uppercased().hasPrefix("POLYGON") else { return nil }

    let scanner = Scanner(string: trimmed)
    scanner.locale = Locale(identifier: "en_US_POSIX")
    scanner.charactersToBeSkipped = CharacterSet(charactersIn: " ,()\t\n\r")

    // Position scanner at the beginning of coordinate numbers
    _ = scanner.scanUpToCharacters(from: CharacterSet(charactersIn: "-0123456789"))

    var coordinates: [CLLocationCoordinate2D] = []

    while !scanner.isAtEnd {
      guard let lon = scanner.scanDouble(),
            let lat = scanner.scanDouble() else {
        break
      }

      // Strict validation of physical geographic range
      guard lat >= -90.0 && lat <= 90.0 && lon >= -180.0 && lon <= 180.0 else {
        return nil
      }

      coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
    }

    // A standard BoundingBox WKT is a 5-point closed polygon (SW, SE, NE, NW, SW) or 4-point unclosed
    guard coordinates.count >= 4 else { return nil }

    // Directly extract SW (index 0) and NE (index 2) to preserve anti-meridian crossing direction natively
    let sw = coordinates[0]
    let ne = coordinates[2]

    return GeographicBoundingBox(southWest: sw, northEast: ne)
  }
  
  // MARK: - Private Math
  
  /// Calculates the shortest angular distance between two longitudes, accounting for the 360-degree wrap at the anti-meridian.
  private nonisolated func shortestLongitudeDelta(from lon1: CLLocationDegrees, to lon2: CLLocationDegrees) -> CLLocationDegrees {
    let delta = abs(lon1 - lon2).truncatingRemainder(dividingBy: 360.0)
    return delta > 180.0 ? 360.0 - delta : delta
  }
  
  private nonisolated func degreesDistance(from start: CLLocationDegrees, to end: CLLocationDegrees) -> CLLocationDegrees {
    var diff = end - start
    
    while diff < 0.0 {
      diff += 360.0
    }
    while diff >= 360.0 {
      diff -= 360.0
    }
    return diff
  }
}

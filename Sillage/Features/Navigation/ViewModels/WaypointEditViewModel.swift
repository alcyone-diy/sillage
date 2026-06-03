//
//  WaypointEditViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-06-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Observation
import CoreLocation

@MainActor
@Observable
public final class WaypointEditViewModel {
  public var name: String = ""
  public var description: String = ""
  public var latitudeString: String = ""
  public var longitudeString: String = ""
  
  public var activeError: Error?
  public var isSaving: Bool = false
  
  private let waypointService: WaypointService
  public let editingWaypointId: String?
  
  public init(waypointService: WaypointService, initialCoordinate: CLLocationCoordinate2D? = nil) {
    self.waypointService = waypointService
    self.editingWaypointId = nil
    if let coord = initialCoordinate {
      self.latitudeString = Self.formatDMM(degrees: coord.latitude, isLatitude: true)
      self.longitudeString = Self.formatDMM(degrees: coord.longitude, isLatitude: false)
    }
  }
  
  public init(waypointService: WaypointService, editingWaypoint: Waypoint) {
    self.waypointService = waypointService
    self.editingWaypointId = editingWaypoint.id
    self.name = editingWaypoint.name
    self.description = editingWaypoint.description ?? ""
    self.latitudeString = Self.formatDMM(degrees: editingWaypoint.latitude.converted(to: .degrees).value, isLatitude: true)
    self.longitudeString = Self.formatDMM(degrees: editingWaypoint.longitude.converted(to: .degrees).value, isLatitude: false)
  }
  
  public var isValid: Bool {
    guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
    guard let lat = parsedLatitude, lat >= -90, lat <= 90 else { return false }
    guard let lon = parsedLongitude, lon >= -180, lon <= 180 else { return false }
    return true
  }
  
  public var parsedLatitude: Double? {
    Self.parseDMM(latitudeString, isLatitude: true)
  }
  
  public var parsedLongitude: Double? {
    Self.parseDMM(longitudeString, isLatitude: false)
  }
  
  public func save() async -> Bool {
    guard isValid, let lat = parsedLatitude, let lon = parsedLongitude else { return false }
    
    isSaving = true
    defer { isSaving = false }
    
    let waypoint = Waypoint(
      id: editingWaypointId ?? UUID().uuidString,
      name: name.trimmingCharacters(in: .whitespaces),
      description: description.trimmingCharacters(in: .whitespaces).isEmpty ? nil : description.trimmingCharacters(in: .whitespaces),
      symbol: nil,
      latitude: Measurement(value: lat, unit: UnitAngle.degrees),
      longitude: Measurement(value: lon, unit: UnitAngle.degrees)
    )
    
    do {
      try await waypointService.saveWaypoint(waypoint)
      return true
    } catch {
      self.activeError = error
      return false
    }
  }
  
  // MARK: - DMM Parsing & Formatting
  
  public static func formatDMM(degrees: Double, isLatitude: Bool) -> String {
    let hemisphere: String
    if isLatitude {
      hemisphere = degrees >= 0 ? "N" : "S"
    } else {
      hemisphere = degrees >= 0 ? "E" : "W"
    }
    
    let absDegrees = abs(degrees)
    let d = floor(absDegrees)
    let m = (absDegrees - d) * 60.0
    
    let formattedMinutes = String(format: "%.3f", m)
    return "\(hemisphere) \(Int(d))° \(formattedMinutes)'"
  }
  
  public static func parseDMM(_ string: String, isLatitude: Bool) -> Double? {
    let cleanString = string.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
    
    // Support simple decimal format as fallback
    if let dec = Double(cleanString) {
        return dec
    }
    
    // Pattern: N 45° 12.345' or 45 12.345 N
    let pattern = "^([NSWE\\-])?\\s*(\\d+)[°\\s]+(\\d+\\.?\\d*)['\\s]*([NSWE])?$"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
    
    let nsRange = NSRange(cleanString.startIndex..<cleanString.endIndex, in: cleanString)
    guard let match = regex.firstMatch(in: cleanString, options: [], range: nsRange) else {
      return nil
    }
    
    var dir1 = ""
    var dir2 = ""
    
    if let r1 = Range(match.range(at: 1), in: cleanString) { dir1 = String(cleanString[r1]) }
    if let r2 = Range(match.range(at: 4), in: cleanString) { dir2 = String(cleanString[r2]) }
    
    let dir = dir1.isEmpty ? dir2 : dir1
    
    guard let rDeg = Range(match.range(at: 2), in: cleanString),
          let rMin = Range(match.range(at: 3), in: cleanString),
          let d = Double(cleanString[rDeg]),
          let m = Double(cleanString[rMin]) else {
      return nil
    }
    
    var decimal = d + (m / 60.0)
    
    if dir == "S" || dir == "W" || dir == "-" {
      decimal *= -1
    }
    
    return decimal
  }
}

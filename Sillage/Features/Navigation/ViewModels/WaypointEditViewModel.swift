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
import SwiftUI

@MainActor
@Observable
public final class WaypointEditViewModel {
  public var name: String = ""
  public var description: String = ""
  public var latHemisphere: Hemisphere = .north
  public var latDegrees: Int? = nil
  public var latMinutes: Double? = nil
  
  public var lonHemisphere: Hemisphere = .west
  public var lonDegrees: Int? = nil
  public var lonMinutes: Double? = nil
  
  public var activeError: Error?
  public var isSaving: Bool = false
  public var color: Color = MarineTheme.Colors.primary
  public var isVisible: Bool = true
  public var isEditable: Bool
  
  private let waypointService: WaypointService
  public let editingWaypointId: String?
  private let originalWaypoint: Waypoint?
  
  public init(waypointService: WaypointService, defaultName: String? = nil, initialCoordinate: CLLocationCoordinate2D? = nil) {
    self.waypointService = waypointService
    self.editingWaypointId = nil
    self.originalWaypoint = nil
    self.isEditable = true
    
    if let defaultName {
      self.name = defaultName
    } else {
      let timeString = Date.now.formatted(date: .omitted, time: .standard)
      self.name = "\(String(localized: "Waypoint")) \(timeString)"
    }
    
    if let coord = initialCoordinate {
      setCoordinate(coord, roundMinutes: true)
    }
  }
  
  public init(waypointService: WaypointService, editingWaypoint: Waypoint, startEditable: Bool = false) {
    self.waypointService = waypointService
    self.editingWaypointId = editingWaypoint.id
    self.originalWaypoint = editingWaypoint
    self.isEditable = startEditable
    self.name = editingWaypoint.name
    self.description = editingWaypoint.description ?? ""
    self.color = editingWaypoint.colorHex.flatMap { Color(hex: $0) } ?? MarineTheme.Colors.primary
    self.isVisible = editingWaypoint.isVisible
    setCoordinate(editingWaypoint.coordinate)
  }
  
  public func revert() {
    guard let original = originalWaypoint else { return }
    self.name = original.name
    self.description = original.description ?? ""
    self.color = original.colorHex.flatMap { Color(hex: $0) } ?? MarineTheme.Colors.primary
    self.isVisible = original.isVisible
    setCoordinate(original.coordinate)
    self.isEditable = false
  }
  
  private func extractDegreesAndMinutes(from value: Double, roundMinutes: Bool) -> (degrees: Int, minutes: Double) {
    let absValue = abs(value)
    var d = floor(absValue)
    let m = (absValue - d) * 60.0
    var mins = roundMinutes ? (m * 1000).rounded() / 1000.0 : m
    
    if mins >= 60.0 {
      mins -= 60.0
      d += 1.0
    }
    
    return (Int(d), mins)
  }

  private func setCoordinate(_ coordinate: CLLocationCoordinate2D, roundMinutes: Bool = false) {
    latHemisphere = coordinate.latitude >= 0 ? .north : .south
    let latComponents = extractDegreesAndMinutes(from: coordinate.latitude, roundMinutes: roundMinutes)
    latDegrees = latComponents.degrees
    latMinutes = latComponents.minutes
    
    lonHemisphere = coordinate.longitude >= 0 ? .east : .west
    let lonComponents = extractDegreesAndMinutes(from: coordinate.longitude, roundMinutes: roundMinutes)
    lonDegrees = lonComponents.degrees
    lonMinutes = lonComponents.minutes
  }
  
  public var isValid: Bool {
    guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
    guard let lat = parsedLatitude, lat >= -90, lat <= 90 else { return false }
    guard let lon = parsedLongitude, lon >= -180, lon <= 180 else { return false }
    return true
  }
  
  public var parsedLatitude: Double? {
    parseCoordinate(degrees: latDegrees, minutes: latMinutes, hemisphere: latHemisphere)
  }
  
  public var parsedLongitude: Double? {
    parseCoordinate(degrees: lonDegrees, minutes: lonMinutes, hemisphere: lonHemisphere)
  }
  
  private func parseCoordinate(degrees: Int?, minutes: Double?, hemisphere: Hemisphere) -> Double? {
    guard let d = degrees, let m = minutes else { return nil }
    guard d >= 0, m >= 0, m < 60 else { return nil }
    
    var decimal = Double(d) + (m / 60.0)
    if hemisphere == .south || hemisphere == .west {
      decimal *= -1
    }
    return decimal
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
      colorHex: color.hexString,
      isVisible: isVisible,
      coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
    )
    
    do {
      try await waypointService.saveWaypoint(waypoint)
      return true
    } catch {
      self.activeError = error
      return false
    }
  }
}

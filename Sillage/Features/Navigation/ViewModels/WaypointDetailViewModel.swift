//
//  WaypointDetailViewModel.swift
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
public final class WaypointDetailViewModel {
  public var name: String = "" {
    didSet {
      guard !isSuppressingDraftUpdates else { return }
      updateDraftWaypoint()
    }
  }
  public var description: String = ""
  
  public var trimmedDescription: String? {
    let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
  
  public var latHemisphere: Hemisphere = .north {
    didSet {
      guard !isSuppressingDraftUpdates else { return }
      exactLatitude = nil
      updateDraftWaypoint()
    }
  }
  public var latDegrees: Int? = nil {
    didSet {
      guard !isSuppressingDraftUpdates else { return }
      exactLatitude = nil
      updateDraftWaypoint()
    }
  }
  public var latMinutes: Double? = nil {
    didSet {
      guard !isSuppressingDraftUpdates else { return }
      exactLatitude = nil
      updateDraftWaypoint()
    }
  }
  
  public var lonHemisphere: Hemisphere = .west {
    didSet {
      guard !isSuppressingDraftUpdates else { return }
      exactLongitude = nil
      updateDraftWaypoint()
    }
  }
  public var lonDegrees: Int? = nil {
    didSet {
      guard !isSuppressingDraftUpdates else { return }
      exactLongitude = nil
      updateDraftWaypoint()
    }
  }
  public var lonMinutes: Double? = nil {
    didSet {
      guard !isSuppressingDraftUpdates else { return }
      exactLongitude = nil
      updateDraftWaypoint()
    }
  }
  
  public var activeError: Error?
  public var isSaving: Bool = false
  public var color: Color = Color(hex: Waypoint.defaultColorHex) ?? .blue {
    didSet {
      guard !isSuppressingDraftUpdates else { return }
      updateDraftWaypoint()
    }
  }
  public var isVisible: Bool = true {
    didSet {
      guard !isSuppressingDraftUpdates else { return }
      updateDraftWaypoint()
    }
  }
  public var isEditable: Bool
  
  public var isGoTo: Bool {
    guard let id = editingWaypointID else { return false }
    return waypointService.goToWaypointID == id
  }
  
  private let waypointService: WaypointService
  public let editingWaypointID: String?
  private var originalWaypoint: Waypoint?
  private let draftID: String?
  private var isSaved: Bool = false
  private var isSuppressingDraftUpdates: Bool = false
  private var exactLatitude: CLLocationDegrees?
  private var exactLongitude: CLLocationDegrees?
  
  public init(waypointService: WaypointService, defaultName: String? = nil, initialCoordinate: CLLocationCoordinate2D? = nil) {
    self.waypointService = waypointService
    self.editingWaypointID = nil
    self.originalWaypoint = nil
    self.draftID = UUID().uuidString
    self.isEditable = true
    self.isSuppressingDraftUpdates = true
    
    if let defaultName {
      self.name = defaultName
    } else {
      let timeString = Date.now.formatted(date: .omitted, time: .standard)
      self.name = "\(String(localized: "Waypoint")) \(timeString)"
    }
    
    if let coord = initialCoordinate {
      setCoordinate(coord, roundMinutes: true)
    }
    
    self.isSuppressingDraftUpdates = false
    updateDraftWaypoint()
  }
  
  public init(waypointService: WaypointService, editingWaypoint: Waypoint, startEditable: Bool = false) {
    self.waypointService = waypointService
    self.editingWaypointID = editingWaypoint.id
    self.originalWaypoint = editingWaypoint
    self.draftID = nil
    self.isEditable = startEditable
    self.name = editingWaypoint.name
    self.description = editingWaypoint.description ?? ""
    self.color = editingWaypoint.displayColor
    self.isVisible = editingWaypoint.isVisible
    setCoordinate(editingWaypoint.coordinate)
  }
  
  public func revert() {
    guard let original = originalWaypoint else { return }
    self.name = original.name
    self.description = original.description ?? ""
    self.color = original.displayColor
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
    let wasSuppressing = isSuppressingDraftUpdates
    isSuppressingDraftUpdates = true
    defer {
      isSuppressingDraftUpdates = wasSuppressing
      if !wasSuppressing {
        updateDraftWaypoint()
      }
    }
    exactLatitude = coordinate.latitude
    exactLongitude = coordinate.longitude
    
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
  
  private func updateDraftWaypoint() {
    guard !isSuppressingDraftUpdates else { return }
    guard editingWaypointID == nil, let draftID else { return }
    
    guard let lat = exactLatitude ?? parsedLatitude,
          let lon = exactLongitude ?? parsedLongitude else {
      waypointService.setDraftWaypoint(nil)
      return
    }
    
    let draft = Waypoint(
      id: draftID,
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      description: trimmedDescription,
      symbol: nil,
      colorHex: color.hexString,
      isVisible: isVisible,
      coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
    )
    waypointService.setDraftWaypoint(draft)
  }

  public func cancelDraft() {
    guard editingWaypointID == nil, !isSaved else { return }
    waypointService.setDraftWaypoint(nil)
  }
  
  public func save() async -> Bool {
    guard isValid,
          let lat = exactLatitude ?? parsedLatitude,
          let lon = exactLongitude ?? parsedLongitude else { return false }
    
    isSaving = true
    defer { isSaving = false }
    
    let targetID = editingWaypointID ?? draftID ?? UUID().uuidString
    let waypoint = Waypoint(
      id: targetID,
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      description: trimmedDescription,
      symbol: nil,
      colorHex: color.hexString,
      isVisible: isVisible,
      coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
    )
    
    do {
      try await waypointService.saveWaypoint(waypoint)
      isSaved = true
      self.originalWaypoint = waypoint
      if editingWaypointID == nil {
        waypointService.setDraftWaypoint(nil)
      }
      return true
    } catch {
      self.activeError = error
      return false
    }
  }

  public func delete() async -> Bool {
    guard let id = editingWaypointID else { return false }
    
    isSaving = true
    defer { isSaving = false }
    
    do {
      try await waypointService.deleteWaypoint(id: id)
      return true
    } catch {
      self.activeError = error
      return false
    }
  }
}

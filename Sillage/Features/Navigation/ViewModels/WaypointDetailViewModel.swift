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
  public var isEditable: Bool {
    didSet {
      guard isEditable != oldValue else { return }
      if isEditable {
        visibilitySaveGeneration &+= 1
        visibilitySaveTask?.cancel()
        visibilitySaveTask = nil
      }
      guard !isSuppressingDraftUpdates else { return }
      onStateChanged?()
    }
  }
  
  public var isGoTo: Bool {
    guard let id = editingWaypointID else { return false }
    return activeNavigationService?.goToWaypointID == id
  }
  
  // MARK: - Point Information (Ephemeris & Magnetism)
  
  public var sunEphemeris: SunEphemeris? = nil
  public var magneticDeclination: Measurement<UnitAngle>? = nil
  public var isPointInfoLoading: Bool = false
  public private(set) var pointInfoDate: Date? = nil

  /// Dynamic conversion instruction for the magnetic declination section footer.
  public var magneticDeclinationFooterText: String? {
    magneticDeclination?.marineDeclinationConversionFooter
  }
  
  private let waypointService: WaypointService
  private let activeNavigationService: ActiveNavigationService?
  private let astronomicalService: AstronomicalService
  private let magneticDeclinationService: MagneticDeclinationService
  private var pointInfoLoadGeneration: UInt64 = 0
  private var visibilitySaveGeneration: UInt64 = 0
  private var visibilitySaveTask: Task<Void, Never>?
  public let editingWaypointID: String?
  private var originalWaypoint: Waypoint?
  private let draftID: String?
  private var isSaved: Bool = false
  private var isSuppressingDraftUpdates: Bool = false
  private var exactLatitude: CLLocationDegrees?
  private var exactLongitude: CLLocationDegrees?
  
  @ObservationIgnored
  public var onStateChanged: (@MainActor () -> Void)?

  @ObservationIgnored
  internal var persistWaypointHandler: (@MainActor (Waypoint) async throws -> Void)?
  
  public init(
    waypointService: WaypointService,
    defaultName: String? = nil,
    initialCoordinate: CLLocationCoordinate2D? = nil,
    astronomicalService: AstronomicalService = AstronomicalService(),
    magneticDeclinationService: MagneticDeclinationService = MagneticDeclinationService()
  ) {
    self.waypointService = waypointService
    self.activeNavigationService = nil
    self.astronomicalService = astronomicalService
    self.magneticDeclinationService = magneticDeclinationService
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
  
  public init(
    waypointService: WaypointService,
    activeNavigationService: ActiveNavigationService,
    editingWaypoint: Waypoint,
    startEditable: Bool = false,
    astronomicalService: AstronomicalService = AstronomicalService(),
    magneticDeclinationService: MagneticDeclinationService = MagneticDeclinationService()
  ) {
    self.waypointService = waypointService
    self.activeNavigationService = activeNavigationService
    self.astronomicalService = astronomicalService
    self.magneticDeclinationService = magneticDeclinationService
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
    visibilitySaveGeneration &+= 1
    visibilitySaveTask?.cancel()
    visibilitySaveTask = nil
    let wasSuppressing = isSuppressingDraftUpdates
    isSuppressingDraftUpdates = true
    defer {
      isSuppressingDraftUpdates = wasSuppressing
      if !wasSuppressing {
        updateDraftWaypoint()
      }
    }
    self.name = original.name
    self.description = original.description ?? ""
    self.color = original.displayColor
    self.isVisible = original.isVisible
    setCoordinate(original.coordinate)
    self.isEditable = false
  }

  public func setVisible(_ newValue: Bool) {
    guard isVisible != newValue else { return }
    isVisible = newValue

    guard !isEditable, let original = originalWaypoint else { return }

    visibilitySaveGeneration &+= 1
    let currentGeneration = visibilitySaveGeneration
    let previousTask = visibilitySaveTask
    previousTask?.cancel()

    let updatedWaypoint = Waypoint(
      id: original.id,
      name: original.name,
      description: original.description,
      symbol: original.symbol,
      colorHex: original.colorHex,
      isVisible: newValue,
      coordinate: original.coordinate,
      timestamp: original.timestamp
    )

    visibilitySaveTask = Task { [weak self] in
      await previousTask?.value
      guard let self, !Task.isCancelled, self.visibilitySaveGeneration == currentGeneration else { return }
      do {
        if let handler = self.persistWaypointHandler {
          try await handler(updatedWaypoint)
        } else {
          try await self.waypointService.saveWaypoint(updatedWaypoint)
        }
        guard !Task.isCancelled, self.visibilitySaveGeneration == currentGeneration else { return }
        self.originalWaypoint = updatedWaypoint
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled, self.visibilitySaveGeneration == currentGeneration else { return }
        self.isVisible = self.originalWaypoint?.isVisible ?? original.isVisible
        self.activeError = error
      }
    }
  }

  internal func waitForPendingVisibilitySave() async {
    await visibilitySaveTask?.value
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

  public var currentCoordinate: CLLocationCoordinate2D? {
    guard let lat = exactLatitude ?? parsedLatitude,
          let lon = exactLongitude ?? parsedLongitude else { return nil }
    let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
    guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
    return coordinate
  }

  public func updateCoordinate(_ coordinate: CLLocationCoordinate2D) {
    setCoordinate(coordinate, roundMinutes: false)
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
    guard let lat = parsedLatitude,
          let lon = parsedLongitude else { return false }
    return CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lon))
  }
  
  public var parsedLatitude: Double? {
    parseCoordinate(degrees: latDegrees, minutes: latMinutes, hemisphere: latHemisphere, maxDegrees: 90)
  }
  
  public var parsedLongitude: Double? {
    parseCoordinate(degrees: lonDegrees, minutes: lonMinutes, hemisphere: lonHemisphere, maxDegrees: 180)
  }
  
  private func parseCoordinate(
    degrees: Int?,
    minutes: Double?,
    hemisphere: Hemisphere,
    maxDegrees: Double
  ) -> Double? {
    guard let d = degrees, let m = minutes else { return nil }
    guard d >= 0, m.isFinite, m >= 0, m < 60 else { return nil }
    
    var decimal = Double(d) + (m / 60.0)
    guard decimal.isFinite, decimal <= maxDegrees else { return nil }
    if hemisphere == .south || hemisphere == .west {
      decimal *= -1
    }
    return decimal
  }
  
  private func updateDraftWaypoint() {
    guard !isSuppressingDraftUpdates else { return }
    
    if editingWaypointID == nil, let draftID {
      guard let coordinate = currentCoordinate else {
        waypointService.setDraftWaypoint(nil)
        onStateChanged?()
        return
      }
      
      let draft = Waypoint(
        id: draftID,
        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
        description: trimmedDescription,
        symbol: nil,
        colorHex: color.hexString,
        isVisible: isVisible,
        coordinate: coordinate
      )
      waypointService.setDraftWaypoint(draft)
    }
    
    onStateChanged?()
  }

  public func cancelDraft() {
    guard editingWaypointID == nil, !isSaved else { return }
    waypointService.setDraftWaypoint(nil)
  }
  
  public func save() async -> Bool {
    guard isValid,
          let coordinate = currentCoordinate else { return false }
    
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
      coordinate: coordinate
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

  /// Loads astronomical ephemeris and magnetic declination in parallel for the current waypoint coordinate.
  public func loadPointInformation(for date: Date = Date()) async {
    pointInfoLoadGeneration &+= 1
    let currentGeneration = pointInfoLoadGeneration

    guard let coordinate = currentCoordinate,
          CLLocationCoordinate2DIsValid(coordinate) else {
      sunEphemeris = nil
      magneticDeclination = nil
      pointInfoDate = nil
      isPointInfoLoading = false
      return
    }

    pointInfoDate = date
    sunEphemeris = nil
    magneticDeclination = nil
    isPointInfoLoading = true

    let astroService = self.astronomicalService
    let magService = self.magneticDeclinationService

    async let ephemeris = astroService.calculateEphemeris(
      for: coordinate,
      date: date,
      timeZone: .current
    )
    async let declination = magService.calculateDeclination(for: coordinate, date: date)

    let (ephemResult, declResult) = await (ephemeris, declination)

    guard self.pointInfoLoadGeneration == currentGeneration else { return }
    guard !Task.isCancelled else {
      self.isPointInfoLoading = false
      return
    }
    self.sunEphemeris = ephemResult
    self.magneticDeclination = declResult
    self.isPointInfoLoading = false
  }
}

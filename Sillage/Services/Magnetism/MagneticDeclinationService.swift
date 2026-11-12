//
//  MagneticDeclinationService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-11.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreLocation
import OSLog

/// Actor responsible for calculating geomagnetic declination (WMM - World Magnetic Model)
/// for any geographic location and date.
/// - Important: Must never rely on Apple's `CoreLocation.CLHeading` or hardware compass.
///   Returns strict physical `Measurement<UnitAngle>` or `nil` on invalid state.
public actor MagneticDeclinationService {

  private let bundle: Bundle?
  private let customFileURL: URL?
  private var isModelLoaded: Bool = false
  private var model: WorldMagneticModel? = nil

  public init(bundle: Bundle = .main) {
    self.bundle = bundle
    self.customFileURL = nil
  }

  public init(fileURL: URL) {
    self.bundle = nil
    self.customFileURL = fileURL
  }

  public init(model: WorldMagneticModel) {
    self.bundle = nil
    self.customFileURL = nil
    self.model = model
    self.isModelLoaded = true
  }

  /// Calculates the decimal year for a given date (e.g. 2026.865).
  /// Accurately takes leap years into account.
  public static func decimalYear(
    from date: Date,
    calendar: Calendar = Calendar(identifier: .gregorian)
  ) -> Double? {
    guard let year = calendar.dateComponents([.year], from: date).year,
          let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1, hour: 0, minute: 0, second: 0)),
          let startOfNextYear = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1, hour: 0, minute: 0, second: 0)) else {
      return nil
    }

    let yearDuration = startOfNextYear.timeIntervalSince(startOfYear)
    guard yearDuration > 0 else { return nil }
    let elapsed = date.timeIntervalSince(startOfYear)
    return Double(year) + (elapsed / yearDuration)
  }

  /// Calculates the magnetic declination for a given location, date, and altitude.
  /// - Parameters:
  ///   - coordinate: The geographical coordinate (`CLLocationCoordinate2D`).
  ///   - date: The date for which the geomagnetic model is evaluated. Defaults to current date.
  ///   - altitudeMeters: Altitude in meters above the WGS-84 ellipsoid (defaults to 0.0 for sea level).
  /// - Returns: The magnetic declination as a `Measurement<UnitAngle>`, positive for East declination,
  ///   negative for West declination, or `nil` if the coordinate is invalid, model file is missing,
  ///   or calculation fails.
  /// - Note: Never returns dummy `0.0` or `-1.0` on failure.
  public func calculateDeclination(
    for coordinate: CLLocationCoordinate2D,
    date: Date = Date(),
    altitudeMeters: Double = 0.0
  ) async -> Measurement<UnitAngle>? {
    guard CLLocationCoordinate2DIsValid(coordinate) else {
      return nil
    }

    guard let decimalYear = Self.decimalYear(from: date) else {
      Logger.navigation.error("Failed to compute decimal year from date \(date, privacy: .public)")
      return nil
    }

    guard let model = await loadModelIfNeeded() else {
      // Model file WMM.COF is absent or failed to load. Safely return nil.
      return nil
    }

    guard let declinationDegrees = model.calculateDeclination(
      latitudeDegrees: coordinate.latitude,
      longitudeDegrees: coordinate.longitude,
      altitudeMeters: altitudeMeters,
      decimalYear: decimalYear
    ) else {
      Logger.navigation.error("Geomagnetic calculation failed for coordinate: \(coordinate.latitude, privacy: .public), \(coordinate.longitude, privacy: .public)")
      return nil
    }

    return Measurement(value: declinationDegrees, unit: UnitAngle.degrees)
  }

  /// Convenience alias matching standard marine declination terminology.
  public func declination(
    for coordinate: CLLocationCoordinate2D,
    date: Date = Date(),
    altitudeMeters: Double = 0.0
  ) async -> Measurement<UnitAngle>? {
    await calculateDeclination(for: coordinate, date: date, altitudeMeters: altitudeMeters)
  }

  // MARK: - Model Loading

  private func loadModelIfNeeded() async -> WorldMagneticModel? {
    if isModelLoaded {
      return model
    }

    isModelLoaded = true

    let targetURL: URL?
    if let customFileURL {
      targetURL = customFileURL
    } else if let bundle {
      targetURL = bundle.url(forResource: "WMM", withExtension: "COF")
    } else {
      targetURL = Bundle.main.url(forResource: "WMM", withExtension: "COF")
    }

    guard let fileURL = targetURL else {
      Logger.navigation.warning("Geomagnetic model file WMM.COF not found. Returning nil.")
      return nil
    }

    do {
      let content = try String(contentsOf: fileURL, encoding: .utf8)
      let parsedModel = try WorldMagneticModel.parse(content: content)
      self.model = parsedModel
      Logger.navigation.info("Successfully loaded WMM model: \(parsedModel.modelName, privacy: .public) (epoch \(parsedModel.epoch, privacy: .public))")
      return parsedModel
    } catch {
      Logger.navigation.error("Failed to parse WMM.COF at \(fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }
}

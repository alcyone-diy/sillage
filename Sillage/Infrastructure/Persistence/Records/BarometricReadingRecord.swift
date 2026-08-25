//
//  BarometricReadingRecord.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-25.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import GRDB

/// GRDB Persistence Model for Barometric Reading.
/// Conforms strictly to `FetchableRecord`, `PersistableRecord`, and `Sendable` (NOT `Codable`).
public struct BarometricReadingRecord: FetchableRecord, PersistableRecord, Sendable, Equatable {
  public var id: Int64?
  public var timestampUnix: Double
  public var pressureHPa: Double

  public static let databaseTableName = "barometric_reading"

  public init(
    id: Int64? = nil,
    timestamp: Date,
    pressure: Measurement<UnitPressure>
  ) {
    self.id = id
    self.timestampUnix = timestamp.timeIntervalSince1970
    self.pressureHPa = pressure.converted(to: .hectopascals).value
  }

  public init(
    id: Int64? = nil,
    timestampUnix: Double,
    pressureHPa: Double
  ) {
    self.id = id
    self.timestampUnix = timestampUnix
    self.pressureHPa = pressureHPa
  }

  // MARK: - GRDB Column Definitions

  public enum Columns: String, ColumnExpression {
    case id
    case timestampUnix = "timestamp_unix"
    case pressureHPa = "pressure_hpa"
  }

  // MARK: - GRDB Custom Row Mapping (FetchableRecord & PersistableRecord)

  public init(row: Row) throws {
    self.id = row[Columns.id]
    self.timestampUnix = row[Columns.timestampUnix]
    self.pressureHPa = row[Columns.pressureHPa]
  }

  public func encode(to container: inout PersistenceContainer) throws {
    container[Columns.id] = id
    container[Columns.timestampUnix] = timestampUnix
    container[Columns.pressureHPa] = pressureHPa
  }

  public mutating func didInsert(_ inserted: InsertionSuccess) {
    id = inserted.rowID
  }
}

// MARK: - Domain Mapping

extension BarometricReadingRecord {
  /// Converts the domain `BarometricReading` into a persistence `BarometricReadingRecord`.
  public init(domainModel: BarometricReading) {
    self.init(
      id: nil,
      timestamp: domainModel.timestamp,
      pressure: domainModel.pressure
    )
  }

  /// Converts the persistence `BarometricReadingRecord` into a domain `BarometricReading`.
  public var domainModel: BarometricReading {
    BarometricReading(
      timestamp: Date(timeIntervalSince1970: timestampUnix),
      pressure: Measurement(value: pressureHPa, unit: .hectopascals)
    )
  }
}

//
//  DiskSpaceProvider.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-17.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import OSLog

/// Protocol abstracting device storage queries for testability and domain decoupling.
public protocol DiskSpaceProviderProtocol: Sendable {
  /// Returns the available storage capacity on the device filesystem.
  /// Uses Foundation.Measurement to enforce strict physical units.
  func availableDiskSpace() -> Measurement<UnitInformationStorage>?
}

/// Production implementation of `DiskSpaceProviderProtocol` querying iOS volume capacity.
nonisolated public final class SystemDiskSpaceProvider: DiskSpaceProviderProtocol, Sendable {

  public nonisolated init() {}

  public nonisolated func availableDiskSpace() -> Measurement<UnitInformationStorage>? {
    guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
      return nil
    }

    do {
      let values = try documentsURL.resourceValues(forKeys: [
        .volumeAvailableCapacityForImportantUsageKey,
        .volumeAvailableCapacityKey
      ])

      return Self.resolveAvailableSpace(
        importantUsageBytes: values.volumeAvailableCapacityForImportantUsage,
        regularBytes: values.volumeAvailableCapacity
      )
    } catch {
      Logger.storage.error("Failed to query available volume storage: \(error.localizedDescription, privacy: .public)")
    }

    return nil
  }

  internal nonisolated static func resolveAvailableSpace(
    importantUsageBytes: Int64?,
    regularBytes: Int?
  ) -> Measurement<UnitInformationStorage>? {
    if let important = importantUsageBytes, important > 0 {
      return Measurement(value: Double(important), unit: .bytes)
    } else if let regular = regularBytes, regular > 0 {
      return Measurement(value: Double(regular), unit: .bytes)
    } else if importantUsageBytes == 0 || regularBytes == 0 {
      return Measurement(value: 0, unit: .bytes)
    }
    return nil
  }
}

//
//  BarometricHistoryStore.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import OSLog

/// Actor responsible for thread-safe storage and persistence of barometric history.
/// It acts as a circular buffer, maintaining readings up to a specified maximum duration.
public actor BarometricHistoryStore {
  
  private var buffer: [BarometricReading] = []
  private let fileURL: URL
  private let maxHistoryDuration: TimeInterval
  
  /// Instant, memory-only initialization.
  /// Call `load()` after initialization to populate the history from disk.
  /// - Parameters:
  ///   - fileURL: The URL where the JSON history is stored. Defaults to `barometric_history.json` in the documents directory.
  ///   - maxHistoryDuration: The maximum duration of data to retain (defaults to 48 hours).
  public init(
    fileURL: URL = URL.documentsDirectory.appendingPathComponent("barometric_history.json"),
    maxHistoryDuration: TimeInterval = 48 * 3600
  ) {
    self.fileURL = fileURL
    self.maxHistoryDuration = maxHistoryDuration
  }
  
  /// Loads the history from disk asynchronously using a detached task.
  /// This should be called once during app startup (e.g. from AppEnvironment).
  public func load() async {
    let url = fileURL
    let loadedBuffer = await Task.detached(priority: .background) {
      guard FileManager.default.fileExists(atPath: url.path) else { return [BarometricReading]() }
      do {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([BarometricReading].self, from: data)
      } catch {
        Logger.barometer.error("Failed to load barometric history from disk: \(error.localizedDescription, privacy: .public)")
        return []
      }
    }.value
    
    self.buffer = loadedBuffer
    self.pruneBuffer()
  }
  
  /// Adds a new reading to the buffer and persists the updated buffer to disk in the background.
  /// - Parameter reading: The new `BarometricReading` to add.
  public func add(reading: BarometricReading) {
    buffer.append(reading)
    pruneBuffer()
    
    let snapshot = buffer
    let url = fileURL
    
    // Detached task ensures that writing to disk does not block the actor's execution queue
    Task.detached(priority: .background) {
      do {
        let encoder = JSONEncoder()
        let data = try encoder.encode(snapshot)
        // Atomic write prevents file corruption if the app is killed during the write process
        try data.write(to: url, options: .atomic)
      } catch {
        Logger.barometer.error("Failed to write barometric history to disk: \(error.localizedDescription, privacy: .public)")
      }
    }
  }
  
  /// Retrieves all readings recorded within the specified number of past hours.
  /// - Parameter lastHours: The number of hours to look back.
  /// - Returns: An array of `BarometricReading` matching the timeframe.
  public func getReadings(for lastHours: Int) -> [BarometricReading] {
    let cutoffDate = Date.now.addingTimeInterval(-Double(lastHours) * 3600)
    return buffer.filter { $0.timestamp >= cutoffDate }
  }
  
  /// Removes readings that are older than the maximum allowed history duration.
  private func pruneBuffer() {
    let cutoff = Date.now.addingTimeInterval(-maxHistoryDuration)
    buffer = buffer.filter { $0.timestamp >= cutoff }
  }
}

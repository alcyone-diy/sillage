//
//  ChartStorageService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

public actor ChartStorageService {
  public init() {}

  /// Discovers MBTiles files located in the app's Documents/Charts directory.
  /// - Returns: An array of `MBTileFile` containing file metadata.
  /// - Throws: An error if the documents directory cannot be accessed or if reading fails.
  public func discoverMBTiles() async throws -> [MBTileFile] {
    let fileManager = FileManager.default
    
    guard let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
      throw NSError(domain: "ChartStorageService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Documents directory not found."])
    }
    
    let chartsDirectory = documentsDirectory.appendingPathComponent("Charts")
    
    // Ensure the directory exists. Does not throw if it already exists due to withIntermediateDirectories: true.
    try fileManager.createDirectory(at: chartsDirectory, withIntermediateDirectories: true, attributes: nil)
    
    // Fetch directory contents, pre-fetching file size attributes to optimize disk I/O.
    let files = try fileManager.contentsOfDirectory(at: chartsDirectory, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles)
    
    return files.compactMap { fileURL in
      // Filter only .mbtiles files
      guard fileURL.pathExtension.lowercased() == "mbtiles" else { return nil }
      
      var fileSizeMeasurement: Measurement<UnitInformationStorage>? = nil
      
      // Retrieve the pre-fetched file size
      if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
         let fileSizeInBytes = resourceValues.fileSize {
        fileSizeMeasurement = Measurement(value: Double(fileSizeInBytes), unit: .bytes)
      }
      
      return MBTileFile(filename: fileURL.lastPathComponent, fileURL: fileURL, fileSize: fileSizeMeasurement)
    }
  }

  /// Creates an asynchronous stream that emits the list of MBTiles files whenever the directory changes.
  /// - Returns: An `AsyncStream` yielding arrays of `MBTileFile`.
  public func observeMBTilesDirectory() -> AsyncStream<[MBTileFile]> {
    AsyncStream { continuation in
      guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
        continuation.finish()
        return
      }
      
      let chartsDirectory = documentsDirectory.appendingPathComponent("Charts")
      
      // Ensure the directory exists before observing it.
      try? FileManager.default.createDirectory(at: chartsDirectory, withIntermediateDirectories: true, attributes: nil)
      
      // Open a read-only file descriptor to monitor directory events.
      let fileDescriptor = open(chartsDirectory.path, O_EVTONLY)
      guard fileDescriptor != -1 else {
        continuation.finish()
        return
      }
      
      // Create a dispatch source to monitor file system writes (additions, deletions, modifications).
      let dispatchSource = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: fileDescriptor,
        eventMask: .write,
        queue: DispatchQueue.global(qos: .background)
      )
      
      // Define the handler triggered on directory changes.
      dispatchSource.setEventHandler {
        Task {
          do {
            let updatedFiles = try await self.discoverMBTiles()
            continuation.yield(updatedFiles)
          } catch {
            print("Error reading files during observation: \(error)")
          }
        }
      }
      
      // IMPORTANT: Close the file descriptor when the observer is cancelled to prevent memory/resource leaks.
      dispatchSource.setCancelHandler {
        close(fileDescriptor)
      }
      
      // Handle cancellation from the consumer side (e.g., when the UI view disappears).
      continuation.onTermination = { @Sendable _ in
        dispatchSource.cancel()
      }
      
      // Start the observer.
      dispatchSource.resume()
      
      // Emit the initial state immediately.
      Task {
        if let initialFiles = try? await self.discoverMBTiles() {
          continuation.yield(initialFiles)
        }
      }
    }
  }
}

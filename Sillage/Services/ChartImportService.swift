//
//  ChartImportService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

final class ChartImportService {

  func handleIncomingURL(_ url: URL) throws {
    guard url.isFileURL else {
      throw ChartImportError.notAFile
    }

    let isSecurityScoped = url.startAccessingSecurityScopedResource()

    // Ensure we clean up Inbox file regardless of success/failure, and stop accessing security scoped resource
    defer {
      if isSecurityScoped {
        url.stopAccessingSecurityScopedResource()
      }

      // Attempt to delete original file (inbox) if it still exists
      if FileManager.default.fileExists(atPath: url.path) {
        do {
          try FileManager.default.removeItem(at: url)
          #if DEBUG
          print("Successfully cleaned up inbox file at \(url)")
          #endif
        } catch {
          #if DEBUG
          print("Failed to clean up inbox file at \(url): \(error)")
          #endif
        }
      }
    }

    let fileManager = FileManager.default

    // Construct destination in Documents/Charts
    guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
      throw ChartImportError.destinationCreationFailed
    }

    let chartsDir = documentsDir.appendingPathComponent("Charts")

    // Ensure Charts directory exists
    if !fileManager.fileExists(atPath: chartsDir.path) {
      do {
        try fileManager.createDirectory(at: chartsDir, withIntermediateDirectories: true, attributes: nil)
      } catch {
        throw ChartImportError.destinationCreationFailed
      }
    }

    let originalFilename = url.lastPathComponent
    let fileExtension = url.pathExtension
    let filenameWithoutExtension = url.deletingPathExtension().lastPathComponent

    var destinationURL = chartsDir.appendingPathComponent(originalFilename)

    // Sequential suffix conflict resolution
    var suffix = 1
    while fileManager.fileExists(atPath: destinationURL.path) {
      let newFilename = "\(filenameWithoutExtension)_\(suffix).\(fileExtension)"
      destinationURL = chartsDir.appendingPathComponent(newFilename)
      suffix += 1
    }

    do {
      try fileManager.moveItem(at: url, to: destinationURL)
      #if DEBUG
      print("Successfully moved chart to \(destinationURL)")
      #endif
    } catch {
      throw ChartImportError.moveFailed(error)
    }
  }
}

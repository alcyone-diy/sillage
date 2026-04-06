//
//  LocalMapManager.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

actor LocalMapManager {
  static let shared = LocalMapManager()

  private let fileManager = FileManager.default

  private var documentsDirectory: URL {
    fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
  }

  func fetchLocalMaps() -> [URL] {
    do {
      let urls = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
      return urls.filter { $0.pathExtension == "mbtiles" }
    } catch {
      print("Error fetching local maps: \(error)")
      return []
    }
  }

  func importMap(from sourceURL: URL) throws -> URL {
    // Start accessing the security-scoped resource
    guard sourceURL.startAccessingSecurityScopedResource() else {
      throw LocalMapError.securityAccessFailed
    }

    // Ensure we stop accessing the resource when we exit this scope
    defer { sourceURL.stopAccessingSecurityScopedResource() }

    let originalFileName = sourceURL.lastPathComponent
    var destinationURL = documentsDirectory.appendingPathComponent(originalFileName)

    // Handle naming collisions
    var fileCount = 1
    let nameWithoutExtension = sourceURL.deletingPathExtension().lastPathComponent
    let fileExtension = sourceURL.pathExtension

    while fileManager.fileExists(atPath: destinationURL.path) {
      let newFileName = "\(nameWithoutExtension)_\(fileCount).\(fileExtension)"
      destinationURL = documentsDirectory.appendingPathComponent(newFileName)
      fileCount += 1
    }

    do {
      try fileManager.copyItem(at: sourceURL, to: destinationURL)
      return destinationURL
    } catch {
      throw LocalMapError.copyFailed(error)
    }
  }
}

enum LocalMapError: Error, LocalizedError {
  case securityAccessFailed
  case copyFailed(Error)

  var errorDescription: String? {
    switch self {
    case .securityAccessFailed:
      return "Failed to access the file securely."
    case .copyFailed(let error):
      return "Failed to copy the file: \(error.localizedDescription)"
    }
  }
}

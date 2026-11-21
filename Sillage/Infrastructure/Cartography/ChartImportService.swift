//
//  ChartImportService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import OSLog

final class ChartImportService {
  private let chartStorageService: ChartStorageService

  init(chartStorageService: ChartStorageService = ChartStorageService()) {
    self.chartStorageService = chartStorageService
  }

  func handleIncomingURL(_ url: URL) async throws {
    guard url.isFileURL else {
      throw ChartImportError.notAFile
    }

    let fileManager = FileManager.default
    let isSecurityScoped = url.startAccessingSecurityScopedResource()

    guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
      if isSecurityScoped {
        url.stopAccessingSecurityScopedResource()
      }
      throw ChartImportError.destinationCreationFailed
    }

    let inboxDir = documentsDir.appendingPathComponent("Inbox").standardizedFileURL
    let standardizedSource = url.standardizedFileURL
    let isFromInbox = standardizedSource.path.hasPrefix(inboxDir.path + "/")

    // Clean up Inbox file before revoking security-scoped access; never delete external open-in-place files.
    defer {
      if isFromInbox && fileManager.fileExists(atPath: url.path) {
        do {
          try fileManager.removeItem(at: url)
          Logger.storage.debug("Successfully cleaned up inbox file at \(url, privacy: .public)")
        } catch {
          Logger.storage.error("Failed to clean up inbox file at \(url, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
      }

      if isSecurityScoped {
        url.stopAccessingSecurityScopedResource()
      }
    }

    do {
      let destinationURL = try await chartStorageService.importChart(from: url)
      Logger.storage.debug("Successfully imported chart to \(destinationURL, privacy: .public)")
    } catch {
      throw ChartImportError.moveFailed(error)
    }
  }
}

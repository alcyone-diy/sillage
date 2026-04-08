//
//  ChartImportError.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

enum ChartImportError: Error, LocalizedError {
  case notAFile
  case securityAccessFailed
  case destinationCreationFailed
  case moveFailed(Error)
  case deleteOriginalFailed(Error) // usually we don't throw for failing to delete original if move succeeds, but defining it just in case

  var errorDescription: String? {
    switch self {
    case .notAFile:
      return String(localized: "The provided URL is not a valid file.")
    case .securityAccessFailed:
      return String(localized: "Failed to access the file securely.")
    case .destinationCreationFailed:
      return String(localized: "Could not create the Charts directory.")
    case .moveFailed(let error):
      return String(localized: "Failed to move the chart file: \(error.localizedDescription)")
    case .deleteOriginalFailed(let error):
      return String(localized: "Import succeeded, but failed to clean up the original file: \(error.localizedDescription)")
    }
  }
}

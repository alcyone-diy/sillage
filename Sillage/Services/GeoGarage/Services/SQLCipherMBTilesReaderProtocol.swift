//
//  SQLCipherMBTilesReaderProtocol.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-16.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Protocol defining the interface for reading encrypted MBTiles tile archives using SQLCipher in RAM.
protocol SQLCipherMBTilesReaderProtocol: Sendable {
  /// Retrieves the decrypted raw raster tile bytes for XYZ tile coordinates (internally converting to TMS).
  /// - Parameters:
  ///   - z: Zoom level.
  ///   - x: Tile column (XYZ format).
  ///   - y: Tile row (XYZ format).
  /// - Returns: Decrypted tile data (PNG/JPEG) if found, or `nil` if tile does not exist.
  func tile(z: Int, x: Int, y: Int) async -> Data?

  /// Closes database connection and frees prepared statements.
  func close() async
}

//
//  LocalTileServerProtocol.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-16.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Protocol defining the local loopback HTTP tile server serving decrypted MBTiles in RAM to MapLibre.
protocol LocalTileServerProtocol: Sendable {
  /// Starts the local HTTP listener on loopback `127.0.0.1` and returns the bound TCP port.
  func start() async throws -> UInt16

  /// Stops the local server, closes all active connections and frees reader resources.
  func stop() async
}

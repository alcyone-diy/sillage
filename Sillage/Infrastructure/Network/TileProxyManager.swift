//
//  TileProxyManager.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreGraphics
import OSLog

/// Protocol for network tile downloading with authentication headers.
protocol TileProxyManagerProtocol: Sendable {
  func fetchTile(z: Int, x: Int, y: Int, layerID: String) async throws -> Data?
  func fetchTile(url: URL) async throws -> Data?
}

actor TileProxyManager: TileProxyManagerProtocol {
  static let shared = TileProxyManager()

  private let session: URLSession = {
    let config = URLSessionConfiguration.default
    config.httpMaximumConnectionsPerHost = 6
    config.timeoutIntervalForRequest = 30
    config.timeoutIntervalForResource = 60
    
    // 1. REMOVE DOUBLE CACHE (MapLibre Ambient Cache already handles this)
    config.urlCache = nil
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    
    return URLSession(configuration: config)
  }()

  func fetchTile(z: Int, x: Int, y: Int, layerID: String = "shom") async throws -> Data? {
    let clientID = await AppConfiguration.shared.geoGarageClientID
    // Construct the GeoGarage URL. Note that GeoGarage tile APIs usually require the layer ID.
    guard let url = URL(string: "https://tiles.geogarage.com/\(clientID)/\(layerID)/\(z)/\(x)/\(y).png") else {
      throw URLError(.badURL)
    }
    return try await fetchTile(url: url)
  }

  func fetchTile(url: URL) async throws -> Data? {
    // MapLibre's native C++ engine already handles request coalescing per view.
    // We avoid custom coalescing (via unstructured Tasks or dictionaries) to ensure 
    // that swift cancellation flows directly and synchronously down to the URLSession task.
    // If MapLibre cancels the tile, the URLSession TCP connection is killed instantly.
    
    var request = URLRequest(url: url)
    if let token = await KeychainManager.shared.retrieveToken(for: "geogarage_access_token"), !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    let (data, response) = try await self.session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      Logger.network.error("Failed to cast response to HTTPURLResponse.")
      throw URLError(.badServerResponse)
    }
    
    if httpResponse.statusCode == 200 {
      return data
    }
    
    // Everything else returns nil to avoid fatally killing MapLibre's source
    return nil
  }
}

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

/// Errors raised by `TileProxyManager` for non-200/non-404 HTTP responses.
enum TileProxyError: Error, Sendable, Equatable {
  case authenticationRequired(statusCode: Int)
  case httpError(statusCode: Int)
  case notConfigured
}

/// Protocol for network tile downloading with authentication headers.
protocol TileProxyManagerProtocol: Sendable {
  func fetchTile(z: Int, x: Int, y: Int, layerID: String) async throws -> Data?
  func fetchTile(url: URL) async throws -> Data?
}

actor TileProxyManager: TileProxyManagerProtocol {
  private let session: URLSession
  private let keychainManager: any KeychainManaging
  private let configuration: AppConfiguration

  init(
    session: URLSession? = nil,
    keychainManager: any KeychainManaging = KeychainManager.shared,
    configuration: AppConfiguration
  ) {
    self.keychainManager = keychainManager
    self.configuration = configuration
    if let session {
      self.session = session
    } else {
      let config = URLSessionConfiguration.default
      config.httpMaximumConnectionsPerHost = 6
      config.timeoutIntervalForRequest = 30
      config.timeoutIntervalForResource = 60
      config.urlCache = nil
      config.requestCachePolicy = .reloadIgnoringLocalCacheData
      self.session = URLSession(configuration: config)
    }
  }

  func fetchTile(z: Int, x: Int, y: Int, layerID: String) async throws -> Data? {
    guard let clientID = configuration.geoGarageClientID else {
      Logger.network.warning("GeoGarage tile request skipped: GEOGARAGE_CLIENT_ID is not configured.")
      throw TileProxyError.notConfigured
    }
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
    if let token = try await keychainManager.retrieveValidToken(for: GeoGarageKeychainKeys.accessToken) {
      request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    let taggedRequest: URLRequest
    if let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest {
      URLProtocol.setProperty(true, forKey: TileProxyProtocol.handledRequestPropertyKey, in: mutableRequest)
      taggedRequest = mutableRequest as URLRequest
    } else {
      taggedRequest = request
    }

    let (data, response) = try await self.session.data(for: taggedRequest)
    guard let httpResponse = response as? HTTPURLResponse else {
      Logger.network.error("Failed to cast response to HTTPURLResponse.")
      throw URLError(.badServerResponse)
    }

    switch httpResponse.statusCode {
    case 200:
      return data
    case 404:
      // Missing tile at this zoom level: allow overzoom fallback in TileProxyProtocol
      return nil
    case 401, 403:
      Logger.network.warning("GeoGarage tile request unauthorized (HTTP \(httpResponse.statusCode, privacy: .public)) for \(url.path, privacy: .public)")
      throw TileProxyError.authenticationRequired(statusCode: httpResponse.statusCode)
    default:
      Logger.network.error("GeoGarage tile request failed (HTTP \(httpResponse.statusCode, privacy: .public)) for \(url.path, privacy: .public)")
      throw TileProxyError.httpError(statusCode: httpResponse.statusCode)
    }
  }
}

//
//  OpenSeaMapRasterFetchPipeline.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-02.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import UIKit
import CoreGraphics
import OSLog

nonisolated public enum OpenSeaMapFetchError: LocalizedError, Sendable {
  case invalidURL(String)
  case baseTileUnavailable(zoom: Int, x: Int, y: Int, statusCode: Int?)
  case rateLimited
  case compositionFailed

  public var errorDescription: String? {
    switch self {
    case .invalidURL(let urlString):
      return String(localized: "Invalid tile URL: \(urlString)")
    case .baseTileUnavailable(let zoom, let x, let y, let code):
      return String(localized: "Base OSM tile unavailable at (\(zoom),\(x),\(y)), status: \(code ?? -1)")
    case .rateLimited:
      return String(localized: "OSM tile server rate limit reached (HTTP 429).")
    case .compositionFailed:
      return String(localized: "Failed to composite OpenSeaMap seamark overlay with base tile.")
    }
  }
}

/// Pipeline responsible for fetching OpenStreetMap base raster tiles and OpenSeaMap seamark
/// transparent overlays, merging them into a unified raster PNG tile using CoreGraphics.
nonisolated public final class OpenSeaMapRasterFetchPipeline: TileFetchPipeline, Sendable {

  public let format = "png"

  private let session: URLSession
  private let baseTemplate: String
  private let seamarkTemplate: String

  public init(
    session: URLSession? = nil,
    baseTemplate: String = "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
    seamarkTemplate: String = "https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png"
  ) {
    self.baseTemplate = baseTemplate
    self.seamarkTemplate = seamarkTemplate

    if let session {
      self.session = session
    } else {
      let config = URLSessionConfiguration.default
      // OSM Policy: Restrict to 2 concurrent connections per host
      config.httpMaximumConnectionsPerHost = 2
      config.timeoutIntervalForRequest = 25
      config.timeoutIntervalForResource = 45
      config.httpAdditionalHeaders = [
        "User-Agent": "Alcyone Sillage (iOS; marine navigation; contact@alcyone.app)"
      ]
      self.session = URLSession(configuration: config)
    }
  }

  public func fetchTileData(zoom: Int, x: Int, y: Int) async throws -> Data? {
    guard let baseURL = resolveURL(from: baseTemplate, zoom: zoom, x: x, y: y),
          let seamarkURL = resolveURL(from: seamarkTemplate, zoom: zoom, x: x, y: y) else {
      throw OpenSeaMapFetchError.invalidURL("z:\(zoom),x:\(x),y:\(y)")
    }

    // 1. Fetch base OSM tile and seamark overlay in parallel
    async let baseResult = fetchHTTPData(from: baseURL)
    async let seamarkResult = fetchHTTPData(from: seamarkURL)

    let (baseData, seamarkData) = try await (baseResult, seamarkResult)

    guard let baseData else {
      Logger.offline.warning("Base OSM tile missing for coordinate (\(zoom, privacy: .public), \(x, privacy: .public), \(y, privacy: .public))")
      return nil
    }

    // 2. Optimization: If no seamarks exist for this tile (404/empty), return base OSM directly (0 CPU cost)
    guard let seamarkData, !seamarkData.isEmpty else {
      return baseData
    }

    // 3. CPU Coopérativité: Yield to prevent starvation of the Swift Concurrency cooperative thread pool
    await Task.yield()

    let mergedData = try compositeRaster(baseData: baseData, seamarkData: seamarkData)

    await Task.yield()

    return mergedData
  }

  // MARK: - Private Helpers

  private func resolveURL(from template: String, zoom: Int, x: Int, y: Int) -> URL? {
    let resolved = template
      .replacingOccurrences(of: "{z}", with: "\(zoom)")
      .replacingOccurrences(of: "{x}", with: "\(x)")
      .replacingOccurrences(of: "{y}", with: "\(y)")
    return URL(string: resolved)
  }

  /// Downloads HTTP tile data with backoff support on HTTP 429 (Too Many Requests).
  private func fetchHTTPData(from url: URL, retriesLeft: Int = 2) async throws -> Data? {
    var attempts = 0
    let maxAttempts = retriesLeft + 1

    while attempts < maxAttempts {
      attempts += 1
      do {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else { return nil }

        if httpResponse.statusCode == 200 {
          return data
        } else if httpResponse.statusCode == 404 {
          // Normal for OpenSeaMap tiles without seamarks
          return nil
        } else if httpResponse.statusCode == 429 {
          if attempts < maxAttempts {
            Logger.offline.warning("OSM rate limited (429) on \(url.absoluteString, privacy: .public). Backing off...")
            try await Task.sleep(for: .seconds(2 * attempts))
            continue
          } else {
            throw OpenSeaMapFetchError.rateLimited
          }
        } else if httpResponse.statusCode >= 500 {
          if attempts < maxAttempts {
            try await Task.sleep(for: .seconds(attempts))
            continue
          }
          return nil
        } else {
          return nil
        }
      } catch {
        if Task.isCancelled { throw error }
        if attempts < maxAttempts {
          try await Task.sleep(for: .seconds(attempts))
          continue
        }
        return nil
      }
    }

    return nil
  }

  /// Merges base tile with transparent seamark layer using CoreGraphics.
  private func compositeRaster(baseData: Data, seamarkData: Data) throws -> Data {
    guard let baseImage = UIImage(data: baseData),
          let seamarkImage = UIImage(data: seamarkData) else {
      return baseData
    }

    let size = CGSize(width: 256, height: 256)
    let renderer = UIGraphicsImageRenderer(size: size)
    let composite = renderer.image { _ in
      baseImage.draw(in: CGRect(origin: .zero, size: size))
      seamarkImage.draw(in: CGRect(origin: .zero, size: size))
    }

    guard let pngData = composite.pngData() else {
      throw OpenSeaMapFetchError.compositionFailed
    }
    return pngData
  }
}

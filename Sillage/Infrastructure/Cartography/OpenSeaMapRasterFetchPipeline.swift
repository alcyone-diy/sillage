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
  private let ownsSession: Bool
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
      self.ownsSession = false
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
      self.ownsSession = true
    }
  }

  deinit {
    if ownsSession {
      session.invalidateAndCancel()
    }
  }

  public func finishAndInvalidateSession() {
    if ownsSession {
      session.finishTasksAndInvalidate()
    }
  }

  public func fetchTileData(zoom: Int, x: Int, y: Int) async throws -> Data? {
    guard let baseURL = resolveURL(from: baseTemplate, zoom: zoom, x: x, y: y),
          let seamarkURL = resolveURL(from: seamarkTemplate, zoom: zoom, x: x, y: y) else {
      throw OpenSeaMapFetchError.invalidURL("z:\(zoom),x:\(x),y:\(y)")
    }

    // 1. Fetch base OSM tile (required) and seamark overlay (best-effort, 404/error-tolerant) in parallel
    async let baseResult = fetchHTTPData(from: baseURL, zoom: zoom, x: x, y: y, isRequiredBaseLayer: true)
    async let seamarkResult = fetchHTTPData(from: seamarkURL, zoom: zoom, x: x, y: y, isRequiredBaseLayer: false)

    let (baseData, seamarkData) = try await (baseResult, seamarkResult)

    guard let baseData else {
      throw OpenSeaMapFetchError.baseTileUnavailable(zoom: zoom, x: x, y: y, statusCode: nil)
    }

    // 2. Optimization: If no seamarks exist for this tile (404/empty), return base OSM directly (0 CPU cost)
    guard let seamarkData, !seamarkData.isEmpty else {
      return baseData
    }

    // 3. Cooperative yield to prevent starvation of the Swift Concurrency thread pool
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

  /// Downloads HTTP tile data with backoff support on HTTP 429 (Too Many Requests) and 5xx errors.
  private func fetchHTTPData(
    from url: URL,
    zoom: Int,
    x: Int,
    y: Int,
    isRequiredBaseLayer: Bool,
    retriesLeft: Int = 2
  ) async throws -> Data? {
    var attempts = 0
    let maxAttempts = retriesLeft + 1

    while attempts < maxAttempts {
      attempts += 1
      do {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
          if isRequiredBaseLayer {
            throw OpenSeaMapFetchError.baseTileUnavailable(zoom: zoom, x: x, y: y, statusCode: nil)
          }
          Logger.offline.warning("Non-HTTP response for optional seamark overlay at (\(zoom, privacy: .public), \(x, privacy: .public), \(y, privacy: .public)); degrading to base tile.")
          return nil
        }

        if httpResponse.statusCode == 200 {
          return data
        } else if httpResponse.statusCode == 404 && !isRequiredBaseLayer {
          // Normal for OpenSeaMap seamark tiles without nautical marks
          return nil
        } else if httpResponse.statusCode == 429 {
          if attempts < maxAttempts {
            Logger.offline.warning("OSM rate limited (429) on \(url.absoluteString, privacy: .public). Backing off...")
            try await Task.sleep(for: .seconds(2 * attempts))
            continue
          } else if isRequiredBaseLayer {
            throw OpenSeaMapFetchError.rateLimited
          } else {
            Logger.offline.warning("Seamark overlay rate limited (429) at (\(zoom, privacy: .public), \(x, privacy: .public), \(y, privacy: .public)); degrading to base tile.")
            return nil
          }
        } else if httpResponse.statusCode >= 500 {
          if attempts < maxAttempts {
            try await Task.sleep(for: .seconds(attempts))
            continue
          }
          if isRequiredBaseLayer {
            throw OpenSeaMapFetchError.baseTileUnavailable(zoom: zoom, x: x, y: y, statusCode: httpResponse.statusCode)
          }
          Logger.offline.warning("Seamark overlay server error (\(httpResponse.statusCode, privacy: .public)) at (\(zoom, privacy: .public), \(x, privacy: .public), \(y, privacy: .public)); degrading to base tile.")
          return nil
        } else {
          if isRequiredBaseLayer {
            throw OpenSeaMapFetchError.baseTileUnavailable(zoom: zoom, x: x, y: y, statusCode: httpResponse.statusCode)
          }
          Logger.offline.warning("Seamark overlay HTTP \(httpResponse.statusCode, privacy: .public) at (\(zoom, privacy: .public), \(x, privacy: .public), \(y, privacy: .public)); degrading to base tile.")
          return nil
        }
      } catch {
        if Task.isCancelled { throw error }
        if error is OpenSeaMapFetchError { throw error }
        if attempts < maxAttempts {
          try await Task.sleep(for: .seconds(attempts))
          continue
        }
        if isRequiredBaseLayer {
          throw error
        }
        Logger.offline.warning("Seamark overlay network error at (\(zoom, privacy: .public), \(x, privacy: .public), \(y, privacy: .public)): \(error.localizedDescription, privacy: .public); degrading to base tile.")
        return nil
      }
    }

    if isRequiredBaseLayer {
      throw OpenSeaMapFetchError.baseTileUnavailable(zoom: zoom, x: x, y: y, statusCode: nil)
    }
    return nil
  }

  /// Merges base tile with transparent seamark layer using CoreGraphics at strict 1x scale (256x256 px).
  private func compositeRaster(baseData: Data, seamarkData: Data) throws -> Data {
    guard let baseImage = UIImage(data: baseData),
          let seamarkImage = UIImage(data: seamarkData) else {
      return baseData
    }

    let format = UIGraphicsImageRendererFormat()
    format.scale = 1.0
    let size = CGSize(width: 256, height: 256)
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
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

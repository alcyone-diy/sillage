//
//  TileProxyProtocol.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import os
import OSLog

private enum TilePayloadSource: Sendable {
  case localPackage
  case network
  case fallback
  case transparent
}

struct TileURLComponents: Sendable {
  let clientID: String
  let layerID: String
  let z: Int
  let x: Int
  let y: Int
}

class TileProxyProtocol: URLProtocol, @unchecked Sendable {
  private let taskLock = OSAllocatedUnfairLock<(task: Task<Void, Never>?, isStopped: Bool)>(initialState: (task: nil, isStopped: false))

  private static let tilePathRegex = #/^/([^/]+)/([^/]+)/(\d+)/(\d+)/(\d+)\.png$/#

  // MARK: - Dependency Injection

  private static let dependenciesLock = OSAllocatedUnfairLock<(
    offlineTileProvider: (any GeoGarageOfflineTileProviderProtocol)?,
    tileProxyManager: (any TileProxyManagerProtocol)?
  )>(initialState: (offlineTileProvider: nil, tileProxyManager: nil))

  static var offlineTileProvider: (any GeoGarageOfflineTileProviderProtocol)? {
    dependenciesLock.withLock { $0.offlineTileProvider }
  }

  static var tileProxyManager: (any TileProxyManagerProtocol)? {
    dependenciesLock.withLock { $0.tileProxyManager }
  }

  /// Injects runtime dependencies without singletons.
  static func configure(
    offlineTileProvider: (any GeoGarageOfflineTileProviderProtocol)?,
    tileProxyManager: (any TileProxyManagerProtocol)? = nil
  ) {
    dependenciesLock.withLock { state in
      state.offlineTileProvider = offlineTileProvider
      if let tileProxyManager {
        state.tileProxyManager = tileProxyManager
      }
    }
  }

  // MARK: - URLProtocol Lifecycle

  override class func canInit(with request: URLRequest) -> Bool {
    guard let url = request.url else { return false }
    return url.host == "tiles.geogarage.com"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    return request
  }

  override func startLoading() {
    guard let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }

    // URLProtocol bridging to Swift Concurrency:
    // We encapsulate the async work inside a standard Task and store it in taskLock.
    // When MapLibre calls stopLoading(), we explicitly cancel this Task.
    // This top-level cancellation propagates down the entire hierarchy (including child Tasks).
    taskLock.withLock { lockState in
      guard !lockState.isStopped else { return }
      lockState.task = Task { [weak self] in
        guard let self = self else { return }

        do {
          try Task.checkCancellation()
          guard let (data, source) = try await fetchTileData(for: url) else {
            try Task.checkCancellation()
            self.client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
          }

          // URLProtocol contract: do not send messages if cancelled
          guard !Task.isCancelled else { return }

          let cacheControl: String
          let storagePolicy: URLCache.StoragePolicy
          switch source {
          case .network:
            cacheControl = "max-age=604800, public"
            storagePolicy = .allowed
          case .localPackage, .fallback, .transparent:
            cacheControl = "no-store"
            storagePolicy = .notAllowed
          }
          let headers = [
            "Content-Type": "image/png",
            "Cache-Control": cacheControl
          ]
          guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers) else {
            Logger.network.error("Failed to create HTTPURLResponse for tile: \(url.absoluteString, privacy: .public)")
            self.client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
          }
          
          // URLProtocol contract: do not send messages if cancelled
          guard !Task.isCancelled else { return }
          self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: storagePolicy)
          
          guard !Task.isCancelled else { return }
          self.client?.urlProtocol(self, didLoad: data)
          
          guard !Task.isCancelled else { return }
          self.client?.urlProtocolDidFinishLoading(self)

        } catch is CancellationError {
          // URLProtocol contract: do not call didFailWithError if stopped by the client
          return
        } catch {
          self.client?.urlProtocol(self, didFailWithError: error)
        }
      }
    }
  }

  override func stopLoading() {
    // Explicitly cancel the top-level Task when MapLibre aborts the request.
    // This triggers Task.checkCancellation() in child operations to abort immediately.
    taskLock.withLock { lockState in
      lockState.isStopped = true
      lockState.task?.cancel()
      lockState.task = nil
    }
  }

  // MARK: - Tile Resolution (Hybrid Offline/Online Pipeline)

  private func fetchTileData(for url: URL, depth: Int = 0) async throws -> (Data, TilePayloadSource)? {
    guard let host = url.host, host == "tiles.geogarage.com" else { return nil }

    // 1. Safe parsing of XYZ tile coordinates
    if let components = Self.parseTileURL(url) {
      // 2. Query offline MBTiles packages first (offline priority)
      if let offlineProvider = Self.offlineTileProvider {
        if let offlineData = await offlineProvider.tile(
          layerID: components.layerID,
          z: components.z,
          x: components.x,
          y: components.y
        ), !offlineData.isEmpty {
          return (offlineData, .localPackage)
        }
      }
    }

    // 3. Intercept & Verify: Local Authorization Firewall for remote network calls
    let token = await KeychainManager.shared.retrieveToken(for: "geogarage_access_token")
    guard let validToken = token, !validToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      // Rule 2: Fail-Closed for remote network streaming if unauthenticated
      return nil
    }

    // 4. Fallback to remote network fetch via TileProxyManager
    let networkManager = Self.tileProxyManager ?? TileProxyManager.shared
    if let data = try await networkManager.fetchTile(url: url) {
      return (data, .network)
    }

    // 5. Overzoom / 404 fallback logic (parent tile upscaling or transparent tile)
    if depth >= 2 {
      if let data = generateTransparentTile() {
        return (data, .transparent)
      }
      return nil
    }

    return try await generateFallbackTile(for: url, depth: depth)
  }

  // MARK: - URL Parsing

  private static func parseTileURL(_ url: URL) -> TileURLComponents? {
    guard let match = url.path.firstMatch(of: tilePathRegex) else {
      Logger.network.warning("Failed to match GeoGarage tile URL path format: \(url.path, privacy: .public)")
      return nil
    }

    let clientID = String(match.output.1)
    let layerID = String(match.output.2)
    guard let z = Int(String(match.output.3)),
          let x = Int(String(match.output.4)),
          let y = Int(String(match.output.5)),
          z >= 0, x >= 0, y >= 0 else {
      Logger.network.warning("Invalid coordinate integers in GeoGarage tile URL: \(url.path, privacy: .public)")
      return nil
    }

    return TileURLComponents(clientID: clientID, layerID: layerID, z: z, x: x, y: y)
  }

  // MARK: - Fallback & Overzooming

  private func generateFallbackTile(for url: URL, depth: Int) async throws -> (Data, TilePayloadSource)? {
    guard let match = url.path.firstMatch(of: Self.tilePathRegex) else { return nil }

    let clientID = String(match.output.1)
    let layerID = String(match.output.2)
    guard let z = Int(String(match.output.3)),
          let x = Int(String(match.output.4)),
          let y = Int(String(match.output.5)) else { return nil }

    let parentZ = z - 1
    guard parentZ >= 0 else { return nil }
    let parentX = x / 2
    let parentY = y / 2

    // Reconstruct URL with parent components
    guard let host = url.host, let parentURL = URL(string: "https://\(host)/\(clientID)/\(layerID)/\(parentZ)/\(parentX)/\(parentY).png") else { return nil }

    // Recursively fetch parent tile
    guard let (parentData, _) = try await fetchTileData(for: parentURL, depth: depth + 1),
          let source = CGImageSourceCreateWithData(parentData as CFData, nil),
          let parentImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      return nil
    }

    let quadrantX = x % 2
    let quadrantY = y % 2

    // Inherit cancellation context so that heavy image cropping is cancelled if tile goes off-screen
    let data = try? await Task {
      try Task.checkCancellation()
      return Self.cropAndScaleImage(parentImage, quadrantX: quadrantX, quadrantY: quadrantY)
    }.value

    if let data = data {
      return (data, .fallback)
    }
    return nil
  }

  private static func cropAndScaleImage(_ image: CGImage, quadrantX: Int, quadrantY: Int) -> Data? {
    let halfWidth = image.width / 2
    let halfHeight = image.height / 2

    let cropRect = CGRect(
      x: quadrantX * halfWidth,
      y: quadrantY * halfHeight,
      width: halfWidth,
      height: halfHeight
    )

    guard let croppedImage = image.cropping(to: cropRect) else { return nil }

    let targetWidth = image.width
    let targetHeight = image.height

    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else { return nil }

    context.interpolationQuality = .none

    let targetRect = CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
    
    // Invert Y axis for CoreGraphics context drawing
    context.translateBy(x: 0, y: CGFloat(targetHeight))
    context.scaleBy(x: 1.0, y: -1.0)
    
    context.draw(croppedImage, in: targetRect)

    guard let scaledImage = context.makeImage() else { return nil }

    let mutableData = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(mutableData as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, scaledImage, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }

    return mutableData as Data
  }

  private static let transparentTileData: Data? = {
    let size = 256
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else { return nil }

    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    guard let image = context.makeImage() else { return nil }

    let mutableData = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(mutableData as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }

    return mutableData as Data
  }()

  private func generateTransparentTile() -> Data? {
    return Self.transparentTileData
  }
}

//
//  TileProxyProtocolTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-21.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import os
@testable import Sillage

// MARK: - Mock Providers

final class MockOfflineTileProvider: GeoGarageOfflineTileProviderProtocol, @unchecked Sendable {
  private let lock = OSAllocatedUnfairLock<[String: Data]>(initialState: [:])

  func setTileData(_ data: Data?, layerID: String, z: Int, x: Int, y: Int) {
    let key = "\(layerID)/\(z)/\(x)/\(y)"
    lock.withLock { dict in
      if let data {
        dict[key] = data
      } else {
        dict.removeValue(forKey: key)
      }
    }
  }

  func tile(layerID: String, z: Int, x: Int, y: Int) async -> Data? {
    let key = "\(layerID)/\(z)/\(x)/\(y)"
    return lock.withLock { $0[key] }
  }

  func reloadDownloads(_ downloads: [OfflineChartDownload], sharedSecret: String, customerID: String) async {}
  func close() async {}
}

final class MockTileProxyManager: TileProxyManagerProtocol, @unchecked Sendable {
  private struct State: Sendable {
    var data: Data?
    var dataByPath: [String: Data] = [:]
    var errorToThrow: Error?
    var lastRequestedURL: URL?
    var callCount: Int = 0
  }

  private let lock = OSAllocatedUnfairLock<State>(initialState: State())

  func setResponseData(_ data: Data?) {
    lock.withLock { $0.data = data }
  }

  func setResponseData(_ data: Data?, forPath path: String) {
    lock.withLock { $0.dataByPath[path] = data }
  }

  func setError(_ error: Error?) {
    lock.withLock { $0.errorToThrow = error }
  }

  var lastRequestedURL: URL? {
    lock.withLock { $0.lastRequestedURL }
  }

  var callCount: Int {
    lock.withLock { $0.callCount }
  }

  func fetchTile(z: Int, x: Int, y: Int, layerID: String) async throws -> Data? {
    guard let url = URL(string: "https://tiles.geogarage.com/mockClient/\(layerID)/\(z)/\(x)/\(y).png") else {
      return nil
    }
    return try await fetchTile(url: url)
  }

  func fetchTile(url: URL) async throws -> Data? {
    try lock.withLock { state in
      state.lastRequestedURL = url
      state.callCount += 1
      if let errorToThrow = state.errorToThrow {
        throw errorToThrow
      }
      if let pathData = state.dataByPath[url.path] {
        return pathData
      }
      return state.data
    }
  }
}

// MARK: - Test Suite

@MainActor
final class TileProxyProtocolTests: XCTestCase {

  private var mockOfflineProvider: MockOfflineTileProvider?
  private var mockNetworkManager: MockTileProxyManager?
  private var mockKeychain: MockKeychainManager?
  private var customSession: URLSession?

  override func setUp() async throws {
    try await super.setUp()
    let offline = MockOfflineTileProvider()
    let network = MockTileProxyManager()
    let keychain = MockKeychainManager()
    mockOfflineProvider = offline
    mockNetworkManager = network
    mockKeychain = keychain

    keychain.saveSync(token: "test_valid_token", for: GeoGarageKeychainKeys.accessToken)

    TileProxyProtocol.configure(
      offlineTileProvider: offline,
      tileProxyManager: network,
      keychainManager: keychain
    )

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [TileProxyProtocol.self]
    config.urlCache = nil
    config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    customSession = URLSession(configuration: config)
  }

  override func tearDown() async throws {
    customSession?.invalidateAndCancel()
    customSession = nil
    TileProxyProtocol.resetForTesting()
    mockOfflineProvider = nil
    mockNetworkManager = nil
    mockKeychain = nil
    URLCache.shared.removeAllCachedResponses()
    try await super.tearDown()
  }

  // MARK: - canInit Tests

  func testCanInit_handlesGeoGarageHostOnly() {
    guard let validURL = URL(string: "https://tiles.geogarage.com/client123/shom/10/512/340.png"),
          let invalidURL = URL(string: "https://api.mapbox.com/v4/mapbox.satellite/10/512/340.png") else {
      XCTFail("Failed to initialize test URLs")
      return
    }

    XCTAssertTrue(TileProxyProtocol.canInit(with: URLRequest(url: validURL)))
    XCTAssertFalse(TileProxyProtocol.canInit(with: URLRequest(url: invalidURL)))
  }

  // MARK: - Offline Hit Tests

  func testTileProxyProtocol_returnsLocalOfflineTileWhenAvailable() async throws {
    guard let mockOfflineProvider, let mockNetworkManager, let customSession else {
      XCTFail("Missing test fixtures")
      return
    }

    guard let sampleOfflineData = "LOCAL_OFFLINE_MBTILES_TILE_BYTES".data(using: .utf8) else {
      XCTFail("Failed to encode test tile data")
      return
    }

    mockOfflineProvider.setTileData(sampleOfflineData, layerID: "shom", z: 12, x: 2048, y: 1360)
    mockNetworkManager.setResponseData(nil) // Network should not be hit

    guard let tileURL = URL(string: "https://tiles.geogarage.com/cus_999/shom/12/2048/1360.png") else {
      XCTFail("Failed to create tile URL")
      return
    }

    let (data, response) = try await customSession.data(from: tileURL)

    guard let httpResponse = response as? HTTPURLResponse else {
      XCTFail("Response must be HTTPURLResponse")
      return
    }

    XCTAssertEqual(httpResponse.statusCode, 200)
    XCTAssertEqual(data, sampleOfflineData, "Must return exact local offline tile data")
    XCTAssertEqual(httpResponse.allHeaderFields["Cache-Control"] as? String, "no-store", "Local offline tiles must be flagged no-store")
    XCTAssertNil(mockNetworkManager.lastRequestedURL, "Network must not be requested when offline tile is found")
  }

  // MARK: - Network Fallback Tests

  func testTileProxyProtocol_fallsBackToNetworkWhenOfflineTileNotFound() async throws {
    guard let mockNetworkManager, let customSession else {
      XCTFail("Missing test fixtures")
      return
    }

    guard let sampleNetworkData = "REMOTE_ONLINE_TILE_BYTES".data(using: .utf8) else {
      XCTFail("Failed to encode test tile data")
      return
    }

    // Offline provider does NOT have the tile
    mockNetworkManager.setResponseData(sampleNetworkData)

    guard let tileURL = URL(string: "https://tiles.geogarage.com/cus_999/ukho/10/512/340.png") else {
      XCTFail("Failed to create tile URL")
      return
    }

    let (data, response) = try await customSession.data(from: tileURL)

    guard let httpResponse = response as? HTTPURLResponse else {
      XCTFail("Response must be HTTPURLResponse")
      return
    }

    XCTAssertEqual(httpResponse.statusCode, 200)
    XCTAssertEqual(data, sampleNetworkData, "Must return remote network tile data")
    XCTAssertEqual(httpResponse.allHeaderFields["Cache-Control"] as? String, "max-age=604800, public", "Remote network tiles must be cacheable")
    XCTAssertEqual(mockNetworkManager.lastRequestedURL, tileURL, "Network manager must have received the tile URL")
  }

  // MARK: - Defensive Parsing Tests

  func testTileProxyProtocol_handlesMalformedURLDefensively() async {
    guard let customSession else {
      XCTFail("Missing customSession")
      return
    }

    guard let malformedURL = URL(string: "https://tiles.geogarage.com/invalid/path/format.png") else {
      XCTFail("Failed to create malformed URL")
      return
    }

    do {
      _ = try await customSession.data(from: malformedURL)
      XCTFail("Should have thrown error on 404 / fileDoesNotExist")
    } catch {
      // Must fail safely without crash or forced unwrap
      XCTAssertNotNil(error)
    }
  }

  // MARK: - Cancellation Tests

  func testTileProxyProtocol_cancelsGracefully() async {
    guard let customSession else {
      XCTFail("Missing customSession")
      return
    }

    guard let tileURL = URL(string: "https://tiles.geogarage.com/cus_999/cancel/14/4096/2720.png") else {
      XCTFail("Failed to create tile URL")
      return
    }

    let task = Task { () -> (Data, URLResponse)? in
      return try? await customSession.data(from: tileURL)
    }

    task.cancel()
    let result = await task.value
    // If task was cancelled early, it should complete gracefully returning nil or throwing URLError.cancelled
    XCTAssertNil(result)
  }

  // MARK: - Offline Resilience (Airplane Mode / Sea Navigation)

  func testTileProxyProtocol_servesOfflineTileEvenWithoutNetworkToken() async throws {
    guard let mockOfflineProvider, let customSession else {
      XCTFail("Missing test fixtures")
      return
    }

    // Simulate airplane mode or expired token
    mockKeychain?.deleteTokenSync(for: GeoGarageKeychainKeys.accessToken)

    guard let sampleOfflineData = "OFFLINE_LA_ROCHELLE_BYTES".data(using: .utf8) else {
      XCTFail("Failed to encode test tile data")
      return
    }

    mockOfflineProvider.setTileData(sampleOfflineData, layerID: "shom", z: 12, x: 2048, y: 1360)

    guard let tileURL = URL(string: "https://tiles.geogarage.com/cus_999/shom/12/2048/1360.png") else {
      XCTFail("Failed to create tile URL")
      return
    }

    let (data, response) = try await customSession.data(from: tileURL)

    guard let httpResponse = response as? HTTPURLResponse else {
      XCTFail("Response must be HTTPURLResponse")
      return
    }

    XCTAssertEqual(httpResponse.statusCode, 200)
    XCTAssertEqual(data, sampleOfflineData, "Must serve local offline tile without network token")
    XCTAssertEqual(httpResponse.allHeaderFields["Cache-Control"] as? String, "no-store")
  }

  // MARK: - Anti-Loop Guard Tests

  func testCanInit_rejectsAlreadyHandledRequests() {
    guard let validURL = URL(string: "https://tiles.geogarage.com/client123/shom/10/512/340.png"),
          let mutableRequest = (URLRequest(url: validURL) as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
      XCTFail("Failed to create mutable request")
      return
    }

    URLProtocol.setProperty(true, forKey: TileProxyProtocol.handledRequestPropertyKey, in: mutableRequest)
    XCTAssertFalse(TileProxyProtocol.canInit(with: mutableRequest as URLRequest))
  }

  // MARK: - HTTP Error & Auth Failure Propagation Tests

  func testTileProxyProtocol_propagatesAuthErrorWithoutFallbackOrTransparentTile() async {
    guard let mockNetworkManager, let customSession else {
      XCTFail("Missing test fixtures")
      return
    }

    let authFailureCount = OSAllocatedUnfairLock(initialState: 0)
    TileProxyProtocol.configure(
      offlineTileProvider: mockOfflineProvider,
      tileProxyManager: mockNetworkManager,
      keychainManager: mockKeychain,
      onAuthenticationFailure: {
        authFailureCount.withLock { $0 += 1 }
      }
    )
    mockNetworkManager.setError(TileProxyError.authenticationRequired(statusCode: 401))

    guard let tileURL = URL(string: "https://tiles.geogarage.com/cus_999/shom/12/2048/1360.png") else {
      XCTFail("Failed to create tile URL")
      return
    }

    do {
      _ = try await customSession.data(from: tileURL)
      XCTFail("Expected authentication error to be thrown instead of 200 OK transparent tile")
    } catch {
      XCTAssertEqual(mockNetworkManager.callCount, 1, "Must fail fast without recursive overzoom requests")
      XCTAssertEqual(authFailureCount.withLock { $0 }, 1, "Must notify auth failure handler once")
    }
  }

  func testTileProxyProtocol_propagatesHTTPErrorWithoutFallbackOrTransparentTile() async {
    guard let mockNetworkManager, let customSession else {
      XCTFail("Missing test fixtures")
      return
    }

    mockNetworkManager.setError(TileProxyError.httpError(statusCode: 503))

    guard let tileURL = URL(string: "https://tiles.geogarage.com/cus_999/shom/12/2048/1360.png") else {
      XCTFail("Failed to create tile URL")
      return
    }

    do {
      _ = try await customSession.data(from: tileURL)
      XCTFail("Expected HTTP error to be thrown instead of 200 OK transparent tile")
    } catch {
      XCTAssertEqual(mockNetworkManager.callCount, 1, "Must not trigger recursive overzoom on 5xx errors")
    }
  }

  // MARK: - Overzoom Orientation Tests

  func testTileProxyProtocol_overzoomPreservesTopBottomOrientation() async throws {
    guard let mockNetworkManager, let customSession else {
      XCTFail("Missing test fixtures")
      return
    }

    // Create a 4x4 PNG where top-left (y=0..1) is RED and bottom-left (y=2..3) is BLUE
    guard let parentPNG = makeQuadrantTestPNG() else {
      XCTFail("Failed to create parent PNG")
      return
    }

    mockNetworkManager.setResponseData(nil)
    mockNetworkManager.setResponseData(parentPNG, forPath: "/cus_999/shom/10/100/200.png")

    // Child (z=11, x=200, y=400) has quadrantX=0 (left), quadrantY=0 (top) -> must be RED, not BLUE
    guard let childURL = URL(string: "https://tiles.geogarage.com/cus_999/shom/11/200/400.png") else {
      XCTFail("Failed to create child URL")
      return
    }

    let (data, response) = try await customSession.data(from: childURL)
    guard let httpResponse = response as? HTTPURLResponse else {
      XCTFail("Expected HTTPURLResponse")
      return
    }
    XCTAssertEqual(httpResponse.statusCode, 200)

    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let resultImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let topLeftPixel = sampleTopLeftPixelRGBA(of: resultImage) else {
      XCTFail("Failed to decode overzoomed PNG")
      return
    }

    XCTAssertGreaterThan(topLeftPixel.r, 200, "Top-left quadrant must be red (not vertically flipped to blue)")
    XCTAssertLessThan(topLeftPixel.b, 50, "Top-left quadrant must not contain bottom-left blue pixels")
  }

  // MARK: - Helpers

  private func makeQuadrantTestPNG() -> Data? {
    let size = 4
    var pixels = [UInt8](repeating: 0, count: size * size * 4)
    for y in 0..<size {
      for x in 0..<size {
        let idx = (y * size + x) * 4
        if y < 2 {
          // Top half: Red
          pixels[idx] = 255
          pixels[idx + 1] = 0
          pixels[idx + 2] = 0
          pixels[idx + 3] = 255
        } else {
          // Bottom half: Blue
          pixels[idx] = 0
          pixels[idx + 1] = 0
          pixels[idx + 2] = 255
          pixels[idx + 3] = 255
        }
      }
    }
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let provider = CGDataProvider(data: Data(pixels) as CFData),
          let image = CGImage(
            width: size,
            height: size,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
          ) else { return nil }

    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
      return nil
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return data as Data
  }

  private func sampleTopLeftPixelRGBA(of image: CGImage) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
    var pixel = [UInt8](repeating: 0, count: 4)
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    return (pixel[0], pixel[1], pixel[2], pixel[3])
  }
}

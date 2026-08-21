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
  private let lock = OSAllocatedUnfairLock<(data: Data?, lastRequestedURL: URL?)>(initialState: (nil, nil))

  func setResponseData(_ data: Data?) {
    lock.withLock { $0.data = data }
  }

  var lastRequestedURL: URL? {
    lock.withLock { $0.lastRequestedURL }
  }

  func fetchTile(z: Int, x: Int, y: Int, layerID: String) async throws -> Data? {
    guard let url = URL(string: "https://tiles.geogarage.com/mockClient/\(layerID)/\(z)/\(x)/\(y).png") else {
      return nil
    }
    return try await fetchTile(url: url)
  }

  func fetchTile(url: URL) async throws -> Data? {
    lock.withLock { state in
      state.lastRequestedURL = url
      return state.data
    }
  }
}

// MARK: - Test Suite

@MainActor
final class TileProxyProtocolTests: XCTestCase {

  private var mockOfflineProvider: MockOfflineTileProvider?
  private var mockNetworkManager: MockTileProxyManager?
  private var customSession: URLSession?

  override func setUp() {
    super.setUp()
    let offline = MockOfflineTileProvider()
    let network = MockTileProxyManager()
    mockOfflineProvider = offline
    mockNetworkManager = network

    TileProxyProtocol.configure(
      offlineTileProvider: offline,
      tileProxyManager: network
    )

    // Store dummy token in Keychain for TileProxyProtocol firewall
    KeychainManager.shared.saveSync(token: "test_valid_token", for: "geogarage_access_token")

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [TileProxyProtocol.self]
    customSession = URLSession(configuration: config)
  }

  override func tearDown() {
    customSession?.invalidateAndCancel()
    customSession = nil
    TileProxyProtocol.configure(offlineTileProvider: nil, tileProxyManager: nil)
    mockOfflineProvider = nil
    mockNetworkManager = nil
    KeychainManager.shared.deleteTokenSync(for: "geogarage_access_token")
    super.tearDown()
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

    guard let tileURL = URL(string: "https://tiles.geogarage.com/cus_999/shom/14/4096/2720.png") else {
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
    KeychainManager.shared.deleteTokenSync(for: "geogarage_access_token")

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
}

//
//  LocalTileServerTests.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-16.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import XCTest
@testable import Sillage

@MainActor
final class LocalTileServerTests: XCTestCase {

  private final class MockReader: SQLCipherMBTilesReaderProtocol, @unchecked Sendable {
    var tiles: [String: Data] = [:]
    var isClosed = false

    func tile(z: Int, x: Int, y: Int) async -> Data? {
      tiles["\(z)/\(x)/\(y)"]
    }

    func close() async {
      isClosed = true
    }
  }

  func testLocalTileServer_servesTileAndClosesConnection() async throws {
    let mockReader = MockReader()
    let tileData = "PNG_FAKE_BYTES_12345".data(using: .utf8)!
    mockReader.tiles["10/512/340"] = tileData

    let server = LocalTileServer(reader: mockReader)
    let port = try await server.start()
    XCTAssertGreaterThan(port, 0)

    let url = URL(string: "http://127.0.0.1:\(port)/tiles/10/512/340.png")!
    var request = URLRequest(url: url)
    request.timeoutInterval = 5.0

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      XCTFail("Expected HTTPURLResponse")
      return
    }

    XCTAssertEqual(httpResponse.statusCode, 200)
    XCTAssertEqual(httpResponse.value(forHTTPHeaderField: "Content-Type"), "image/png")
    XCTAssertEqual(httpResponse.value(forHTTPHeaderField: "Connection"), "close")
    XCTAssertEqual(data, tileData)

    await server.stop()
    XCTAssertTrue(mockReader.isClosed)
  }

  func testLocalTileServer_returns204ForMissingTile() async throws {
    let mockReader = MockReader()
    let server = LocalTileServer(reader: mockReader)
    let port = try await server.start()

    let url = URL(string: "http://127.0.0.1:\(port)/tiles/5/10/10")!
    let (_, response) = try await URLSession.shared.data(for: URLRequest(url: url))
    guard let httpResponse = response as? HTTPURLResponse else {
      XCTFail("Expected HTTPURLResponse")
      return
    }

    XCTAssertEqual(httpResponse.statusCode, 204)
    XCTAssertEqual(httpResponse.value(forHTTPHeaderField: "Connection"), "close")

    await server.stop()
  }
}

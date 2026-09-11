//
//  GeoGaragePackageServiceTests.swift
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
final class GeoGaragePackageServiceTests: XCTestCase {

  private var session: URLSession!

  override func setUp() {
    super.setUp()
    MockURLProtocol.reset()
    session = MockURLProtocol.makeMockSession()
  }

  override func tearDown() {
    MockURLProtocol.reset()
    session = nil
    super.tearDown()
  }

  /// En-têtes qui porteraient encore une clé CaaS (voie A, avant le 11 sept. 2026).
  private static func legacyKeyHeaders(of request: URLRequest) -> [String] {
    (request.allHTTPHeaderFields ?? [:]).keys.filter { $0.lowercased().hasPrefix("api") }
  }

  /// Corps x-www-form-urlencoded d'une requête interceptée. URLSession ne transmet le corps à un
  /// URLProtocol que sous forme de flux (`httpBodyStream`), jamais dans `httpBody`.
  private static func formBody(of request: URLRequest) -> [String: String] {
    var data = request.httpBody ?? Data()
    if data.isEmpty, let stream = request.httpBodyStream {
      stream.open()
      defer { stream.close() }
      var buffer = [UInt8](repeating: 0, count: 4096)
      while stream.hasBytesAvailable {
        let read = stream.read(&buffer, maxLength: buffer.count)
        guard read > 0 else { break }
        data.append(buffer, count: read)
      }
    }
    guard let body = String(data: data, encoding: .utf8) else { return [:] }
    var result: [String: String] = [:]
    for pair in body.split(separator: "&") {
      let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
      guard parts.count == 2 else { continue }
      result[parts[0].removingPercentEncoding ?? parts[0]] = parts[1].removingPercentEncoding ?? parts[1]
    }
    return result
  }

  // MARK: - POST /packages/request/

  func testRequestPackage_success() async throws {
    let packageUUID = UUID(uuidString: "3FA85F64-5717-4562-B3FC-2C963F66AFA6")!
    MockURLProtocol.setHandler { request in
      XCTAssertEqual(request.httpMethod, "POST")
      XCTAssertEqual(request.url?.path, "/packages/request")
      // Voie B (11 sept. 2026) : jeton de l'utilisateur en en-tête, plus aucune clé ni identifiant
      // client dans la requête.
      XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test_access_token")
      XCTAssertTrue(Self.legacyKeyHeaders(of: request).isEmpty, "plus d'en-tête de clé CaaS")
      XCTAssertNil(request.url?.query)
      let body = Self.formBody(of: request)
      XCTAssertEqual(
        Set(body.keys),
        ["layer_id", "zone", "zoom_max", "format", "cipher"],
        "ni clé CaaS ni identifiant client dans le corps"
      )
      XCTAssertEqual(body["layer_id"], "shom")
      XCTAssertEqual(body["zoom_max"], "14")

      let json = """
      {
        "uuid": "\(packageUUID.uuidString.lowercased())",
        "state": "STARTED"
      }
      """.data(using: .utf8)!

      let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
      return (response, json)
    }

    let service = GeoGaragePackageService(
      baseURL: URL(string: "https://caas.geogarage.com")!,
      session: session
    )

    let request = PackageRequest(
      layerID: "shom",
      zoneWKT: "POLYGON((-5 47, 0 47, 0 50, -5 50, -5 47))",
      zoomMax: 14,
      format: .mbtiles,
      cipher: .v3
    )

    let returnedUUID = try await service.requestPackage(request, accessToken: "test_access_token")
    XCTAssertEqual(returnedUUID, packageUUID)
  }

  func testRequestPackage_httpError_throwsRequestFailed() async {
    MockURLProtocol.setHandler { request in
      let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
      return (response, "Invalid WKT".data(using: .utf8))
    }

    let service = GeoGaragePackageService(
      baseURL: URL(string: "https://caas.geogarage.com")!,
      session: session
    )

    let request = PackageRequest(
      layerID: "shom",
      zoneWKT: "INVALID",
      zoomMax: 14,
      format: .mbtiles,
      cipher: .v3
    )

    do {
      _ = try await service.requestPackage(request, accessToken: "test_access_token")
      XCTFail("Should have thrown CaasError.requestFailed")
    } catch {
      guard case CaasError.requestFailed(let code) = error else {
        XCTFail("Expected CaasError.requestFailed(400), got \(error)")
        return
      }
      XCTAssertEqual(code, 400)
    }
  }

  // MARK: - GET /packages/{pkg_id}

  func testFetchStatus_success() async throws {
    let packageUUID = UUID(uuidString: "3FA85F64-5717-4562-B3FC-2C963F66AFA6")!
    MockURLProtocol.setHandler { request in
      XCTAssertEqual(request.httpMethod, "GET")
      XCTAssertEqual(request.url?.path, "/packages/\(packageUUID.uuidString.lowercased())")
      XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test_access_token")
      XCTAssertTrue(Self.legacyKeyHeaders(of: request).isEmpty, "plus d'en-tête de clé CaaS")
      XCTAssertNil(request.url?.query, "plus de clé en query string")

      let json = """
      {
        "uuid": "\(packageUUID.uuidString.lowercased())",
        "state": "PROGRESS",
        "monitor": "500/1000",
        "eta": 1737900000
      }
      """.data(using: .utf8)!

      let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
      return (response, json)
    }

    let service = GeoGaragePackageService(
      baseURL: URL(string: "https://caas.geogarage.com")!,
      session: session
    )

    let status = try await service.fetchStatus(packageID: packageUUID, accessToken: "test_access_token")
    XCTAssertEqual(status.uuid, packageUUID)
    XCTAssertEqual(status.state, .progress)
    XCTAssertEqual(status.monitor, "500/1000")
    XCTAssertNotNil(status.eta)
  }

  // MARK: - DELETE /packages/{pkg_id}

  func testDeletePackage_success() async throws {
    let packageUUID = UUID(uuidString: "3FA85F64-5717-4562-B3FC-2C963F66AFA6")!
    MockURLProtocol.setHandler { request in
      XCTAssertEqual(request.httpMethod, "DELETE")
      XCTAssertEqual(request.url?.path, "/packages/\(packageUUID.uuidString.lowercased())")
      XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test_access_token")
      XCTAssertTrue(Self.legacyKeyHeaders(of: request).isEmpty, "plus d'en-tête de clé CaaS")
      XCTAssertNil(request.url?.query, "plus de clé en query string")

      let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
      return (response, nil)
    }

    let service = GeoGaragePackageService(
      baseURL: URL(string: "https://caas.geogarage.com")!,
      session: session
    )

    try await service.deletePackage(packageID: packageUUID, accessToken: "test_access_token")
  }

  // MARK: - Polling Loop (pollUntilComplete)

  func testPollUntilComplete_emitsProgressAndFinishesOnSuccess() async throws {
    let packageUUID = UUID(uuidString: "3FA85F64-5717-4562-B3FC-2C963F66AFA6")!
    var callCount = 0

    MockURLProtocol.setHandler { request in
      callCount += 1
      let json: Data
      if callCount == 1 {
        json = """
        {
          "uuid": "\(packageUUID.uuidString.lowercased())",
          "state": "PROGRESS",
          "monitor": "500/1000"
        }
        """.data(using: .utf8)!
      } else {
        json = """
        {
          "uuid": "\(packageUUID.uuidString.lowercased())",
          "state": "SUCCESS",
          "url": "https://caas.geogarage.com/download",
          "md5": "d41d8cd98f00b204e9800998ecf8427e",
          "size": 1048576
        }
        """.data(using: .utf8)!
      }
      let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
      return (response, json)
    }

    let service = GeoGaragePackageService(
      baseURL: URL(string: "https://caas.geogarage.com")!,
      session: session
    )

    var states: [PackageState] = []
    let stream = await service.pollUntilComplete(
      packageID: packageUUID,
      accessToken: "test_access_token",
      interval: .milliseconds(50),
      timeout: .seconds(5)
    )

    for try await update in stream {
      states.append(update.state)
    }

    XCTAssertEqual(states, [.progress, .success])
  }

  func testPollUntilComplete_throwsOnFailureState() async {
    let packageUUID = UUID(uuidString: "3FA85F64-5717-4562-B3FC-2C963F66AFA6")!

    MockURLProtocol.setHandler { request in
      let json = """
      {
        "uuid": "\(packageUUID.uuidString.lowercased())",
        "state": "FAILURE",
        "error": "Bounding box area exceeded"
      }
      """.data(using: .utf8)!
      let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
      return (response, json)
    }

    let service = GeoGaragePackageService(
      baseURL: URL(string: "https://caas.geogarage.com")!,
      session: session
    )

    let stream = await service.pollUntilComplete(
      packageID: packageUUID,
      accessToken: "test_access_token",
      interval: .milliseconds(50),
      timeout: .seconds(5)
    )

    do {
      for try await _ in stream {
        // should yield failure once and throw
      }
      XCTFail("Should have thrown error on FAILURE state")
    } catch {
      guard case CaasError.packageGenerationFailed(let message) = error else {
        XCTFail("Expected CaasError.packageGenerationFailed, got \(error)")
        return
      }
      XCTAssertTrue(message.contains("Bounding box area exceeded"))
    }
  }

  func testPollUntilComplete_cooperativeCancellation() async throws {
    let packageUUID = UUID(uuidString: "3FA85F64-5717-4562-B3FC-2C963F66AFA6")!

    MockURLProtocol.setHandler { request in
      let json = """
      {
        "uuid": "\(packageUUID.uuidString.lowercased())",
        "state": "PROGRESS",
        "monitor": "100/1000"
      }
      """.data(using: .utf8)!
      let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
      return (response, json)
    }

    let service = GeoGaragePackageService(
      baseURL: URL(string: "https://caas.geogarage.com")!,
      session: session
    )

    let stream = await service.pollUntilComplete(
      packageID: packageUUID,
      accessToken: "test_access_token",
      interval: .milliseconds(200),
      timeout: .seconds(10)
    )

    let task = Task {
      var count = 0
      for try await _ in stream {
        count += 1
      }
      return count
    }

    // Cancel after 100ms
    try await Task.sleep(for: .milliseconds(100))
    task.cancel()

    let result = try? await task.value
    // Should terminate gracefully without deadlock
    XCTAssertNotNil(result)
  }

  func testPollUntilComplete_withExponentialBackoff() async throws {
    let packageUUID = UUID(uuidString: "3FA85F64-5717-4562-B3FC-2C963F66AFA6")!
    var callCount = 0

    MockURLProtocol.setHandler { request in
      callCount += 1
      let json: Data
      if callCount < 3 {
        json = """
        {
          "uuid": "\(packageUUID.uuidString.lowercased())",
          "state": "PROGRESS",
          "monitor": "\(callCount * 250)/1000"
        }
        """.data(using: .utf8)!
      } else {
        json = """
        {
          "uuid": "\(packageUUID.uuidString.lowercased())",
          "state": "SUCCESS",
          "url": "https://caas.geogarage.com/download",
          "md5": "d41d8cd98f00b204e9800998ecf8427e",
          "size": 1048576
        }
        """.data(using: .utf8)!
      }
      let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
      return (response, json)
    }

    let service = GeoGaragePackageService(
      baseURL: URL(string: "https://caas.geogarage.com")!,
      session: session
    )

    var states: [PackageState] = []
    let stream = await service.pollUntilComplete(
      packageID: packageUUID,
      accessToken: "test_access_token",
      initialInterval: .milliseconds(20),
      maxInterval: .milliseconds(100),
      backoffMultiplier: 2.0,
      timeout: .seconds(5)
    )

    for try await update in stream {
      states.append(update.state)
    }

    XCTAssertEqual(states, [.progress, .progress, .success])
    XCTAssertEqual(callCount, 3)
  }
}

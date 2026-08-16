//
//  MockURLProtocol.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-16.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// A custom URLProtocol subclass allowing deterministic request intercept and response mocking
/// for URLSession tests under Swift 6 strict concurrency.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {

  private static let lock = NSLock()
  private static var requestHandlers: [(URLRequest) -> (HTTPURLResponse, Data?)] = []
  private static var errorHandlers: [(URLRequest) -> Error?] = []

  static func reset() {
    lock.lock()
    defer { lock.unlock() }
    requestHandlers.removeAll()
    errorHandlers.removeAll()
  }

  static func setHandler(_ handler: @escaping (URLRequest) -> (HTTPURLResponse, Data?)) {
    lock.lock()
    defer { lock.unlock() }
    requestHandlers.append(handler)
  }

  static func setErrorHandler(_ handler: @escaping (URLRequest) -> Error?) {
    lock.lock()
    defer { lock.unlock() }
    errorHandlers.append(handler)
  }

  static func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
  }

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    MockURLProtocol.lock.lock()
    let errorHandlersCopy = MockURLProtocol.errorHandlers
    let requestHandlersCopy = MockURLProtocol.requestHandlers
    MockURLProtocol.lock.unlock()

    for errorHandler in errorHandlersCopy {
      if let error = errorHandler(request) {
        client?.urlProtocol(self, didFailWithError: error)
        return
      }
    }

    for handler in requestHandlersCopy.reversed() {
      let (response, data) = handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      if let data {
        client?.urlProtocol(self, didLoad: data)
      }
      client?.urlProtocolDidFinishLoading(self)
      return
    }

    let defaultResponse = HTTPURLResponse(
      url: request.url ?? URL(string: "https://mock.local")!,
      statusCode: 404,
      httpVersion: nil,
      headerFields: nil
    )!
    client?.urlProtocol(self, didReceive: defaultResponse, cacheStoragePolicy: .notAllowed)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

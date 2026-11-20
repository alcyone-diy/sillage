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
import os

/// A custom URLProtocol subclass allowing deterministic request intercept and response mocking
/// for URLSession tests under Swift 6 strict concurrency.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {

  private struct HandlerState: Sendable {
    var requestHandlers: [@Sendable (URLRequest) -> (HTTPURLResponse, Data?)] = []
    var errorHandlers: [@Sendable (URLRequest) -> Error?] = []
  }

  private static let stateLock = OSAllocatedUnfairLock<HandlerState>(initialState: HandlerState())

  static func reset() {
    stateLock.withLock { state in
      state.requestHandlers.removeAll()
      state.errorHandlers.removeAll()
    }
  }

  static func setHandler(_ handler: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data?)) {
    stateLock.withLock { state in
      state.requestHandlers.append(handler)
    }
  }

  static func setErrorHandler(_ handler: @escaping @Sendable (URLRequest) -> Error?) {
    stateLock.withLock { state in
      state.errorHandlers.append(handler)
    }
  }

  static func makeMockConfiguration() -> URLSessionConfiguration {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return config
  }

  static func makeMockSession() -> URLSession {
    return URLSession(configuration: makeMockConfiguration())
  }

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    let (errorHandlersCopy, requestHandlersCopy) = MockURLProtocol.stateLock.withLock { state in
      (state.errorHandlers, state.requestHandlers)
    }

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

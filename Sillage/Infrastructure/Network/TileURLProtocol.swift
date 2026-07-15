//
//  TileURLProtocol.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-07-09.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import OSLog
import os

class TileURLProtocol: URLProtocol, @unchecked Sendable {
  private let taskLock = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

  override class func canInit(with request: URLRequest) -> Bool {
    guard let url = request.url else { return false }
    return url.scheme == "sillage" && url.host == "tiles"
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    return request
  }

  override func startLoading() {
    guard let url = request.url else {
        client?.urlProtocol(self, didFailWithError: URLError(.badURL))
        return
    }

    taskLock.withLock { lockState in
      lockState = Task { [weak self] in
        guard let self = self else { return }
        do {
          guard url.scheme == "sillage", url.host == "tiles" else {
            self.client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
          }

          // Robust path components parsing
          let pathComponents = url.pathComponents.filter { $0 != "/" }
          guard pathComponents.count >= 3 else {
            self.client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
          }
          
          let zString = pathComponents[pathComponents.count - 3]
          let xString = pathComponents[pathComponents.count - 2]
          let yString = pathComponents[pathComponents.count - 1]
            .replacingOccurrences(of: ".png", with: "")
            .replacingOccurrences(of: "@2x", with: "")
            .replacingOccurrences(of: "@3x", with: "")
          
          guard let z = Int(zString), let x = Int(xString), let y = Int(yString) else {
            self.client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
          }

          if let data = try await TileProxyManager.shared.fetchTile(z: z, x: x, y: y) {
            try Task.checkCancellation()
            let headers = [
              "Content-Type": "image/png",
              "Cache-Control": "max-age=604800, public"
            ]
            guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers) else {
              Logger.network.error("Failed to create HTTPURLResponse for tile: \(url.absoluteString, privacy: .public)")
              self.client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
              return
            }
            // URLProtocol contract: do not send messages if cancelled
            guard !Task.isCancelled else { return }
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            
            guard !Task.isCancelled else { return }
            self.client?.urlProtocol(self, didLoad: data)
            
            guard !Task.isCancelled else { return }
            self.client?.urlProtocolDidFinishLoading(self)
          } else {
            try Task.checkCancellation()
            self.client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
          }
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
    taskLock.withLock { let t = $0; $0 = nil; t?.cancel() }
  }
}

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

class TileURLProtocol: URLProtocol {
    private var activeTask: Task<Void, Never>?

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

        activeTask = Task {
            do {
                // Parse sillage://tiles/{z}/{x}/{y}.png
                let pathComponents = url.pathComponents.filter { $0 != "/" }
                guard pathComponents.count >= 3 else {
                    self.client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                    return
                }
                
                let zString = pathComponents[pathComponents.count - 3]
                let xString = pathComponents[pathComponents.count - 2]
                let yString = pathComponents[pathComponents.count - 1].replacingOccurrences(of: ".png", with: "")
                
                guard let z = Int(zString), let x = Int(xString), let y = Int(yString) else {
                    self.client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                    return
                }

                if let data = try await TileProxyManager.shared.fetchTile(z: z, x: x, y: y) {
                    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png"])!
                    self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                    self.client?.urlProtocol(self, didLoad: data)
                    self.client?.urlProtocolDidFinishLoading(self)
                } else {
                    self.client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
                }
            } catch {
                self.client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {
        activeTask?.cancel()
    }
}

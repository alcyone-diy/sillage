//
//  TileProxyManager.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import CoreGraphics
import UIKit

actor TileProxyManager {
    static let shared = TileProxyManager()

    private var inFlightTasks: [URL: Task<Data?, Error>] = [:]
    private let cache = NSCache<NSURL, NSData>()

    init() {
        // Configure cache limits if necessary
        cache.countLimit = 1000 // reasonable limit for map tiles
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.protocolClasses = [TileURLProtocol.self] + (config.protocolClasses ?? [])
        return URLSession(configuration: config)
    }()

    func fetchTile(z: Int, x: Int, y: Int, layerID: String = "shom") async throws -> Data? {
        let clientID = AppConfiguration.shared.geoGarageClientID
        // Construct the GeoGarage URL. Note that GeoGarage tile APIs usually require the layer ID.
        guard let url = URL(string: "https://tiles.geogarage.com/\(clientID)/\(layerID)/\(z)/\(x)/\(y).png") else { return nil }
        return try await fetchTile(url: url)
    }

    func fetchTile(url: URL) async throws -> Data? {
        let nsURL = url as NSURL

        // 1. Check completed cache
        if let cachedData = cache.object(forKey: nsURL) {
            return cachedData as Data
        }

        // 2. Check in-flight tasks
        if let existingTask = inFlightTasks[url] {
            return try await existingTask.value
        }

        // 3. Create new fetch task
        let task = Task<Data?, Error> {
            defer { inFlightTasks.removeValue(forKey: url) }

            var request = URLRequest(url: url)
            if let token = KeychainManager.shared.retrieveToken(for: "geogarage_access_token"), !token.isEmpty {
                request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let (data, response) = try await self.session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return nil
            }
            if httpResponse.statusCode == 200 {
                cache.setObject(data as NSData, forKey: nsURL)
                return data
            } else if httpResponse.statusCode == 404 {
                // Return nil to trigger fallback or just return nil
                return nil
            }
            return nil
        }

        inFlightTasks[url] = task
        return try await task.value
    }
}

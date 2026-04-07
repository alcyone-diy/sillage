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

            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                return nil
            }
            if httpResponse.statusCode == 200 {
                cache.setObject(data as NSData, forKey: nsURL)
                return data
            } else if httpResponse.statusCode == 404 {
                // Return nil to trigger fallback
                return nil
            }
            return nil
        }

        inFlightTasks[url] = task
        return try await task.value
    }
}

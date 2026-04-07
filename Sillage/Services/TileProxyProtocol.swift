import Foundation
import CoreGraphics
import UIKit

class TileProxyProtocol: URLProtocol {
    private var activeTask: Task<Void, Never>?

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        return url.scheme == "sillage-geo"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        // 1. Intercept & Verify: Local Authorization Firewall
        let token = KeychainManager.shared.retrieveToken(for: "geogarage_access_token")
        if token == nil || token!.isEmpty {
            // Rule 2: Fail-Closed
            client?.urlProtocol(self, didFailWithError: URLError(.userAuthenticationRequired))
            return
        }

        activeTask = Task {
            do {
                guard let data = try await fetchTileData(for: url) else {
                    self.client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
                    return
                }

                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png"])!
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
                self.client?.urlProtocol(self, didLoad: data)
                self.client?.urlProtocolDidFinishLoading(self)
            } catch {
                self.client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {
        activeTask?.cancel()
    }

    private func fetchTileData(for url: URL, depth: Int = 0) async throws -> Data? {
        // Rewrite and Dispatch
        // Example URL: sillage-geo://geogarage-proxy/<layerID>/{z}/{x}/{y}.png
        guard url.host == "geogarage-proxy" else { return nil }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 4 else { return nil }

        let layerID = pathComponents[0]
        let z = pathComponents[1]
        let x = pathComponents[2]
        let y = pathComponents[3]

        let clientID = AppConfiguration.shared.geoGarageClientID
        guard let httpsURL = URL(string: "https://tiles.geogarage.com/\(clientID)/\(layerID)/\(z)/\(x)/\(y)") else { return nil }

        // Use TileProxyManager to fetch with request coalescing
        if let data = try await TileProxyManager.shared.fetchTile(url: httpsURL) {
            return data
        }

        // 404 Case: fallback logic
        if depth >= 2 {
            return generateTransparentTile()
        }

        return try await generateFallbackTile(for: url, depth: depth)
    }

    private func generateFallbackTile(for url: URL, depth: Int) async throws -> Data? {
        let pathComponents = url.pathComponents
        guard pathComponents.count >= 3 else { return nil }

        // URL path format is typically .../{z}/{x}/{y}.png
        let yString = pathComponents[pathComponents.count - 1].replacingOccurrences(of: ".png", with: "")
        let xString = pathComponents[pathComponents.count - 2]
        let zString = pathComponents[pathComponents.count - 3]

        guard let z = Int(zString), let x = Int(xString), let y = Int(yString) else { return nil }

        let parentZ = z - 1
        let parentX = x / 2
        let parentY = y / 2

        var parentPathComponents = pathComponents
        parentPathComponents[pathComponents.count - 1] = "\(parentY).png"
        parentPathComponents[pathComponents.count - 2] = "\(parentX)"
        parentPathComponents[pathComponents.count - 3] = "\(parentZ)"

        // Reconstruct URL with parent components
        let parentPath = parentPathComponents.dropFirst().joined(separator: "/")
        guard let parentURL = URL(string: "sillage-geo://\(url.host!)/\(parentPath)") else { return nil }

        // Recursively fetch parent tile
        guard let parentData = try await fetchTileData(for: parentURL, depth: depth + 1),
              let parentImage = UIImage(data: parentData)?.cgImage else {
            return nil
        }

        let quadrantX = x % 2
        let quadrantY = y % 2

        return cropAndScaleImage(parentImage, quadrantX: quadrantX, quadrantY: quadrantY)
    }

    private func cropAndScaleImage(_ image: CGImage, quadrantX: Int, quadrantY: Int) -> Data? {
        let halfWidth = image.width / 2
        let halfHeight = image.height / 2

        let cropRect = CGRect(
            x: quadrantX * halfWidth,
            y: quadrantY * halfHeight,
            width: halfWidth,
            height: halfHeight
        )

        guard let croppedImage = image.cropping(to: cropRect) else { return nil }

        let targetSize = CGSize(width: image.width, height: image.height)

        // Nearest-neighbor scaling
        UIGraphicsBeginImageContextWithOptions(targetSize, false, 1.0)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }

        context.interpolationQuality = .none

        // Invert Y axis for CoreGraphics context drawing
        context.translateBy(x: 0, y: targetSize.height)
        context.scaleBy(x: 1.0, y: -1.0)

        context.draw(croppedImage, in: CGRect(origin: .zero, size: targetSize))

        let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return scaledImage?.pngData()
    }

    private func generateTransparentTile() -> Data? {
        let size = CGSize(width: 256, height: 256)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image?.pngData()
    }
}

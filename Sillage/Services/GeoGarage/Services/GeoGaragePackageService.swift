//
//  GeoGaragePackageService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-16.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import OSLog

/// Implementation of `GeoGaragePackageServiceProtocol` executing asynchronous REST calls
/// to `https://caas.geogarage.com` off the Main Thread within a background actor.
actor GeoGaragePackageService: GeoGaragePackageServiceProtocol {

  private let baseURL: URL
  private let session: URLSession

  init(
    baseURL: URL = URL(string: "https://caas.geogarage.com")!,
    session: URLSession = .shared
  ) {
    self.baseURL = baseURL
    self.session = session
  }

  // MARK: - Helper Struct for Request Response

  private struct PackageCreationResponse: Codable {
    let uuid: UUID?
    let id: UUID?
    var resolvedUUID: UUID? { uuid ?? id }
  }

  // MARK: - POST /packages/request/

  func requestPackage(
    _ request: PackageRequest,
    apiKey: String,
    userID: String
  ) async throws(CaasError) -> UUID {
    guard let endpoint = URL(string: "packages/request/", relativeTo: baseURL)?.absoluteURL else {
      throw CaasError.invalidDownloadURL(raw: "packages/request/")
    }

    var urlRequest = URLRequest(url: endpoint)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    urlRequest.setValue(apiKey, forHTTPHeaderField: "api_key")
    urlRequest.timeoutInterval = 30.0

    let parameters: [String: String] = [
      "api_key": apiKey,
      "layer_id": request.layerID,
      "zone": request.zoneWKT,
      "zoom_max": String(request.zoomMax),
      "format": request.format.rawValue,
      "cipher": request.cipher.rawValue,
      "userid": userID
    ]

    urlRequest.httpBody = encodeParameters(parameters)

    Logger.caas.info("Requesting offline package for layer '\(request.layerID, privacy: .public)' (zoomMax: \(request.zoomMax, privacy: .public))")

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await session.data(for: urlRequest)
    } catch {
      Logger.caas.error("Failed to execute package request: \(error.localizedDescription, privacy: .public)")
      throw CaasError.networkError(underlying: error.localizedDescription)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw CaasError.networkError(underlying: "Invalid non-HTTP response received from CAAS server.")
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      let bodyText = String(data: data, encoding: .utf8) ?? "unknown error"
      Logger.caas.error("Package request failed with HTTP \(httpResponse.statusCode, privacy: .public): \(bodyText, privacy: .public)")
      throw CaasError.requestFailed(statusCode: httpResponse.statusCode)
    }

    do {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .secondsSince1970
      let creation = try decoder.decode(PackageCreationResponse.self, from: data)
      guard let uuid = creation.resolvedUUID else {
        throw CaasError.packageGenerationFailed(message: "Server response did not contain a valid package UUID.")
      }
      Logger.caas.info("Package generation request accepted. UUID: \(uuid.uuidString, privacy: .public)")
      return uuid
    } catch let error as CaasError {
      throw error
    } catch {
      Logger.caas.error("Failed to decode package request response: \(error.localizedDescription, privacy: .public)")
      throw CaasError.packageGenerationFailed(message: "Failed to decode server response: \(error.localizedDescription)")
    }
  }

  // MARK: - GET /packages/{pkg_id}

  func fetchStatus(
    packageID: UUID,
    apiKey: String
  ) async throws(CaasError) -> PackageStatusResponse {
    let lowerUUID = packageID.uuidString.lowercased()
    guard let baseURLWithUUID = URL(string: "packages/\(lowerUUID)", relativeTo: baseURL)?.absoluteURL else {
      throw CaasError.invalidDownloadURL(raw: "packages/\(lowerUUID)")
    }
    var components = URLComponents(
      url: baseURLWithUUID,
      resolvingAgainstBaseURL: true
    )
    components?.queryItems = [URLQueryItem(name: "api_key", value: apiKey)]

    guard let endpoint = components?.url else {
      throw CaasError.invalidDownloadURL(raw: "packages/\(lowerUUID)")
    }

    var urlRequest = URLRequest(url: endpoint)
    urlRequest.httpMethod = "GET"
    urlRequest.setValue(apiKey, forHTTPHeaderField: "api_key")
    urlRequest.timeoutInterval = 15.0

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await session.data(for: urlRequest)
    } catch {
      throw CaasError.networkError(underlying: error.localizedDescription)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw CaasError.networkError(underlying: "Invalid non-HTTP response received.")
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      Logger.caas.error("Fetch status failed for package \(packageID.uuidString, privacy: .public) with HTTP \(httpResponse.statusCode, privacy: .public)")
      throw CaasError.requestFailed(statusCode: httpResponse.statusCode)
    }

    do {
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .secondsSince1970
      return try decoder.decode(PackageStatusResponse.self, from: data)
    } catch {
      Logger.caas.error("Failed to decode PackageStatusResponse: \(error.localizedDescription, privacy: .public)")
      throw CaasError.packageGenerationFailed(message: "Failed to decode status response: \(error.localizedDescription)")
    }
  }

  // MARK: - DELETE /packages/{pkg_id}

  func deletePackage(
    packageID: UUID,
    apiKey: String
  ) async throws(CaasError) {
    let lowerUUID = packageID.uuidString.lowercased()
    guard let baseURLWithUUID = URL(string: "packages/\(lowerUUID)", relativeTo: baseURL)?.absoluteURL else {
      throw CaasError.invalidDownloadURL(raw: "packages/\(lowerUUID)")
    }
    var components = URLComponents(
      url: baseURLWithUUID,
      resolvingAgainstBaseURL: true
    )
    components?.queryItems = [URLQueryItem(name: "api_key", value: apiKey)]

    guard let endpoint = components?.url else {
      throw CaasError.invalidDownloadURL(raw: "packages/\(lowerUUID)")
    }

    var urlRequest = URLRequest(url: endpoint)
    urlRequest.httpMethod = "DELETE"
    urlRequest.setValue(apiKey, forHTTPHeaderField: "api_key")
    urlRequest.timeoutInterval = 15.0

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await session.data(for: urlRequest)
    } catch {
      throw CaasError.networkError(underlying: error.localizedDescription)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw CaasError.networkError(underlying: "Invalid non-HTTP response received.")
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? ""
      Logger.caas.warning("Server package deletion returned HTTP \(httpResponse.statusCode, privacy: .public): \(body, privacy: .public)")
      throw CaasError.requestFailed(statusCode: httpResponse.statusCode)
    }

    Logger.caas.info("Successfully deleted remote package \(packageID.uuidString, privacy: .public) on CAAS server.")
  }

  // MARK: - Polling Loop (AsyncThrowingStream)

  func pollUntilComplete(
    packageID: UUID,
    apiKey: String,
    interval: Duration = .seconds(5),
    timeout: Duration = .seconds(900)
  ) -> AsyncThrowingStream<PackageStatusResponse, Error> {
    AsyncThrowingStream { continuation in
      let pollingTask = Task { [weak self] in
        let startTime = ContinuousClock.now

        while !Task.isCancelled {
          guard let self else {
            continuation.finish()
            return
          }

          let status: PackageStatusResponse
          do {
            status = try await self.fetchStatus(packageID: packageID, apiKey: apiKey)
          } catch {
            continuation.finish(throwing: error)
            return
          }

          continuation.yield(status)

          switch status.state {
          case .success:
            Logger.caas.info("Package \(packageID.uuidString, privacy: .public) reached SUCCESS state.")
            continuation.finish()
            return

          case .failure:
            let errorMsg = status.error ?? "Unknown error occurred during package generation."
            Logger.caas.error("Package \(packageID.uuidString, privacy: .public) failed: \(errorMsg, privacy: .public)")
            continuation.finish(throwing: CaasError.packageGenerationFailed(message: errorMsg))
            return

          case .started, .progress, .encryption:
            let elapsed = ContinuousClock.now - startTime
            if elapsed > timeout {
              Logger.caas.error("Polling timed out for package \(packageID.uuidString, privacy: .public) after \(elapsed, privacy: .public)")
              continuation.finish(throwing: CaasError.pollingTimeout)
              return
            }

            do {
              try await Task.sleep(for: interval)
            } catch {
              // Task cancellation during sleep (cooperative cancellation)
              continuation.finish(throwing: error)
              return
            }
          }
        }

        continuation.finish()
      }

      continuation.onTermination = { _ in
        pollingTask.cancel()
      }
    }
  }

  // MARK: - Private Helpers

  private func encodeParameters(_ parameters: [String: String]) -> Data? {
    var components = URLComponents()
    components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
    return components.percentEncodedQuery?.data(using: .utf8)
  }
}

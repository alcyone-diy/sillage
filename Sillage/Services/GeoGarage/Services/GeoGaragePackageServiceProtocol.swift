//
//  GeoGaragePackageServiceProtocol.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-16.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Protocol defining the interface for interacting with the GeoGarage CAAS offline map generation API.
protocol GeoGaragePackageServiceProtocol: Sendable {
  /// Initiates an asynchronous package generation request (POST /packages/request/).
  /// - Parameters:
  ///   - request: Package configuration parameters (layer, zone WKT, zoomMax, format, cipher).
  ///   - apiKey: Dedicated CAAS API key.
  ///   - userID: Customer account identifier (`customer_id`).
  /// - Returns: Generated package UUID.
  func requestPackage(
    _ request: PackageRequest,
    apiKey: String,
    userID: String
  ) async throws(CaasError) -> UUID

  /// Fetches the current generation state and progress for a package (GET /packages/{pkg_id}).
  /// - Parameters:
  ///   - packageID: Unique package UUID.
  ///   - apiKey: Dedicated CAAS API key.
  func fetchStatus(
    packageID: UUID,
    apiKey: String
  ) async throws(CaasError) -> PackageStatusResponse

  /// Deletes a completed or cancelled package on the CAAS server (DELETE /packages/{pkg_id}).
  /// - Parameters:
  ///   - packageID: Unique package UUID.
  ///   - apiKey: Dedicated CAAS API key.
  func deletePackage(
    packageID: UUID,
    apiKey: String
  ) async throws(CaasError)

  /// Emits package status updates iteratively until `.success` or `.failure` state is reached.
  /// Handles cooperative task cancellation cleanly.
  /// - Parameters:
  ///   - packageID: Unique package UUID.
  ///   - apiKey: Dedicated CAAS API key.
  ///   - interval: Polling delay between subsequent requests (defaults to 5 seconds).
  ///   - timeout: Maximum cumulative duration before throwing `CaasError.pollingTimeout` (defaults to 15 minutes).
  func pollUntilComplete(
    packageID: UUID,
    apiKey: String,
    interval: Duration,
    timeout: Duration
  ) async -> AsyncThrowingStream<PackageStatusResponse, Error>
}

extension GeoGaragePackageServiceProtocol {
  func pollUntilComplete(
    packageID: UUID,
    apiKey: String
  ) async -> AsyncThrowingStream<PackageStatusResponse, Error> {
    await pollUntilComplete(
      packageID: packageID,
      apiKey: apiKey,
      interval: .seconds(5),
      timeout: .seconds(900)
    )
  }
}

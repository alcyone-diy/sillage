//
//  GeoGaragePartnerSecretService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-11.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import OSLog

/// Response of `GET /partners/me/`: the package decryption secret of the application that issued
/// the access token, for the signed-in user.
nonisolated struct GeoGaragePartnerSecrets: Codable, Sendable {
  let clientID: String
  /// `nil` for a user who never had a subscription; package generation is refused for them.
  let customerID: String?
  let packageSecret: String
  let teaSecret: String

  enum CodingKeys: String, CodingKey {
    case clientID = "client_id"
    case customerID = "customer_id"
    case packageSecret = "package_secret"
    case teaSecret = "tea_secret"
  }
}

nonisolated enum PartnerSecretError: Error {
  /// Missing, expired or revoked token (401/403): refresh the tokens or sign in again.
  case unauthorized
  /// The application has no active partner profile (404): nothing can be decrypted.
  case noProfile
  case invalidResponse
  case networkError(String)
  /// The task was cancelled during the call (e.g. sign-in sheet dismissed): neither a failure
  /// nor an error to display, same policy as `GeoGarageAuthService`.
  case cancelled
}

protocol GeoGaragePartnerSecretServiceProtocol: Sendable {
  func refresh(accessToken: String) async throws -> GeoGaragePartnerSecrets
}

/// Fetches the package decryption secret from accounts.geogarage.com after sign-in, so nothing
/// secret ships in the binary. The secret lives in the Keychain under `keychainAccount`, never in
/// UserDefaults nor in logs.
actor GeoGaragePartnerSecretService: GeoGaragePartnerSecretServiceProtocol {
  static let keychainAccount = "geogarage_package_secret"

  private let endpoint: URL?
  private let session: URLSession

  init(baseURLString: String = AppConstants.GeoGarage.accountsBaseURLString, session: URLSession = .shared) {
    self.endpoint = URL(string: "\(baseURLString)/partners/me/")
    self.session = session
  }

  func refresh(accessToken: String) async throws -> GeoGaragePartnerSecrets {
    guard let endpoint else {
      throw PartnerSecretError.invalidResponse
    }
    var request = URLRequest(url: endpoint)
    request.httpMethod = "GET"
    // Token in a header, never in the query string: it would end up in the portal's access logs.
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.timeoutInterval = 15.0

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await session.data(for: request)
    } catch is CancellationError {
      throw PartnerSecretError.cancelled
    } catch let error as URLError where error.code == .cancelled {
      // URLSession surfaces Swift task cancellation as URLError.cancelled: same outcome.
      throw PartnerSecretError.cancelled
    } catch {
      throw PartnerSecretError.networkError(error.localizedDescription)
    }
    guard let http = response as? HTTPURLResponse else {
      throw PartnerSecretError.invalidResponse
    }
    switch http.statusCode {
    case 200:
      let secrets: GeoGaragePartnerSecrets
      do {
        secrets = try JSONDecoder().decode(GeoGaragePartnerSecrets.self, from: data)
      } catch {
        Logger.network.error("Failed to decode /partners/me/ response: \(error, privacy: .public)")
        throw PartnerSecretError.invalidResponse
      }
      // A 200 with an empty secret would decrypt nothing: storing it would make an offline-unusable
      // session look healthy.
      guard !secrets.packageSecret.isEmpty else {
        Logger.network.error("/partners/me/ returned an empty package secret for client \(secrets.clientID, privacy: .public).")
        throw PartnerSecretError.invalidResponse
      }
      await KeychainManager.shared.save(token: secrets.packageSecret, for: Self.keychainAccount)
      Logger.network.info("Partner package secret refreshed for client \(secrets.clientID, privacy: .public).")
      return secrets
    case 401, 403:
      throw PartnerSecretError.unauthorized
    case 404:
      throw PartnerSecretError.noProfile
    default:
      throw PartnerSecretError.invalidResponse
    }
  }
}

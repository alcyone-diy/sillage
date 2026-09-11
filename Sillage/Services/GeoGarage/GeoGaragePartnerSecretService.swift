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

/// Réponse de GET /partners/me/ (portail, spec 2026-09-10 §2b) : le secret de déchiffrement des
/// paquets de l'Application qui a émis le token, pour l'utilisateur connecté.
nonisolated struct GeoGaragePartnerSecrets: Codable, Sendable {
  let clientID: String
  /// `nil` pour un utilisateur qui n'a jamais eu d'abonnement : GPKGenerator refusera le paquet.
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
  /// Token absent, expiré ou révoqué (403) : rafraîchir les tokens ou se reconnecter.
  case unauthorized
  /// L'Application n'a pas de fiche partenaire active (404) : rien à déchiffrer, voir avec GeoGarage.
  case noProfile
  case invalidResponse
  case networkError(String)
}

protocol GeoGaragePartnerSecretServiceProtocol: Sendable {
  func refresh(accessToken: String) async throws -> GeoGaragePartnerSecrets
}

/// Lit le secret de déchiffrement des paquets sur accounts.geogarage.com après connexion
/// (voie B partenaires, 11 sept. 2026) : plus rien de secret dans le binaire. Le secret vit dans
/// le trousseau sous `keychainAccount`, jamais dans les préférences ni dans les logs.
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
    // Token en en-tête, jamais en query string : il finirait dans les logs nginx du portail.
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.timeoutInterval = 15.0

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await session.data(for: request)
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

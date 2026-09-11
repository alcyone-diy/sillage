//
//  MockGeoGaragePartnerSecretService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-11.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
@testable import Sillage

final class MockGeoGaragePartnerSecretService: GeoGaragePartnerSecretServiceProtocol, @unchecked Sendable {
  var errorToThrow: PartnerSecretError?
  var secrets = GeoGaragePartnerSecrets(clientID: "mock-client", customerID: "cus_mock123", packageSecret: "mock-secret", teaSecret: "")
  /// Réponses servies dans l'ordre d'appel (FIFO) : permet de rejouer « premier appel rejeté,
  /// second accepté après renouvellement des tokens » (revue finale de la branche, 11 sept. 2026).
  /// Vide, le mock retombe sur `errorToThrow` / `secrets`.
  var results: [Result<GeoGaragePartnerSecrets, PartnerSecretError>] = []
  private(set) var receivedAccessTokens: [String] = []

  func refresh(accessToken: String) async throws -> GeoGaragePartnerSecrets {
    receivedAccessTokens.append(accessToken)
    if !results.isEmpty {
      switch results.removeFirst() {
      case .success(let secrets):
        return secrets
      case .failure(let error):
        throw error
      }
    }
    if let errorToThrow {
      throw errorToThrow
    }
    return secrets
  }
}

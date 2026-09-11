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
  private(set) var receivedAccessTokens: [String] = []

  func refresh(accessToken: String) async throws -> GeoGaragePartnerSecrets {
    receivedAccessTokens.append(accessToken)
    if let errorToThrow {
      throw errorToThrow
    }
    return secrets
  }
}

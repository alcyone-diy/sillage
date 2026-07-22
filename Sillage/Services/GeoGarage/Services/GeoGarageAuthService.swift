//
//  GeoGarageAuthService.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-04-05.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

@MainActor
protocol GeoGarageAuthServiceProtocol: AnyObject {
  var authError: Error? { get set }
  func authenticate(username: String, password: String) async throws -> AuthSuccessResponse
  func fetchAccountSettings(accessToken: String) async throws -> GeoGarageSettingsResponse
  func logout()
}

@Observable
@MainActor
final class GeoGarageAuthService: GeoGarageAuthServiceProtocol {
  var authError: Error? = nil
  private let endpoint = URL(string: "https://accounts.geogarage.com/o/token/")!
  private let settingsEndpoint = URL(string: "https://accounts.geogarage.com/api/account/settings")!

  func logout() {
    KeychainManager.shared.deleteToken(for: "geogarage_access_token")
    KeychainManager.shared.deleteToken(for: "geogarage_refresh_token")
    self.authError = nil
  }

  func authenticate(username: String, password: String) async throws -> AuthSuccessResponse {
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 15.0 // Marine Context: Fail Fast

    let parameters: [String: String] = [
      "grant_type": "password",
      "client_id": AppConfiguration.shared.geoGarageClientID,
      "username": username,
      "password": password
    ]

    let bodyString = encodeParameters(parameters)
    guard let bodyData = bodyString.data(using: .utf8) else {
      throw AuthError.encodingError
    }
    request.httpBody = bodyData

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await URLSession.shared.data(for: request)
    } catch {
      throw AuthError.networkError(error)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw AuthError.invalidResponse
    }

    if httpResponse.statusCode == 200 {
      do {
        let successResponse = try JSONDecoder().decode(AuthSuccessResponse.self, from: data)
        self.authError = nil
        return successResponse
      } catch {
        throw AuthError.invalidResponse
      }
    } else if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
      if let errorResponse = try? JSONDecoder().decode(AuthErrorResponse.self, from: data),
         let description = errorResponse.error_description, !description.isEmpty {
        let error = AuthError.apiError(description: description)
        throw error
      } else {
        throw AuthError.unknown
      }
    } else {
      throw AuthError.invalidResponse
    }
  }

  func fetchAccountSettings(accessToken: String) async throws -> GeoGarageSettingsResponse {
    var request = URLRequest(url: settingsEndpoint)
    request.httpMethod = "GET"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.timeoutInterval = 15.0

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await URLSession.shared.data(for: request)
    } catch {
      throw AuthError.networkError(error)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw AuthError.invalidResponse
    }

    if httpResponse.statusCode == 200 {
      do {
        let settingsResponse = try JSONDecoder().decode(GeoGarageSettingsResponse.self, from: data)
        self.authError = nil
        return settingsResponse
      } catch {
        throw AuthError.invalidResponse
      }
    } else if httpResponse.statusCode == 401 {
      let error = AuthError.tokenExpired
      self.authError = error
      throw error
    } else {
      let error = AuthError.fetchSettingsFailed(statusCode: httpResponse.statusCode)
      self.authError = error
      throw error
    }
  }

  /// Robustly encodes dictionary parameters into an x-www-form-urlencoded string.
  private func encodeParameters(_ parameters: [String: String]) -> String {
    return parameters.map { key, value in
      let escapedKey = escape(key)
      let escapedValue = escape(value)
      return "\(escapedKey)=\(escapedValue)"
    }.joined(separator: "&")
  }

  /// Custom URL encoding for x-www-form-urlencoded that safely escapes special characters.
  private func escape(_ string: String) -> String {
    // x-www-form-urlencoded requires more aggressive encoding than .urlQueryAllowed
    // Specifically, we must ensure characters like +, &, =, and / are properly encoded.
    var allowedCharacters = CharacterSet.alphanumerics
    allowedCharacters.insert(charactersIn: "-._~") // Unreserved characters per RFC 3986

    return string.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? string
  }
}

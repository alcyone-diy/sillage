//
//  GeoGarageAuthService.swift
//  Alcyone Sillage
//
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

protocol GeoGarageAuthServiceProtocol {
  func authenticate(username: String, password: String) async throws -> AuthSuccessResponse
  func fetchAccountSettings(accessToken: String) async throws -> GeoGarageSettingsResponse
}

struct GeoGarageAuthService: GeoGarageAuthServiceProtocol {
  private let endpoint = URL(string: "https://accounts.geogarage.com/o/token/")!
  private let settingsEndpoint = URL(string: "https://accounts.geogarage.com/api/account/settings")!

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
        return successResponse
      } catch {
        throw AuthError.invalidResponse
      }
    } else if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
      if let errorResponse = try? JSONDecoder().decode(AuthErrorResponse.self, from: data),
         let description = errorResponse.error_description, !description.isEmpty {
        throw AuthError.apiError(description: description)
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
        return settingsResponse
      } catch {
        throw AuthError.invalidResponse
      }
    } else if httpResponse.statusCode == 401 {
      throw AuthError.tokenExpired
    } else {
      throw AuthError.fetchSettingsFailed(statusCode: httpResponse.statusCode)
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

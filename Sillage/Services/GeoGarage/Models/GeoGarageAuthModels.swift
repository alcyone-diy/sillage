//
//  GeoGarageAuthModels.swift
//  Alcyone Sillage
//
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

struct AuthSuccessResponse: Codable {
  let access_token: String
  let token_type: String
  let expires_in: Int
  let refresh_token: String
  let scope: String
}

struct AuthErrorResponse: Codable {
  let error_description: String?
  let error: String?
}

enum AuthError: Error, LocalizedError {
  case apiError(description: String)
  case networkError(Error)
  case invalidResponse
  case encodingError
  case fetchSettingsFailed(statusCode: Int)
  case tokenExpired
  case unknown

  var errorDescription: String? {
    let fallback = String(localized: "Authentication failed. Please check your network connection or credentials.")
    switch self {
    case .apiError(let description):
      return description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : description
    case .networkError(let error):
      return String(localized: "Network error: \(error.localizedDescription)")
    case .invalidResponse:
      return String(localized: "Invalid response from the server.")
    case .encodingError:
      return String(localized: "Failed to encode the request.")
    case .fetchSettingsFailed(let statusCode):
      return String(localized: "Failed to fetch account settings. Server returned code \(statusCode).")
    case .tokenExpired:
      return String(localized: "Your session has expired. Please log in again.")
    case .unknown:
      return fallback
    }
  }
}

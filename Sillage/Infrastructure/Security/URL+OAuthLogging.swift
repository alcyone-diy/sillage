//
//  URL+OAuthLogging.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-22.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

extension URL {
  /// Structural URL summary safe for OSLog (`scheme`, `host`, `path`) without query values or fragments.
  var oauthStructureSummary: String {
    let schemeValue = scheme ?? "<none>"
    let hostValue = host ?? "<none>"
    let pathValue = path.isEmpty ? "/" : path
    return "scheme=\(schemeValue) host=\(hostValue) path=\(pathValue)"
  }

  /// Structural URL summary plus boolean presence of `code` and `state` query parameters.
  var oauthCallbackSummary: String {
    let queryItems = URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let hasCode = queryItems.contains { $0.name == "code" && !($0.value ?? "").isEmpty }
    let hasState = queryItems.contains { $0.name == "state" && !($0.value ?? "").isEmpty }
    return "\(oauthStructureSummary) hasCode=\(hasCode) hasState=\(hasState)"
  }
}

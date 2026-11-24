//
//  AppConfiguration.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-05-16.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import OSLog

/// Runtime configuration for external integrations, resolved from the app bundle or injected in tests.
public struct AppConfiguration: Sendable, Equatable {
  public let geoGarageClientID: String?

  /// Indicates whether GeoGarage OAuth and remote chart streaming are configured in this build.
  public var isGeoGarageConfigured: Bool {
    geoGarageClientID != nil
  }

  public init(geoGarageClientID: String?) {
    // Strip quotes before trimming whitespace so values like "\"   \"" also normalize to nil,
    // and treat unexpanded Xcode Info.plist placeholders (e.g. "$(GEOGARAGE_CLIENT_ID)") as nil.
    let normalized = geoGarageClientID?
      .replacingOccurrences(of: "\"", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if let normalized, !normalized.isEmpty, !normalized.hasPrefix("$(") {
      self.geoGarageClientID = normalized
    } else {
      self.geoGarageClientID = nil
    }
  }

  /// Loads configuration from `Info.plist` without failing if optional third-party keys are missing.
  /// Open-source builds without `Secrets.xcconfig` must remain fully usable for GPS, offline charts,
  /// anchor watch, and track recording.
  public static func fromBundle(_ bundle: Bundle = .main) -> AppConfiguration {
    let rawClientID = bundle.object(forInfoDictionaryKey: "GEOGARAGE_CLIENT_ID") as? String
    let configuration = AppConfiguration(geoGarageClientID: rawClientID)
    if configuration.geoGarageClientID == nil {
      Logger.system.warning("GEOGARAGE_CLIENT_ID is not configured in Info.plist. GeoGarage sign-in and remote charts are disabled.")
    }
    return configuration
  }
}

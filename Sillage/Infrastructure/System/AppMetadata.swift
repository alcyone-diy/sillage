//
//  AppMetadata.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 23/05/2026.
//  Copyright © 2026 Alcyone. All rights reserved.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import OSLog

public struct AppMetadata: Sendable {
    public let version: String?
    public let build: String?
    public let gitHash: String?
    
    public init(version: String? = nil, build: String? = nil, gitHash: String? = nil) {
        self.version = version
        self.build = build
        self.gitHash = gitHash
    }
}

public struct AppMetadataProvider {
  public static func resolve() -> AppMetadata {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    var gitHash: String? = nil
    
    if let url = Bundle.main.url(forResource: "GitHash", withExtension: "txt") {
      do {
        let content = try String(contentsOf: url, encoding: .utf8)
        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        gitHash = cleaned.isEmpty ? nil : cleaned
      } catch {
        Logger.system.error("Cannot read GitHash.txt : \(error.localizedDescription)")
      }
    } else {
      Logger.system.warning("GitHash.txt not found.")
    }
    
    return AppMetadata(version: version, build: build, gitHash: gitHash)
  }
}

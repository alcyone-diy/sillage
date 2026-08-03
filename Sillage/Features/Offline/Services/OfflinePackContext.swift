//
//  OfflinePackContext.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-08-04.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Internal context attached to a `MLNOfflinePack` to identify and name offline regions.
///
/// Declared in its own file with an explicit `init(from:)` to prevent Swift 6 from
/// inferring `@MainActor` isolation on the synthesized `Decodable` conformance.
/// Without this, the compiler rejects its use inside `Task.detached` or any
/// other nonisolated context (e.g., `nonisolated func deletePack`).
struct OfflinePackContext: Codable, Sendable {
  let id: String
  let regionName: String

  init(id: String, regionName: String) {
    self.id = id
    self.regionName = regionName
  }

  // Explicit implementation: nonisolated by default, prevents Swift 6 from
  // promoting the synthesized version to @MainActor isolation.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    regionName = try container.decode(String.self, forKey: .regionName)
  }
}

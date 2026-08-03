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
/// Declared in its own file to prevent Swift 6 from inferring `@MainActor` isolation
/// on the synthesized `Decodable.init(from:)`, which would make it unusable in
/// `nonisolated` contexts (e.g., inside `Task.detached`).
struct OfflinePackContext: Codable, Sendable {
  let id: String
  let regionName: String
}

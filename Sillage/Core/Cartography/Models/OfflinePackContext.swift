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

/// Internal DTO attached to a `MLNOfflinePack` to persist region identity across sessions.
///
/// Declared as a pure, non-isolated value type. All decoding happens on the `@MainActor`
/// (inside `@MainActor`-isolated methods of `OfflineMapManager`), so no actor annotation
/// is needed or desired here.
struct OfflinePackContext: Codable, Sendable {
  let id: String
  let regionName: String
}

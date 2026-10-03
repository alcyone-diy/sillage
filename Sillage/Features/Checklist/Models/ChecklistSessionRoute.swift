//
//  ChecklistSessionRoute.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-03.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Encapsulates routing parameters for presenting an active or completed checklist session.
///
/// Route identity (`Equatable` and `Hashable`) is defined exclusively by the immutable session `id`.
/// The optional `snapshot` acts solely as a transient fast-path payload to eliminate initial UI latency,
/// ensuring that live in-memory mutations (e.g. checking items, updating progress) do not alter the
/// navigation stack identity or trigger unexpected route invalidations in SwiftUI.
public struct ChecklistSessionRoute: Hashable, Sendable {
  public let id: UUID
  public let snapshot: ChecklistSession?

  public init(id: UUID, snapshot: ChecklistSession? = nil) {
    self.id = id
    self.snapshot = snapshot
  }

  public init(_ session: ChecklistSession) {
    self.id = session.id
    self.snapshot = session
  }

  public static func == (lhs: ChecklistSessionRoute, rhs: ChecklistSessionRoute) -> Bool {
    lhs.id == rhs.id
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

//
//  ChecklistCategoryDetailPayload.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-10.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Encapsulates navigation parameters for inspecting or editing a checklist category.
///
/// Payload identity (`Equatable` and `Hashable`) is defined exclusively by the immutable `categoryId`.
/// The optional `category` acts solely as a transient fast-path snapshot to eliminate initial UI latency,
/// ensuring that mutations do not alter the navigation stack identity in SwiftUI.
public struct ChecklistCategoryDetailPayload: Hashable, Sendable {
  public let categoryId: String?
  public let category: ChecklistCategoryItem?
  public let startEditable: Bool

  public init(
    categoryId: String? = nil,
    category: ChecklistCategoryItem? = nil,
    startEditable: Bool = false
  ) {
    self.categoryId = categoryId ?? category?.id
    self.category = category
    self.startEditable = startEditable
  }

  public init(_ category: ChecklistCategoryItem, startEditable: Bool = false) {
    self.categoryId = category.id
    self.category = category
    self.startEditable = startEditable
  }

  public static func == (lhs: ChecklistCategoryDetailPayload, rhs: ChecklistCategoryDetailPayload) -> Bool {
    lhs.categoryId == rhs.categoryId && lhs.startEditable == rhs.startEditable
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(categoryId)
    hasher.combine(startEditable)
  }
}

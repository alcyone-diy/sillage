//
//  ChecklistCatalogServiceProtocol.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-11-25.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation

/// Public contract defining operations on maritime checklist templates, categories, and default seeding.
@MainActor
public protocol ChecklistCatalogServiceProtocol: Sendable {
  // MARK: - Templates

  /// Fetches all available checklist templates ordered by sort position.
  func fetchTemplates() async throws -> [ChecklistTemplate]

  /// Fetches a specific template by its identifier.
  func fetchTemplate(id: UUID) async throws -> ChecklistTemplate?

  /// Creates a checklist template.
  func createTemplate(
    title: String,
    description: String?,
    categoryId: String,
    items: [(title: String, detail: String?)]
  ) async throws -> ChecklistTemplate

  /// Updates an existing checklist template and its items.
  func updateTemplate(
    id: UUID,
    title: String,
    description: String?,
    categoryId: String,
    items: [(id: UUID?, title: String, detail: String?)]
  ) async throws -> ChecklistTemplate

  /// Deletes a template and its associated sessions (via SQLite cascade).
  func deleteTemplate(id: UUID) async throws

  /// Seeds default system checklists if not present in the database.
  func seedDefaultTemplatesIfNeeded() async throws

  // MARK: - Categories

  /// Fetches all checklist categories ordered by sort position.
  func fetchCategories() async throws -> [ChecklistCategoryItem]

  /// Fetches a specific category by its identifier.
  func fetchCategory(id: String) async throws -> ChecklistCategoryItem?

  /// Creates a checklist category.
  func createCategory(
    id: String?,
    name: String,
    icon: String?,
    sortOrder: Int?
  ) async throws -> ChecklistCategoryItem

  /// Updates an existing checklist category.
  func updateCategory(
    id: String,
    name: String,
    icon: String?,
    sortOrder: Int?
  ) async throws -> ChecklistCategoryItem

  /// Deletes a checklist category if no templates reference it.
  func deleteCategory(id: String) async throws

  /// Updates the sort order of checklist categories according to the given ordered list of identifiers.
  func reorderCategories(ids: [String]) async throws

  /// Fetches count of checklist templates grouped by category identifier.
  func fetchChecklistCountsByCategory() async throws -> [String: Int]
}

extension ChecklistCatalogServiceProtocol {
  /// Updates an existing checklist template with simple item tuples (generating fresh item IDs where unmatched).
  public func updateTemplate(
    id: UUID,
    title: String,
    description: String? = nil,
    categoryId: String = "routine",
    items: [(title: String, detail: String?)]
  ) async throws -> ChecklistTemplate {
    try await updateTemplate(
      id: id,
      title: title,
      description: description,
      categoryId: categoryId,
      items: items.map { (id: nil, title: $0.title, detail: $0.detail) }
    )
  }

  /// Creates a checklist template in the default `"routine"` category without a description.
  public func createTemplate(
    title: String,
    items: [(title: String, detail: String?)]
  ) async throws -> ChecklistTemplate {
    try await createTemplate(
      title: title,
      description: nil,
      categoryId: "routine",
      items: items
    )
  }
}

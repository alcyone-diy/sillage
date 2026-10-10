//
//  ChecklistCategoryDetailViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-10.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Observation
import OSLog

/// A view model managing the consultation and inspection of a specific maritime checklist category.
@MainActor
@Observable
public final class ChecklistCategoryDetailViewModel {
  private let checklistService: any ChecklistServiceProtocol

  public let categoryId: String
  public private(set) var category: ChecklistCategoryItem?
  public private(set) var associatedTemplates: [ChecklistTemplate] = []
  public private(set) var isLoading: Bool = false
  public var errorMessage: String?

  /// Whether this is a built-in standard maritime category (vs custom user-defined category).
  public var isBuiltIn: Bool {
    ChecklistSeeder.initialCategories.contains { $0.id == categoryId }
  }

  /// Display name of the category.
  public var name: String {
    category?.name ?? ""
  }

  /// SF Symbol icon name.
  public var icon: String? {
    category?.icon
  }

  /// Resolved display system image.
  public var displaySystemImage: String {
    category?.displaySystemImage ?? "checklist"
  }

  /// Sort position order.
  public var sortOrder: Int {
    category?.sortOrder ?? 0
  }

  public init(
    categoryId: String,
    category: ChecklistCategoryItem? = nil,
    checklistService: any ChecklistServiceProtocol
  ) {
    self.categoryId = categoryId
    self.category = category
    self.checklistService = checklistService
  }

  /// Loads category details and associated templates from the database.
  public func loadCategory() async {
    isLoading = true
    defer { isLoading = false }
    errorMessage = nil

    do {
      async let fetchedCategory = checklistService.fetchCategory(id: categoryId)
      async let allTemplates = checklistService.fetchTemplates()

      let (cat, templates) = try await (fetchedCategory, allTemplates)
      if let cat {
        self.category = cat
      }
      self.associatedTemplates = templates
        .filter { $0.categoryId == categoryId }
        .sorted { $0.sortOrder < $1.sortOrder }
    } catch {
      if error is CancellationError {
        return
      }
      Logger.checklist.error("Failed to load category \(self.categoryId, privacy: .public): \(String(reflecting: error), privacy: .public)")
      errorMessage = String(localized: "Unable to load category details. Please try again.")
    }
  }
}

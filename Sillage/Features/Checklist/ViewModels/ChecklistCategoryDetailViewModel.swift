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

/// A view model managing the consultation, creation, and editing of a maritime checklist category.
@MainActor
@Observable
public final class ChecklistCategoryDetailViewModel {
  private let checklistService: any ChecklistServiceProtocol

  public private(set) var categoryId: String?
  public private(set) var category: ChecklistCategoryItem?
  public private(set) var associatedTemplates: [ChecklistTemplate] = []
  public private(set) var isLoading: Bool = false
  public private(set) var isSaving: Bool = false
  public var isEditable: Bool
  public var alertTitle: String = String(localized: "Error")
  public var errorMessage: String?

  /// Editable display name of the category.
  public var name: String = ""

  /// Editable SF Symbol icon name.
  public var icon: String?

  /// Default available icons read from the design system, ensuring the current icon is included.
  public var availableIcons: [String] {
    var icons = MarineTheme.Icons.checklistCategoryDefaults
    let current = displaySystemImage
    if !icons.contains(current) {
      icons.insert(current, at: 0)
    }
    return icons
  }

  /// Returns true if creating a new category (no existing categoryId).
  public var isNew: Bool {
    categoryId == nil
  }

  /// Returns whether this view model is modifying an existing category.
  public var isEditing: Bool {
    !isNew
  }

  /// Indicates whether deletion is allowed (existing category with no associated checklists).
  public var canDelete: Bool {
    !isNew && associatedTemplates.isEmpty && !isSaving
  }

  /// Resolved display system image.
  public var displaySystemImage: String {
    if let icon, !icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return icon.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return category?.displaySystemImage ?? "checklist"
  }

  /// Sort position order.
  public var sortOrder: Int {
    category?.sortOrder ?? 0
  }

  /// Returns true if the category has a valid non-empty name.
  public var isValid: Bool {
    validationErrorMessage == nil
  }

  /// Explains why the category cannot be saved, or returns nil if valid.
  public var validationErrorMessage: String? {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmedName.isEmpty {
      return String(localized: "Please provide a name for this category.")
    }
    return nil
  }

  public init(
    categoryId: String? = nil,
    category: ChecklistCategoryItem? = nil,
    checklistService: any ChecklistServiceProtocol,
    startEditable: Bool = false
  ) {
    let resolvedId = categoryId ?? category?.id
    self.categoryId = resolvedId
    self.category = category
    self.checklistService = checklistService
    self.isEditable = (resolvedId == nil) ? true : startEditable

    if let category {
      populate(from: category)
    } else if resolvedId == nil {
      self.icon = "checklist"
    }
  }

  /// Loads category details and associated templates from the database.
  public func loadCategory() async {
    guard let categoryId else { return }

    isLoading = true
    defer { isLoading = false }
    errorMessage = nil

    do {
      async let fetchedCategory = checklistService.fetchCategory(id: categoryId)
      async let allTemplates = checklistService.fetchTemplates()

      let (cat, templates) = try await (fetchedCategory, allTemplates)
      if let cat {
        self.category = cat
        populate(from: cat)
      }
      self.associatedTemplates = templates
        .filter { $0.categoryId == categoryId }
        .sorted { $0.sortOrder < $1.sortOrder }
    } catch {
      if error is CancellationError {
        return
      }
      Logger.checklist.error("Failed to load category \(categoryId, privacy: .public): \(String(reflecting: error), privacy: .public)")
      errorMessage = String(localized: "Unable to load category details. Please try again.")
    }
  }

  private func populate(from category: ChecklistCategoryItem) {
    self.name = category.name
    self.icon = category.icon
  }

  /// Reverts any in-progress edits back to the loaded category state.
  public func revert() {
    if let category {
      populate(from: category)
      isEditable = false
    } else {
      name = ""
      icon = "checklist"
    }
  }

  /// Persists the category (creating if new, updating if existing).
  /// - Returns: The saved `ChecklistCategoryItem` if successful, or `nil` on failure.
  public func save() async -> ChecklistCategoryItem? {
    guard isValid, !isSaving else {
      if let validation = validationErrorMessage {
        alertTitle = String(localized: "Incomplete Category")
        errorMessage = validation
      }
      return nil
    }

    isSaving = true
    defer { isSaving = false }
    errorMessage = nil

    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedIcon = icon?.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedIcon = (trimmedIcon?.isEmpty == false) ? trimmedIcon : nil

    do {
      let saved: ChecklistCategoryItem
      if let categoryId {
        saved = try await checklistService.updateCategory(
          id: categoryId,
          name: trimmedName,
          icon: resolvedIcon,
          sortOrder: category?.sortOrder
        )
        Logger.checklist.info("Successfully updated checklist category: \(saved.id, privacy: .public)")
      } else {
        saved = try await checklistService.createCategory(
          id: nil,
          name: trimmedName,
          icon: resolvedIcon,
          sortOrder: nil
        )
        Logger.checklist.info("Successfully created checklist category: \(saved.id, privacy: .public)")
      }

      self.category = saved
      self.categoryId = saved.id
      populate(from: saved)
      self.isEditable = false
      return saved
    } catch {
      Logger.checklist.error("Failed to save checklist category: \(String(reflecting: error), privacy: .public)")
      alertTitle = String(localized: "Error")
      errorMessage = ChecklistSessionError.userMessage(for: error)
      return nil
    }
  }

  /// Deletes the category if allowed.
  /// - Returns: `true` if deletion succeeded, `false` otherwise.
  public func deleteCategory() async -> Bool {
    guard let categoryId else { return false }
    do {
      try await checklistService.deleteCategory(id: categoryId)
      Logger.checklist.info("Successfully deleted category: \(categoryId, privacy: .public)")
      return true
    } catch {
      Logger.checklist.error("Failed to delete category: \(String(reflecting: error), privacy: .public)")
      alertTitle = String(localized: "Error")
      errorMessage = ChecklistSessionError.userMessage(for: error)
      return false
    }
  }
}

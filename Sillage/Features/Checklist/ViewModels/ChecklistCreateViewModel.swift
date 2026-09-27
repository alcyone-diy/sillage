//
//  ChecklistCreateViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import SwiftUI
import Observation
import OSLog

/// A draft model representing an item being authored within a new checklist template.
public struct ChecklistItemDraft: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var title: String
  public var detail: String

  public init(
    id: UUID = UUID(),
    title: String = "",
    detail: String = ""
  ) {
    self.id = id
    self.title = title
    self.detail = detail
  }
}

/// A view model managing the creation and validation of a new maritime checklist template.
@MainActor
@Observable
public final class ChecklistCreateViewModel {
  private let checklistService: any ChecklistServiceProtocol

  public var title: String = ""
  public var descriptionText: String = ""
  public var category: ChecklistCategory = .routine
  public var items: [ChecklistItemDraft] = []
  public private(set) var isSaving: Bool = false
  public var alertTitle: String = "Error"
  public var errorMessage: String?

  /// Returns true if the template has a valid non-empty title and at least one step with a non-empty title.
  public var isValid: Bool {
    validationErrorMessage == nil
  }

  /// Explains why the checklist template cannot be saved, or returns nil if valid.
  public var validationErrorMessage: String? {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let validItems = items.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    let isTitleEmpty = trimmedTitle.isEmpty
    let isStepsEmpty = validItems.isEmpty

    if isTitleEmpty && isStepsEmpty {
      return String(localized: "Please provide a title and at least one step for your checklist.")
    } else if isTitleEmpty {
      return String(localized: "Please provide a title for your checklist.")
    } else if isStepsEmpty {
      return String(localized: "Please add at least one step with a title to your checklist.")
    }
    return nil
  }

  public init(
    checklistService: any ChecklistServiceProtocol,
    initialCategory: ChecklistCategory = .routine
  ) {
    self.checklistService = checklistService
    self.category = initialCategory
    self.items = [ChecklistItemDraft()]
  }

  /// Appends a new draft step to the checklist.
  public func addItem(
    title: String = "",
    detail: String = ""
  ) {
    items.append(ChecklistItemDraft(
      title: title,
      detail: detail
    ))
  }

  /// Removes steps at the specified offsets.
  public func removeItems(atOffsets offsets: IndexSet) {
    items.remove(atOffsets: offsets)
  }

  /// Moves steps from source offsets to destination index.
  public func moveItems(fromOffsets source: IndexSet, toOffset destination: Int) {
    items.move(fromOffsets: source, toOffset: destination)
  }

  /// Moves an item at the given index up by one position if possible.
  public func moveItemUp(at index: Int) {
    guard index > 0, index < items.count else { return }
    items.swapAt(index, index - 1)
  }

  /// Moves an item at the given index down by one position if possible.
  public func moveItemDown(at index: Int) {
    guard index >= 0, index < items.count - 1 else { return }
    items.swapAt(index, index + 1)
  }

  /// Moves the item with the given ID up by one position if possible.
  public func moveItemUp(id: UUID) {
    guard let index = items.firstIndex(where: { $0.id == id }) else { return }
    moveItemUp(at: index)
  }

  /// Moves the item with the given ID down by one position if possible.
  public func moveItemDown(id: UUID) {
    guard let index = items.firstIndex(where: { $0.id == id }) else { return }
    moveItemDown(at: index)
  }

  /// Persists the new checklist template to the database.
  /// - Returns: The newly created `ChecklistTemplate` if successful, or `nil` on failure.
  public func save() async -> ChecklistTemplate? {
    guard isValid, !isSaving else {
      if let validation = validationErrorMessage {
        alertTitle = String(localized: "Incomplete Checklist")
        errorMessage = validation
      }
      return nil
    }
    isSaving = true
    defer { isSaving = false }
    errorMessage = nil

    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
    let desc = trimmedDescription.isEmpty ? nil : trimmedDescription

    // Filter out completely blank steps
    let validItems = items.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    let serviceItems = validItems.map { item in
      let itemTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
      let itemDetail = item.detail.trimmingCharacters(in: .whitespacesAndNewlines)
      return (
        title: itemTitle,
        detail: itemDetail.isEmpty ? nil : itemDetail
      )
    }

    do {
      let createdTemplate = try await checklistService.createCustomTemplate(
        title: trimmedTitle,
        description: desc,
        category: category,
        items: serviceItems
      )
      Logger.checklist.info("Successfully created custom checklist template: \(createdTemplate.id.uuidString, privacy: .public)")
      return createdTemplate
    } catch {
      Logger.checklist.error("Failed to create custom checklist template: \(error.localizedDescription, privacy: .public)")
      errorMessage = error.localizedDescription
      return nil
    }
  }
}

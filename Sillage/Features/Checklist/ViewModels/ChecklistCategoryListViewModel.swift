//
//  ChecklistCategoryListViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-09.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import SwiftUI
import Observation
import OSLog

/// A view model managing the presentation and reordering of available checklist categories.
@MainActor
@Observable
public final class ChecklistCategoryListViewModel {
  private let checklistService: any ChecklistServiceProtocol
  private var saveTask: Task<Void, Never>?

  public private(set) var categories: [ChecklistCategoryItem] = []
  public private(set) var checklistCounts: [String: Int] = [:]
  public private(set) var isLoading: Bool = false
  public var errorMessage: String?

  public init(checklistService: any ChecklistServiceProtocol) {
    self.checklistService = checklistService
  }

  /// Returns the number of checklist templates belonging to the given category.
  public func checklistCount(for categoryId: String) -> Int {
    checklistCounts[categoryId] ?? 0
  }

  /// Loads available categories and checklist templates from the database.
  public func loadCategories() async {
    isLoading = true
    defer { isLoading = false }
    errorMessage = nil

    do {
      async let fetchedCategories = checklistService.fetchCategories()
      async let fetchedCounts = checklistService.fetchChecklistCountsByCategory()
      let (categoriesList, counts) = try await (fetchedCategories, fetchedCounts)

      categories = categoriesList
      checklistCounts = counts
    } catch {
      if error is CancellationError {
        return
      }
      Logger.checklist.error("Failed to load checklist categories: \(String(reflecting: error), privacy: .public)")
      errorMessage = String(localized: "Unable to load checklist categories. Please try again.")
    }
  }

  // MARK: - Reordering Actions

  /// Moves categories from source offsets to destination index and persists the new order.
  public func moveCategories(fromOffsets source: IndexSet, toOffset destination: Int) {
    categories.move(fromOffsets: source, toOffset: destination)
    normalizeCategorySortOrders()
    saveTask?.cancel()
    saveTask = Task { [weak self] in
      await self?.persistCategoryOrder()
    }
  }

  /// Moves a category at the given index up by one position if possible and persists the new order.
  public func moveCategoryUp(at index: Int) {
    guard index > 0, index < categories.count else { return }
    categories.swapAt(index, index - 1)
    normalizeCategorySortOrders()
    saveTask?.cancel()
    saveTask = Task { [weak self] in
      await self?.persistCategoryOrder()
    }
  }

  /// Moves a category at the given index down by one position if possible and persists the new order.
  public func moveCategoryDown(at index: Int) {
    guard index >= 0, index < categories.count - 1 else { return }
    categories.swapAt(index, index + 1)
    normalizeCategorySortOrders()
    saveTask?.cancel()
    saveTask = Task { [weak self] in
      await self?.persistCategoryOrder()
    }
  }

  /// Moves the category with the given ID up by one position if possible and persists the new order.
  public func moveCategoryUp(id: String) {
    guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
    moveCategoryUp(at: index)
  }

  /// Moves the category with the given ID down by one position if possible and persists the new order.
  public func moveCategoryDown(id: String) {
    guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
    moveCategoryDown(at: index)
  }

  /// Persists the current in-memory category order to the database.
  public func persistCategoryOrder() async {
    guard !Task.isCancelled else { return }
    let orderedIds = categories.map(\.id)
    do {
      try await checklistService.reorderCategories(ids: orderedIds)
    } catch {
      if error is CancellationError {
        return
      }
      Logger.checklist.error("Failed to reorder checklist categories: \(String(reflecting: error), privacy: .public)")
      errorMessage = ChecklistSessionError.userMessage(for: error)
    }
  }

  private func normalizeCategorySortOrders() {
    let now = Date()
    categories = categories.enumerated().map { index, item in
      ChecklistCategoryItem(
        id: item.id,
        name: item.name,
        icon: item.icon,
        sortOrder: index,
        createdAt: item.createdAt,
        updatedAt: now
      )
    }
  }
}

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
import Observation
import OSLog

/// A view model managing the presentation of available checklist categories.
@MainActor
@Observable
public final class ChecklistCategoryListViewModel {
  private let checklistService: any ChecklistServiceProtocol

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
}

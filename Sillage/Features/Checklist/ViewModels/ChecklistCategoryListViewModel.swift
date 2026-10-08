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
  public private(set) var isLoading: Bool = false
  public var errorMessage: String?

  public init(checklistService: any ChecklistServiceProtocol) {
    self.checklistService = checklistService
  }

  /// Loads available categories from the database.
  public func loadCategories() async {
    isLoading = true
    defer { isLoading = false }
    errorMessage = nil

    do {
      categories = try await checklistService.fetchCategories()
    } catch {
      if error is CancellationError {
        return
      }
      Logger.checklist.error("Failed to load checklist categories: \(String(reflecting: error), privacy: .public)")
      errorMessage = String(localized: "Unable to load checklist categories. Please try again.")
    }
  }
}

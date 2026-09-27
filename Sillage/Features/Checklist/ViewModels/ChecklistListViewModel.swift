//
//  ChecklistListViewModel.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import Foundation
import Observation
import OSLog

/// A view model managing the presentation of available checklist templates.
@MainActor
@Observable
public final class ChecklistListViewModel {
  private let checklistService: any ChecklistServiceProtocol

  public private(set) var templates: [ChecklistTemplate] = []
  public private(set) var isLoading: Bool = false
  public var errorMessage: String?

  /// Templates grouped by category in defined order.
  public var groupedTemplates: [(category: ChecklistCategory, templates: [ChecklistTemplate])] {
    let grouped = Dictionary(grouping: templates, by: \.category)
    return ChecklistCategory.allCases.compactMap { category in
      guard let list = grouped[category], !list.isEmpty else { return nil }
      return (category: category, templates: list.sorted { $0.sortOrder < $1.sortOrder })
    }
  }

  public init(checklistService: any ChecklistServiceProtocol) {
    self.checklistService = checklistService
  }

  /// Loads available checklist templates from the database.
  public func loadTemplates() async {
    isLoading = true
    defer { isLoading = false }
    errorMessage = nil

    do {
      templates = try await checklistService.fetchTemplates()
    } catch {
      Logger.checklist.error("Failed to load checklist templates: \(error.localizedDescription, privacy: .public)")
      errorMessage = error.localizedDescription
    }
  }
}

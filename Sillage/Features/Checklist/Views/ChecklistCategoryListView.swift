//
//  ChecklistCategoryListView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-09.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// Displays the catalog of available maritime checklist categories.
@MainActor
public struct ChecklistCategoryListView: View {
  @Environment(\.marineTheme) private var marineTheme
  private let checklistService: any ChecklistServiceProtocol
  @State private var viewModel: ChecklistCategoryListViewModel

  public init(checklistService: any ChecklistServiceProtocol) {
    self.checklistService = checklistService
    _viewModel = State(wrappedValue: ChecklistCategoryListViewModel(checklistService: checklistService))
  }

  public var body: some View {
    Group {
      if viewModel.isLoading && viewModel.categories.isEmpty {
        ProgressView()
          .tint(marineTheme.colors.accent)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let errorMessage = viewModel.errorMessage, viewModel.categories.isEmpty {
        ContentUnavailableView {
          Label("Error Loading Categories", systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(marineTheme.colors.warning)
        } description: {
          Text(errorMessage)
            .marineFont(.body)
        }
      } else if viewModel.categories.isEmpty {
        ContentUnavailableView {
          Label("No Categories", systemImage: "tag.slash")
        } description: {
          Text("No categories available")
            .marineFont(.body)
        }
      } else {
        List {
          ForEach(viewModel.categories) { category in
            ChecklistCategoryRowView(category: category)
              .marineListCell()
          }
        }
        .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
      }
    }
    .marineListBackground()
    .navigationTitle("Checklist Categories")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await viewModel.loadCategories()
    }
  }
}

private struct ChecklistCategoryRowView: View {
  @Environment(\.marineTheme) private var marineTheme
  let category: ChecklistCategoryItem

  var body: some View {
    HStack(spacing: MarineTheme.Spacing.medium) {
      Image(systemName: category.displaySystemImage)
        .font(.title3)
        .foregroundStyle(category.color(for: marineTheme))
        .frame(width: 32, alignment: .center)

      Text(category.name)
        .marineFont(.body)
        .foregroundStyle(marineTheme.colors.textPrimary)

      Spacer()
    }
    .frame(minHeight: marineTheme.minTouchTarget)
    .contentShape(Rectangle())
  }
}

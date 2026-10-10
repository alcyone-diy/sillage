//
//  ChecklistCategoryDetailView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-10-10.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// A dedicated view for inspecting a maritime checklist category and its associated checklists.
@MainActor
public struct ChecklistCategoryDetailView: View {
  @Environment(\.marineTheme) private var marineTheme
  @State private var viewModel: ChecklistCategoryDetailViewModel

  public init(
    categoryId: String,
    category: ChecklistCategoryItem? = nil,
    checklistService: any ChecklistServiceProtocol
  ) {
    _viewModel = State(
      wrappedValue: ChecklistCategoryDetailViewModel(
        categoryId: categoryId,
        category: category,
        checklistService: checklistService
      )
    )
  }

  public var body: some View {
    Group {
      if viewModel.isLoading && viewModel.category == nil {
        ProgressView()
          .tint(marineTheme.colors.accent)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let errorMessage = viewModel.errorMessage, viewModel.category == nil {
        ContentUnavailableView {
          Label("Error Loading Category", systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(marineTheme.colors.warning)
        } description: {
          Text(errorMessage)
            .marineFont(.body)
        }
      } else {
        contentForm
      }
    }
    .marineListBackground()
    .navigationTitle(viewModel.name.isEmpty ? String(localized: "Category") : viewModel.name)
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await viewModel.loadCategory()
    }
  }

  // MARK: - Subviews

  @ViewBuilder
  private var contentForm: some View {
    Form {
      informationSection
      associatedChecklistsSection
    }
  }

  @ViewBuilder
  private var informationSection: some View {
    Section {
      HStack {
        Text("Type")
          .marineFont(.body)
          .foregroundStyle(marineTheme.colors.textPrimary)
        Spacer()
        Text(viewModel.isBuiltIn ? "Standard" : "Custom")
          .marineFont(.body)
          .foregroundStyle(marineTheme.colors.textSecondary)
      }
      .marineListCell()

      HStack {
        Text("Icon")
          .marineFont(.body)
          .foregroundStyle(marineTheme.colors.textPrimary)
        Spacer()
        HStack(spacing: MarineTheme.Spacing.small) {
          Image(systemName: viewModel.displaySystemImage)
            .foregroundStyle(viewModel.category?.color(for: marineTheme) ?? marineTheme.colors.accent)
          Text(viewModel.icon ?? "None")
            .marineFont(.body)
            .foregroundStyle(marineTheme.colors.textSecondary)
        }
      }
      .marineListCell()

      HStack {
        Text("Identifier")
          .marineFont(.body)
          .foregroundStyle(marineTheme.colors.textPrimary)
        Spacer()
        Text(viewModel.categoryId)
          .marineFont(.body)
          .foregroundStyle(marineTheme.colors.textSecondary)
      }
      .marineListCell()

      HStack {
        Text("Sort Order")
          .marineFont(.body)
          .foregroundStyle(marineTheme.colors.textPrimary)
        Spacer()
        Text("\(viewModel.sortOrder)")
          .marineFont(.body)
          .foregroundStyle(marineTheme.colors.textSecondary)
      }
      .marineListCell()
    } header: {
      Text("Information")
        .marineSectionHeader()
    }
  }

  @ViewBuilder
  private var associatedChecklistsSection: some View {
    Section {
      if viewModel.associatedTemplates.isEmpty {
        Text("No checklists in this category")
          .marineFont(.body)
          .foregroundStyle(marineTheme.colors.textSecondary)
          .marineListCell()
      } else {
        ForEach(viewModel.associatedTemplates) { template in
          HStack(spacing: MarineTheme.Spacing.small) {
            VStack(alignment: .leading, spacing: 2) {
              Text(template.title)
                .marineFont(.body)
                .foregroundStyle(marineTheme.colors.textPrimary)

              if let description = template.description, !description.isEmpty {
                Text(description)
                  .marineFont(.caption)
                  .foregroundStyle(marineTheme.colors.textSecondary)
                  .lineLimit(1)
              }
            }

            Spacer()

            Text("\(template.items.count) steps")
              .marineFont(.caption)
              .foregroundStyle(marineTheme.colors.textSecondary)
          }
          .marineListCell()
        }
      }
    } header: {
      HStack {
        Text("Associated Checklists")
          .marineSectionHeader()
        Spacer()
        if !viewModel.associatedTemplates.isEmpty {
          Text("\(viewModel.associatedTemplates.count)")
            .marineFont(.caption)
            .foregroundStyle(marineTheme.colors.textSecondary)
        }
      }
    } footer: {
      Text("Checklists can be managed and started from the Checklists panel.")
        .marineFont(.caption)
        .foregroundStyle(marineTheme.colors.textSecondary)
    }
  }
}

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

/// A dedicated view for inspecting, creating, and editing a maritime checklist category.
@MainActor
public struct ChecklistCategoryDetailView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.marineTheme) private var marineTheme

  private let startEditable: Bool
  @State private var viewModel: ChecklistCategoryDetailViewModel
  @State private var showDeleteConfirmation: Bool = false
  @FocusState private var isNameFocused: Bool
  public var onCategorySaved: (@MainActor (ChecklistCategoryItem) -> Void)?

  public init(
    categoryId: String? = nil,
    category: ChecklistCategoryItem? = nil,
    checklistService: any ChecklistServiceProtocol,
    startEditable: Bool = false,
    onCategorySaved: (@MainActor (ChecklistCategoryItem) -> Void)? = nil
  ) {
    self.startEditable = startEditable
    self.onCategorySaved = onCategorySaved
    _viewModel = State(
      wrappedValue: ChecklistCategoryDetailViewModel(
        categoryId: categoryId,
        category: category,
        checklistService: checklistService,
        startEditable: startEditable
      )
    )
  }

  public var body: some View {
    Group {
      if viewModel.isLoading && viewModel.category == nil && !viewModel.isNew {
        ProgressView()
          .tint(marineTheme.colors.accent)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let errorMessage = viewModel.errorMessage, viewModel.category == nil && !viewModel.isNew && !viewModel.isEditable {
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
    .interactiveDismissDisabled(viewModel.isSaving)
    .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
    .marineListBackground()
    .navigationTitle(
      viewModel.isEditable
        ? (viewModel.isNew ? String(localized: "New Category") : String(localized: "Edit Category"))
        : (viewModel.name.isEmpty ? String(localized: "Category") : viewModel.name)
    )
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(viewModel.isEditable)
    .toolbar {
      if viewModel.isEditable {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            if viewModel.isNew || startEditable {
              dismiss()
            } else {
              withAnimation {
                viewModel.revert()
              }
            }
          } label: {
            Image(marineIcon: .close)
              .foregroundStyle(marineTheme.colors.textSecondary)
              .padding(8)
              .contentShape(Rectangle())
          }
          .disabled(viewModel.isSaving)
          .accessibilityLabel(String(localized: "Cancel"))
        }

        ToolbarItem(placement: .confirmationAction) {
          Button {
            guard viewModel.isValid else {
              viewModel.alertTitle = String(localized: "Incomplete Category")
              viewModel.errorMessage = viewModel.validationErrorMessage
              return
            }

            Task {
              let wasNew = viewModel.isNew
              if let saved = await viewModel.save() {
                onCategorySaved?(saved)
                if wasNew || startEditable {
                  dismiss()
                }
              }
            }
          } label: {
            Image(marineIcon: .save)
              .padding(8)
              .contentShape(Rectangle())
          }
          .disabled(viewModel.isSaving)
          .accessibilityLabel(String(localized: "Save"))
        }
      } else if viewModel.category != nil {
        ToolbarItem(placement: .primaryAction) {
          Button {
            withAnimation {
              viewModel.isEditable = true
            }
          } label: {
            Text("Edit")
              .marineFont(.body)
              .foregroundStyle(marineTheme.colors.accent)
          }
          .accessibilityLabel(String(localized: "Edit Category"))
        }
      }
    }
    .task {
      await viewModel.loadCategory()
    }
    .alert(
      "Delete Category?",
      isPresented: $showDeleteConfirmation
    ) {
      Button("Delete", role: .destructive) {
        Task {
          if await viewModel.deleteCategory() {
            dismiss()
          }
        }
      }
      Button("Cancel", role: .cancel) { }
    } message: {
      Text("Are you sure you want to permanently delete this category?")
    }
    .alert(
      viewModel.alertTitle,
      isPresented: Binding(
        get: { viewModel.errorMessage != nil && (viewModel.category != nil || viewModel.isEditable) },
        set: { if !$0 { viewModel.errorMessage = nil } }
      ),
      presenting: viewModel.errorMessage
    ) { _ in
      Button("OK", role: .cancel) { }
    } message: { message in
      Text(message)
    }
  }

  // MARK: - Subviews

  @ViewBuilder
  private var contentForm: some View {
    Form {
      if viewModel.isEditable {
        informationEditSection
        iconPickerSection
      } else {
        informationSection
        associatedChecklistsSection
      }
    }
  }

  // MARK: - Edit Mode Sections

  @ViewBuilder
  private var informationEditSection: some View {
    Section {
      VStack(alignment: .leading, spacing: MarineTheme.Spacing.small) {
        Text("Name")
          .marineFont(.caption)
          .foregroundStyle(marineTheme.colors.textSecondary)
        TextField("Category Name", text: $viewModel.name)
          .marineFont(.body)
          .focused($isNameFocused)
          .task {
            if viewModel.isNew {
              do {
                try await Task.sleep(for: .milliseconds(150))
                if !isNameFocused {
                  isNameFocused = true
                }
              } catch {
                // Task was cancelled (e.g. view dismissed before timeout)
              }
            }
          }
      }
      .marineListCell()
    } header: {
      Text("Information")
        .marineSectionHeader()
    }
  }

  @ViewBuilder
  private var iconPickerSection: some View {
    Section {
      let icons = viewModel.availableIcons
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: marineTheme.minTouchTarget), spacing: MarineTheme.Spacing.small)],
        spacing: MarineTheme.Spacing.small
      ) {
        ForEach(icons, id: \.self) { iconName in
          let isSelected = viewModel.displaySystemImage == iconName
          Button {
            viewModel.icon = iconName
          } label: {
            Image(systemName: iconName)
              .font(.title3)
              .foregroundStyle(isSelected ? marineTheme.colors.onPrimary : marineTheme.colors.textPrimary)
              .frame(minWidth: marineTheme.minTouchTarget, minHeight: marineTheme.minTouchTarget)
              .background(
                RoundedRectangle(cornerRadius: MarineTheme.Metrics.cornerRadius)
                  .fill(isSelected ? marineTheme.colors.accent : marineTheme.colors.secondaryActionBackground)
              )
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text(iconName))
          .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
      }
      .padding(.vertical, MarineTheme.Spacing.small)
      .marineListCell()
    } header: {
      Text("Icon")
        .marineSectionHeader()
    } footer: {
      if !viewModel.isNew {
        VStack(alignment: .leading, spacing: MarineTheme.Spacing.medium) {
          if !viewModel.associatedTemplates.isEmpty {
            Text("This category cannot be deleted while it contains checklists.")
              .marineFont(.caption)
              .foregroundStyle(marineTheme.colors.textSecondary)
          }

          Button {
            showDeleteConfirmation = true
          } label: {
            HStack {
              Image(marineIcon: .delete)
              Text("Delete Category")
            }
          }
          .buttonStyle(MarineButtonStyle(.destructive))
          .disabled(!viewModel.canDelete)
          .textCase(nil)
          .padding(.top, MarineTheme.Spacing.small)
        }
      }
    }
  }

  // MARK: - Consultation Mode Sections

  @ViewBuilder
  private var informationSection: some View {
    Section {
      HStack {
        Text("Icon")
          .marineFont(.body)
          .foregroundStyle(marineTheme.colors.textPrimary)
        Spacer()
        Image(systemName: viewModel.displaySystemImage)
          .font(.title3)
          .foregroundStyle(marineTheme.colors.accent)
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

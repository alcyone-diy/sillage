//
//  ChecklistCreateView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// A view for composing and persisting a new custom maritime checklist template.
@MainActor
struct ChecklistCreateView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.marineTheme) private var marineTheme

  @State private var viewModel: ChecklistCreateViewModel
  var onTemplateCreated: (@MainActor (ChecklistTemplate) -> Void)?

  init(
    checklistService: any ChecklistServiceProtocol,
    initialCategory: ChecklistCategory = .routine,
    onTemplateCreated: (@MainActor (ChecklistTemplate) -> Void)? = nil
  ) {
    _viewModel = State(initialValue: ChecklistCreateViewModel(
      checklistService: checklistService,
      initialCategory: initialCategory
    ))
    self.onTemplateCreated = onTemplateCreated
  }

  var body: some View {
    Form {
      generalSection
      stepsSection
    }
    .marineListBackground()
    .interactiveDismissDisabled(viewModel.isSaving)
    .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
    .navigationTitle("New Checklist")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button {
          dismiss()
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
          Task {
            if let template = await viewModel.save() {
              onTemplateCreated?(template)
              dismiss()
            }
          }
        } label: {
          if viewModel.isSaving {
            ProgressView()
              .tint(marineTheme.colors.accent)
          } else {
            Image(marineIcon: .save)
              .foregroundStyle(viewModel.isValid ? marineTheme.colors.accent : marineTheme.colors.inactive)
              .padding(8)
              .contentShape(Rectangle())
          }
        }
        .disabled(!viewModel.isValid || viewModel.isSaving)
        .accessibilityLabel(String(localized: "Save"))
      }
    }
    .alert(
      "Error",
      isPresented: Binding(
        get: { viewModel.errorMessage != nil },
        set: { if !$0 { viewModel.errorMessage = nil } }
      ),
      presenting: viewModel.errorMessage
    ) { _ in
      Button("OK", role: .cancel) { }
    } message: { message in
      Text(message)
    }
  }

  // MARK: - Sections

  @ViewBuilder
  private var generalSection: some View {
    Section(header: Text("Information")) {
      TextField("Title", text: $viewModel.title)
        .marineFont(.body)
        .marineListCell()

      Picker("Category", selection: $viewModel.category) {
        ForEach(ChecklistCategory.allCases, id: \.self) { category in
          Label(category.title, systemImage: category.systemImage).tag(category)
        }
      }
      .pickerStyle(.menu)
      .marineFont(.body)
      .marineListCell()

      TextField("Description (Optional)", text: $viewModel.descriptionText)
        .marineFont(.body)
        .marineListCell()
    }
  }

  @ViewBuilder
  private var stepsSection: some View {
    Section {
      if viewModel.items.isEmpty {
        Text("No steps added yet")
          .marineFont(.body)
          .foregroundStyle(marineTheme.colors.textSecondary)
          .marineListCell()
      } else {
        ForEach($viewModel.items) { $item in
          VStack(alignment: .leading, spacing: MarineTheme.Spacing.small) {
            HStack(alignment: .center, spacing: MarineTheme.Spacing.small) {
              if let index = viewModel.items.firstIndex(where: { $0.id == item.id }) {
                Text("\(index + 1).")
                  .marineFont(.subheadline)
                  .foregroundStyle(marineTheme.colors.textSecondary)
                  .frame(minWidth: 22, alignment: .leading)
              }

              TextField("Step title", text: $item.title)
                .marineFont(.body)
            }

            TextField("Detail / instructions (Optional)", text: $item.detail)
              .marineFont(.subheadline)
              .foregroundStyle(marineTheme.colors.textSecondary)
              .padding(.leading, 30)

            Toggle(isOn: $item.isMandatory) {
              HStack(spacing: 4) {
                if item.isMandatory {
                  Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(marineTheme.colors.warning)
                    .font(.caption)
                }
                Text("Mandatory step")
                  .marineFont(.caption)
                  .foregroundStyle(item.isMandatory ? marineTheme.colors.warning : marineTheme.colors.textSecondary)
              }
            }
            .padding(.leading, 30)
            .tint(marineTheme.colors.accent)
          }
          .padding(.vertical, 6)
          .marineListCell()
        }
        .onDelete(perform: viewModel.removeItems)
        .onMove(perform: viewModel.moveItems)
      }

      Button {
        viewModel.addItem()
      } label: {
        HStack(spacing: MarineTheme.Spacing.small) {
          Image(marineIcon: .add)
          Text("Add Step")
        }
        .foregroundStyle(marineTheme.colors.accent)
        .marineFont(.body)
      }
      .marineListCell()
    } header: {
      HStack {
        Text("Steps")
        Spacer()
        Text("\(viewModel.items.count)")
          .foregroundStyle(marineTheme.colors.textSecondary)
      }
      .marineFont(.caption)
    } footer: {
      Text("Swipe to delete. Mark critical steps as mandatory.")
        .marineFont(.caption)
        .foregroundStyle(marineTheme.colors.textSecondary)
    }
  }
}

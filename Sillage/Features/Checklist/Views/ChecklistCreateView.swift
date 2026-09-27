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
  @State private var editMode: EditMode = .inactive
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
    .environment(\.editMode, $editMode)
    .onChange(of: viewModel.items.count) { _, newCount in
      if newCount <= 1 && editMode == .active {
        editMode = .inactive
      }
    }
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
          let index = viewModel.items.firstIndex(where: { $0.id == item.id }) ?? 0
          let isFirst = index == 0
          let isLast = index == viewModel.items.count - 1

          VStack(alignment: .leading, spacing: MarineTheme.Spacing.small) {
            HStack(alignment: .center, spacing: MarineTheme.Spacing.small) {
              Text("\(index + 1).")
                .marineFont(.subheadline)
                .foregroundStyle(marineTheme.colors.textSecondary)
                .frame(minWidth: 22, alignment: .leading)

              TextField("Step title", text: $item.title)
                .marineFont(.body)

              if editMode == .active {
                HStack(spacing: MarineTheme.Spacing.tiny) {
                  Button {
                    withAnimation {
                      viewModel.moveItemUp(id: item.id)
                    }
                  } label: {
                    Image(systemName: "chevron.up")
                      .font(.body.weight(.semibold))
                      .foregroundStyle(isFirst ? marineTheme.colors.inactive.opacity(0.3) : marineTheme.colors.accent)
                      .frame(minWidth: 32, minHeight: 32)
                      .contentShape(Rectangle())
                  }
                  .buttonStyle(.plain)
                  .disabled(isFirst)
                  .accessibilityLabel(Text("Move up"))

                  Button {
                    withAnimation {
                      viewModel.moveItemDown(id: item.id)
                    }
                  } label: {
                    Image(systemName: "chevron.down")
                      .font(.body.weight(.semibold))
                      .foregroundStyle(isLast ? marineTheme.colors.inactive.opacity(0.3) : marineTheme.colors.accent)
                      .frame(minWidth: 32, minHeight: 32)
                      .contentShape(Rectangle())
                  }
                  .buttonStyle(.plain)
                  .disabled(isLast)
                  .accessibilityLabel(Text("Move down"))
                }
              }
            }

            TextField("Detail / instructions (Optional)", text: $item.detail)
              .marineFont(.subheadline)
              .foregroundStyle(marineTheme.colors.textSecondary)
              .padding(.leading, 30)
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
        if viewModel.items.count > 1 {
          Button {
            withAnimation {
              editMode = editMode == .active ? .inactive : .active
            }
          } label: {
            HStack(spacing: 4) {
              Image(systemName: editMode == .active ? "checkmark" : "arrow.up.arrow.down")
                .font(.caption2)
              Text(editMode == .active ? "Done" : "Reorder")
                .marineFont(.caption)
            }
            .foregroundStyle(marineTheme.colors.accent)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
              Capsule()
                .fill(marineTheme.colors.secondaryActionBackground)
            )
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text(editMode == .active ? "Done" : "Reorder"))
        }
        Text("\(viewModel.items.count)")
          .foregroundStyle(marineTheme.colors.textSecondary)
      }
      .marineFont(.caption)
    } footer: {
      if editMode == .active {
        Text("Drag handles or tap arrows to change step order.")
          .marineFont(.caption)
          .foregroundStyle(marineTheme.colors.textSecondary)
      } else if viewModel.items.count > 1 {
        Text("Swipe to delete. Tap Reorder to change step order.")
          .marineFont(.caption)
          .foregroundStyle(marineTheme.colors.textSecondary)
      } else {
        Text("Swipe to delete.")
          .marineFont(.caption)
          .foregroundStyle(marineTheme.colors.textSecondary)
      }
    }
  }
}

//
//  ChecklistDetailView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// Detail and interactive execution view for a nautical checklist.
@MainActor
struct ChecklistDetailView: View {
  @Environment(\.marineTheme) private var marineTheme
  @Environment(\.dismiss) private var dismiss

  @State private var viewModel: ChecklistDetailViewModel

  init(templateId: UUID, checklistService: any ChecklistServiceProtocol) {
    _viewModel = State(initialValue: ChecklistDetailViewModel(
      templateId: templateId,
      checklistService: checklistService
    ))
  }

  var body: some View {
    List {
      if viewModel.isLoading && viewModel.execution == nil {
        loadingSection
      } else {
        headerSection
        itemsSection
        actionsSection
      }
    }
    .listStyle(.insetGrouped)
    .marineListBackground()
    .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
    .navigationTitle(viewModel.title.isEmpty ? String(localized: "Checklist") : viewModel.title)
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await viewModel.load()
    }
    .alert(
      "Reset Checklist?",
      isPresented: $viewModel.showResetConfirmation
    ) {
      Button("Reset", role: .destructive) {
        Task {
          await viewModel.reset()
        }
      }
      Button("Cancel", role: .cancel) { }
    } message: {
      Text("This will uncheck all items in this active session.")
    }
    .alert(
      "Delete Template?",
      isPresented: $viewModel.showDeleteConfirmation
    ) {
      Button("Delete", role: .destructive) {
        Task {
          if await viewModel.deleteTemplate() {
            dismiss()
          }
        }
      }
      Button("Cancel", role: .cancel) { }
    } message: {
      Text("Are you sure you want to permanently delete this custom checklist?")
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
  private var loadingSection: some View {
    Section {
      HStack {
        Spacer()
        ProgressView()
          .tint(marineTheme.colors.accent)
        Spacer()
      }
      .marineListCell()
    }
  }

  @ViewBuilder
  private var headerSection: some View {
    Section {
      VStack(alignment: .leading, spacing: MarineTheme.Spacing.small) {
        if let category = viewModel.category {
          HStack(spacing: MarineTheme.Spacing.small) {
            Image(systemName: category.systemImage)
            Text(category.title)
          }
          .marineFont(.caption)
          .foregroundStyle(categoryColor(for: category))
        }

        if let description = viewModel.description, !description.isEmpty {
          Text(description)
            .marineFont(.subheadline)
            .foregroundStyle(marineTheme.colors.textSecondary)
        }

        VStack(spacing: MarineTheme.Spacing.small) {
          HStack {
            Text("\(viewModel.completedCount) of \(viewModel.totalCount) completed")
              .marineFont(.caption)
              .foregroundStyle(marineTheme.colors.textSecondary)

            Spacer()

            if viewModel.isCompleted {
              Label("Completed", systemImage: "checkmark.circle.fill")
                .marineFont(.caption)
                .foregroundStyle(marineTheme.colors.accent)
            } else {
              Text("\(Int(viewModel.progressRatio * 100))%")
                .marineFont(.caption)
                .foregroundStyle(marineTheme.colors.textSecondary)
            }
          }

          ProgressView(value: viewModel.progressRatio)
            .tint(viewModel.isCompleted ? .green : marineTheme.colors.accent)
        }
        .padding(.top, MarineTheme.Spacing.small)
      }
      .padding(.vertical, 4)
      .marineListCell()
    }
  }

  @ViewBuilder
  private var itemsSection: some View {
    Section("Items") {
      ForEach(viewModel.items) { item in
        ChecklistExecutionItemRowView(
          item: item,
          isPerformingAction: viewModel.isPerformingAction,
          onToggle: {
            Task {
              await viewModel.toggleItem(item)
            }
          }
        )
        .marineListCell()
      }
    }
  }

  @ViewBuilder
  private var actionsSection: some View {
    Section {
      if !viewModel.isCompleted {
        Button {
          Task {
            await viewModel.complete()
          }
        } label: {
          HStack(spacing: MarineTheme.Spacing.small) {
            Image(systemName: "checkmark.circle")
            Text("Complete Checklist")
          }
        }
        .buttonStyle(MarineButtonStyle(.primary))
        .disabled(!viewModel.canComplete || viewModel.isPerformingAction)
        .marineListCell()

        if viewModel.canReset {
          Button(role: .destructive) {
            viewModel.showResetConfirmation = true
          } label: {
            HStack(spacing: MarineTheme.Spacing.small) {
              Image(systemName: "arrow.counterclockwise")
              Text("Reset Checklist")
            }
          }
          .buttonStyle(MarineButtonStyle(.destructive))
          .disabled(viewModel.isPerformingAction)
          .marineListCell()
        }
      } else {
        Button {
          Task {
            await viewModel.restartSession()
          }
        } label: {
          HStack(spacing: MarineTheme.Spacing.small) {
            Image(systemName: "arrow.clockwise")
            Text("Start New Session")
          }
        }
        .buttonStyle(MarineButtonStyle(.primary))
        .disabled(viewModel.isPerformingAction)
        .marineListCell()
      }

      if viewModel.canDeleteTemplate {
        Button(role: .destructive) {
          viewModel.showDeleteConfirmation = true
        } label: {
          HStack(spacing: MarineTheme.Spacing.small) {
            Image(marineIcon: .delete)
            Text("Delete Template")
          }
        }
        .buttonStyle(MarineButtonStyle(.destructive))
        .disabled(viewModel.isPerformingAction)
        .marineListCell()
      }
    }
  }

  private func categoryColor(for category: ChecklistCategory) -> Color {
    switch category {
    case .safetyEmergency:
      return marineTheme.colors.warning
    case .navigationManeuver:
      return marineTheme.colors.accent
    case .routine:
      return marineTheme.colors.primary
    case .engineTechnical:
      return marineTheme.colors.textSecondary
    case .winteringMaintenance:
      return marineTheme.colors.inactive
    }
  }
}

/// Interactive item row in a checklist execution.
@MainActor
private struct ChecklistExecutionItemRowView: View {
  @Environment(\.marineTheme) private var marineTheme
  let item: ChecklistExecutionItem
  let isPerformingAction: Bool
  let onToggle: @MainActor () -> Void

  var body: some View {
    HStack(spacing: MarineTheme.Spacing.medium) {
      Button {
        onToggle()
      } label: {
        Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
          .font(.title2)
          .foregroundStyle(item.isChecked ? marineTheme.colors.accent : marineTheme.colors.textSecondary)
          .frame(minWidth: marineTheme.minTouchTarget, minHeight: marineTheme.minTouchTarget)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(isPerformingAction)
      .accessibilityLabel(item.isChecked ? String(localized: "Checked") : String(localized: "Unchecked"))

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: MarineTheme.Spacing.small) {
          Text(item.title)
            .marineFont(.body)
            .foregroundStyle(item.isChecked ? marineTheme.colors.textSecondary : marineTheme.colors.textPrimary)
            .strikethrough(item.isChecked, color: marineTheme.colors.textSecondary)

          if item.isMandatory {
            Text("Required")
              .marineFont(.caption)
              .foregroundStyle(item.isChecked ? marineTheme.colors.textSecondary : marineTheme.colors.warning)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(
                Capsule()
                  .fill(item.isChecked ? marineTheme.colors.secondaryActionBackground : marineTheme.colors.warning.opacity(0.15))
              )
          }
        }

        if let detail = item.detail, !detail.isEmpty {
          Text(detail)
            .marineFont(.caption)
            .foregroundStyle(marineTheme.colors.textSecondary)
        }

        if let checkedAt = item.checkedAt, item.isChecked {
          Text(checkedAt.formatted(date: .omitted, time: .shortened))
            .marineFont(.caption)
            .foregroundStyle(marineTheme.colors.textSecondary.opacity(0.7))
        }
      }
      .contentShape(Rectangle())
      .onTapGesture {
        onToggle()
      }

      Spacer()
    }
    .padding(.vertical, 4)
  }
}

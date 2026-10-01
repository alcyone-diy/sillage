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

/// Detail and interactive session view for a nautical checklist.
@MainActor
struct ChecklistDetailView: View {
  @Environment(\.marineTheme) private var marineTheme
  @Environment(\.dismiss) private var dismiss

  private let checklistService: any ChecklistServiceProtocol
  @State private var viewModel: ChecklistDetailViewModel
  @State private var isShowingEditSheet = false

  init(
    templateId: UUID,
    checklistService: any ChecklistServiceProtocol,
    locationProvider: (@MainActor () -> NavigationFix?)? = nil
  ) {
    self.checklistService = checklistService
    _viewModel = State(initialValue: ChecklistDetailViewModel(
      templateId: templateId,
      checklistService: checklistService,
      locationProvider: locationProvider
    ))
  }

  var body: some View {
    List {
      if viewModel.isLoading && viewModel.template == nil && viewModel.session == nil {
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
    .toolbar {
      if viewModel.template != nil {
        ToolbarItem(placement: .primaryAction) {
          Button {
            isShowingEditSheet = true
          } label: {
            Text("Edit")
              .marineFont(.body)
              .foregroundStyle(marineTheme.colors.accent)
          }
          .accessibilityLabel(String(localized: "Edit Checklist"))
        }
      }
    }
    .sheet(isPresented: $isShowingEditSheet) {
      if let template = viewModel.template {
        NavigationStack {
          ChecklistEditView(
            template: template,
            checklistService: checklistService,
            onTemplateUpdated: { _ in
              Task {
                await viewModel.refreshTemplate()
              }
            }
          )
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
      }
    }
    .task {
      await viewModel.load()
    }
    .task {
      await viewModel.observe()
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
          .foregroundStyle(category.color(for: marineTheme))
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
      ForEach(viewModel.items, id: \.stableId) { item in
        let isCurrent = (item.stableId == viewModel.currentItemId)
        ChecklistSessionItemRowView(
          item: item,
          isCurrentItem: isCurrent,
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
    }
  }
}

/// Interactive item row in a checklist session adhering strictly to Glove Mode.
@MainActor
private struct ChecklistSessionItemRowView: View {
  @Environment(\.marineTheme) private var marineTheme
  let item: ChecklistSessionItem
  let isCurrentItem: Bool
  let isPerformingAction: Bool
  let onToggle: @MainActor () -> Void

  var body: some View {
    Button {
      onToggle()
    } label: {
      HStack(spacing: MarineTheme.Spacing.medium) {
        Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
          .font(.title2)
          .foregroundStyle(
            item.isChecked
              ? marineTheme.colors.accent
              : (isCurrentItem ? marineTheme.colors.accent : marineTheme.colors.textSecondary)
          )

        VStack(alignment: .leading, spacing: 4) {
          Text(item.title)
            .marineFont(isCurrentItem ? .headline : .body)
            .fontWeight(isCurrentItem ? .bold : .regular)
            .foregroundStyle(item.isChecked ? marineTheme.colors.textSecondary : marineTheme.colors.textPrimary)
            .strikethrough(item.isChecked, color: marineTheme.colors.textSecondary)

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

        Spacer()
      }
      .frame(minHeight: marineTheme.minTouchTarget)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(isPerformingAction)
    .accessibilityLabel("\(item.title), \(item.isChecked ? String(localized: "Checked") : String(localized: "Unchecked"))")
  }
}

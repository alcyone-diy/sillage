//
//  ChecklistSessionView.swift
//  Alcyone Sillage
//
//  Created by Alcyone on 2026-09-27.
//  Copyright © 2026 Alcyone.
//  This file is released under the MIT License.
//  See LICENSE file in the project root for full license information.
//

import SwiftUI

/// Detail and interactive session view for a maritime checklist in execution (Glove Mode).
@MainActor
public struct ChecklistSessionView: View {
  @Environment(\.marineTheme) private var marineTheme
  @Environment(\.dismiss) private var dismiss
  private let checklistService: any ChecklistServiceProtocol
  @State private var viewModel: ChecklistSessionViewModel

  /// Initializes the checklist session view.
  /// - Parameters:
  ///   - sessionId: Persistent identifier of the session.
  ///   - session: Optional in-memory session snapshot enabling zero-latency initial rendering.
  ///   - checklistService: The checklist service handling data mutations and observation.
  ///   - locationProvider: Optional provider for auditing GPS coordinates upon step completion.
  public init(
    sessionId: UUID,
    session: ChecklistSession? = nil,
    checklistService: any ChecklistServiceProtocol,
    locationProvider: (@MainActor () -> NavigationFix?)? = nil
  ) {
    self.checklistService = checklistService
    _viewModel = State(initialValue: ChecklistSessionViewModel(
      sessionId: sessionId,
      session: session,
      checklistService: checklistService,
      locationProvider: locationProvider
    ))
  }

  public var body: some View {
    List {
      if viewModel.isLoading && viewModel.session == nil {
        loadingSection
      } else {
        headerSection
        itemsSection
      }
    }
    .listStyle(.insetGrouped)
    .marineListBackground()
    .environment(\.defaultMinListRowHeight, marineTheme.minTouchTarget)
    .navigationTitle(viewModel.title.isEmpty ? String(localized: "Checklist") : viewModel.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if !viewModel.isCompleted, let templateId = viewModel.session?.templateId ?? viewModel.template?.id {
        ToolbarItem(placement: .primaryAction) {
          NavigationLink(value: ChecklistOverlayDestination.templateDetail(templateId: templateId, startEditable: true)) {
            Text("Edit")
              .marineFont(.body)
              .foregroundStyle(marineTheme.colors.accent)
          }
          .accessibilityLabel(String(localized: "Edit Checklist"))
        }
      }
    }
    .task {
      await viewModel.load()
    }
    .task {
      await viewModel.observe()
    }
    .alert(
      viewModel.isCompleted ? Text("Delete Log Entry?") : Text("Reset Progress?"),
      isPresented: $viewModel.showResetConfirmation
    ) {
      Button(role: .destructive) {
        Task {
          await viewModel.delete()
        }
      } label: {
        Text(viewModel.isCompleted ? "Delete" : "Reset")
      }
      Button("Cancel", role: .cancel) { }
    } message: {
      Text(viewModel.isCompleted ? "This will permanently delete this log entry." : "This will clear your current progress.")
    }
    .alert(
      "Error",
      isPresented: Binding(
        get: { viewModel.errorMessage != nil && !viewModel.isSessionDeleted },
        set: { if !$0 { viewModel.errorMessage = nil } }
      ),
      presenting: viewModel.errorMessage
    ) { _ in
      Button("OK", role: .cancel) { }
    } message: { message in
      Text(message)
    }
    .onChange(of: viewModel.isSessionDeleted) { _, isDeleted in
      if isDeleted {
        dismiss()
      }
    }
    .onAppear {
      if viewModel.isSessionDeleted {
        dismiss()
      }
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

        if let description = viewModel.description {
          Text(description)
            .marineFont(.subheadline)
            .foregroundStyle(marineTheme.colors.textSecondary)
        }

        VStack(spacing: MarineTheme.Spacing.small) {
          HStack {
            Text("\(viewModel.completedCount) of \(viewModel.totalCount) checked")
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
    Section {
      if viewModel.items.isEmpty {
        Text("No steps in this checklist.")
          .marineFont(.body)
          .foregroundStyle(marineTheme.colors.textSecondary)
          .marineListCell()
      } else {
        ForEach(viewModel.items, id: \.stableId) { item in
          let isCurrent = (item.stableId == viewModel.currentItemId)
          ChecklistSessionItemRowView(
            item: item,
            isCurrentItem: isCurrent,
            isCompletedSession: viewModel.isCompleted,
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
    } header: {
      Text("Steps")
        .marineSectionHeader()
    } footer: {
      actionsFooter
    }
  }

  @ViewBuilder
  private var actionsFooter: some View {
    VStack(spacing: MarineTheme.Spacing.small) {
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

        if viewModel.canReset {
          Button(role: .destructive) {
            viewModel.showResetConfirmation = true
          } label: {
            HStack(spacing: MarineTheme.Spacing.small) {
              Image(systemName: "arrow.counterclockwise")
              Text("Reset Progress")
            }
          }
          .buttonStyle(MarineButtonStyle(.destructive))
          .disabled(viewModel.isPerformingAction)
        }
      } else {
        if viewModel.canReset {
          Button(role: .destructive) {
            viewModel.showResetConfirmation = true
          } label: {
            HStack(spacing: MarineTheme.Spacing.small) {
              Image(systemName: MarineIcon.delete.rawValue)
              Text("Delete Log Entry")
            }
          }
          .buttonStyle(MarineButtonStyle(.destructive))
          .disabled(viewModel.isPerformingAction)
        }
      }
    }
    .textCase(nil)
    .padding(.top, MarineTheme.Spacing.medium)
  }
}

/// Interactive item row in a checklist session adhering strictly to Glove Mode.
@MainActor
private struct ChecklistSessionItemRowView: View {
  @Environment(\.marineTheme) private var marineTheme
  let item: ChecklistSessionItem
  let isCurrentItem: Bool
  let isCompletedSession: Bool
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
        }

        Spacer()

        ZStack(alignment: .trailing) {
          Text("00:00")
            .marineFont(.caption)
            .hidden()
            .accessibilityHidden(true)

          if let checkedAt = item.checkedAt, item.isChecked {
            Text(checkedAt.formatted(date: .omitted, time: .shortened))
              .marineFont(.caption)
              .foregroundStyle(marineTheme.colors.textSecondary.opacity(0.7))
          }
        }
      }
      .frame(minHeight: marineTheme.minTouchTarget)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(isPerformingAction || isCompletedSession)
    .accessibilityLabel("\(item.title), \(item.isChecked ? String(localized: "Checked") : String(localized: "Unchecked"))")
  }
}
